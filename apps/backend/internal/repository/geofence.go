package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type geofenceRepository struct {
	client *supabase.Client
}

// NewGeofenceRepository creates a new geofence repository
func NewGeofenceRepository(client *supabase.Client) GeofenceRepository {
	return &geofenceRepository{client: client}
}

func (r *geofenceRepository) Create(ctx context.Context, geofence *models.Geofence) (*models.Geofence, error) {
	data := map[string]interface{}{
		"user_id":         geofence.UserID,
		"name":            geofence.Name,
		"latitude":        geofence.Latitude,
		"longitude":       geofence.Longitude,
		"radius":          geofence.Radius,
		"is_active":       geofence.IsActive,
		"notify_on_entry": geofence.NotifyOnEntry,
		"notify_on_exit":  geofence.NotifyOnExit,
	}

	if geofence.EventTypeEntryID != nil {
		data["event_type_entry_id"] = *geofence.EventTypeEntryID
	}
	if geofence.EventTypeExitID != nil {
		data["event_type_exit_id"] = *geofence.EventTypeExitID
	}

	// Extract user token from context for RLS
	userToken := ""
	if token := ctx.Value("user_token"); token != nil {
		if tokenStr, ok := token.(string); ok {
			userToken = tokenStr
		}
	}

	body, err := r.client.InsertWithToken("geofences", data, userToken)
	if err != nil {
		return nil, fmt.Errorf("failed to create geofence: %w", err)
	}

	var geofences []models.Geofence
	if err := json.Unmarshal(body, &geofences); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(geofences) == 0 {
		return nil, fmt.Errorf("no geofence returned")
	}

	return &geofences[0], nil
}

func (r *geofenceRepository) GetByID(ctx context.Context, id string) (*models.Geofence, error) {
	query := map[string]interface{}{
		"id": fmt.Sprintf("eq.%s", id),
	}

	body, err := r.client.Query("geofences", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get geofence: %w", err)
	}

	var geofences []models.Geofence
	if err := json.Unmarshal(body, &geofences); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(geofences) == 0 {
		return nil, fmt.Errorf("geofence not found")
	}

	return &geofences[0], nil
}

func (r *geofenceRepository) GetByUserID(ctx context.Context, userID string) ([]models.Geofence, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"order":   "created_at.desc",
	}

	body, err := r.client.Query("geofences", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get geofences: %w", err)
	}

	var geofences []models.Geofence
	if err := json.Unmarshal(body, &geofences); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return geofences, nil
}

func (r *geofenceRepository) GetActiveByUserID(ctx context.Context, userID string) ([]models.Geofence, error) {
	query := map[string]interface{}{
		"user_id":   fmt.Sprintf("eq.%s", userID),
		"is_active": "eq.true",
		"order":     "created_at.desc",
	}

	body, err := r.client.Query("geofences", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get active geofences: %w", err)
	}

	var geofences []models.Geofence
	if err := json.Unmarshal(body, &geofences); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return geofences, nil
}

func (r *geofenceRepository) Update(ctx context.Context, id string, geofence *models.Geofence) (*models.Geofence, error) {
	data := make(map[string]interface{})

	if geofence.Name != "" {
		data["name"] = geofence.Name
	}
	if geofence.Latitude != 0 {
		data["latitude"] = geofence.Latitude
	}
	if geofence.Longitude != 0 {
		data["longitude"] = geofence.Longitude
	}
	if geofence.Radius != 0 {
		data["radius"] = geofence.Radius
	}

	// Always update these boolean fields (they have explicit values)
	data["is_active"] = geofence.IsActive
	data["notify_on_entry"] = geofence.NotifyOnEntry
	data["notify_on_exit"] = geofence.NotifyOnExit

	// Handle optional foreign keys
	if geofence.EventTypeEntryID != nil {
		data["event_type_entry_id"] = *geofence.EventTypeEntryID
	}
	if geofence.EventTypeExitID != nil {
		data["event_type_exit_id"] = *geofence.EventTypeExitID
	}

	body, err := r.client.Update("geofences", id, data)
	if err != nil {
		return nil, fmt.Errorf("failed to update geofence: %w", err)
	}

	var geofences []models.Geofence
	if err := json.Unmarshal(body, &geofences); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(geofences) == 0 {
		return nil, fmt.Errorf("geofence not found")
	}

	return &geofences[0], nil
}

func (r *geofenceRepository) Delete(ctx context.Context, id string) error {
	if err := r.client.Delete("geofences", id); err != nil {
		return fmt.Errorf("failed to delete geofence: %w", err)
	}
	return nil
}
