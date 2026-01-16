# Trendy iOS Data Infrastructure Overhaul

## What This Is

A complete rebuild of Trendy's iOS background data systems — HealthKit integration, geofence monitoring, and sync engine. The goal is reliable, offline-first data capture that works seamlessly in the background without user intervention.

## Core Value

**Data capture must be reliable.** When a workout ends or a geofence triggers, that event must be recorded — whether online or offline, whether the app is open or not. Users should never have to manually refresh or wonder if their data was captured.

## Requirements

### Validated

<!-- Existing capabilities that work and are relied upon -->

- ✓ Manual event creation with timestamps and notes — existing
- ✓ EventType management with colors, icons, and properties — existing
- ✓ SwiftData local persistence with UUIDv7 client-generated IDs — existing
- ✓ Cursor-based sync with backend API — existing (but fragile)
- ✓ HealthKit sleep and steps data import — existing (reliable)
- ✓ Geofence creation and configuration UI — existing
- ✓ Supabase authentication with JWT tokens — existing
- ✓ Backend API with clean architecture (Handler → Service → Repository) — existing
- ✓ Offline event queueing — existing (basic)

### Active

<!-- Current scope. Building toward these. -->

**HealthKit Reliability:**
- [ ] Immediate background notification when workout/active energy data arrives (within minutes)
- [ ] Reliable background delivery for ALL HealthKit data types, not just sleep/steps
- [ ] Observer queries properly configured for each enabled data type
- [ ] Proper handling of HealthKit authorization state across app lifecycle

**Geofence Reliability:**
- [ ] Persistent geofence monitoring that survives days/weeks without dropping
- [ ] Re-registration of geofences on app launch, device restart, and iOS eviction
- [ ] Reliable enter/exit notifications that fire every time
- [ ] Event logging even if notification delivery fails

**Sync Engine Robustness:**
- [ ] Backend database as single source of truth
- [ ] Full offline functionality — app works normally, syncs transparently when online
- [ ] Reliable mutation queue that never loses data
- [ ] Proper conflict handling when offline edits sync
- [ ] Clear sync state visibility (what's pending, what's synced)

**Code Quality:**
- [ ] Split monolithic HealthKitService (1,972 lines) into focused modules
- [ ] Replace all print() statements with structured logging (Log.category.level)
- [ ] Clean separation of concerns in GeofenceManager
- [ ] Proper error handling and recovery throughout

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Real-time push from backend to iOS (WebSocket/SSE) — adds complexity, pull-based sync is sufficient for now
- Web app changes — this project focuses on iOS data infrastructure
- Backend API changes — only if absolutely required for sync; prefer client-side solutions
- Calendar sync improvements — separate concern, not part of this overhaul
- New HealthKit data types — focus on making existing types reliable first
- Analytics/insights changes — downstream of reliable data capture

## Context

**Current State:**
- HealthKitService is 1,972 lines — largest file in codebase, handles workouts, sleep, steps, and configuration all in one
- GeofenceManager has 45+ print statements and fragile state management
- SyncEngine is 1,116 lines with complex cursor logic and pending delete tracking
- Background delivery works for sleep/steps but not reliably for workouts/active energy
- Geofences register but silently unregister over time — iOS limits (20 regions) may be a factor
- Two deprecated SwiftData models still exist (QueuedOperation, HealthKitConfiguration)

**iOS Background Constraints:**
- iOS aggressively limits background execution
- HealthKit background delivery requires proper observer query setup per data type
- CoreLocation geofence monitoring is managed by iOS, but regions can be evicted
- App must re-register geofences after restart, update, or iOS eviction
- Background App Refresh affects sync behavior

**Data Architecture:**
- Backend (Supabase/PostgreSQL) is the source of truth
- iOS uses SwiftData for local persistence
- UUIDv7 enables client-generated IDs for offline-first
- Cursor-based incremental sync with change feed API

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
| Full overhaul vs incremental fixes | Current code is too tangled; patches would compound tech debt | — Pending |
| Include SyncEngine in scope | Reliable data capture requires reliable sync; they're interconnected | — Pending |
| Backend as source of truth | Enables multi-device, web access, and data recovery | — Pending |
| Full offline functionality | Users shouldn't notice or care about network state | — Pending |
| Split HealthKitService into modules | 1,972 lines is unmaintainable; separation of concerns needed | — Pending |

---
*Last updated: 2026-01-15 after initialization*
