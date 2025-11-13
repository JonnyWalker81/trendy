package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type propertyDefinitionRepository struct {
	client *supabase.Client
}

// NewPropertyDefinitionRepository creates a new property definition repository
func NewPropertyDefinitionRepository(client *supabase.Client) PropertyDefinitionRepository {
	return &propertyDefinitionRepository{client: client}
}

func (r *propertyDefinitionRepository) Create(ctx context.Context, def *models.PropertyDefinition) (*models.PropertyDefinition, error) {
	data := map[string]interface{}{
		"event_type_id": def.EventTypeID,
		"user_id":       def.UserID,
		"key":           def.Key,
		"label":         def.Label,
		"property_type": def.PropertyType,
		"display_order": def.DisplayOrder,
	}

	// Add optional fields
	if len(def.Options) > 0 {
		data["options"] = def.Options
	}
	if def.DefaultValue != nil {
		data["default_value"] = def.DefaultValue
	}

	// Extract user token from context for RLS
	userToken := ""
	if token := ctx.Value("user_token"); token != nil {
		if tokenStr, ok := token.(string); ok {
			userToken = tokenStr
		}
	}

	body, err := r.client.InsertWithToken("property_definitions", data, userToken)
	if err != nil {
		return nil, fmt.Errorf("failed to create property definition: %w", err)
	}

	var definitions []models.PropertyDefinition
	if err := json.Unmarshal(body, &definitions); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(definitions) == 0 {
		return nil, fmt.Errorf("no property definition returned")
	}

	return &definitions[0], nil
}

func (r *propertyDefinitionRepository) GetByID(ctx context.Context, id string) (*models.PropertyDefinition, error) {
	query := map[string]interface{}{
		"id": fmt.Sprintf("eq.%s", id),
	}

	body, err := r.client.Query("property_definitions", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get property definition: %w", err)
	}

	var definitions []models.PropertyDefinition
	if err := json.Unmarshal(body, &definitions); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(definitions) == 0 {
		return nil, fmt.Errorf("property definition not found")
	}

	return &definitions[0], nil
}

func (r *propertyDefinitionRepository) GetByEventTypeID(ctx context.Context, eventTypeID string) ([]models.PropertyDefinition, error) {
	query := map[string]interface{}{
		"event_type_id": fmt.Sprintf("eq.%s", eventTypeID),
		"order":         "display_order.asc,created_at.asc",
	}

	body, err := r.client.Query("property_definitions", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get property definitions: %w", err)
	}

	var definitions []models.PropertyDefinition
	if err := json.Unmarshal(body, &definitions); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return definitions, nil
}

func (r *propertyDefinitionRepository) Update(ctx context.Context, id string, def *models.PropertyDefinition) (*models.PropertyDefinition, error) {
	data := make(map[string]interface{})

	if def.Key != "" {
		data["key"] = def.Key
	}
	if def.Label != "" {
		data["label"] = def.Label
	}
	if def.PropertyType != "" {
		data["property_type"] = def.PropertyType
	}
	if len(def.Options) > 0 {
		data["options"] = def.Options
	}
	if def.DefaultValue != nil {
		data["default_value"] = def.DefaultValue
	}
	if def.DisplayOrder >= 0 {
		data["display_order"] = def.DisplayOrder
	}

	body, err := r.client.Update("property_definitions", id, data)
	if err != nil {
		return nil, fmt.Errorf("failed to update property definition: %w", err)
	}

	var definitions []models.PropertyDefinition
	if err := json.Unmarshal(body, &definitions); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(definitions) == 0 {
		return nil, fmt.Errorf("property definition not found")
	}

	return &definitions[0], nil
}

func (r *propertyDefinitionRepository) Delete(ctx context.Context, id string) error {
	if err := r.client.Delete("property_definitions", id); err != nil {
		return fmt.Errorf("failed to delete property definition: %w", err)
	}
	return nil
}
