package repository

import (
	"context"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
)

// UpsertResult represents the outcome of a single upsert operation in a batch.
type UpsertResult struct {
	Index  int    // Position in original request
	ID     string // Event ID
	Action string // "created" | "deduplicated" | "failed"
	Error  error  // Non-nil if Action is "failed"
}

// EventRepository defines the interface for event data access
type EventRepository interface {
	Create(ctx context.Context, event *models.Event) (*models.Event, error)
	CreateBatch(ctx context.Context, events []models.Event) ([]models.Event, error)
	GetByID(ctx context.Context, id string) (*models.Event, error)
	GetByUserID(ctx context.Context, userID string, limit, offset int) ([]models.Event, error)
	GetByUserIDAndDateRange(ctx context.Context, userID string, startDate, endDate time.Time) ([]models.Event, error)
	GetForExport(ctx context.Context, userID string, startDate, endDate *time.Time, eventTypeIDs []string) ([]models.Event, error)
	Update(ctx context.Context, id string, event *models.Event) (*models.Event, error)
	Delete(ctx context.Context, id string) error
	CountByEventType(ctx context.Context, userID string) (map[string]int64, error)
	// Upsert creates or updates an event by ID. Returns (event, wasCreated, error).
	// wasCreated is true if this was a new insert, false if existing was updated.
	Upsert(ctx context.Context, event *models.Event) (*models.Event, bool, error)
	// UpsertBatch creates or updates multiple events by ID.
	// Returns (events, results) where results contains per-item status.
	UpsertBatch(ctx context.Context, events []models.Event) ([]models.Event, []UpsertResult, error)
	// GetByIDs retrieves events by their IDs.
	GetByIDs(ctx context.Context, ids []string) ([]models.Event, error)
	// UpsertHealthKitEvent inserts or updates a HealthKit event by sample ID.
	// Returns (event, wasCreated, error) where wasCreated indicates if this was a new insert.
	UpsertHealthKitEvent(ctx context.Context, event *models.Event) (*models.Event, bool, error)
	// UpsertHealthKitEventsBatch inserts or updates multiple HealthKit events.
	// Returns (events, createdIDs, error) where createdIDs contains IDs of newly created events.
	UpsertHealthKitEventsBatch(ctx context.Context, events []models.Event) ([]models.Event, []string, error)
	// GetByHealthKitSampleIDs retrieves events by their HealthKit sample IDs for a user.
	GetByHealthKitSampleIDs(ctx context.Context, userID string, sampleIDs []string) ([]models.Event, error)
	// CountByUser returns total events for a user
	CountByUser(ctx context.Context, userID string) (int64, error)
	// CountHealthKitByUser returns HealthKit events for a user
	CountHealthKitByUser(ctx context.Context, userID string) (int64, error)
	// GetLatestTimestamp returns the most recent event updated_at for a user
	GetLatestTimestamp(ctx context.Context, userID string) (*time.Time, error)
	// GetLatestHealthKitTimestamp returns the most recent HealthKit event timestamp for a user
	GetLatestHealthKitTimestamp(ctx context.Context, userID string) (*time.Time, error)
}

// EventTypeRepository defines the interface for event type data access
type EventTypeRepository interface {
	Create(ctx context.Context, eventType *models.EventType) (*models.EventType, error)
	GetByID(ctx context.Context, id string) (*models.EventType, error)
	GetByUserID(ctx context.Context, userID string) ([]models.EventType, error)
	Update(ctx context.Context, id string, eventType *models.EventType) (*models.EventType, error)
	Delete(ctx context.Context, id string) error
	// CountByUser returns total event types for a user
	CountByUser(ctx context.Context, userID string) (int64, error)
	// GetLatestTimestamp returns the most recent event_type updated_at for a user
	GetLatestTimestamp(ctx context.Context, userID string) (*time.Time, error)
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
