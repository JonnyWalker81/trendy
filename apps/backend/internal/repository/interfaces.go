package repository

import (
	"context"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
)

// EventRepository defines the interface for event data access
type EventRepository interface {
	Create(ctx context.Context, event *models.Event) (*models.Event, error)
	GetByID(ctx context.Context, id string) (*models.Event, error)
	GetByUserID(ctx context.Context, userID string, limit, offset int) ([]models.Event, error)
	GetByUserIDAndDateRange(ctx context.Context, userID string, startDate, endDate time.Time) ([]models.Event, error)
	GetForExport(ctx context.Context, userID string, startDate, endDate *time.Time, eventTypeIDs []string) ([]models.Event, error)
	Update(ctx context.Context, id string, event *models.Event) (*models.Event, error)
	Delete(ctx context.Context, id string) error
	CountByEventType(ctx context.Context, userID string) (map[string]int64, error)
}

// EventTypeRepository defines the interface for event type data access
type EventTypeRepository interface {
	Create(ctx context.Context, eventType *models.EventType) (*models.EventType, error)
	GetByID(ctx context.Context, id string) (*models.EventType, error)
	GetByUserID(ctx context.Context, userID string) ([]models.EventType, error)
	Update(ctx context.Context, id string, eventType *models.EventType) (*models.EventType, error)
	Delete(ctx context.Context, id string) error
}

// UserRepository defines the interface for user data access
type UserRepository interface {
	GetByID(ctx context.Context, id string) (*models.User, error)
	GetByEmail(ctx context.Context, email string) (*models.User, error)
	Create(ctx context.Context, user *models.User) (*models.User, error)
}

// PropertyDefinitionRepository defines the interface for property definition data access
type PropertyDefinitionRepository interface {
	Create(ctx context.Context, def *models.PropertyDefinition) (*models.PropertyDefinition, error)
	GetByID(ctx context.Context, id string) (*models.PropertyDefinition, error)
	GetByEventTypeID(ctx context.Context, eventTypeID string) ([]models.PropertyDefinition, error)
	Update(ctx context.Context, id string, def *models.PropertyDefinition) (*models.PropertyDefinition, error)
	Delete(ctx context.Context, id string) error
}

// GeofenceRepository defines the interface for geofence data access
type GeofenceRepository interface {
	Create(ctx context.Context, geofence *models.Geofence) (*models.Geofence, error)
	GetByID(ctx context.Context, id string) (*models.Geofence, error)
	GetByUserID(ctx context.Context, userID string) ([]models.Geofence, error)
	GetActiveByUserID(ctx context.Context, userID string) ([]models.Geofence, error)
	Update(ctx context.Context, id string, geofence *models.Geofence) (*models.Geofence, error)
	Delete(ctx context.Context, id string) error
}

// InsightRepository defines the interface for insight data access
type InsightRepository interface {
	Create(ctx context.Context, insight *models.Insight) (*models.Insight, error)
	BulkCreate(ctx context.Context, insights []models.Insight) error
	GetByUserID(ctx context.Context, userID string) ([]models.Insight, error)
	GetValidByUserID(ctx context.Context, userID string) ([]models.Insight, error)
	GetByType(ctx context.Context, userID string, insightType models.InsightType) ([]models.Insight, error)
	DeleteByUserID(ctx context.Context, userID string) error
	DeleteExpired(ctx context.Context, userID string) error
	InvalidateAll(ctx context.Context, userID string) error
}

// DailyAggregateRepository defines the interface for daily aggregate data access
type DailyAggregateRepository interface {
	Upsert(ctx context.Context, agg *models.DailyAggregate) (*models.DailyAggregate, error)
	BulkUpsert(ctx context.Context, aggs []models.DailyAggregate) error
	GetByUserID(ctx context.Context, userID string) ([]models.DailyAggregate, error)
	GetByUserIDAndDateRange(ctx context.Context, userID string, startDate, endDate time.Time) ([]models.DailyAggregate, error)
	GetByUserIDAndEventType(ctx context.Context, userID, eventTypeID string, startDate, endDate time.Time) ([]models.DailyAggregate, error)
	DeleteByUserID(ctx context.Context, userID string) error
	DeleteOlderThan(ctx context.Context, userID string, date time.Time) error
}

// StreakRepository defines the interface for streak data access
type StreakRepository interface {
	Upsert(ctx context.Context, streak *models.Streak) (*models.Streak, error)
	GetByUserID(ctx context.Context, userID string) ([]models.Streak, error)
	GetByUserIDAndEventType(ctx context.Context, userID, eventTypeID string) ([]models.Streak, error)
	GetActiveByUserID(ctx context.Context, userID string) ([]models.Streak, error)
	DeleteByUserID(ctx context.Context, userID string) error
	DeleteByEventType(ctx context.Context, userID, eventTypeID string) error
}
