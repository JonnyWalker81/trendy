---
status: verifying
trigger: "Clearing notes completely (empty text box) does NOT sync. Changing notes to another non-empty string DOES sync."
created: 2026-01-18T12:00:00Z
updated: 2026-01-18T12:15:00Z
---

## Current Focus

hypothesis: CONFIRMED - Go JSON unmarshaling treats `null` the same as "field absent" for pointer types
test: Unit tests for NullableString/NullableTime confirm behavior
expecting: Backend should now correctly clear notes when receiving null
next_action: Manual verification - test clearing notes in iOS app

## Symptoms

expected: When user clears notes in iOS event edit, the cleared notes should sync to backend
actual: Clearing notes does not sync, but changing notes to a different non-empty string works
errors: None visible
reproduction: Edit event -> delete all text from notes field -> save -> check backend
started: Issue existed but masked by previous encoding bug that was recently fixed

## Eliminated

## Evidence

- timestamp: 2026-01-18T12:01:00Z
  checked: EventEditView.swift saveEvent() line 234
  found: `existingEvent.notes = formState.notes.isEmpty ? nil : formState.notes` - correctly converts empty string to nil
  implication: iOS side correctly sets notes to nil when clearing

- timestamp: 2026-01-18T12:02:00Z
  checked: APIModels.swift UpdateEventRequest custom encode(to:) method lines 222-242
  found: Custom encoding correctly encodes nil as JSON null: `try container.encode(notes, forKey: .notes)`
  implication: iOS correctly sends `{"notes": null}` in JSON payload

- timestamp: 2026-01-18T12:03:00Z
  checked: Go backend models/models.go UpdateEventRequest struct lines 90-106
  found: `Notes *string json:"notes"` - pointer type
  implication: Go JSON decoder treats JSON null as nil pointer

- timestamp: 2026-01-18T12:04:00Z
  checked: Go backend service/event.go UpdateEvent() lines 332-334
  found: `if req.Notes != nil { update.Notes = req.Notes }` - only sets Notes if NOT nil
  implication: When iOS sends null, req.Notes is nil, so update.Notes is not set

- timestamp: 2026-01-18T12:05:00Z
  checked: Go backend repository/event.go Update() lines 206-208
  found: `if event.Notes != nil { data["notes"] = *event.Notes }` - only includes notes in update if not nil
  implication: CONFIRMED ROOT CAUSE - null values never reach the database update

- timestamp: 2026-01-18T12:15:00Z
  checked: Unit tests for NullableString/NullableTime
  found: All tests pass - correctly distinguishes null from absent
  implication: Fix is working at code level

## Resolution

root_cause: Go's standard JSON unmarshaling cannot distinguish between "field present with null value" and "field absent". When iOS sends `{"notes": null}` to clear notes:
1. Go unmarshals this as `Notes = nil` (pointer is nil)
2. Service layer checks `if req.Notes != nil` and skips because it's nil
3. Repository layer checks `if event.Notes != nil` and doesn't add "notes" to update map
4. Supabase only updates fields present in the request, so notes is never cleared

The same pattern exists for all nullable fields: EndDate, ExternalID, OriginalTitle, etc.

fix: Implemented NullableString and NullableTime wrapper types with custom JSON unmarshaling:
- Created `internal/models/nullable.go` with NullableString and NullableTime types
- Each type has three fields: Value, Valid (has value), Set (was present in JSON)
- Updated UpdateEventRequest to use NullableString for clearable string fields
- Updated UpdateEventRequest to use NullableTime for clearable time fields
- Added `UpdateFields` method to EventRepository for direct map-based updates
- Updated EventService.UpdateEvent to build a fields map and explicitly set null when needed

verification: Unit tests pass. Pending manual testing with iOS app.
files_changed:
  - apps/backend/internal/models/nullable.go (NEW)
  - apps/backend/internal/models/nullable_test.go (NEW)
  - apps/backend/internal/models/models.go (UpdateEventRequest uses NullableString/NullableTime)
  - apps/backend/internal/repository/interfaces.go (added UpdateFields to interface)
  - apps/backend/internal/repository/event.go (implemented UpdateFields)
  - apps/backend/internal/service/event.go (use UpdateFields with explicit nulls)
  - apps/backend/internal/service/event_test.go (added UpdateFields to mock)
