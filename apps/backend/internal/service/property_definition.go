package service

import (
	"context"
	"fmt"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type propertyDefinitionService struct {
	propertyDefRepo repository.PropertyDefinitionRepository
	eventTypeRepo   repository.EventTypeRepository
	changeLogRepo   repository.ChangeLogRepository
}

// NewPropertyDefinitionService creates a new property definition service
func NewPropertyDefinitionService(
	propertyDefRepo repository.PropertyDefinitionRepository,
	eventTypeRepo repository.EventTypeRepository,
	changeLogRepo repository.ChangeLogRepository,
) PropertyDefinitionService {
	return &propertyDefinitionService{
		propertyDefRepo: propertyDefRepo,
		eventTypeRepo:   eventTypeRepo,
		changeLogRepo:   changeLogRepo,
	}
}

func (s *propertyDefinitionService) CreatePropertyDefinition(ctx context.Context, userID string, req *models.CreatePropertyDefinitionRequest) (*models.PropertyDefinition, error) {
	// Verify event type exists and belongs to user
	eventType, err := s.eventTypeRepo.GetByID(ctx, req.EventTypeID)
	if err != nil {
		return nil, fmt.Errorf("event type not found")
	}

	if eventType.UserID != userID {
		return nil, fmt.Errorf("event type not found")
	}

	// Validate that select type has options
	if req.PropertyType == models.PropertyTypeSelect && (req.Options == nil || len(req.Options) == 0) {
		return nil, fmt.Errorf("select property type requires options")
	}

	propertyDef := &models.PropertyDefinition{
		EventTypeID:  req.EventTypeID,
		UserID:       userID,
		Key:          req.Key,
		Label:        req.Label,
		PropertyType: req.PropertyType,
		Options:      req.Options,
		DefaultValue: req.DefaultValue,
		DisplayOrder: req.DisplayOrder,
	}

	created, err := s.propertyDefRepo.Create(ctx, propertyDef)
	if err != nil {
		return nil, err
	}

	// Append to change log
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypePropertyDefinition,
		Operation:  models.OperationCreate,
		EntityID:   created.ID,
		UserID:     userID,
		Data:       created,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append to change log", logger.Err(err), logger.String("property_def_id", created.ID))
	}

	return created, nil
}

func (s *propertyDefinitionService) GetPropertyDefinition(ctx context.Context, userID, propertyDefID string) (*models.PropertyDefinition, error) {
	propertyDef, err := s.propertyDefRepo.GetByID(ctx, propertyDefID)
	if err != nil {
		return nil, err
	}

	// Verify the property definition belongs to the user
	if propertyDef.UserID != userID {
		return nil, fmt.Errorf("property definition not found")
	}

	return propertyDef, nil
}

func (s *propertyDefinitionService) GetPropertyDefinitionsByEventType(ctx context.Context, userID, eventTypeID string) ([]models.PropertyDefinition, error) {
	// Verify event type belongs to user
	eventType, err := s.eventTypeRepo.GetByID(ctx, eventTypeID)
	if err != nil {
		return nil, fmt.Errorf("event type not found")
	}

	if eventType.UserID != userID {
		return nil, fmt.Errorf("event type not found")
	}

	return s.propertyDefRepo.GetByEventTypeID(ctx, eventTypeID)
}

func (s *propertyDefinitionService) UpdatePropertyDefinition(ctx context.Context, userID, propertyDefID string, req *models.UpdatePropertyDefinitionRequest) (*models.PropertyDefinition, error) {
	// Get existing property definition to verify ownership
	existingPropertyDef, err := s.propertyDefRepo.GetByID(ctx, propertyDefID)
	if err != nil {
		return nil, err
	}

	if existingPropertyDef.UserID != userID {
		return nil, fmt.Errorf("property definition not found")
	}

	// Validate that select type has options if property type is being set to select
	if req.PropertyType != nil && *req.PropertyType == models.PropertyTypeSelect {
		if req.Options != nil && len(*req.Options) == 0 {
			return nil, fmt.Errorf("select property type requires options")
		}
	}

	// Build update object
	update := &models.PropertyDefinition{}
	if req.Key != nil {
		update.Key = *req.Key
	}
	if req.Label != nil {
		update.Label = *req.Label
	}
	if req.PropertyType != nil {
		update.PropertyType = *req.PropertyType
	}
	if req.Options != nil {
		update.Options = *req.Options
	}
	if req.DefaultValue != nil {
		update.DefaultValue = req.DefaultValue
	}
	if req.DisplayOrder != nil {
		update.DisplayOrder = *req.DisplayOrder
	}

	updated, err := s.propertyDefRepo.Update(ctx, propertyDefID, update)
	if err != nil {
		return nil, err
	}

	// Append to change log
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypePropertyDefinition,
		Operation:  models.OperationUpdate,
		EntityID:   updated.ID,
		UserID:     userID,
		Data:       updated,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append update to change log", logger.Err(err), logger.String("property_def_id", updated.ID))
	}

	return updated, nil
}

func (s *propertyDefinitionService) DeletePropertyDefinition(ctx context.Context, userID, propertyDefID string) error {
	// Verify property definition exists and belongs to user
	propertyDef, err := s.propertyDefRepo.GetByID(ctx, propertyDefID)
	if err != nil {
		return err
	}

	if propertyDef.UserID != userID {
		return fmt.Errorf("property definition not found")
	}

	if err := s.propertyDefRepo.Delete(ctx, propertyDefID); err != nil {
		return err
	}

	// Append to change log
	now := time.Now()
	if _, err := s.changeLogRepo.Append(ctx, &models.ChangeLogInput{
		EntityType: models.EntityTypePropertyDefinition,
		Operation:  models.OperationDelete,
		EntityID:   propertyDefID,
		UserID:     userID,
		DeletedAt:  &now,
	}); err != nil {
		log := logger.FromContext(ctx)
		log.Warn("failed to append delete to change log", logger.Err(err), logger.String("property_def_id", propertyDefID))
	}

	return nil
}
