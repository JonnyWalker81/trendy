# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-19)

**Core value:** Effortless tracking. Users should be able to set up tracking once and forget about it.
**Current focus:** v1.1 Onboarding Overhaul — Phase 10 in progress

## Current Position

Phase: 10 of 4 (Visual Design & Flow)
Plan: 3 of 5 complete
Status: In progress
Last activity: 2026-01-20 — Completed 10-03-PLAN.md (Permission Priming Screens)

Progress: [███████_] 3/5 plans in current phase

## Milestone History

- v1.0 iOS Data Infrastructure Overhaul — SHIPPED 2026-01-18
  - 7 phases, 27 plans, 25 requirements
  - Archive: .planning/milestones/v1.0-*.md

## Roadmap Summary

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 8 | Backend Onboarding Status | 2 | Complete |
| 9 | iOS State Architecture | 7 | Complete |
| 10 | Visual Design & Flow | 10 | In Progress (3/5 plans) |
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

**Phase 10 decisions:**
- Spring animation: response 0.3, dampingFraction 0.8 for snappy iOS-native feel
- Hero view height: 280pt per RESEARCH.md
- Pulse animation: 1.0 to 1.05 scale, 2.5s loop for subtle visual interest
- Dual glow shadows on hero symbols (16px + 32px radius)
- Hero height for OnboardingAuthView: 200pt (reduced to accommodate form)
- Feature highlights reduced from 3 to 2 rows for minimal text density
- Haptic feedback on WelcomeView primary button using sensoryFeedback modifier
- Skip delay: 1.5s between showing explanation and proceeding
- Gradient colors per permission: orange-red (notifications), blue-purple (location), pink-red (healthkit)
- Skip link styled as subtle text (not prominent button) per CONTEXT.md

### Pending Todos

None

### Blockers/Concerns

None

## Next Action

**Phase 10 Plan 03 Complete - Ready for Plan 04**

Permission Priming Screens delivered:
- NotificationPrimingScreen: Hero + benefit bullets + skip flow
- LocationPrimingScreen: Hero + benefit bullets + skip flow
- HealthKitPrimingScreen: Hero + benefit bullets + skip flow
- OnboardingPermissionType: Enhanced with skipExplanation, benefitBullets, gradientColors

Next: Execute 10-04-PLAN.md (Flow Integration)

## Session Continuity

Last session: 2026-01-20T21:52:00Z
Stopped at: Completed 10-03-PLAN.md
Resume file: None
Next: Execute 10-04-PLAN.md
