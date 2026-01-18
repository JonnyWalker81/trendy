---
phase: 06-server-api
plan: 02
subsystem: api
tags: [uuidv7, idempotency, offline-first, deduplication, go, gin]

# Dependency graph
requires:
  - phase: 06-server-api-01
    provides: RFC 9457 ProblemDetails error infrastructure
provides:
  - UUIDv7 validation service with timestamp bounds checking
  - Idempotent event creation via Upsert/UpsertBatch
  - GET /events returns 200 for duplicates (pure idempotency)
  - Integration with apierror for validation error responses
affects: [06-server-api-03, ios-sync, web-sync]

# Tech tracking
tech-stack:
  added: []
  patterns: [uuidv7-validation, idempotent-upsert, check-then-insert]

key-files:
  created:
    - apps/backend/internal/service/uuid.go
    - apps/backend/internal/service/uuid_test.go
  modified:
    - apps/backend/internal/repository/interfaces.go
    - apps/backend/internal/repository/event.go
    - apps/backend/internal/service/interfaces.go
    - apps/backend/internal/service/event.go
    - apps/backend/internal/service/event_test.go
    - apps/backend/internal/handlers/event.go

key-decisions:
  - "1-minute future tolerance for UUIDv7 timestamps (handles clock skew)"
  - "Pure idempotency: duplicates return existing record without update"
  - "Batch imports skip UPDATE change_log entries (client already has data)"
  - "UseUpsert for client-provided IDs, Create for server-generated"

patterns-established:
  - "UUIDv7 validation: ValidateUUIDv7() in service layer before repository"
  - "Idempotent upsert: check-then-insert pattern for PostgREST compatibility"
  - "Status differentiation: 201 for creates, 200 for duplicates"

# Metrics
duration: 32min
completed: 2026-01-17
---

# Phase 06 Plan 02: Client-Generated IDs Summary

**UUIDv7 validation with timestamp bounds + idempotent upsert for offline-first sync**

## Performance

- **Duration:** 32 min
- **Started:** 2026-01-18T01:42:30Z
- **Completed:** 2026-01-18T02:14:30Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- UUIDv7 validation service with version check and 1-minute future tolerance
- Upsert/UpsertBatch repository methods for idempotent creates
- Handler returns 201 for new creates, 200 for duplicates
- Comprehensive test coverage (16+ tests)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create UUIDv7 validation service** - `3206c99` (feat)
2. **Task 2: Update repository with upsert for events** - `13f20f3` (feat)
3. **Task 3: Update service and handlers for UUIDv7 + idempotency** - `ea4fb7a` (feat)

## Files Created/Modified

**Created:**
- `apps/backend/internal/service/uuid.go` - UUIDv7 validation with timestamp extraction
- `apps/backend/internal/service/uuid_test.go` - 9 test cases covering all validation scenarios

**Modified:**
- `apps/backend/internal/repository/interfaces.go` - Added UpsertResult type, Upsert, UpsertBatch, GetByIDs methods
- `apps/backend/internal/repository/event.go` - Implemented upsert methods with check-then-insert pattern
- `apps/backend/internal/service/interfaces.go` - Updated CreateEvent to return (event, wasCreated, error)
- `apps/backend/internal/service/event.go` - Added UUIDv7 validation, upsert routing logic
- `apps/backend/internal/service/event_test.go` - Updated tests for new return signature, added mock methods
- `apps/backend/internal/handlers/event.go` - Integrated apierror, return 200 for duplicates

## Decisions Made

1. **1-minute future tolerance**: UUIDv7 timestamps more than 1 minute in the future are rejected. This handles clock skew while preventing abuse.

2. **Pure idempotency for duplicates**: When a client sends an event with an existing ID, the server returns the existing record as-is (200 OK) without modification. This differs from "upsert" semantics that would update.

3. **Check-then-insert pattern**: PostgREST's upsert doesn't support partial indexes well, so we query first then insert/update explicitly.

4. **Batch imports skip UPDATE change_log**: When re-importing HealthKit batches, duplicate events don't create UPDATE entries since the importing client already has the data.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

1. **uuid library version**: The google/uuid v1.6.0 doesn't have `NewV7AtTime()` for testing. Solved by manually constructing UUIDv7s with specific timestamps in test helpers.

2. **Linter auto-additions**: The Go linter kept adding incomplete 06-03 code (SyncService, CountByUser methods). Required multiple resets to keep commits clean.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Idempotent event creation complete, ready for sync status endpoint (06-03)
- UUIDv7 validation reusable for event_types endpoint (06-04)
- iOS app can safely retry failed requests with same IDs

---
*Phase: 06-server-api*
*Completed: 2026-01-17*
