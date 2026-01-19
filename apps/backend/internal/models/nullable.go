package models

import (
	"encoding/json"
	"time"
)

// NullableString represents a string field that can distinguish between:
// - Field absent in JSON: Set=false, Valid=false, Value=""
// - Field present with null: Set=true, Valid=false, Value=""
// - Field present with value: Set=true, Valid=true, Value="the value"
//
// This is needed because Go's standard JSON unmarshaling treats both
// "field absent" and "field: null" as nil for pointer types.
type NullableString struct {
	Value string
	Valid bool // true if Value is not null
	Set   bool // true if field was present in JSON
}

// UnmarshalJSON implements custom JSON unmarshaling for NullableString.
func (ns *NullableString) UnmarshalJSON(data []byte) error {
	ns.Set = true // Field was present in JSON

	if string(data) == "null" {
		ns.Valid = false
		ns.Value = ""
		return nil
	}

	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return err
	}
	ns.Value = s
	ns.Valid = true
	return nil
}

// MarshalJSON implements custom JSON marshaling for NullableString.
func (ns NullableString) MarshalJSON() ([]byte, error) {
	if !ns.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(ns.Value)
}

// ToPtr converts NullableString to *string for use with existing code.
// Returns nil if Valid is false, otherwise returns pointer to Value.
func (ns NullableString) ToPtr() *string {
	if !ns.Valid {
		return nil
	}
	return &ns.Value
}

// NullableTime represents a time field that can distinguish between:
// - Field absent in JSON: Set=false, Valid=false
// - Field present with null: Set=true, Valid=false
// - Field present with value: Set=true, Valid=true, Value=time
type NullableTime struct {
	Value time.Time
	Valid bool
	Set   bool
}

// UnmarshalJSON implements custom JSON unmarshaling for NullableTime.
func (nt *NullableTime) UnmarshalJSON(data []byte) error {
	nt.Set = true

	if string(data) == "null" {
		nt.Valid = false
		nt.Value = time.Time{}
		return nil
	}

	var t time.Time
	if err := json.Unmarshal(data, &t); err != nil {
		return err
	}
	nt.Value = t
	nt.Valid = true
	return nil
}

// MarshalJSON implements custom JSON marshaling for NullableTime.
func (nt NullableTime) MarshalJSON() ([]byte, error) {
	if !nt.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(nt.Value)
}

// ToPtr converts NullableTime to *time.Time for use with existing code.
func (nt NullableTime) ToPtr() *time.Time {
	if !nt.Valid {
		return nil
	}
	return &nt.Value
}
