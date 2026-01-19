package service

import (
	"context"
	"fmt"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type eventService struct {
	eventRepo     repository.EventRepository
	eventTypeRepo repository.EventTypeRepository
	changeLogRepo repository.ChangeLogRepository
}

// NewEventService creates a new event service
func NewEventService(eventRepo repository.EventRepository, eventTypeRepo repository.EventTypeRepository, changeLogRepo repository.ChangeLogRepository) EventService {
	return &eventService{
		eventRepo:     eventRepo,
		eventTypeRepo: eventTypeRepo,
		changeLogRepo: changeLogRepo,
	}
}

func (s *eventService) CreateEvent(ctx context.Context, userID string, req *models.CreateEventRequest) (*models.Event, bool, error) {
	// Validate UUIDv7 if client-provided ID
	if req.ID != nil && *req.ID != "" {
		if err := ValidateUUIDv7(*req.ID); err != nil {
			// Return the validation error - handler translates to ProblemDetails
			return nil, false, err
		}
	}

	// Validate event type exists and belongs to user
	eventType, err := s.eventTypeRepo.GetByID(ctx, req.EventTypeID)
	if err != nil {
		return nil, false, fmt.Errorf("invalid event type: %w", err)
	}

	if eventType.UserID != userID {
		return nil, false, fmt.Errorf("event type does not belong to user")
	}

	// Set default source_type if not provided
	sourceType := req.SourceType
	if sourceType == "" {
		sourceType = "manual"
	}

	event := &models.Event{
		UserID:            userID,
		EventTypeID:       req.EventTypeID,
		Timestamp:         req.Timestamp,
		Notes:             req.Notes,
		IsAllDay:          req.IsAllDay,
		EndDate:           req.EndDate,
		SourceType:        sourceType,
		ExternalID:        req.ExternalID,
		OriginalTitle:     req.OriginalTitle,
		HealthKitSampleID: req.HealthKitSampleID,
		HealthKitCategory: req.HealthKitCategory,
		Properties:        req.Properties,
	}

	// Use client-provided ID if present (for offline-first/UUIDv7 support)
	if req.ID != nil && *req.ID != "" {
		event.ID = *req.ID
	}

	// Determine upsert strategy based on event type
	// - HealthKit events: upsert by sample ID (immutable data, dedup by sample)
	// - Events with client ID: upsert by event ID (idempotent creates)
	// - Events without ID: standard insert
	isHealthKit := sourceType == "healthkit" &&
		req.HealthKitSampleID != nil &&
		*req.HealthKitSampleID != ""
	hasClientID := req.ID != nil && *req.ID != ""

	var created *models.Event
	var wasCreated bool
	var operation models.Operation

	if isHealthKit {
		// Use upsert for HealthKit events - idempotent by sample ID
		created, wasCreated, err = s.eventRepo.UpsertHealthKitEvent(ctx, event)
		if err != nil {
			return nil, false, err
		}
	} else if hasClientID {
		// Use upsert for events with client-provided ID - idempotent by event ID
		created, wasCreated, err = s.eventRepo.Upsert(ctx, event)
		if err != nil {
			return nil, false, err
		}
	} else {
		// Standard insert for events without client ID
		created, err = s.eventRepo.Create(ctx, event)
		if err != nil {
			return nil, false, err
		}
		wasCreated = true
	}

	// Determine operation for change log
	if wasCreated {
		operation = models.OperationCreate
	} else {
		operation = models.OperationUpdate
	}

	// Append to change log with correct operation
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEvent,
		Operation:  operation,
		EntityID:   created.ID,
		UserID:     userID,
		Data:       created,
	}); err != nil {
		// Log but don't fail - the event was created successfully
		log := logger.FromContext(ctx)
		log.Warn("failed to append to change log", logger.Err(err), logger.String("event_id", created.ID))
	}

	return created, wasCreated, nil
}

