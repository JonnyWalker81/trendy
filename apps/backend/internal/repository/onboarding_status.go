package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type onboardingStatusRepository struct {
	client *supabase.Client
}

// NewOnboardingStatusRepository creates a new onboarding status repository
func NewOnboardingStatusRepository(client *supabase.Client) OnboardingStatusRepository {
	return &onboardingStatusRepository{client: client}
}

func (r *onboardingStatusRepository) GetOrCreate(ctx context.Context, userID string) (*models.OnboardingStatus, error) {
	// Use Upsert with user_id as conflict column - atomically creates default if none exists
	data := map[string]interface{}{
		"user_id":   userID,
		"completed": false,
	}

	body, err := r.client.Upsert("onboarding_status", data, "user_id")
	if err != nil {
		return nil, fmt.Errorf("failed to get or create onboarding status: %w", err)
	}

	var statuses []models.OnboardingStatus
	if err := json.Unmarshal(body, &statuses); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(statuses) == 0 {
		return nil, fmt.Errorf("no onboarding status returned")
	}

	return &statuses[0], nil
}

func (r *onboardingStatusRepository) Update(ctx context.Context, userID string, status *models.OnboardingStatus) (*models.OnboardingStatus, error) {
	data := map[string]interface{}{
		"completed":                  status.Completed,
		"welcome_completed_at":       status.WelcomeCompletedAt,
		"auth_completed_at":          status.AuthCompletedAt,
		"permissions_completed_at":   status.PermissionsCompletedAt,
		"notifications_status":       status.NotificationsStatus,
		"notifications_completed_at": status.NotificationsCompletedAt,
		"healthkit_status":           status.HealthkitStatus,
		"healthkit_completed_at":     status.HealthkitCompletedAt,
		"location_status":            status.LocationStatus,
		"location_completed_at":      status.LocationCompletedAt,
	}

	// Use UpdateWhere since primary key is user_id, not id
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	body, err := r.client.UpdateWhere("onboarding_status", query, data)
	if err != nil {
		return nil, fmt.Errorf("failed to update onboarding status: %w", err)
	}

	var statuses []models.OnboardingStatus
	if err := json.Unmarshal(body, &statuses); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(statuses) == 0 {
		return nil, fmt.Errorf("onboarding status not found")
	}

	return &statuses[0], nil
}

func (r *onboardingStatusRepository) SoftReset(ctx context.Context, userID string) (*models.OnboardingStatus, error) {
	// Soft reset: clear step completion timestamps but preserve permission fields
	data := map[string]interface{}{
		"completed":                false,
		"welcome_completed_at":     nil,
		"auth_completed_at":        nil,
		"permissions_completed_at": nil,
		// Note: permission fields (notifications_status, healthkit_status, location_status)
		// are NOT included - they preserve their current values
	}

	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	body, err := r.client.UpdateWhere("onboarding_status", query, data)
	if err != nil {
		return nil, fmt.Errorf("failed to soft reset onboarding status: %w", err)
	}

	var statuses []models.OnboardingStatus
	if err := json.Unmarshal(body, &statuses); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(statuses) == 0 {
		return nil, fmt.Errorf("onboarding status not found")
	}

	return &statuses[0], nil
}
