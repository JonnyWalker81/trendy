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
