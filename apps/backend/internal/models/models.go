package models

import "time"

// User represents a user in the system
type User struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// EventType represents a category of events
type EventType struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Name      string    `json:"name"`
	Color     string    `json:"color"`
	Icon      string    `json:"icon"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Event represents a tracked event
type Event struct {
	ID            string     `json:"id"`
	UserID        string     `json:"user_id"`
	EventTypeID   string     `json:"event_type_id"`
	Timestamp     time.Time  `json:"timestamp"`
	Notes         *string    `json:"notes,omitempty"`
	IsAllDay      bool       `json:"is_all_day"`
	EndDate       *time.Time `json:"end_date,omitempty"`
	SourceType    string     `json:"source_type"`
	ExternalID    *string    `json:"external_id,omitempty"`
	OriginalTitle *string    `json:"original_title,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	EventType     *EventType `json:"event_type,omitempty"`
}

// CreateEventRequest represents the request to create an event
type CreateEventRequest struct {
	EventTypeID   string     `json:"event_type_id" binding:"required"`
	Timestamp     time.Time  `json:"timestamp" binding:"required"`
	Notes         *string    `json:"notes"`
	IsAllDay      bool       `json:"is_all_day"`
	EndDate       *time.Time `json:"end_date"`
	SourceType    string     `json:"source_type"`
	ExternalID    *string    `json:"external_id"`
	OriginalTitle *string    `json:"original_title"`
}

// UpdateEventRequest represents the request to update an event
type UpdateEventRequest struct {
	EventTypeID   *string    `json:"event_type_id"`
	Timestamp     *time.Time `json:"timestamp"`
	Notes         *string    `json:"notes"`
	IsAllDay      *bool      `json:"is_all_day"`
	EndDate       *time.Time `json:"end_date"`
	SourceType    *string    `json:"source_type"`
	ExternalID    *string    `json:"external_id"`
	OriginalTitle *string    `json:"original_title"`
}

// CreateEventTypeRequest represents the request to create an event type
type CreateEventTypeRequest struct {
	Name  string `json:"name" binding:"required"`
	Color string `json:"color" binding:"required"`
	Icon  string `json:"icon" binding:"required"`
}

// UpdateEventTypeRequest represents the request to update an event type
type UpdateEventTypeRequest struct {
	Name  *string `json:"name"`
	Color *string `json:"color"`
	Icon  *string `json:"icon"`
}

// LoginRequest represents the login request
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

// SignupRequest represents the signup request
type SignupRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

// AuthResponse represents the authentication response
type AuthResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	User         User   `json:"user"`
}

// AnalyticsSummary represents analytics summary data
type AnalyticsSummary struct {
	TotalEvents     int64              `json:"total_events"`
	EventTypeCounts map[string]int64   `json:"event_type_counts"`
	RecentEvents    []Event            `json:"recent_events"`
}

// TrendData represents trend data for a specific event type
type TrendData struct {
	EventTypeID string                 `json:"event_type_id"`
	Period      string                 `json:"period"` // "week", "month", "year"
	Data        []TimeSeriesDataPoint  `json:"data"`
	Average     float64                `json:"average"`
	Trend       string                 `json:"trend"` // "increasing", "decreasing", "stable"
}

// TimeSeriesDataPoint represents a data point in time series
type TimeSeriesDataPoint struct {
	Date  time.Time `json:"date"`
	Count int64     `json:"count"`
}
