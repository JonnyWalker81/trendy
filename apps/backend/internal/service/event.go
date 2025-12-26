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

func (s *eventService) CreateEvent(ctx context.Context, userID string, req *models.CreateEventRequest) (*models.Event, error) {
	// Validate event type exists and belongs to user
	eventType, err := s.eventTypeRepo.GetByID(ctx, req.EventTypeID)
	if err != nil {
		return nil, fmt.Errorf("invalid event type: %w", err)
	}

	if eventType.UserID != userID {
		return nil, fmt.Errorf("event type does not belong to user")
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

	created, err := s.eventRepo.Create(ctx, event)
	if err != nil {
		return nil, err
	}

	// Append to change log
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEvent,
		Operation:  models.OperationCreate,
		EntityID:   created.ID,
		UserID:     userID,
		Data:       created,
	}); err != nil {
		// Log but don't fail - the event was created successfully
		log := logger.FromContext(ctx)
		log.Warn("failed to append to change log", logger.Err(err), logger.String("event_id", created.ID))
	}

	return created, nil
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

	// Validate and prepare events
	validEvents := make([]models.Event, 0, len(req.Events))
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

		validEvents = append(validEvents, event)
	}

	// Batch insert valid events
	if len(validEvents) > 0 {
		created, err := s.eventRepo.CreateBatch(ctx, validEvents)
		if err != nil {
			return nil, fmt.Errorf("failed to batch create events: %w", err)
		}
		response.Created = created

		// Append to change log for each created event
		log := logger.FromContext(ctx)
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

	// Build update object
	update := &models.Event{}
	if req.EventTypeID != nil {
		update.EventTypeID = *req.EventTypeID
	}
	if req.Timestamp != nil {
		update.Timestamp = *req.Timestamp
	}
	if req.Notes != nil {
		update.Notes = req.Notes
	}
	if req.IsAllDay != nil {
		update.IsAllDay = *req.IsAllDay
	}
	if req.EndDate != nil {
		update.EndDate = req.EndDate
	}
	if req.SourceType != nil {
		update.SourceType = *req.SourceType
	}
	if req.ExternalID != nil {
		update.ExternalID = req.ExternalID
	}
	if req.OriginalTitle != nil {
		update.OriginalTitle = req.OriginalTitle
	}
	if req.HealthKitSampleID != nil {
		update.HealthKitSampleID = req.HealthKitSampleID
	}
	if req.HealthKitCategory != nil {
		update.HealthKitCategory = req.HealthKitCategory
	}
	if req.Properties != nil {
		update.Properties = *req.Properties
	}

	updated, err := s.eventRepo.Update(ctx, eventID, update)
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