func (s *eventService) CreateEventsBatch(ctx context.Context, userID string, req *models.BatchCreateEventsRequest) (*models.BatchCreateEventsResponse, error) {
	response := &models.BatchCreateEventsResponse{
		Created: []models.Event{},
		Errors:  []models.BatchError{},
		Total:   len(req.Events),
	}

	// First, get all user's event types for validation
	eventTypes, err := s.eventTypeRepo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get event types: %w", err)
	}

	// Build a map for quick lookup
	eventTypeMap := make(map[string]bool)
	for _, et := range eventTypes {
		eventTypeMap[et.ID] = true
	}

	// Validate and prepare events, separating HealthKit from regular events
	regularEvents := make([]models.Event, 0, len(req.Events))
	healthKitEvents := make([]models.Event, 0)

	for i, eventReq := range req.Events {
		// Validate event type
		if !eventTypeMap[eventReq.EventTypeID] {
			response.Errors = append(response.Errors, models.BatchError{
				Index:   i,
				Message: fmt.Sprintf("invalid event type: %s", eventReq.EventTypeID),
			})
			continue
		}

		// Set default source_type if not provided
		sourceType := eventReq.SourceType
		if sourceType == "" {
			sourceType = "manual"
		}

		event := models.Event{
			UserID:            userID,
			EventTypeID:       eventReq.EventTypeID,
			Timestamp:         eventReq.Timestamp,
			Notes:             eventReq.Notes,
			IsAllDay:          eventReq.IsAllDay,
			EndDate:           eventReq.EndDate,
			SourceType:        sourceType,
			ExternalID:        eventReq.ExternalID,
			OriginalTitle:     eventReq.OriginalTitle,
			GeofenceID:        eventReq.GeofenceID,
			LocationLatitude:  eventReq.LocationLatitude,
			LocationLongitude: eventReq.LocationLongitude,
			LocationName:      eventReq.LocationName,
			HealthKitSampleID: eventReq.HealthKitSampleID,
			HealthKitCategory: eventReq.HealthKitCategory,
			Properties:        eventReq.Properties,
		}

		// Use client-provided ID if present (for offline-first/UUIDv7 support)
		if eventReq.ID != nil && *eventReq.ID != "" {
			event.ID = *eventReq.ID
		}

		// Separate HealthKit events for upsert handling
		isHealthKit := sourceType == "healthkit" &&
			eventReq.HealthKitSampleID != nil &&
			*eventReq.HealthKitSampleID != ""

		if isHealthKit {
			healthKitEvents = append(healthKitEvents, event)
		} else {
			regularEvents = append(regularEvents, event)
		}
	}

	log := logger.FromContext(ctx)

	// Batch insert regular events (non-HealthKit)
	if len(regularEvents) > 0 {
		created, err := s.eventRepo.CreateBatch(ctx, regularEvents)
		if err != nil {
			return nil, fmt.Errorf("failed to batch create events: %w", err)
		}
		response.Created = append(response.Created, created...)

		// Append to change log for each created event
		for _, event := range created {
			if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
				EntityType: models.EntityTypeEvent,
				Operation:  models.OperationCreate,
				EntityID:   event.ID,
				UserID:     userID,
				Data:       event,
			}); err != nil {
				log.Warn("failed to append batch event to change log", logger.Err(err), logger.String("event_id", event.ID))
			}
		}
	}

	// Batch upsert HealthKit events (idempotent)
	if len(healthKitEvents) > 0 {
		upserted, createdIDs, err := s.eventRepo.UpsertHealthKitEventsBatch(ctx, healthKitEvents)
		if err != nil {
			return nil, fmt.Errorf("failed to batch upsert HealthKit events: %w", err)
		}
		response.Created = append(response.Created, upserted...)

		// Build set of created IDs for quick lookup
		createdIDSet := make(map[string]bool)
		for _, id := range createdIDs {
			createdIDSet[id] = true
		}

		// Append to change log ONLY for genuinely new events (CREATE operations)
		// Skip UPDATE operations for HealthKit batch imports - the client already has
		// this data and logging updates floods the change_log unnecessarily
		for _, event := range upserted {
			if createdIDSet[event.ID] {
				if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
					EntityType: models.EntityTypeEvent,
					Operation:  models.OperationCreate,
					EntityID:   event.ID,
					UserID:     userID,
					Data:       event,
				}); err != nil {
					log.Warn("failed to append HealthKit event to change log", logger.Err(err), logger.String("event_id", event.ID))
				}
			}
			// Note: Intentionally skip change_log for UPDATE operations in batch imports
			// The importing client already has the data, and other clients will get it
			// via bootstrap or the next CREATE that triggers a sync
		}
	}

	response.Success = len(response.Created)
	response.Failed = len(response.Errors)

	return response, nil
}

func (s *eventService) GetEvent(ctx context.Context, userID, eventID string) (*models.Event, error) {
	event, err := s.eventRepo.GetByID(ctx, eventID)
	if err != nil {
		return nil, err
	}

	// Verify the event belongs to the user
	if event.UserID != userID {
		return nil, fmt.Errorf("event not found")
	}

	return event, nil
}

func (s *eventService) GetUserEvents(ctx context.Context, userID string, limit, offset int) ([]models.Event, error) {
	// Set default pagination limits
	// Allow up to 1000 events per request to support iOS full-sync
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}

	return s.eventRepo.GetByUserID(ctx, userID, limit, offset)
}

