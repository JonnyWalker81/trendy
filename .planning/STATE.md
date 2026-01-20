# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-19)

**Core value:** Effortless tracking. Users should be able to set up tracking once and forget about it.
**Current focus:** v1.1 Onboarding Overhaul — Phase 9 complete

## Current Position

Phase: 9 of 4 (iOS State Architecture)
Plan: 3 of 3 complete
Status: Phase verified and complete
Last activity: 2026-01-20 — Phase 9 verified (5/5 must-haves passed)

Progress: [████____] 2/4 phases complete

## Milestone History

- v1.0 iOS Data Infrastructure Overhaul — SHIPPED 2026-01-18
  - 7 phases, 27 plans, 25 requirements
  - Archive: .planning/milestones/v1.0-*.md

## Roadmap Summary

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 8 | Backend Onboarding Status | 2 | Complete |
| 9 | iOS State Architecture | 7 | Complete |
| 10 | Visual Design & Flow | 10 | Pending |
| 11 | Accessibility | 2 | Pending |

**Total requirements:** 21

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
v1.0 decisions archived in milestones/v1.0-ROADMAP.md.

**Phase 8 decisions:**
- user_id is PRIMARY KEY for onboarding_status (one record per user)
- Permission status validated via CHECK constraints (database-level)
- All four RLS policies for user-scoped access
- GET returns 200 with defaults for new users (not 404) via GetOrCreate upsert
- DELETE returns 200 with reset state (not 204) so iOS sees new state immediately
- UpdateWhere used since primary key is user_id, not id

**Phase 9 decisions:**
- UserDefaults for onboarding cache (fast synchronous access, survives reinstall)
- Per-user keying with userId prefix prevents status leakage between accounts
- createEventType and logFirstEvent tracked locally only (not in backend schema)
- Cache preserved on logout so returning users skip re-onboarding
- Fire-and-forget backend push with cache-first updates for instant UX
- determineInitialRoute() is SYNCHRONOUS - no async in hot path
- Cache-first strategy avoids race condition with async session restore
- Background session verification after initial routing
- Fresh install vs returning user distinguished via hasAnyUserCompletedOnboarding()
- Setter methods for dependency injection in view models
- onChange observer pattern in LoginView since AuthViewModel.signIn() doesn't return success
- isLoggingIn flag prevents spurious handleLogin calls during session restore
- ContentView retained for DEBUG screenshot mode only

### Pending Todos

None

### Blockers/Concerns

None

## Next Action

**Phase 9 Verified - Ready for Phase 10**

Phase 9 deliverables complete and verified:
- Data layer: API models, OnboardingCache, OnboardingStatusService (09-01) ✓
- Routing: AppRouter Observable with cache-first determination (09-02) ✓
- Wiring: Views use AppRouter, NotificationCenter removed (09-03) ✓
- Verification: 5/5 must-haves passed

Next: `/gsd:discuss-phase 10` or `/gsd:plan-phase 10`

## Session Continuity

Last session: 2026-01-20
Stopped at: Phase 9 complete and verified
Resume file: None
Next: Plan Phase 10 (Visual Design & Flow)
