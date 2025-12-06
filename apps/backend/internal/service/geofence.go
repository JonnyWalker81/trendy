package service

import (
	"context"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type geofenceService struct {
	geofenceRepo repository.GeofenceRepository
}

// NewGeofenceService creates a new geofence service
func NewGeofenceService(geofenceRepo repository.GeofenceRepository) GeofenceService {
	return &geofenceService{
		geofenceRepo: geofenceRepo,
	}
}

func (s *geofenceService) CreateGeofence(ctx context.Context, userID string, req *models.CreateGeofenceRequest) (*models.Geofence, error) {
	// Validate radius (should be between 50m and 10km)
	if req.Radius < 50 || req.Radius > 10000 {
		return nil, fmt.Errorf("radius must be between 50 and 10000 meters")
	}

	// Validate coordinates
	if req.Latitude < -90 || req.Latitude > 90 {
		return nil, fmt.Errorf("latitude must be between -90 and 90")
	}
	if req.Longitude < -180 || req.Longitude > 180 {
		return nil, fmt.Errorf("longitude must be between -180 and 180")
	}

	geofence := &models.Geofence{
		UserID:              userID,
		Name:                req.Name,
		Latitude:            req.Latitude,
		Longitude:           req.Longitude,
		Radius:              req.Radius,
		EventTypeEntryID:    req.EventTypeEntryID,
		EventTypeExitID:     req.EventTypeExitID,
		IsActive:            &req.IsActive,
		NotifyOnEntry:       &req.NotifyOnEntry,
		NotifyOnExit:        &req.NotifyOnExit,
		IOSRegionIdentifier: req.IOSRegionIdentifier,
	}

	return s.geofenceRepo.Create(ctx, geofence)
}

func (s *geofenceService) GetGeofence(ctx context.Context, userID, geofenceID string) (*models.Geofence, error) {
	geofence, err := s.geofenceRepo.GetByID(ctx, geofenceID)
	if err != nil {
		return nil, err
	}

	// Verify the geofence belongs to the user
	if geofence.UserID != userID {
		return nil, fmt.Errorf("geofence not found")
	}

	return geofence, nil
}

func (s *geofenceService) GetUserGeofences(ctx context.Context, userID string) ([]models.Geofence, error) {
	return s.geofenceRepo.GetByUserID(ctx, userID)
}

func (s *geofenceService) GetActiveGeofences(ctx context.Context, userID string) ([]models.Geofence, error) {
	return s.geofenceRepo.GetActiveByUserID(ctx, userID)
}

func (s *geofenceService) UpdateGeofence(ctx context.Context, userID, geofenceID string, req *models.UpdateGeofenceRequest) (*models.Geofence, error) {
	// Get existing geofence to verify ownership
	existingGeofence, err := s.geofenceRepo.GetByID(ctx, geofenceID)
	if err != nil {
		return nil, err
	}

	if existingGeofence.UserID != userID {
		return nil, fmt.Errorf("geofence not found")
	}

	// Validate updated values if provided
	if req.Radius != nil {
		if *req.Radius < 50 || *req.Radius > 10000 {
			return nil, fmt.Errorf("radius must be between 50 and 10000 meters")
		}
	}
	if req.Latitude != nil {
		if *req.Latitude < -90 || *req.Latitude > 90 {
			return nil, fmt.Errorf("latitude must be between -90 and 90")
		}
	}
	if req.Longitude != nil {
		if *req.Longitude < -180 || *req.Longitude > 180 {
			return nil, fmt.Errorf("longitude must be between -180 and 180")
		}
	}

	// Build update object
	update := &models.Geofence{}
	if req.Name != nil {
		update.Name = *req.Name
	}
	if req.Latitude != nil {
		update.Latitude = *req.Latitude
	}
	if req.Longitude != nil {
		update.Longitude = *req.Longitude
	}
	if req.Radius != nil {
		update.Radius = *req.Radius
	}
	if req.EventTypeEntryID != nil {
		update.EventTypeEntryID = req.EventTypeEntryID
	}
	if req.EventTypeExitID != nil {
		update.EventTypeExitID = req.EventTypeExitID
	}
	if req.IsActive != nil {
		update.IsActive = req.IsActive
	}
	if req.NotifyOnEntry != nil {
		update.NotifyOnEntry = req.NotifyOnEntry
	}
	if req.NotifyOnExit != nil {
		update.NotifyOnExit = req.NotifyOnExit
	}
	if req.IOSRegionIdentifier != nil {
		update.IOSRegionIdentifier = req.IOSRegionIdentifier
	}

	return s.geofenceRepo.Update(ctx, geofenceID, update)
}

func (s *geofenceService) DeleteGeofence(ctx context.Context, userID, geofenceID string) error {
	// Verify geofence exists and belongs to user
	geofence, err := s.geofenceRepo.GetByID(ctx, geofenceID)
	if err != nil {
		return err
	}

	if geofence.UserID != userID {
		return fmt.Errorf("geofence not found")
	}

	return s.geofenceRepo.Delete(ctx, geofenceID)
}
