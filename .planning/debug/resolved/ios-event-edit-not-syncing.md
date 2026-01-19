---
status: resolved
trigger: "When editing an event in iOS app (e.g., deleting notes), the edit shows correctly locally but is not being pushed to the backend server."
created: 2026-01-18T00:00:00Z
updated: 2026-01-18T00:06:00Z
---

## Current Focus

hypothesis: Swift's JSONEncoder omits nil values by default, so when user clears notes, the `notes` field is omitted from the JSON payload rather than sent as `null`
test: Check the JSONEncoder configuration in EventStore.updateEvent() and verify the encoding behavior
expecting: Confirm that nil values are being omitted and propose a fix to explicitly encode null values
next_action: Implement fix to ensure nil values are sent as JSON null to the backend

## Symptoms

expected: When editing an event in iOS (like deleting/modifying notes), the changes should sync to the backend server
actual: Local edit displays correctly in iOS app, but the edit is not syncing with the server database
errors: No visible error messages in the app or console
reproduction: Open an existing event, modify fields (like notes), save
started: Noticed yesterday, unsure exactly when it started - may have never worked correctly

## Eliminated

## Evidence

- timestamp: 2026-01-18T00:01:00Z
  checked: EventStore.swift updateEvent() method (lines 726-818)
  found: updateEvent() DOES call syncEngine.queueMutation with operation .update and triggers performSync() if online
  implication: The issue is likely NOT in EventStore - the update mutation IS being queued

- timestamp: 2026-01-18T00:01:30Z
  checked: APIClient.swift updateEvent() method (line 310-311)
  found: updateEvent(id:_:) method exists and calls PUT /events/{id} endpoint
  implication: APIClient has the correct method to update events

- timestamp: 2026-01-18T00:02:00Z
  checked: SyncEngine.swift flushUpdate() method (lines 1074-1095)
  found: flushUpdate decodes UpdateEventRequest from payload and calls apiClient.updateEvent()
  implication: SyncEngine correctly processes update mutations

- timestamp: 2026-01-18T00:02:30Z
  checked: Backend service/event.go UpdateEvent() (lines 301-378) and repository/event.go Update() (lines 197-279)
  found: Backend correctly handles partial updates - only updates fields that are present in the request
  implication: Backend is working correctly; issue is with what iOS is sending

- timestamp: 2026-01-18T00:03:00Z
  checked: EventStore.swift updateEvent() (line 770) - JSONEncoder usage
  found: Uses plain JSONEncoder() without custom configuration
  implication: Swift's default JSONEncoder omits nil values from output JSON

- timestamp: 2026-01-18T00:03:30Z
  checked: UpdateEventRequest in APIModels.swift (lines 163-197)
  found: All fields are Optional (String?, Date?, Bool?) - these get omitted when nil
  implication: CONFIRMED ROOT CAUSE - When user clears notes (sets to nil), the field is omitted from JSON. Backend sees no "notes" field so doesn't update it.

## Resolution

root_cause: Swift's default JSONEncoder omits nil values from the JSON output. When a user edits an event and clears a field (e.g., deletes notes), the field value becomes nil. The UpdateEventRequest struct has all Optional fields, so when encoded, the nil fields are completely omitted from the JSON. The backend sees no "notes" field in the request, so it doesn't update the notes - it only updates fields that ARE present. The user expects clearing notes to sync, but the backend never receives the instruction to clear them.

fix: Added custom encode(to:) methods to all Update*Request structs to explicitly encode all fields including nil values. The structs modified were:
- UpdateEventRequest
- UpdateEventTypeRequest
- UpdateGeofenceRequest
- UpdatePropertyDefinitionRequest

The custom encoding uses `try container.encode(optionalField, forKey: .key)` for each field, which encodes nil as JSON null rather than omitting the key.

verification: Build succeeded (xcodebuild -scheme "trendy (local)" -configuration Debug). Full end-to-end verification requires testing on a device with the backend running.
files_changed:
- /Users/cipher/Repositories/trendy/apps/ios/trendy/Models/API/APIModels.swift
