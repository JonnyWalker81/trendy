# Trendy

## What This Is

A cross-platform event tracking app for iOS and web. Users track life events — workouts, sleep, location-based triggers, and custom events — with reliable background data capture and offline-first sync. The iOS app now has solid data infrastructure (v1.0), a polished first-run experience (v1.1), and is ready for production use.

## Core Value

**Effortless tracking.** Users should be able to set up tracking once and forget about it. Data capture happens automatically in the background, sync happens invisibly, and the app stays out of the way while reliably recording what matters.

## Current State (v1.1 shipped 2026-01-21)

**Tech stack:**
- iOS: Swift/SwiftUI with SwiftData, ~80,000 LOC
- Backend: Go with Gin/Supabase, ~12,000 LOC
- Total: ~92,000 lines across both platforms

**Architecture:**
- Server does the heavy lifting
- iOS handles platform-specific capture (HealthKit, CoreLocation) and offline storage
- Push mutations to server for processing, deduplication, and persistence
- Thin client with cache-first loading

**What shipped in v1.1:**
- Backend onboarding status API for cross-device sync
- Synchronous cache-first routing (no onboarding flash for returning users)
- Modern visual design with hero layouts and spring animations
- Permission priming flow with skip explanations
- Confetti celebration on completion
- Full accessibility support (VoiceOver, Reduce Motion)

## Requirements

### Validated

<!-- Capabilities that have been built and verified -->

**Core Functionality (pre-v1.0):**
- ✓ Manual event creation with timestamps and notes
- ✓ EventType management with colors, icons, and properties
- ✓ SwiftData local persistence with UUIDv7 client-generated IDs
- ✓ HealthKit sleep and steps data import
- ✓ Geofence creation and configuration UI
- ✓ Supabase authentication with JWT tokens
- ✓ Backend API with clean architecture (Handler → Service → Repository)

**HealthKit Reliability (v1.0):**
- ✓ HLTH-01: Background delivery within iOS timing constraints — v1.0
- ✓ HLTH-02: Observer queries per enabled data type — v1.0
- ✓ HLTH-03: Server deduplication by external_id — v1.0
- ✓ HLTH-04: Freshness indicator for last update — v1.0
- ✓ HLTH-05: Debug view shows active observers — v1.0

**Geofence Reliability (v1.0):**
- ✓ GEO-01: Persistent monitoring (days/weeks) — v1.0
- ✓ GEO-02: Re-registration on launch/restart/eviction — v1.0
- ✓ GEO-03: Event logging even if notification fails — v1.0
- ✓ GEO-04: Health monitoring (iOS vs app registered) — v1.0

**Sync Engine (v1.0):**
- ✓ SYNC-01: Offline CRUD operations — v1.0
- ✓ SYNC-02: Auto-sync on network restore — v1.0
- ✓ SYNC-03: Mutation persistence via server — v1.0
- ✓ SYNC-04: Sync state visibility — v1.0
- ✓ API-01: UUIDv7 client-generated IDs — v1.0
- ✓ API-02: HealthKit deduplication — v1.0
- ✓ API-03: Sync status endpoint — v1.0
- ✓ API-04: Clear error responses (RFC 9457) — v1.0

**Code Quality (v1.0):**
- ✓ CODE-01: HealthKitService <400 lines per module — v1.0 (12 modules)
- ✓ CODE-02: Structured logging (Log.category.level) — v1.0
- ✓ CODE-03: GeofenceManager separation of concerns — v1.0 (7 extensions)
- ✓ CODE-04: Proper error handling and recovery — v1.0

**UX Indicators (v1.0):**
- ✓ UX-01: Sync status indicator — v1.0
- ✓ UX-02: Last sync timestamp — v1.0
- ✓ UX-03: Tappable sync errors — v1.0
- ✓ UX-04: Deterministic progress counts — v1.0

**Onboarding State Management (v1.1):**
- ✓ STATE-01: Onboarding completion status stored in backend database — v1.1
- ✓ STATE-02: Backend endpoint to get/set user's onboarding status — v1.1
- ✓ STATE-03: Local cache of onboarding status for fast app launches — v1.1
- ✓ STATE-04: App determines launch state from local cache before any UI renders — v1.1
- ✓ STATE-05: Single enum-based route state — v1.1
- ✓ STATE-06: Returning users never see onboarding screens — v1.1
- ✓ STATE-07: Unauthenticated returning users go directly to login — v1.1
- ✓ STATE-08: Replace NotificationCenter routing with shared Observable — v1.1
- ✓ STATE-09: Sync onboarding status from backend on login — v1.1

**Onboarding Visual Design (v1.1):**
- ✓ DESIGN-01: Modern layouts for all onboarding screens — v1.1
- ✓ DESIGN-02: Consistent design language throughout flow — v1.1
- ✓ DESIGN-03: Single loading view matching Launch Screen aesthetic — v1.1
- ✓ DESIGN-04: Spring animations for polished step transitions — v1.1
- ✓ DESIGN-05: Progress indicator showing steps remaining — v1.1
- ✓ DESIGN-06: Celebration animation on onboarding completion — v1.1

