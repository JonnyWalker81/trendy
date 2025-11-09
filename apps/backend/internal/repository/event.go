package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type eventRepository struct {
	client *supabase.Client
}

// NewEventRepository creates a new event repository
func NewEventRepository(client *supabase.Client) EventRepository {
	return &eventRepository{client: client}
}

func (r *eventRepository) Create(ctx context.Context, event *models.Event) (*models.Event, error) {
	data := map[string]interface{}{
		"user_id":       event.UserID,
		"event_type_id": event.EventTypeID,
		"timestamp":     event.Timestamp,
		"is_all_day":    event.IsAllDay,
		"source_type":   event.SourceType,
	}

	if event.Notes != nil {
		data["notes"] = *event.Notes
	}
	if event.EndDate != nil {
		data["end_date"] = *event.EndDate
	}
	if event.ExternalID != nil {
		data["external_id"] = *event.ExternalID
	}
	if event.OriginalTitle != nil {
		data["original_title"] = *event.OriginalTitle
	}

	body, err := r.client.Insert("events", data)
	if err != nil {
		return nil, fmt.Errorf("failed to create event: %w", err)
	}

	var events []models.Event
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(events) == 0 {
		return nil, fmt.Errorf("no event returned")
	}

	return &events[0], nil
}

func (r *eventRepository) GetByID(ctx context.Context, id string) (*models.Event, error) {
	query := map[string]interface{}{
		"id":     fmt.Sprintf("eq.%s", id),
		"select": "*,event_type:event_types(*)",
	}

	body, err := r.client.Query("events", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get event: %w", err)
	}

	var events []models.Event
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(events) == 0 {
		return nil, fmt.Errorf("event not found")
	}

	return &events[0], nil
}

func (r *eventRepository) GetByUserID(ctx context.Context, userID string, limit, offset int) ([]models.Event, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"select":  "*,event_type:event_types(*)",
		"order":   "timestamp.desc",
		"limit":   limit,
		"offset":  offset,
	}

	body, err := r.client.Query("events", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get events: %w", err)
	}

	var events []models.Event
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return events, nil
}

func (r *eventRepository) GetByUserIDAndDateRange(ctx context.Context, userID string, startDate, endDate time.Time) ([]models.Event, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"timestamp": fmt.Sprintf("gte.%s&timestamp=lte.%s", startDate.Format(time.RFC3339), endDate.Format(time.RFC3339)),
		"select":  "*,event_type:event_types(*)",
		"order":   "timestamp.desc",
	}

	body, err := r.client.Query("events", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get events: %w", err)
	}

	var events []models.Event
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return events, nil
}

func (r *eventRepository) Update(ctx context.Context, id string, event *models.Event) (*models.Event, error) {
	data := make(map[string]interface{})

	if event.EventTypeID != "" {
		data["event_type_id"] = event.EventTypeID
	}
	if !event.Timestamp.IsZero() {
		data["timestamp"] = event.Timestamp
	}
	if event.Notes != nil {
		data["notes"] = *event.Notes
	}
	// Always include is_all_day since it's a boolean
	data["is_all_day"] = event.IsAllDay

	if event.EndDate != nil {
		data["end_date"] = *event.EndDate
	}
	if event.SourceType != "" {
		data["source_type"] = event.SourceType
	}
	if event.ExternalID != nil {
		data["external_id"] = *event.ExternalID
	}
	if event.OriginalTitle != nil {
		data["original_title"] = *event.OriginalTitle
	}

	body, err := r.client.Update("events", id, data)
	if err != nil {
		return nil, fmt.Errorf("failed to update event: %w", err)
	}

	var events []models.Event
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(events) == 0 {
		return nil, fmt.Errorf("event not found")
	}

	return &events[0], nil
}

func (r *eventRepository) Delete(ctx context.Context, id string) error {
	if err := r.client.Delete("events", id); err != nil {
		return fmt.Errorf("failed to delete event: %w", err)
	}
	return nil
}

func (r *eventRepository) CountByEventType(ctx context.Context, userID string) (map[string]int64, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"select":  "event_type_id",
	}

	body, err := r.client.Query("events", query)
	if err != nil {
		return nil, fmt.Errorf("failed to count events: %w", err)
	}

	var events []struct {
		EventTypeID string `json:"event_type_id"`
	}
	if err := json.Unmarshal(body, &events); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	counts := make(map[string]int64)
	for _, event := range events {
		counts[event.EventTypeID]++
	}

	return counts, nil
}
