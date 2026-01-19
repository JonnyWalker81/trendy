---
status: resolved
trigger: "Validation errors not aggregated - POST with multiple invalid fields returns only first parsing error"
created: 2026-01-17T00:00:00Z
updated: 2026-01-18T00:00:00Z
resolved: 2026-01-18T00:00:00Z
resolution_type: documented_limitation
symptoms_prefilled: true
goal: find_root_cause_only
---

## Current Focus

hypothesis: Gin's ShouldBindJSON fails on first JSON parsing error before custom validation runs
test: Trace POST /events handler to see binding vs validation flow
expecting: Confirm JSON parsing happens first and stops at first malformed field
next_action: Find event handler and trace binding logic

## Symptoms

expected: All validation errors aggregated together in response
actual: Only first parsing error returned
errors: {"type":"urn:trendy:error:bad_request","detail":"parsing time \"bad\" as \"2006-01-02T15:04:05Z07:00\"..."}
reproduction: POST /api/v1/events with {"id": "not-uuid", "event_type_id": "", "timestamp": "bad"}
started: Current behavior (apierror package exists but aggregation not used)

## Eliminated

## Evidence

- timestamp: 2026-01-17T00:01:00Z
  checked: apps/backend/internal/handlers/event.go - CreateEvent handler (lines 28-75)
  found: Uses c.ShouldBindJSON(&req) for JSON parsing/binding, then calls NewBadRequestError with err.Error() on first error
  implication: JSON parsing errors short-circuit - never reaches custom validation

- timestamp: 2026-01-17T00:02:00Z
  checked: apps/backend/internal/models/models.go - CreateEventRequest (lines 48-66)
  found: Uses binding tags (binding:"required") but timestamp is time.Time parsed during JSON decode
  implication: time.Time parsing happens during json.Unmarshal, not during Gin's validation phase

- timestamp: 2026-01-17T00:03:00Z
  checked: apps/backend/internal/apierror/response.go - NewValidationError (lines 39-51)
  found: Function exists and accepts []FieldError for aggregation, but is NEVER called in event.go handler
  implication: Aggregation capability exists but is unused

- timestamp: 2026-01-17T00:04:00Z
  checked: Gin binding behavior analysis
  found: ShouldBindJSON does two things: 1) json.Unmarshal (fails on type errors like bad timestamp) 2) validator.Validate (fails on binding tags)
  implication: Two-phase process - if unmarshal fails, validation never runs. Both fail on first error.

## Resolution

root_cause: Two-phase limitation - Gin's ShouldBindJSON uses json.Unmarshal first (fails on first type error like bad timestamp), then runs validator (fails on first binding constraint). Neither phase aggregates errors. The apierror.NewValidationError exists for aggregation but handler never uses it.
fix: Requires custom approach - use json.RawMessage for fields that need aggregated validation, decode each manually, collect all errors
decision: DOCUMENTED AS KNOWN LIMITATION - The fix requires significant refactoring of all handlers. Current behavior (first-error-only) is acceptable for MVP. Can revisit if user feedback indicates this is a pain point.
verification: N/A - Not fixing, documenting as known limitation
files_changed: []
