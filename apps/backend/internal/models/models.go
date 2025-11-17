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
	ID                string                    `json:"id"`
	UserID            string                    `json:"user_id"`
	EventTypeID       string                    `json:"event_type_id"`
	Timestamp         time.Time                 `json:"timestamp"`
	Notes             *string                   `json:"notes,omitempty"`
	IsAllDay          bool                      `json:"is_all_day"`
	EndDate           *time.Time                `json:"end_date,omitempty"`
	SourceType        string                    `json:"source_type"`
	ExternalID        *string                   `json:"external_id,omitempty"`
	OriginalTitle     *string                   `json:"original_title,omitempty"`
	GeofenceID        *string                   `json:"geofence_id,omitempty"`
	LocationLatitude  *float64                  `json:"location_latitude,omitempty"`
	LocationLongitude *float64                  `json:"location_longitude,omitempty"`
	LocationName      *string                   `json:"location_name,omitempty"`
	Properties        map[string]PropertyValue  `json:"properties,omitempty"`
	CreatedAt         time.Time                 `json:"created_at"`
	UpdatedAt         time.Time                 `json:"updated_at"`
	EventType         *EventType                `json:"event_type,omitempty"`
}

// CreateEventRequest represents the request to create an event
type CreateEventRequest struct {
	EventTypeID       string                    `json:"event_type_id" binding:"required"`
	Timestamp         time.Time                 `json:"timestamp" binding:"required"`
	Notes             *string                   `json:"notes"`
	IsAllDay          bool                      `json:"is_all_day"`
	EndDate           *time.Time                `json:"end_date"`
	SourceType        string                    `json:"source_type"`
	ExternalID        *string                   `json:"external_id"`
	OriginalTitle     *string                   `json:"original_title"`
	GeofenceID        *string                   `json:"geofence_id"`
	LocationLatitude  *float64                  `json:"location_latitude"`
	LocationLongitude *float64                  `json:"location_longitude"`
	LocationName      *string                   `json:"location_name"`
	Properties        map[string]PropertyValue  `json:"properties,omitempty"`
}

// UpdateEventRequest represents the request to update an event
type UpdateEventRequest struct {
	EventTypeID       *string                    `json:"event_type_id"`
	Timestamp         *time.Time                 `json:"timestamp"`
	Notes             *string                    `json:"notes"`
	IsAllDay          *bool                      `json:"is_all_day"`
	EndDate           *time.Time                 `json:"end_date"`
	SourceType        *string                    `json:"source_type"`
	ExternalID        *string                    `json:"external_id"`
	OriginalTitle     *string                    `json:"original_title"`
	GeofenceID        *string                    `json:"geofence_id"`
	LocationLatitude  *float64                   `json:"location_latitude"`
	LocationLongitude *float64                   `json:"location_longitude"`
	LocationName      *string                    `json:"location_name"`
	Properties        *map[string]PropertyValue  `json:"properties,omitempty"`
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

// PropertyType represents the data type of a custom property
type PropertyType string

const (
	PropertyTypeText     PropertyType = "text"
	PropertyTypeNumber   PropertyType = "number"
	PropertyTypeBoolean  PropertyType = "boolean"
	PropertyTypeDate     PropertyType = "date"
	PropertyTypeSelect   PropertyType = "select"
	PropertyTypeDuration PropertyType = "duration"
	PropertyTypeURL      PropertyType = "url"
	PropertyTypeEmail    PropertyType = "email"
)

// PropertyDefinition represents a custom property schema for an event type
type PropertyDefinition struct {
	ID           string          `json:"id"`
	EventTypeID  string          `json:"event_type_id"`
	UserID       string          `json:"user_id"`
	Key          string          `json:"key"`
	Label        string          `json:"label"`
	PropertyType PropertyType    `json:"property_type"`
	Options      []string        `json:"options,omitempty"`
	DefaultValue interface{}     `json:"default_value,omitempty"`
	DisplayOrder int             `json:"display_order"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

// PropertyValue represents the actual value of a property on an event
type PropertyValue struct {
	Type  PropertyType `json:"type"`
	Value interface{}  `json:"value"`
}

// CreatePropertyDefinitionRequest represents the request to create a property definition
type CreatePropertyDefinitionRequest struct {
	EventTypeID  string          `json:"event_type_id" binding:"required"`
	Key          string          `json:"key" binding:"required"`
	Label        string          `json:"label" binding:"required"`
	PropertyType PropertyType    `json:"property_type" binding:"required"`
	Options      []string        `json:"options,omitempty"`
	DefaultValue interface{}     `json:"default_value,omitempty"`
	DisplayOrder int             `json:"display_order"`
}

// UpdatePropertyDefinitionRequest represents the request to update a property definition
type UpdatePropertyDefinitionRequest struct {
	Key          *string         `json:"key"`
	Label        *string         `json:"label"`
	PropertyType *PropertyType   `json:"property_type"`
	Options      *[]string       `json:"options"`
	DefaultValue interface{}     `json:"default_value"`
	DisplayOrder *int            `json:"display_order"`
}

// Geofence represents a geographic region for automatic event tracking
type Geofence struct {
	ID                 string     `json:"id"`
	UserID             string     `json:"user_id"`
	Name               string     `json:"name"`
	Latitude           float64    `json:"latitude"`
	Longitude          float64    `json:"longitude"`
	Radius             float64    `json:"radius"`
	EventTypeEntryID   *string    `json:"event_type_entry_id,omitempty"`
	EventTypeExitID    *string    `json:"event_type_exit_id,omitempty"`
	IsActive           bool       `json:"is_active"`
	NotifyOnEntry      bool       `json:"notify_on_entry"`
	NotifyOnExit       bool       `json:"notify_on_exit"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
	EventTypeEntry     *EventType `json:"event_type_entry,omitempty"`
	EventTypeExit      *EventType `json:"event_type_exit,omitempty"`
}

// CreateGeofenceRequest represents the request to create a geofence
type CreateGeofenceRequest struct {
	Name             string   `json:"name" binding:"required"`
	Latitude         float64  `json:"latitude" binding:"required,min=-90,max=90"`
	Longitude        float64  `json:"longitude" binding:"required,min=-180,max=180"`
	Radius           float64  `json:"radius" binding:"required,min=50,max=10000"`
	EventTypeEntryID *string  `json:"event_type_entry_id"`
	EventTypeExitID  *string  `json:"event_type_exit_id"`
	IsActive         bool     `json:"is_active"`
	NotifyOnEntry    bool     `json:"notify_on_entry"`
	NotifyOnExit     bool     `json:"notify_on_exit"`
}

// UpdateGeofenceRequest represents the request to update a geofence
type UpdateGeofenceRequest struct {
	Name             *string  `json:"name"`
	Latitude         *float64 `json:"latitude" binding:"omitempty,min=-90,max=90"`
	Longitude        *float64 `json:"longitude" binding:"omitempty,min=-180,max=180"`
	Radius           *float64 `json:"radius" binding:"omitempty,min=50,max=10000"`
	EventTypeEntryID *string  `json:"event_type_entry_id"`
	EventTypeExitID  *string  `json:"event_type_exit_id"`
	IsActive         *bool    `json:"is_active"`
	NotifyOnEntry    *bool    `json:"notify_on_entry"`
	NotifyOnExit     *bool    `json:"notify_on_exit"`
}