func (s *eventService) ExportEvents(ctx context.Context, userID string, startDate, endDate *time.Time, eventTypeIDs []string) ([]models.Event, error) {
	return s.eventRepo.GetForExport(ctx, userID, startDate, endDate, eventTypeIDs)
}

func (s *eventService) UpdateEvent(ctx context.Context, userID, eventID string, req *models.UpdateEventRequest) (*models.Event, error) {
	// Get existing event to verify ownership
	existingEvent, err := s.eventRepo.GetByID(ctx, eventID)
	if err != nil {
		return nil, err
	}

	if existingEvent.UserID != userID {
		return nil, fmt.Errorf("event not found")
	}

	// Validate event type if provided
	if req.EventTypeID != nil {
		eventType, err := s.eventTypeRepo.GetByID(ctx, *req.EventTypeID)
		if err != nil {
			return nil, fmt.Errorf("invalid event type: %w", err)
		}

		if eventType.UserID != userID {
			return nil, fmt.Errorf("event type does not belong to user")
		}
	}

	// Build fields map for update.
	// For NullableString/NullableTime fields:
	// - Set=true means the field was present in the request (update it)
	// - Valid=true means it has a value, Valid=false means clear it (set to null)
	// Using a map allows explicit null values to be sent to the database.
	fields := make(map[string]interface{})

	if req.EventTypeID != nil {
		fields["event_type_id"] = *req.EventTypeID
	}
	if req.Timestamp != nil {
		fields["timestamp"] = *req.Timestamp
	}
	// Notes: use NullableString to distinguish "clear" from "don't update"
	if req.Notes.Set {
		if req.Notes.Valid {
			fields["notes"] = req.Notes.Value
		} else {
			fields["notes"] = nil // Explicitly set to NULL
		}
	}
	if req.IsAllDay != nil {
		fields["is_all_day"] = *req.IsAllDay
	}
	// EndDate: use NullableTime to distinguish "clear" from "don't update"
	if req.EndDate.Set {
		if req.EndDate.Valid {
			fields["end_date"] = req.EndDate.Value
		} else {
			fields["end_date"] = nil // Explicitly set to NULL
		}
	}
	if req.SourceType != nil {
		fields["source_type"] = *req.SourceType
	}
	// ExternalID: use NullableString
	if req.ExternalID.Set {
		if req.ExternalID.Valid {
			fields["external_id"] = req.ExternalID.Value
		} else {
			fields["external_id"] = nil
		}
	}
	// OriginalTitle: use NullableString
	if req.OriginalTitle.Set {
		if req.OriginalTitle.Valid {
			fields["original_title"] = req.OriginalTitle.Value
		} else {
			fields["original_title"] = nil
		}
	}
	if req.HealthKitSampleID != nil {
		fields["healthkit_sample_id"] = *req.HealthKitSampleID
	}
	if req.HealthKitCategory != nil {
		fields["healthkit_category"] = *req.HealthKitCategory
	}
	if req.Properties != nil {
		fields["properties"] = *req.Properties
	}
	// GeofenceID: use NullableString
	if req.GeofenceID.Set {
		if req.GeofenceID.Valid {
			fields["geofence_id"] = req.GeofenceID.Value
		} else {
			fields["geofence_id"] = nil
		}
	}
	// LocationLatitude and LocationLongitude
	if req.LocationLatitude != nil {
		fields["location_latitude"] = *req.LocationLatitude
	}
	if req.LocationLongitude != nil {
		fields["location_longitude"] = *req.LocationLongitude
	}
	// LocationName: use NullableString
	if req.LocationName.Set {
		if req.LocationName.Valid {
			fields["location_name"] = req.LocationName.Value
		} else {
			fields["location_name"] = nil
		}
	}

	updated, err := s.eventRepo.UpdateFields(ctx, eventID, fields)
	if err != nil {
		return nil, err
	}

	// Append to change log
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEvent,
		Operation:  models.OperationUpdate,
		EntityID:   updated.ID,
		UserID:     userID,
		Data:       updated,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append update to change log", logger.Err(err), logger.String("event_id", updated.ID))
	}

	return updated, nil
}

func (s *eventService) DeleteEvent(ctx context.Context, userID, eventID string) error {
	// Verify event exists and belongs to user
	event, err := s.eventRepo.GetByID(ctx, eventID)
	if err != nil {
		return err
	}

	if event.UserID != userID {
		return fmt.Errorf("event not found")
	}

	if err := s.eventRepo.Delete(ctx, eventID); err != nil {
		return err
	}

	// Append to change log
	now := time.Now()
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEvent,
		Operation:  models.OperationDelete,
		EntityID:   eventID,
		UserID:     userID,
		DeletedAt:  &now,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append delete to change log", logger.Err(err), logger.String("event_id", eventID))
	}

	return nil
}
