# Phase 8: Backend Onboarding Status - Context

**Gathered:** 2026-01-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Backend stores and serves onboarding completion status per user. Provides GET/PATCH endpoints for iOS app to read and update onboarding progress. Admin endpoints are out of scope for this phase.

</domain>

<decisions>
## Implementation Decisions

### Data Model
- Separate `onboarding_status` table (not columns on users table)
- Track three main steps: welcome, auth, permissions
- Track three permissions individually: notifications, healthkit, location
- Timestamps per step AND per permission (welcome_completed_at, auth_completed_at, notifications_completed_at, etc.)
- Permission status stored as string (flexible values defined by iOS)
- Valid permission values: granted, denied, skipped, not_requested (strict validation)
- Explicit `completed` boolean flag stored alongside steps (not just derived)
- Fixed columns for each field (not JSONB) — requires migration for new permissions

### API Response Format
- GET returns 200 with defaults for new users (completed: false, all nulls) — no 404
- Response includes computed `completed` flag for easy iOS checks
- Response includes all timestamps
- PATCH for updates (not POST)
- PATCH requires full object (not partial updates)

### Edge Cases
- Reset via API supported — soft reset (preserves permission data, clears step completion)
- Last-write-wins for sync conflicts (no timestamp-based rejection)
- User deletion = fresh start on re-register (cascade delete, new record)

### Claude's Discretion
- API response structure (flat vs nested)
- API path (/api/v1/users/onboarding vs /api/v1/onboarding)
- Reset endpoint method (DELETE vs POST /reset)
- Row Level Security policy implementation
- Error message formatting

</decisions>

<specifics>
## Specific Ideas

- iOS permissions persist at OS level even if user re-does onboarding — soft reset preserves permission data because actual OS permission state won't change
- Backend should validate permission status values strictly to maintain data integrity

</specifics>

<deferred>
## Deferred Ideas

- Admin endpoint for viewing other users' onboarding status (GET /api/v1/admin/users/{id}/onboarding) — useful for support/debugging

</deferred>

---

*Phase: 08-backend-onboarding-status*
*Context gathered: 2026-01-20*
