package service

import (
	"context"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type eventService struct {
	eventRepo     repository.EventRepository
	eventTypeRepo repository.EventTypeRepository
}

// NewEventService creates a new event service
func NewEventService(eventRepo repository.EventRepository, eventTypeRepo repository.EventTypeRepository) EventService {
	return &eventService{
		eventRepo:     eventRepo,
		eventTypeRepo: eventTypeRepo,
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
		UserID:        userID,
		EventTypeID:   req.EventTypeID,
		Timestamp:     req.Timestamp,
		Notes:         req.Notes,
		IsAllDay:      req.IsAllDay,
		EndDate:       req.EndDate,
		SourceType:    sourceType,
		ExternalID:    req.ExternalID,
		OriginalTitle: req.OriginalTitle,
	}

	return s.eventRepo.Create(ctx, event)
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
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	return s.eventRepo.GetByUserID(ctx, userID, limit, offset)
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

	return s.eventRepo.Update(ctx, eventID, update)
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

	return s.eventRepo.Delete(ctx, eventID)
}
