# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-19)

**Core value:** Effortless tracking. Users should be able to set up tracking once and forget about it.
**Current focus:** v1.1 Onboarding Overhaul — Phase 9 in progress

## Current Position

Phase: 9 of 4 (iOS State Architecture)
Plan: 2 of 7 complete
Status: In progress
Last activity: 2026-01-20 — Completed 09-02-PLAN.md (AppRouter Implementation)

Progress: [██______] 1/4 phases complete

## Milestone History

- v1.0 iOS Data Infrastructure Overhaul — SHIPPED 2026-01-18
  - 7 phases, 27 plans, 25 requirements
  - Archive: .planning/milestones/v1.0-*.md

## Roadmap Summary

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 8 | Backend Onboarding Status | 2 | Complete |
| 9 | iOS State Architecture | 7 | In Progress (2/7) |
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

**Phase 9 decisions (09-01):**
- UserDefaults for onboarding cache (fast synchronous access, survives reinstall)
- Per-user keying with userId prefix prevents status leakage between accounts
- createEventType and logFirstEvent tracked locally only (not in backend schema)
- Cache preserved on logout so returning users skip re-onboarding
- Fire-and-forget backend push with cache-first updates for instant UX

**Phase 9 decisions (09-02):**
- determineInitialRoute() is SYNCHRONOUS - no async in hot path
- Cache-first strategy avoids race condition with async session restore
- Background session verification after initial routing
- Fresh install vs returning user distinguished via hasAnyUserCompletedOnboarding()

### Pending Todos

None

### Blockers/Concerns

None

## Next Action

**Phase 9 Plan 2 Complete - Continue to Plan 3**

Phase 9 Plan 2 deliverables complete:
- AppRouter Observable with synchronous route determination
- RootView switching on router.currentRoute
- trendyApp wiring with environment injection
- Cache-first strategy eliminating loading flash

Next: Execute 09-03-PLAN.md

## Session Continuity

Last session: 2026-01-20T19:48:02Z
Stopped at: Completed 09-02-PLAN.md
Resume file: None
Next: Execute 09-03-PLAN.md
