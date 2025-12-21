package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

// IdempotencyRepository defines the interface for idempotency key operations
type IdempotencyRepository interface {
	// Get retrieves an existing idempotency record if it exists
	Get(ctx context.Context, key, route, userID string) (*models.IdempotencyKey, error)

	// Store saves a new idempotency record
	Store(ctx context.Context, key, route, userID string, responseBody []byte, statusCode int) error
}

type idempotencyRepository struct {
	client *supabase.Client
}

// NewIdempotencyRepository creates a new idempotency repository
func NewIdempotencyRepository(client *supabase.Client) IdempotencyRepository {
	return &idempotencyRepository{client: client}
}

func (r *idempotencyRepository) Get(ctx context.Context, key, route, userID string) (*models.IdempotencyKey, error) {
	query := map[string]interface{}{
		"key":     fmt.Sprintf("eq.%s", key),
		"route":   fmt.Sprintf("eq.%s", route),
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	body, err := r.client.Query("idempotency_keys", query)
	if err != nil {
		return nil, fmt.Errorf("failed to query idempotency key: %w", err)
	}

	var keys []models.IdempotencyKey
	if err := json.Unmarshal(body, &keys); err != nil {
		return nil, fmt.Errorf("failed to unmarshal idempotency keys: %w", err)
	}

	if len(keys) == 0 {
		return nil, nil // Not found - this is not an error
	}

	return &keys[0], nil
}

func (r *idempotencyRepository) Store(ctx context.Context, key, route, userID string, responseBody []byte, statusCode int) error {
	data := map[string]interface{}{
		"key":           key,
		"route":         route,
		"user_id":       userID,
		"response_body": json.RawMessage(responseBody),
		"status_code":   statusCode,
	}

	_, err := r.client.Insert("idempotency_keys", data)
	if err != nil {
		return fmt.Errorf("failed to store idempotency key: %w", err)
	}

	return nil
}
