# Roadmap: Trendy v1.1 Onboarding Overhaul

**Milestone:** v1.1
**Defined:** 2026-01-19
**Phases:** 4 (Phase 8-11)
**Depth:** Comprehensive
**Requirements:** 21

## Overview

This roadmap fixes the onboarding experience for Trendy iOS. The core problem is a race condition where returning users see onboarding screens flash before being routed to the main app. The solution requires backend storage of onboarding status, a synchronous state architecture on iOS that reads cached state before rendering, and visual polish with modern SwiftUI animations.

Phases are ordered by dependency: backend foundation enables iOS state management, which enables visual work, which enables accessibility polish.

## Phases

### Phase 8: Backend Onboarding Status ✓

**Goal:** Backend stores and serves onboarding completion status per user.

**Dependencies:** None (foundation phase)

**Requirements:**
- STATE-01: Onboarding completion status stored in backend database (source of truth)
- STATE-02: Backend endpoint to get/set user's onboarding status

**Plans:** 2 plans

Plans:
- [x] 08-01-PLAN.md — Database schema and migration for onboarding_status table
- [x] 08-02-PLAN.md — Go API layer (handler/service/repository) with GET/PATCH/DELETE endpoints

**Success Criteria:**
1. ✓ Backend has database table/column storing onboarding completion status per user
2. ✓ GET /api/v1/users/onboarding returns current user's onboarding status
3. ✓ PATCH /api/v1/users/onboarding updates current user's onboarding status
4. ✓ Unauthenticated requests return 401

**Completed:** 2026-01-20

---

### Phase 9: iOS State Architecture ✓

**Goal:** Returning users never see onboarding screens flash on app launch.

**Dependencies:** Phase 8 (backend onboarding status)

**Requirements:**
- STATE-03: Local cache of onboarding status for fast app launches
- STATE-04: App determines launch state from local cache before any UI renders (no flash)
- STATE-05: Single enum-based route state (`loading`, `onboarding`, `authenticated`)
- STATE-06: Returning users never see onboarding screens
- STATE-07: Unauthenticated returning users go directly to login
- STATE-08: Replace NotificationCenter routing with shared Observable
- STATE-09: Sync onboarding status from backend on login (updates local cache)

**Plans:** 3 plans

Plans:
- [x] 09-01-PLAN.md — API models, OnboardingCache, OnboardingStatusService (data layer foundation)
- [x] 09-02-PLAN.md — AppRouter Observable and RootView (routing state machine)
- [x] 09-03-PLAN.md — Remove NotificationCenter routing, wire AppRouter to existing views

**Success Criteria:**
1. ✓ Returning authenticated user launches app and sees main app immediately (no loading screen, no onboarding flash)
2. ✓ Returning unauthenticated user launches app and sees login screen immediately (not onboarding)
3. ✓ New user completes onboarding, force quits, relaunches - goes to main app (status persisted)
4. ✓ User signs out on device A, signs in on device B with completed onboarding - goes to main app (backend sync)
5. ✓ No NotificationCenter posts for routing decisions (Observable only)

**Completed:** 2026-01-20

---

### Phase 10: Visual Design & Flow

**Goal:** New users experience a polished, well-ordered onboarding flow with modern design.

**Dependencies:** Phase 9 (stable state architecture)

**Requirements:**
- DESIGN-01: Modern layouts for all onboarding screens
- DESIGN-02: Consistent design language throughout flow
- DESIGN-03: Single loading view matching Launch Screen aesthetic
- DESIGN-04: PhaseAnimator/KeyframeAnimator for polished step transitions
- DESIGN-05: Progress indicator showing steps remaining
- DESIGN-06: Celebration animation on onboarding completion
- FLOW-01: Flow order is Welcome -> Auth -> Permissions
- FLOW-02: Pre-permission priming screens explain value before system dialog
- FLOW-03: Skip option available with explanation of what user will miss
- FLOW-04: Each permission request has contextual benefit messaging

**Success Criteria:**
1. New user sees Welcome screens before being asked to authenticate
2. New user sees custom priming screen before each system permission dialog
3. User can skip permission step and sees explanation of what features require it
4. Step transitions animate smoothly (not instant cuts)
5. Progress indicator visible throughout flow showing current step of total

---

### Phase 11: Accessibility

**Goal:** Onboarding is usable with VoiceOver and respects motion preferences.

**Dependencies:** Phase 10 (visual design complete)

**Requirements:**
- A11Y-01: All onboarding screens support VoiceOver
- A11Y-02: Animations respect `accessibilityReduceMotion` preference

**Success Criteria:**
1. VoiceOver user can complete entire onboarding flow using only screen reader
2. All interactive elements have accessibility labels and hints
3. User with Reduce Motion enabled sees no animations (instant transitions)
4. Focus order follows visual layout top-to-bottom

---

## Progress

| Phase | Name | Status | Requirements | Success |
|-------|------|--------|--------------|---------|
| 8 | Backend Onboarding Status | Complete | 2/2 | 4/4 |
| 9 | iOS State Architecture | Complete | 7/7 | 5/5 |
| 10 | Visual Design & Flow | Pending | 10/10 | 0/5 |
| 11 | Accessibility | Pending | 2/2 | 0/4 |

**Total:** 21 requirements mapped, 9 complete

## Coverage Verification

All 21 v1.1 requirements mapped:

| Requirement | Phase |
|-------------|-------|
| STATE-01 | Phase 8 |
| STATE-02 | Phase 8 |
| STATE-03 | Phase 9 |
| STATE-04 | Phase 9 |
| STATE-05 | Phase 9 |
| STATE-06 | Phase 9 |
| STATE-07 | Phase 9 |
| STATE-08 | Phase 9 |
| STATE-09 | Phase 9 |
| DESIGN-01 | Phase 10 |
| DESIGN-02 | Phase 10 |
| DESIGN-03 | Phase 10 |
| DESIGN-04 | Phase 10 |
| DESIGN-05 | Phase 10 |
| DESIGN-06 | Phase 10 |
| FLOW-01 | Phase 10 |
| FLOW-02 | Phase 10 |
| FLOW-03 | Phase 10 |
| FLOW-04 | Phase 10 |
| A11Y-01 | Phase 11 |
| A11Y-02 | Phase 11 |

**Orphaned requirements:** None
**Coverage:** 21/21 (100%)

---
*Roadmap created: 2026-01-19*
*Last updated: 2026-01-20 — Phase 9 complete*
