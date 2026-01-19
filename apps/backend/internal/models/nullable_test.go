package models

import (
	"encoding/json"
	"testing"
	"time"
)

func TestNullableString_UnmarshalJSON(t *testing.T) {
	tests := []struct {
		name      string
		json      string
		wantSet   bool
		wantValid bool
		wantValue string
	}{
		{
			name:      "field present with string value",
			json:      `{"notes": "hello"}`,
			wantSet:   true,
			wantValid: true,
			wantValue: "hello",
		},
		{
			name:      "field present with null value",
			json:      `{"notes": null}`,
			wantSet:   true,
			wantValid: false,
			wantValue: "",
		},
		{
			name:      "field absent",
			json:      `{}`,
			wantSet:   false,
			wantValid: false,
			wantValue: "",
		},
		{
			name:      "field present with empty string",
			json:      `{"notes": ""}`,
			wantSet:   true,
			wantValid: true,
			wantValue: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result struct {
				Notes NullableString `json:"notes"`
			}
			err := json.Unmarshal([]byte(tt.json), &result)
			if err != nil {
				t.Fatalf("Unmarshal error: %v", err)
			}

			if result.Notes.Set != tt.wantSet {
				t.Errorf("Set = %v, want %v", result.Notes.Set, tt.wantSet)
			}
			if result.Notes.Valid != tt.wantValid {
				t.Errorf("Valid = %v, want %v", result.Notes.Valid, tt.wantValid)
			}
			if result.Notes.Value != tt.wantValue {
				t.Errorf("Value = %q, want %q", result.Notes.Value, tt.wantValue)
			}
		})
	}
}

func TestNullableString_ToPtr(t *testing.T) {
	tests := []struct {
		name    string
		ns      NullableString
		wantNil bool
		wantVal string
	}{
		{
			name:    "valid string",
			ns:      NullableString{Value: "hello", Valid: true, Set: true},
			wantNil: false,
			wantVal: "hello",
		},
		{
			name:    "null value",
			ns:      NullableString{Valid: false, Set: true},
			wantNil: true,
		},
		{
			name:    "not set",
			ns:      NullableString{Valid: false, Set: false},
			wantNil: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ptr := tt.ns.ToPtr()
			if tt.wantNil {
				if ptr != nil {
					t.Errorf("ToPtr() = %v, want nil", *ptr)
				}
			} else {
				if ptr == nil {
					t.Errorf("ToPtr() = nil, want %q", tt.wantVal)
				} else if *ptr != tt.wantVal {
					t.Errorf("ToPtr() = %q, want %q", *ptr, tt.wantVal)
				}
			}
		})
	}
}

func TestNullableTime_UnmarshalJSON(t *testing.T) {
	testTime := time.Date(2024, 1, 15, 10, 30, 0, 0, time.UTC)
	testTimeJSON := `"2024-01-15T10:30:00Z"`

	tests := []struct {
		name      string
		json      string
		wantSet   bool
		wantValid bool
		wantTime  time.Time
	}{
		{
			name:      "field present with time value",
			json:      `{"end_date": ` + testTimeJSON + `}`,
			wantSet:   true,
			wantValid: true,
			wantTime:  testTime,
		},
		{
			name:      "field present with null value",
			json:      `{"end_date": null}`,
			wantSet:   true,
			wantValid: false,
			wantTime:  time.Time{},
		},
		{
			name:      "field absent",
			json:      `{}`,
			wantSet:   false,
			wantValid: false,
			wantTime:  time.Time{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result struct {
				EndDate NullableTime `json:"end_date"`
			}
			err := json.Unmarshal([]byte(tt.json), &result)
			if err != nil {
				t.Fatalf("Unmarshal error: %v", err)
			}

			if result.EndDate.Set != tt.wantSet {
				t.Errorf("Set = %v, want %v", result.EndDate.Set, tt.wantSet)
			}
			if result.EndDate.Valid != tt.wantValid {
				t.Errorf("Valid = %v, want %v", result.EndDate.Valid, tt.wantValid)
			}
			if !result.EndDate.Value.Equal(tt.wantTime) {
				t.Errorf("Value = %v, want %v", result.EndDate.Value, tt.wantTime)
			}
		})
	}
}

func TestUpdateEventRequest_WithNullableFields(t *testing.T) {
	// Test that UpdateEventRequest correctly handles null notes
	json1 := `{"notes": null}`
	var req1 UpdateEventRequest
	err := json.Unmarshal([]byte(json1), &req1)
	if err != nil {
		t.Fatalf("Unmarshal error: %v", err)
	}

	if !req1.Notes.Set {
		t.Error("Expected Notes.Set to be true when field is present with null")
	}
	if req1.Notes.Valid {
		t.Error("Expected Notes.Valid to be false when value is null")
	}

	// Test that absent field is not set
	json2 := `{"is_all_day": true}`
	var req2 UpdateEventRequest
	err = json.Unmarshal([]byte(json2), &req2)
	if err != nil {
		t.Fatalf("Unmarshal error: %v", err)
	}

	if req2.Notes.Set {
		t.Error("Expected Notes.Set to be false when field is absent")
	}

	// Test with actual string value
	json3 := `{"notes": "test note"}`
	var req3 UpdateEventRequest
	err = json.Unmarshal([]byte(json3), &req3)
	if err != nil {
		t.Fatalf("Unmarshal error: %v", err)
	}

	if !req3.Notes.Set {
		t.Error("Expected Notes.Set to be true when field has value")
	}
	if !req3.Notes.Valid {
		t.Error("Expected Notes.Valid to be true when field has value")
	}
	if req3.Notes.Value != "test note" {
		t.Errorf("Expected Notes.Value to be 'test note', got %q", req3.Notes.Value)
	}
}
