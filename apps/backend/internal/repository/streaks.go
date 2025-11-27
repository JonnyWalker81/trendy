package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type streakRepository struct {
	client *supabase.Client
}

// NewStreakRepository creates a new streak repository
func NewStreakRepository(client *supabase.Client) StreakRepository {
	return &streakRepository{client: client}
}

func (r *streakRepository) Upsert(ctx context.Context, streak *models.Streak) (*models.Streak, error) {
	data := map[string]interface{}{
		"user_id":       streak.UserID,
		"event_type_id": streak.EventTypeID,
		"streak_type":   streak.StreakType,
		"start_date":    streak.StartDate.Format("2006-01-02"),
		"length":        streak.Length,
		"is_active":     streak.IsActive,
	}

	if streak.EndDate != nil {
		data["end_date"] = streak.EndDate.Format("2006-01-02")
	}

	body, err := r.client.Upsert("streaks", data, "user_id,event_type_id,streak_type")
	if err != nil {
		return nil, fmt.Errorf("failed to upsert streak: %w", err)
	}

	var streaks []models.Streak
	if err := json.Unmarshal(body, &streaks); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(streaks) == 0 {
		return nil, fmt.Errorf("no streak returned")
	}

	return &streaks[0], nil
}

func (r *streakRepository) GetByUserID(ctx context.Context, userID string) ([]models.Streak, error) {
	// Use simple select without embedded resources to avoid schema cache issues
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"select":  "*",
		"order":   "length.desc",
	}

	body, err := r.client.Query("streaks", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get streaks: %w", err)
	}

	var streaks []models.Streak
	if err := json.Unmarshal(body, &streaks); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return streaks, nil
}

func (r *streakRepository) GetByUserIDAndEventType(ctx context.Context, userID, eventTypeID string) ([]models.Streak, error) {
	// Use simple select without embedded resources to avoid schema cache issues
	query := map[string]interface{}{
		"user_id":       fmt.Sprintf("eq.%s", userID),
		"event_type_id": fmt.Sprintf("eq.%s", eventTypeID),
		"select":        "*",
		"order":         "streak_type.asc",
	}

	body, err := r.client.Query("streaks", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get streaks: %w", err)
	}

	var streaks []models.Streak
	if err := json.Unmarshal(body, &streaks); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return streaks, nil
}

func (r *streakRepository) GetActiveByUserID(ctx context.Context, userID string) ([]models.Streak, error) {
	// Use simple select without embedded resources to avoid schema cache issues
	query := map[string]interface{}{
		"user_id":   fmt.Sprintf("eq.%s", userID),
		"is_active": "eq.true",
		"select":    "*",
		"order":     "length.desc",
	}

	body, err := r.client.Query("streaks", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get active streaks: %w", err)
	}

	var streaks []models.Streak
	if err := json.Unmarshal(body, &streaks); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return streaks, nil
}

func (r *streakRepository) DeleteByUserID(ctx context.Context, userID string) error {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	if err := r.client.DeleteWhere("streaks", query); err != nil {
		return fmt.Errorf("failed to delete streaks: %w", err)
	}

	return nil
}

func (r *streakRepository) DeleteByEventType(ctx context.Context, userID, eventTypeID string) error {
	query := map[string]interface{}{
		"user_id":       fmt.Sprintf("eq.%s", userID),
		"event_type_id": fmt.Sprintf("eq.%s", eventTypeID),
	}

	if err := r.client.DeleteWhere("streaks", query); err != nil {
		return fmt.Errorf("failed to delete streaks by event type: %w", err)
	}

	return nil
}
