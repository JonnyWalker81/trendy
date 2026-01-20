package service

import (
	"context"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

var validPermissionStatuses = map[string]bool{
	"granted":       true,
	"denied":        true,
	"skipped":       true,
	"not_requested": true,
}

func validatePermissionStatus(status *string, fieldName string) error {
	if status == nil {
		return nil
	}
	if !validPermissionStatuses[*status] {
		return fmt.Errorf("invalid %s: must be one of granted, denied, skipped, not_requested", fieldName)
	}
	return nil
}

type onboardingService struct {
	repo repository.OnboardingStatusRepository
}

// NewOnboardingService creates a new onboarding service
func NewOnboardingService(repo repository.OnboardingStatusRepository) OnboardingService {
	return &onboardingService{repo: repo}
}

func (s *onboardingService) GetOnboardingStatus(ctx context.Context, userID string) (*models.OnboardingStatus, error) {
	return s.repo.GetOrCreate(ctx, userID)
}

func (s *onboardingService) UpdateOnboardingStatus(ctx context.Context, userID string, req *models.UpdateOnboardingStatusRequest) (*models.OnboardingStatus, error) {
	// Validate permission status values
	if err := validatePermissionStatus(req.NotificationsStatus, "notifications_status"); err != nil {
		return nil, err
	}
	if err := validatePermissionStatus(req.HealthkitStatus, "healthkit_status"); err != nil {
		return nil, err
	}
	if err := validatePermissionStatus(req.LocationStatus, "location_status"); err != nil {
		return nil, err
	}

	// Build OnboardingStatus from request
	status := &models.OnboardingStatus{
		UserID:                   userID,
		Completed:                req.Completed,
		WelcomeCompletedAt:       req.WelcomeCompletedAt,
		AuthCompletedAt:          req.AuthCompletedAt,
		PermissionsCompletedAt:   req.PermissionsCompletedAt,
		NotificationsStatus:      req.NotificationsStatus,
		NotificationsCompletedAt: req.NotificationsCompletedAt,
		HealthkitStatus:          req.HealthkitStatus,
		HealthkitCompletedAt:     req.HealthkitCompletedAt,
		LocationStatus:           req.LocationStatus,
		LocationCompletedAt:      req.LocationCompletedAt,
	}

	return s.repo.Update(ctx, userID, status)
}

func (s *onboardingService) ResetOnboardingStatus(ctx context.Context, userID string) (*models.OnboardingStatus, error) {
	return s.repo.SoftReset(ctx, userID)
}
