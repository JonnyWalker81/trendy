package service

import (
	"context"
	"fmt"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type eventTypeService struct {
	eventTypeRepo repository.EventTypeRepository
	changeLogRepo repository.ChangeLogRepository
}

// NewEventTypeService creates a new event type service
func NewEventTypeService(eventTypeRepo repository.EventTypeRepository, changeLogRepo repository.ChangeLogRepository) EventTypeService {
	return &eventTypeService{
		eventTypeRepo: eventTypeRepo,
		changeLogRepo: changeLogRepo,
	}
}

func (s *eventTypeService) CreateEventType(ctx context.Context, userID string, req *models.CreateEventTypeRequest) (*models.EventType, error) {
	eventType := &models.EventType{
		UserID: userID,
		Name:   req.Name,
		Color:  req.Color,
		Icon:   req.Icon,
	}

	// Use client-provided ID if present (for offline-first/UUIDv7 support)
	if req.ID != nil && *req.ID != "" {
		eventType.ID = *req.ID
	}

	created, err := s.eventTypeRepo.Create(ctx, eventType)
	if err != nil {
		return nil, err
	}

	// Append to change log
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEventType,
		Operation:  models.OperationCreate,
		EntityID:   created.ID,
		UserID:     userID,
		Data:       created,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append to change log", logger.Err(err), logger.String("event_type_id", created.ID))
	}

	return created, nil
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

	updated, err := s.eventTypeRepo.Update(ctx, eventTypeID, update)
	if err != nil {
		return nil, err
	}

	// Append to change log
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEventType,
		Operation:  models.OperationUpdate,
		EntityID:   updated.ID,
		UserID:     userID,
		Data:       updated,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append update to change log", logger.Err(err), logger.String("event_type_id", updated.ID))
	}

	return updated, nil
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

	if err := s.eventTypeRepo.Delete(ctx, eventTypeID); err != nil {
		return err
	}

	// Append to change log
	now := time.Now()
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypeEventType,
		Operation:  models.OperationDelete,
		EntityID:   eventTypeID,
		UserID:     userID,
		DeletedAt:  &now,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append delete to change log", logger.Err(err), logger.String("event_type_id", eventTypeID))
	}

	return nil
}
