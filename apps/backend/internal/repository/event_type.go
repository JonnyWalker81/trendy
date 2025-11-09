package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type eventTypeRepository struct {
	client *supabase.Client
}

// NewEventTypeRepository creates a new event type repository
func NewEventTypeRepository(client *supabase.Client) EventTypeRepository {
	return &eventTypeRepository{client: client}
}

func (r *eventTypeRepository) Create(ctx context.Context, eventType *models.EventType) (*models.EventType, error) {
	data := map[string]interface{}{
		"user_id": eventType.UserID,
		"name":    eventType.Name,
		"color":   eventType.Color,
		"icon":    eventType.Icon,
	}

	// Extract user token from context for RLS
	userToken := ""
	if token := ctx.Value("user_token"); token != nil {
		if tokenStr, ok := token.(string); ok {
			userToken = tokenStr
		}
	}

	body, err := r.client.InsertWithToken("event_types", data, userToken)
	if err != nil {
		return nil, fmt.Errorf("failed to create event type: %w", err)
	}

	var eventTypes []models.EventType
	if err := json.Unmarshal(body, &eventTypes); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(eventTypes) == 0 {
		return nil, fmt.Errorf("no event type returned")
	}

	return &eventTypes[0], nil
}

func (r *eventTypeRepository) GetByID(ctx context.Context, id string) (*models.EventType, error) {
	query := map[string]interface{}{
		"id": fmt.Sprintf("eq.%s", id),
	}

	body, err := r.client.Query("event_types", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get event type: %w", err)
	}

	var eventTypes []models.EventType
	if err := json.Unmarshal(body, &eventTypes); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(eventTypes) == 0 {
		return nil, fmt.Errorf("event type not found")
	}

	return &eventTypes[0], nil
}

func (r *eventTypeRepository) GetByUserID(ctx context.Context, userID string) ([]models.EventType, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"order":   "created_at.asc",
	}

	body, err := r.client.Query("event_types", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get event types: %w", err)
	}

	var eventTypes []models.EventType
	if err := json.Unmarshal(body, &eventTypes); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return eventTypes, nil
}

func (r *eventTypeRepository) Update(ctx context.Context, id string, eventType *models.EventType) (*models.EventType, error) {
	data := make(map[string]interface{})

	if eventType.Name != "" {
		data["name"] = eventType.Name
	}
	if eventType.Color != "" {
		data["color"] = eventType.Color
	}
	if eventType.Icon != "" {
		data["icon"] = eventType.Icon
	}

	body, err := r.client.Update("event_types", id, data)
	if err != nil {
		return nil, fmt.Errorf("failed to update event type: %w", err)
	}

	var eventTypes []models.EventType
	if err := json.Unmarshal(body, &eventTypes); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(eventTypes) == 0 {
		return nil, fmt.Errorf("event type not found")
	}

	return &eventTypes[0], nil
}

func (r *eventTypeRepository) Delete(ctx context.Context, id string) error {
	if err := r.client.Delete("event_types", id); err != nil {
		return fmt.Errorf("failed to delete event type: %w", err)
	}
	return nil
}
