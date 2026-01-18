---
phase: 06-server-api
plan: 01
subsystem: api
tags: [rfc-9457, problem-details, error-handling, gin, go]

# Dependency graph
requires: []
provides:
  - RFC 9457 ProblemDetails struct with standard and extension fields
  - Error type URIs (urn:trendy:error:*) for validation, auth, rate-limit, etc.
  - Response helpers with Content-Type and Retry-After header support
  - Factory functions for common error scenarios
affects: [06-02, 06-03, 06-04, 06-05, 06-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - RFC 9457 Problem Details for all API error responses
    - URN-based error type registry (urn:trendy:error:*)
    - Validation errors aggregated (all failures, not just first)
    - User-facing vs developer messages separation

key-files:
  created:
    - apps/backend/internal/apierror/problem.go
    - apps/backend/internal/apierror/codes.go
    - apps/backend/internal/apierror/response.go
    - apps/backend/internal/apierror/problem_test.go
  modified: []

key-decisions:
  - "ProblemDetails implements error interface for ergonomic error handling"
  - "GetRequestID extracts from gin context first, falls back to header"
  - "NewServiceUnavailableError added for 503 responses with retry hint"
  - "Added title constants alongside type URIs for consistency"

patterns-established:
  - "RFC 9457 error format: All errors use ProblemDetails with type, title, status, detail"
  - "Request correlation: All errors include request_id from middleware"
  - "Validation aggregation: NewValidationError accepts slice of FieldError"
  - "Retry hints: RetryAfter field AND Retry-After header for 429/503"

# Metrics
duration: 3min
completed: 2026-01-18
---

# Phase 6 Plan 1: RFC 9457 Error Response Infrastructure Summary

**RFC 9457 Problem Details package with type URIs, response helpers, and Retry-After support for standardized API error handling**

## Performance

- **Duration:** 3 min
- **Started:** 2026-01-18T01:37:32Z
- **Completed:** 2026-01-18T01:40:04Z
- **Tasks:** 3
- **Files created:** 4

## Accomplishments

- Created `internal/apierror` package with RFC 9457 compliant ProblemDetails struct
- Defined error type URIs for validation, not_found, conflict, rate_limit, unauthorized, forbidden, internal, invalid_uuid, future_timestamp, bad_request
- Implemented response helpers that set `Content-Type: application/problem+json` and `Retry-After` headers
- Added comprehensive unit tests (16 tests passing)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ProblemDetails struct and error codes** - `fda084c` (feat)
2. **Task 2: Create response helpers** - `c207bda` (feat)
3. **Task 3: Add unit tests for apierror package** - `be1193a` (test)

## Files Created

- `apps/backend/internal/apierror/problem.go` - RFC 9457 ProblemDetails struct with standard and extension fields
- `apps/backend/internal/apierror/codes.go` - Error type URIs and title constants
- `apps/backend/internal/apierror/response.go` - WriteProblem and factory functions for all error types
- `apps/backend/internal/apierror/problem_test.go` - 16 unit tests covering JSON structure, headers, and all factories

## Decisions Made

- **ProblemDetails implements error interface:** Allows using ProblemDetails as a standard Go error for ergonomic error handling
- **Title constants alongside type URIs:** Added TitleValidation, TitleNotFound, etc. for consistency in human-readable summaries
- **NewServiceUnavailableError added:** Plan mentioned 503 for Retry-After but didn't include factory - added for completeness
- **GetRequestID dual extraction:** Checks gin context first (set by logger middleware), falls back to X-Request-ID header

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - all tasks completed successfully without issues.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- RFC 9457 error infrastructure ready for use in handlers
- Next plan (06-02) should refactor existing handlers to use apierror package
- All success criteria met:
  - `internal/apierror` package exists and compiles
  - ProblemDetails has all RFC 9457 fields plus extensions
  - Error codes defined as URN constants
  - WriteProblem sets correct Content-Type
  - WriteProblem sets Retry-After header when applicable
  - Factory functions create correctly structured errors
  - 16 unit tests passing

---
*Phase: 06-server-api*
*Completed: 2026-01-18*
