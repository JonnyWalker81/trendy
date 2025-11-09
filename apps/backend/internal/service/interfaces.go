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
