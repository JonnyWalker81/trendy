package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

// ChangeLogRepository defines the interface for change log operations
type ChangeLogRepository interface {
	// Append adds a new entry to the change log
	Append(ctx context.Context, input *models.ChangeLogInput) (int64, error)

	// GetSince retrieves changes since the given cursor for a user
	GetSince(ctx context.Context, userID string, cursor int64, limit int) (*models.ChangeFeedResponse, error)

	// GetLatestCursor returns the maximum change_log ID for a user
	GetLatestCursor(ctx context.Context, userID string) (int64, error)
}

type changeLogRepository struct {
	client *supabase.Client
}

// NewChangeLogRepository creates a new change log repository
func NewChangeLogRepository(client *supabase.Client) ChangeLogRepository {
	return &changeLogRepository{client: client}
}

func (r *changeLogRepository) Append(ctx context.Context, input *models.ChangeLogInput) (int64, error) {
	// Marshal the entity data to JSON
	var dataJSON json.RawMessage
	if input.Data != nil {
		dataBytes, err := json.Marshal(input.Data)
		if err != nil {
			return 0, fmt.Errorf("failed to marshal entity data: %w", err)
		}
		dataJSON = dataBytes
	}

	data := map[string]interface{}{
		"entity_type": string(input.EntityType),
		"operation":   string(input.Operation),
		"entity_id":   input.EntityID,
		"user_id":     input.UserID,
	}

	if len(dataJSON) > 0 {
		data["data"] = dataJSON
	}

	if input.DeletedAt != nil {
		data["deleted_at"] = input.DeletedAt
	}

	body, err := r.client.Insert("change_log", data)
	if err != nil {
		return 0, fmt.Errorf("failed to append to change log: %w", err)
	}

	// Parse the response to get the generated ID
	var entries []models.ChangeEntry
	if err := json.Unmarshal(body, &entries); err != nil {
		return 0, fmt.Errorf("failed to unmarshal change log response: %w", err)
	}

	if len(entries) == 0 {
		return 0, fmt.Errorf("no change log entry returned")
	}

	return entries[0].ID, nil
}

func (r *changeLogRepository) GetSince(ctx context.Context, userID string, cursor int64, limit int) (*models.ChangeFeedResponse, error) {
	if limit <= 0 {
		limit = 100
	}
	if limit > 500 {
		limit = 500
	}

	// Build query with cursor-based pagination
	// We fetch limit+1 to detect if there are more results
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"id":      fmt.Sprintf("gt.%d", cursor),
		"order":   "id.asc",
		"limit":   limit + 1,
	}

	body, err := r.client.Query("change_log", query)
	if err != nil {
		return nil, fmt.Errorf("failed to query change log: %w", err)
	}

	var entries []models.ChangeEntry
	if err := json.Unmarshal(body, &entries); err != nil {
		return nil, fmt.Errorf("failed to unmarshal change log entries: %w", err)
	}

	// Determine if there are more results
	hasMore := len(entries) > limit
	if hasMore {
		entries = entries[:limit] // Remove the extra entry
	}

	// Calculate next cursor
	// When there are no new entries, preserve the original cursor
	// to prevent the client from treating the next sync as a first-time sync
	var nextCursor int64
	if len(entries) > 0 {
		nextCursor = entries[len(entries)-1].ID
	} else {
		nextCursor = cursor
	}

	return &models.ChangeFeedResponse{
		Changes:    entries,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}, nil
}

func (r *changeLogRepository) GetLatestCursor(ctx context.Context, userID string) (int64, error) {
	// Query for the single highest ID for this user
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"select":  "id",
		"order":   "id.desc",
		"limit":   1,
	}

	body, err := r.client.Query("change_log", query)
	if err != nil {
		return 0, fmt.Errorf("failed to query change log: %w", err)
	}

	var entries []struct {
		ID int64 `json:"id"`
	}
	if err := json.Unmarshal(body, &entries); err != nil {
		return 0, fmt.Errorf("failed to unmarshal change log entries: %w", err)
	}

	if len(entries) == 0 {
		return 0, nil // No entries for this user
	}

	return entries[0].ID, nil
}
