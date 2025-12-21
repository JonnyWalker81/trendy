package models

import (
	"encoding/json"
	"time"
)

// EntityType represents the type of entity in the change log
type EntityType string

const (
	EntityTypeEvent              EntityType = "event"
	EntityTypeEventType          EntityType = "event_type"
	EntityTypeGeofence           EntityType = "geofence"
	EntityTypePropertyDefinition EntityType = "property_definition"
)

// Operation represents the type of change operation
type Operation string

const (
	OperationCreate Operation = "create"
	OperationUpdate Operation = "update"
	OperationDelete Operation = "delete"
)

// ChangeEntry represents a single entry in the change log
type ChangeEntry struct {
	ID         int64           `json:"id"`                    // Monotonic cursor
	EntityType EntityType      `json:"entity_type"`           // Type of entity changed
	Operation  Operation       `json:"operation"`             // Type of change
	EntityID   string          `json:"entity_id"`             // ID of the affected entity
	UserID     string          `json:"user_id,omitempty"`     // Owner of the entity (omitted in responses)
	Data       json.RawMessage `json:"data,omitempty"`        // Full entity data for create/update
	DeletedAt  *time.Time      `json:"deleted_at,omitempty"`  // Timestamp for delete operations
	CreatedAt  time.Time       `json:"created_at"`            // When the change was recorded
}

// ChangeFeedResponse represents the response from the changes endpoint
type ChangeFeedResponse struct {
	Changes    []ChangeEntry `json:"changes"`
	NextCursor int64         `json:"next_cursor"` // 0 if no more changes
	HasMore    bool          `json:"has_more"`
}

// IdempotencyKey represents a stored idempotency key record
type IdempotencyKey struct {
	ID           string          `json:"id"`
	Key          string          `json:"key"`
	Route        string          `json:"route"`
	UserID       string          `json:"user_id"`
	RequestHash  *string         `json:"request_hash,omitempty"`
	ResponseBody json.RawMessage `json:"response_body"`
	StatusCode   int             `json:"status_code"`
	CreatedAt    time.Time       `json:"created_at"`
}

// ChangeLogInput represents input for creating a change log entry
type ChangeLogInput struct {
	EntityType EntityType
	Operation  Operation
	EntityID   string
	UserID     string
	Data       interface{} // Will be marshaled to JSON
	DeletedAt  *time.Time  // Set for delete operations
}
