---
phase: 08-backend-onboarding-status
plan: 02
subsystem: api
tags: [go, gin, supabase, onboarding, rest-api, clean-architecture]

# Dependency graph
requires:
  - phase: 08-01
    provides: onboarding_status database schema with RLS policies
provides:
  - GET /api/v1/users/onboarding endpoint (returns defaults for new users)
  - PATCH /api/v1/users/onboarding endpoint (validates permission status)
  - DELETE /api/v1/users/onboarding endpoint (soft reset)
  - OnboardingStatus model and request types
  - Repository with upsert pattern for atomic get-or-create
  - Service with permission status validation
affects: [09-ios-state-architecture]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - GetOrCreate via Supabase upsert with user_id conflict column
    - UpdateWhere for tables with user_id as primary key (not id)
    - Soft reset preserves permission data while clearing step timestamps

key-files:
  created:
    - apps/backend/internal/models/models.go (OnboardingStatus, UpdateOnboardingStatusRequest)
    - apps/backend/internal/repository/onboarding_status.go
    - apps/backend/internal/service/onboarding.go
    - apps/backend/internal/handlers/onboarding.go
  modified:
    - apps/backend/internal/repository/interfaces.go
    - apps/backend/internal/service/interfaces.go
    - apps/backend/cmd/trendy-api/serve.go

key-decisions:
  - "GET returns 200 with defaults for new users (not 404) via GetOrCreate upsert"
  - "DELETE returns 200 with reset state (not 204) so iOS can see new state immediately"
  - "Permission status validation: granted, denied, skipped, not_requested"
  - "UpdateWhere used since primary key is user_id, not id"

patterns-established:
  - "GetOrCreate pattern using Supabase upsert for user-scoped singleton tables"
  - "Soft reset pattern: clear step timestamps but preserve permission fields"

# Metrics
duration: 3min
completed: 2026-01-20
---

# Phase 8 Plan 2: Onboarding Status API Summary

**Go backend API with GET/PATCH/DELETE endpoints for onboarding status following Handler -> Service -> Repository clean architecture**

## Performance

- **Duration:** 3 min
- **Started:** 2026-01-20T18:39:41Z
- **Completed:** 2026-01-20T18:42:32Z
- **Tasks:** 3
- **Files created:** 4
- **Files modified:** 3

## Accomplishments
- Implemented OnboardingStatus model with step timestamps and permission fields
- Created repository with GetOrCreate (upsert), Update, and SoftReset operations
- Built service with permission status validation (granted/denied/skipped/not_requested)
- Added handler with GET, PATCH, DELETE endpoints under protected route group
- Wired all components in serve.go following established dependency injection pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Add models and interfaces** - `4b0419b` (feat)
2. **Task 2: Implement repository and service** - `a0e6122` (feat)
3. **Task 3: Implement handler and wire routes** - `6c4656a` (feat)

## Files Created/Modified
- `apps/backend/internal/models/models.go` - Added OnboardingStatus and UpdateOnboardingStatusRequest structs
- `apps/backend/internal/repository/interfaces.go` - Added OnboardingStatusRepository interface
- `apps/backend/internal/service/interfaces.go` - Added OnboardingService interface
- `apps/backend/internal/repository/onboarding_status.go` - Repository implementation with upsert pattern
- `apps/backend/internal/service/onboarding.go` - Service with permission validation
- `apps/backend/internal/handlers/onboarding.go` - HTTP handlers for GET/PATCH/DELETE
- `apps/backend/cmd/trendy-api/serve.go` - Wired repository, service, handler, and routes

## Decisions Made

1. **GET returns 200 with defaults via GetOrCreate** - Per CONTEXT.md, new users should get 200 with defaults (completed: false, all nulls) rather than 404. This is achieved via Supabase upsert with user_id as conflict column.

2. **DELETE returns 200 with reset state** - Rather than 204 No Content, DELETE returns 200 with the reset OnboardingStatus so iOS can immediately see the new state without an additional GET request.

3. **UpdateWhere for user_id primary key** - Since onboarding_status uses user_id as primary key (not id), used UpdateWhere instead of Update which expects id=eq.{id} query.

4. **Service-level validation** - Permission status validation happens in service layer, returning descriptive error messages that handler converts to 400 responses.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

**Database migration required.** The onboarding_status table must be created before these endpoints will work. See 08-01-SUMMARY.md for migration instructions.

## Next Phase Readiness

- Backend API complete for onboarding status management
- Ready for iOS integration (Phase 9)
- Endpoints follow existing patterns (auth middleware, structured logging, JSON responses)
- No blockers for next phase

---
*Phase: 08-backend-onboarding-status*
*Completed: 2026-01-20*