**Onboarding Flow (v1.1):**
- ✓ FLOW-01: Flow order Welcome → Auth → CreateEventType → LogFirstEvent → Permissions → Finish — v1.1
- ✓ FLOW-02: Pre-permission priming screens explain value before system dialog — v1.1
- ✓ FLOW-03: Skip option available with explanation — v1.1
- ✓ FLOW-04: Each permission request has contextual benefit messaging — v1.1

**Onboarding Accessibility (v1.1):**
- ✓ A11Y-01: All onboarding screens support VoiceOver — v1.1
- ✓ A11Y-02: Animations respect accessibilityReduceMotion — v1.1

### Active

<!-- Current scope for next milestone — defined with /gsd:new-milestone -->

(No active requirements — run `/gsd:new-milestone` to define next milestone)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Real-time push from backend to iOS (WebSocket/SSE) — adds complexity, pull-based sync is sufficient
- Web app changes — focus has been on iOS infrastructure
- Calendar sync improvements — separate concern
- New HealthKit data types — focus on making existing types reliable first
- Analytics/insights changes — downstream of reliable data capture
- Manual "Sync Now" button — creates unmet expectations; iOS controls timing
- Unlimited geofences — iOS hard limit is 20; smart rotation deferred
- Continuous location tracking — massive battery drain; event-driven only
- Background HealthKit polling — Apple discourages; may break background delivery
- Silent conflict resolution — user loses changes without knowing
- Complex client-side retry logic — server handles queue persistence; client stays thin
- Value-first onboarding (try before auth) — significant architecture change; consider for v1.2
- Contextual permission requests — requires feature flags and analytics; consider for v1.2

## Context

**v1.1 Shipped 2026-01-21:**
- 4 phases (8-11), 12 plans, 21 requirements
- 78 files changed, ~11,000 net lines added
- Single day execution (2026-01-20)
- All audit checks passed (requirements, integration, E2E flows)

**v1.0 Shipped 2026-01-18:**
- 7 phases (1-7), 27 plans, 25 requirements
- 166 files changed, 3 days of execution
- All audit checks passed

**Minor tech debt carried forward from v1.0:**
- println() debug logging in handlers/event.go:325-343 (should use structured logger)
- Legacy gin.H error format in non-Phase-6 handlers (other handlers not yet migrated to RFC 9457)

## Constraints

- **Platform**: iOS 17.0+ (SwiftData requirement)
- **Backend**: Must work with existing Supabase backend and Go API
- **Schema**: No breaking changes to data model — existing events must remain accessible
- **Auth**: Continue using Supabase auth (JWT tokens, session management)
- **Testing**: Real device required for HealthKit and background testing (simulator limitations)

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full overhaul vs incremental fixes | Current code was too tangled; patches would compound tech debt | ✓ Good — clean modular architecture |
| Include SyncEngine in scope | Reliable data capture requires reliable sync; they're interconnected | ✓ Good — offline-first works |
| Backend as source of truth | Enables multi-device, web access, and data recovery | ✓ Good — verified |
| Full offline functionality | Users shouldn't notice or care about network state | ✓ Good — cache-first loading |
| Split HealthKitService into modules | 1,972 lines was unmaintainable; separation of concerns needed | ✓ Good — 12 modules <400 lines each |
| Default 30-day HealthKit sync | User has 500+ workouts; importing all causes multi-minute hang | ✓ Good — instant load |
| Skip heart rate enrichment on bulk import | Each HR query takes 100-500ms; 500 workouts = 50-250 seconds | ✓ Good — fast import |
| Cache-first, sync-later pattern | Load from SwiftData cache first for instant UI (<3s), sync in background | ✓ Good — verified |
| RFC 9457 Problem Details for all errors | Standardized error format with type URIs, request correlation, retry hints | ✓ Good — clear errors |
| Pure idempotency: duplicates return existing | 200 OK with existing record, no update (differs from upsert) | ✓ Good — safe retries |
| Error persistence until dismissed | Errors don't auto-dismiss; user must dismiss or sync must succeed | ✓ Good — no silent failures |
| user_id as PRIMARY KEY for onboarding_status | One record per user, simpler than id + user_id FK | ✓ Good — clean schema |
| UserDefaults for onboarding cache | Fast synchronous access, survives reinstall, per-user keying | ✓ Good — instant routing |
| Synchronous determineInitialRoute() | No async in hot path avoids race condition with session restore | ✓ Good — no flash |
| Cache-first routing strategy | Read cached state before any UI renders; verify session in background | ✓ Good — instant startup |
| Spring animations (0.25/0.7) | Snappy iOS-native feel for step transitions | ✓ Good — feels right |
| Skip delay with VoiceOver extension | 1.5s normally, 3.0s for VoiceOver users to hear explanation | ✓ Good — accessible |
| Confetti respects Reduce Motion | num=0 and no haptic when reduceMotion enabled | ✓ Good — inclusive |
| Progress bar announces step context | "stepName, step N of M" format for VoiceOver | ✓ Good — informative |

---
*Last updated: 2026-01-21 after v1.1 milestone*
