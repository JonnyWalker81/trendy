# Trendy

## What This Is

A cross-platform event tracking app for iOS and web. Users track life events — workouts, sleep, location-based triggers, and custom events — with reliable background data capture and offline-first sync. The iOS app now has solid data infrastructure (v1.0) and needs a polished first-run experience.

## Core Value

**Effortless tracking.** Users should be able to set up tracking once and forget about it. Data capture happens automatically in the background, sync happens invisibly, and the app stays out of the way while reliably recording what matters.

## Current Milestone: v1.1 Onboarding Overhaul

**Goal:** Fix the confusing onboarding experience — returning users should never see onboarding screens, and new users should have a polished, well-ordered first-run flow.

**Problems to solve:**
- Returning users see onboarding screens flash on app launch (state management bug)
- Flow order is wrong for new users
- Visual design is dated/rough

**Target features:**
- Proper state detection — returning users go straight to login or main app
- Correct flow order: Welcome → Auth → Permissions
- Full visual redesign with modern layouts and animations

## Current State (v1.0 shipped 2026-01-18)

**Tech stack:**
- iOS: Swift/SwiftUI with SwiftData, 76,420 LOC
- Backend: Go with Gin/Supabase, 10,506 LOC
- Total: ~87,000 lines across both platforms

**Architecture:**
- Server does the heavy lifting
- iOS handles platform-specific capture (HealthKit, CoreLocation) and offline storage
- Push mutations to server for processing, deduplication, and persistence
- Thin client with cache-first loading

**What shipped:**
- Structured logging with Apple's unified logging (Log.category.level)
- Reliable HealthKit background delivery with anchor persistence
- Persistent geofence monitoring with lifecycle re-registration
- Offline-first sync engine with cache-first loading (<3s)
- RFC 9457 error handling on server

## Requirements

### Validated

<!-- Capabilities that have been built and verified -->

- ✓ Manual event creation with timestamps and notes — existing
- ✓ EventType management with colors, icons, and properties — existing
- ✓ SwiftData local persistence with UUIDv7 client-generated IDs — existing
- ✓ Cursor-based sync with backend API — v1.0
- ✓ HealthKit sleep and steps data import — existing
- ✓ Geofence creation and configuration UI — existing
- ✓ Supabase authentication with JWT tokens — existing
- ✓ Backend API with clean architecture (Handler → Service → Repository) — existing
- ✓ Offline event queueing — v1.0

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

**Server API (v1.0):**
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

### Active

<!-- Current scope for next milestone -->

**Onboarding State Management (v1.1):**
- [ ] OB-STATE-01: Returning users never see onboarding screens
- [ ] OB-STATE-02: App detects onboarding completion status before rendering
- [ ] OB-STATE-03: Unauthenticated returning users go to login, not onboarding

**Onboarding Flow (v1.1):**
- [ ] OB-FLOW-01: Welcome screens show app value proposition
- [ ] OB-FLOW-02: Auth flow (login/signup) comes after welcome
- [ ] OB-FLOW-03: Permission requests come after auth with context
- [ ] OB-FLOW-04: Flow order is Welcome → Auth → Permissions

**Onboarding Design (v1.1):**
- [ ] OB-DESIGN-01: Modern visual design with new layouts
- [ ] OB-DESIGN-02: Smooth animations and transitions
- [ ] OB-DESIGN-03: Consistent design language throughout flow

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Real-time push from backend to iOS (WebSocket/SSE) — adds complexity, pull-based sync is sufficient for now
- Web app changes — this project focused on iOS data infrastructure
- Calendar sync improvements — separate concern, not part of this overhaul
- New HealthKit data types — focus on making existing types reliable first
- Analytics/insights changes — downstream of reliable data capture
- Manual "Sync Now" button — Creates unmet expectations; iOS controls timing
- Unlimited geofences — iOS hard limit is 20; smart rotation deferred to v2
- Continuous location tracking — Massive battery drain; event-driven only
- Background HealthKit polling — Apple discourages; may break background delivery
- Silent conflict resolution — User loses changes without knowing
- Complex client-side retry logic — Server handles queue persistence; client stays thin

## Context

**Shipped v1.0 2026-01-18:**
- 7 phases, 27 plans, 25 requirements
- 166 files changed, 3 days of execution
- All audit checks passed (requirements, integration, E2E flows)

**Minor tech debt carried forward:**
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

---
*Last updated: 2026-01-19 after v1.1 milestone started*
