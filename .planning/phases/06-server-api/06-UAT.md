---
status: diagnosed
phase: 06-server-api
source: 06-01-SUMMARY.md, 06-02-SUMMARY.md, 06-03-SUMMARY.md
started: 2026-01-18T02:30:00Z
updated: 2026-01-18T03:32:00Z
---

## Current Test

[testing complete]

## Tests

### 1. RFC 9457 Error Response Format
expected: API errors return JSON with `type`, `title`, `status`, `detail`, and `request_id` fields. Content-Type header is `application/problem+json`.
result: issue
reported: "Auth middleware errors use old format {\"error\":\"...\"} instead of RFC 9457. Validation errors DO use RFC 9457 correctly."
severity: minor

### 2. Validation Error Aggregation
expected: When creating an event with multiple invalid fields, all validation errors are returned together (not just the first one).
result: issue
reported: "Only first error shown. Sent id=not-uuid, event_type_id=empty, timestamp=bad but only got timestamp parsing error back."
severity: minor

### 3. Client-Generated UUIDv7 Accepted
expected: POST /api/v1/events with a client-generated UUIDv7 ID creates the event and returns 201 with the new event.
result: pass

### 4. Duplicate Event Returns Existing (Idempotent)
expected: POST /api/v1/events with an already-existing event ID returns 200 with the existing event (not 201, not an error).
result: pass

### 5. Future UUIDv7 Rejected
expected: POST /api/v1/events with a UUIDv7 timestamp more than 1 minute in the future returns a validation error.
result: pass

### 6. Sync Status Endpoint
expected: GET /api/v1/me/sync returns event counts, event_type counts, HealthKit counts, latest timestamps, and a status indicator.
result: pass

### 7. Sync Status Cache Header
expected: GET /api/v1/me/sync response includes Cache-Control header with max-age for client-side caching.
result: pass

## Summary

total: 7
passed: 5
issues: 2
pending: 0
skipped: 0

## Gaps

- truth: "All API errors use RFC 9457 Problem Details format"
  status: failed
  reason: "User reported: Auth middleware errors use old format {\"error\":\"...\"} instead of RFC 9457. Validation errors DO use RFC 9457 correctly."
  severity: minor
  test: 1
  root_cause: "Auth middleware uses legacy c.JSON(gin.H{\"error\": ...}) instead of apierror.WriteProblem() with RFC 9457 ProblemDetails"
  artifacts:
    - path: "apps/backend/internal/middleware/auth.go"
      issue: "Lines 20, 29, 42 use c.JSON(http.StatusUnauthorized, gin.H{\"error\": \"...\"}) instead of apierror package"
  missing:
    - "Import apierror package in auth.go"
    - "Replace c.JSON calls with apierror.WriteProblem(c, apierror.NewUnauthorizedError(...))"
  debug_session: ".planning/debug/auth-middleware-rfc9457.md"

- truth: "Validation errors aggregate all field errors"
  status: failed
  reason: "User reported: Only first error shown. Sent id=not-uuid, event_type_id=empty, timestamp=bad but only got timestamp parsing error back."
  severity: minor
  test: 2
  root_cause: "Gin's ShouldBindJSON fails on first json.Unmarshal type error before validation runs; handler uses NewBadRequestError instead of aggregating with NewValidationError"
  artifacts:
    - path: "apps/backend/internal/handlers/event.go"
      issue: "Lines 37-41 use ShouldBindJSON which fails on first parse error"
    - path: "apps/backend/internal/models/models.go"
      issue: "CreateEventRequest.Timestamp is time.Time (parsed during unmarshal, not validation)"
  missing:
    - "Create RawCreateEventRequest struct with string fields"
    - "Manually parse and validate each field, collecting errors into []FieldError"
    - "Use NewValidationError for aggregated errors"
  debug_session: ".planning/debug/validation-errors-not-aggregated.md"
