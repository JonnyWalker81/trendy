package service

import (
	"context"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
)

// EventService defines the interface for event business logic
type EventService interface {
	CreateEvent(ctx context.Context, userID string, req *models.CreateEventRequest) (*models.Event, error)
	GetEvent(ctx context.Context, userID, eventID string) (*models.Event, error)
	GetUserEvents(ctx context.Context, userID string, limit, offset int) ([]models.Event, error)
	ExportEvents(ctx context.Context, userID string, startDate, endDate *time.Time, eventTypeIDs []string) ([]models.Event, error)
	UpdateEvent(ctx context.Context, userID, eventID string, req *models.UpdateEventRequest) (*models.Event, error)
	DeleteEvent(ctx context.Context, userID, eventID string) error
}

// EventTypeService defines the interface for event type business logic
type EventTypeService interface {
	CreateEventType(ctx context.Context, userID string, req *models.CreateEventTypeRequest) (*models.EventType, error)
	GetEventType(ctx context.Context, userID, eventTypeID string) (*models.EventType, error)
	GetUserEventTypes(ctx context.Context, userID string) ([]models.EventType, error)
	UpdateEventType(ctx context.Context, userID, eventTypeID string, req *models.UpdateEventTypeRequest) (*models.EventType, error)
	DeleteEventType(ctx context.Context, userID, eventTypeID string) error
}

// AnalyticsService defines the interface for analytics business logic
type AnalyticsService interface {
	GetSummary(ctx context.Context, userID string) (*models.AnalyticsSummary, error)
	GetTrends(ctx context.Context, userID string, period string, startDate, endDate time.Time) ([]models.TrendData, error)
	GetEventTypeAnalytics(ctx context.Context, userID, eventTypeID string, period string, startDate, endDate time.Time) (*models.TrendData, error)
}

// AuthService defines the interface for authentication business logic
type AuthService interface {
	Login(ctx context.Context, req *models.LoginRequest) (*models.AuthResponse, error)
	Signup(ctx context.Context, req *models.SignupRequest) (*models.AuthResponse, error)
	GetUserByID(ctx context.Context, userID string) (*models.User, error)
}

// PropertyDefinitionService defines the interface for property definition business logic
type PropertyDefinitionService interface {
	CreatePropertyDefinition(ctx context.Context, userID string, req *models.CreatePropertyDefinitionRequest) (*models.PropertyDefinition, error)
	GetPropertyDefinition(ctx context.Context, userID, propertyDefID string) (*models.PropertyDefinition, error)
	GetPropertyDefinitionsByEventType(ctx context.Context, userID, eventTypeID string) ([]models.PropertyDefinition, error)
	UpdatePropertyDefinition(ctx context.Context, userID, propertyDefID string, req *models.UpdatePropertyDefinitionRequest) (*models.PropertyDefinition, error)
	DeletePropertyDefinition(ctx context.Context, userID, propertyDefID string) error
}

// GeofenceService defines the interface for geofence business logic
type GeofenceService interface {
	CreateGeofence(ctx context.Context, userID string, req *models.CreateGeofenceRequest) (*models.Geofence, error)
	GetGeofence(ctx context.Context, userID, geofenceID string) (*models.Geofence, error)
	GetUserGeofences(ctx context.Context, userID string) ([]models.Geofence, error)
	GetActiveGeofences(ctx context.Context, userID string) ([]models.Geofence, error)
	UpdateGeofence(ctx context.Context, userID, geofenceID string, req *models.UpdateGeofenceRequest) (*models.Geofence, error)
	DeleteGeofence(ctx context.Context, userID, geofenceID string) error
}

// IntelligenceService defines the interface for insights and correlation analysis
type IntelligenceService interface {
	GetInsights(ctx context.Context, userID string) (*models.InsightsResponse, error)
	ComputeInsights(ctx context.Context, userID string) error
	RefreshIfStale(ctx context.Context, userID string) error
	InvalidateInsights(ctx context.Context, userID string) error
	GetWeeklySummary(ctx context.Context, userID string) ([]models.WeeklySummary, error)
	GetStreaks(ctx context.Context, userID string) ([]models.Streak, error)
}
