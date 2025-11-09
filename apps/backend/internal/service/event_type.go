package service

import (
	"context"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type eventTypeService struct {
	eventTypeRepo repository.EventTypeRepository
}

// NewEventTypeService creates a new event type service
func NewEventTypeService(eventTypeRepo repository.EventTypeRepository) EventTypeService {
	return &eventTypeService{
		eventTypeRepo: eventTypeRepo,
	}
}

func (s *eventTypeService) CreateEventType(ctx context.Context, userID string, req *models.CreateEventTypeRequest) (*models.EventType, error) {
	eventType := &models.EventType{
		UserID: userID,
		Name:   req.Name,
		Color:  req.Color,
		Icon:   req.Icon,
	}

	return s.eventTypeRepo.Create(ctx, eventType)
}

func (s *eventTypeService) GetEventType(ctx context.Context, userID, eventTypeID string) (*models.EventType, error) {
	eventType, err := s.eventTypeRepo.GetByID(ctx, eventTypeID)
	if err != nil {
		return nil, err
	}

	// Verify the event type belongs to the user
	if eventType.UserID != userID {
		return nil, fmt.Errorf("event type not found")
	}

	return eventType, nil
}

func (s *eventTypeService) GetUserEventTypes(ctx context.Context, userID string) ([]models.EventType, error) {
	return s.eventTypeRepo.GetByUserID(ctx, userID)
}

func (s *eventTypeService) UpdateEventType(ctx context.Context, userID, eventTypeID string, req *models.UpdateEventTypeRequest) (*models.EventType, error) {
	// Get existing event type to verify ownership
	existingEventType, err := s.eventTypeRepo.GetByID(ctx, eventTypeID)
	if err != nil {
		return nil, err
	}

	if existingEventType.UserID != userID {
		return nil, fmt.Errorf("event type not found")
	}

	// Build update object
	update := &models.EventType{}
	if req.Name != nil {
		update.Name = *req.Name
	}
	if req.Color != nil {
		update.Color = *req.Color
	}
	if req.Icon != nil {
		update.Icon = *req.Icon
	}

	return s.eventTypeRepo.Update(ctx, eventTypeID, update)
}

func (s *eventTypeService) DeleteEventType(ctx context.Context, userID, eventTypeID string) error {
	// Verify event type exists and belongs to user
	eventType, err := s.eventTypeRepo.GetByID(ctx, eventTypeID)
	if err != nil {
		return err
	}

	if eventType.UserID != userID {
		return fmt.Errorf("event type not found")
	}

	return s.eventTypeRepo.Delete(ctx, eventTypeID)
}
