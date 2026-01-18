package service

import (
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

var (
	// ErrInvalidUUID indicates the string is not a valid UUID format
	ErrInvalidUUID = errors.New("invalid UUID format")
	// ErrNotUUIDv7 indicates the UUID is not version 7
	ErrNotUUIDv7 = errors.New("UUID must be version 7")
	// ErrFutureTimestamp indicates the UUIDv7 timestamp is too far in the future
	ErrFutureTimestamp = errors.New("UUID timestamp is too far in the future")
)

// MaxFutureMinutes is the tolerance for UUIDv7 timestamp validation (1 minute per CONTEXT.md)
const MaxFutureMinutes = 1

// ValidateUUIDv7 validates that a string is a valid UUIDv7 with timestamp within bounds.
// Returns nil if valid, or ErrInvalidUUID, ErrNotUUIDv7, or ErrFutureTimestamp.
func ValidateUUIDv7(id string) error {
	parsed, err := uuid.Parse(id)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrInvalidUUID, err)
	}

	if parsed.Version() != 7 {
		return fmt.Errorf("%w: got version %d", ErrNotUUIDv7, parsed.Version())
	}

	// Extract timestamp from UUIDv7
	// UUID.Time() returns 100-nanosecond intervals since Oct 15, 1582
	// For UUIDv7, this is derived from embedded Unix milliseconds
	sec, nsec := parsed.Time().UnixTime()
	timestamp := time.Unix(sec, nsec)

	// Reject if more than MaxFutureMinutes in the future
	maxAllowed := time.Now().Add(time.Duration(MaxFutureMinutes) * time.Minute)
	if timestamp.After(maxAllowed) {
		return fmt.Errorf("%w: %v is more than %d minute(s) ahead",
			ErrFutureTimestamp, timestamp.Format(time.RFC3339), MaxFutureMinutes)
	}

	return nil
}

// ExtractUUIDv7Timestamp extracts the embedded timestamp from a UUIDv7.
// Returns zero time if parsing fails.
func ExtractUUIDv7Timestamp(id string) time.Time {
	parsed, err := uuid.Parse(id)
	if err != nil {
		return time.Time{}
	}
	sec, nsec := parsed.Time().UnixTime()
	return time.Unix(sec, nsec)
}
