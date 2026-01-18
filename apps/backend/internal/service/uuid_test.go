package service

import (
	"encoding/binary"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
)

// newUUIDv7AtTime creates a UUIDv7 with a specific timestamp.
// UUIDv7 format: first 48 bits are Unix milliseconds timestamp, then version (7),
// then random bits with variant set.
func newUUIDv7AtTime(t time.Time) uuid.UUID {
	var id uuid.UUID

	// Get Unix milliseconds
	ms := uint64(t.UnixMilli())

	// First 48 bits (6 bytes) are timestamp in big-endian
	id[0] = byte(ms >> 40)
	id[1] = byte(ms >> 32)
	id[2] = byte(ms >> 24)
	id[3] = byte(ms >> 16)
	id[4] = byte(ms >> 8)
	id[5] = byte(ms)

	// Byte 6: version (7) in upper 4 bits, random in lower 4 bits
	id[6] = 0x70 | (id[6] & 0x0F)

	// Byte 8: variant (10xx) in upper 2 bits
	id[8] = 0x80 | (id[8] & 0x3F)

	// Random bytes for the rest (bytes 7, 9-15)
	// Using fixed values for test determinism
	id[7] = 0x00
	id[9] = 0x00
	id[10] = 0x00
	id[11] = 0x00
	id[12] = 0x00
	id[13] = 0x00
	id[14] = 0x00
	id[15] = 0x01

	return id
}

func TestValidateUUIDv7_ValidUUID(t *testing.T) {
	// Generate a valid UUIDv7
	id, err := uuid.NewV7()
	if err != nil {
		t.Fatalf("uuid.NewV7() failed: %v", err)
	}
	err = ValidateUUIDv7(id.String())
	if err != nil {
		t.Errorf("ValidateUUIDv7(%s) = %v, want nil", id.String(), err)
	}
}

func TestValidateUUIDv7_UUIDv4Fails(t *testing.T) {
	// Generate a UUIDv4 (should fail)
	id := uuid.New() // uuid.New() generates v4
	err := ValidateUUIDv7(id.String())
	if err == nil {
		t.Error("ValidateUUIDv7(v4) = nil, want ErrNotUUIDv7")
	}
	if !errors.Is(err, ErrNotUUIDv7) {
		t.Errorf("ValidateUUIDv7(v4) = %v, want ErrNotUUIDv7", err)
	}
}

func TestValidateUUIDv7_MalformedUUID(t *testing.T) {
	testCases := []string{
		"not-a-uuid",
		"12345",
		"",
		"019471a0-0000-7000-8000-",
		"zzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz",
	}

	for _, tc := range testCases {
		err := ValidateUUIDv7(tc)
		if err == nil {
			t.Errorf("ValidateUUIDv7(%q) = nil, want ErrInvalidUUID", tc)
		}
		if !errors.Is(err, ErrInvalidUUID) {
			t.Errorf("ValidateUUIDv7(%q) = %v, want ErrInvalidUUID", tc, err)
		}
	}
}

func TestValidateUUIDv7_FutureTimestamp(t *testing.T) {
	// Create a UUIDv7 with timestamp 5 minutes in the future
	futureTime := time.Now().Add(5 * time.Minute)
	futureID := newUUIDv7AtTime(futureTime)

	err := ValidateUUIDv7(futureID.String())
	if err == nil {
		t.Error("ValidateUUIDv7(future) = nil, want ErrFutureTimestamp")
	}
	if !errors.Is(err, ErrFutureTimestamp) {
		t.Errorf("ValidateUUIDv7(future) = %v, want ErrFutureTimestamp", err)
	}
}

func TestValidateUUIDv7_PastTimestamp(t *testing.T) {
	// Create a UUIDv7 with timestamp in the past (should pass)
	pastTime := time.Now().Add(-24 * time.Hour)
	pastID := newUUIDv7AtTime(pastTime)

	err := ValidateUUIDv7(pastID.String())
	if err != nil {
		t.Errorf("ValidateUUIDv7(past) = %v, want nil", err)
	}
}

func TestValidateUUIDv7_JustUnderOneMinuteFuture(t *testing.T) {
	// Create a UUIDv7 with timestamp 30 seconds in the future (should pass)
	nearFutureTime := time.Now().Add(30 * time.Second)
	nearFutureID := newUUIDv7AtTime(nearFutureTime)

	err := ValidateUUIDv7(nearFutureID.String())
	if err != nil {
		t.Errorf("ValidateUUIDv7(30s future) = %v, want nil", err)
	}
}

func TestExtractUUIDv7Timestamp(t *testing.T) {
	// Generate a UUIDv7 and verify timestamp extraction
	now := time.Now()
	id, err := uuid.NewV7()
	if err != nil {
		t.Fatalf("uuid.NewV7() failed: %v", err)
	}

	extracted := ExtractUUIDv7Timestamp(id.String())
	if extracted.IsZero() {
		t.Error("ExtractUUIDv7Timestamp returned zero time")
	}

	// Extracted time should be within 1 second of now
	diff := extracted.Sub(now)
	if diff < -time.Second || diff > time.Second {
		t.Errorf("ExtractUUIDv7Timestamp time difference = %v, want within 1 second", diff)
	}
}

func TestExtractUUIDv7Timestamp_InvalidUUID(t *testing.T) {
	extracted := ExtractUUIDv7Timestamp("not-a-uuid")
	if !extracted.IsZero() {
		t.Errorf("ExtractUUIDv7Timestamp(invalid) = %v, want zero time", extracted)
	}
}

func TestExtractUUIDv7Timestamp_SpecificTime(t *testing.T) {
	// Create a UUIDv7 at a specific time and verify extraction
	specificTime := time.Date(2026, 1, 15, 12, 0, 0, 0, time.UTC)
	id := newUUIDv7AtTime(specificTime)

	extracted := ExtractUUIDv7Timestamp(id.String())

	// UUIDv7 has millisecond precision, so compare at that level
	if extracted.UnixMilli() != specificTime.UnixMilli() {
		t.Errorf("ExtractUUIDv7Timestamp = %v, want %v", extracted.UnixMilli(), specificTime.UnixMilli())
	}
}

// Ensure binary import is used
var _ = binary.BigEndian
