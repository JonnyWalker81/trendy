# Roadmap: Trendy iOS Data Infrastructure Overhaul

## Overview

A complete rebuild of Trendy's iOS background data systems — HealthKit integration, geofence monitoring, and sync engine. We start with foundational fixes (logging, entitlements), then make HealthKit and Geofence reliable, refactor the code for maintainability, rebuild the sync engine for offline-first operation, add server-side support for the thin client architecture, and finish with UX indicators so users can see what's happening.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Foundation** - Structured logging, entitlement verification, error handling foundation
- [x] **Phase 2: HealthKit Reliability** - Background delivery, observer queries, server deduplication
- [x] **Phase 3: Geofence Reliability** - Persistent monitoring, re-registration, health monitoring
- [x] **Phase 4: Code Quality** - Split HealthKitService, separate GeofenceManager concerns
- [ ] **Phase 5: Sync Engine** - Offline-first CRUD, automatic sync, mutation persistence
- [ ] **Phase 6: Server API** - UUIDv7 support, deduplication, sync status endpoint
- [ ] **Phase 7: UX Indicators** - Sync status, timestamps, error surfacing, progress counts

## Phase Details

### Phase 1: Foundation
**Goal**: Fix silent failures before any refactoring. Establish structured logging and verify entitlements.
**Depends on**: Nothing (first phase)
**Requirements**: CODE-02, CODE-04
**Success Criteria** (what must be TRUE):
  1. All print() statements in HealthKitService and GeofenceManager replaced with Log.category.level
  2. HealthKit background delivery entitlement verified in both entitlements file AND provisioning profile
  3. Error handling returns meaningful error types (not just print and continue)
**Research**: Unlikely (audit and fix, established patterns)
**Plans**: TBD

Plans:
- [x] 01-01: HealthKitService structured logging migration
- [x] 01-02: GeofenceManager structured logging and entitlements verification
- [x] 01-03: HealthKit error handling (gap closure)
- [x] 01-04: Geofence error handling (gap closure)

### Phase 2: HealthKit Reliability
**Goal**: Reliable background delivery for all enabled HealthKit data types
**Depends on**: Phase 1
**Requirements**: HLTH-01, HLTH-02, HLTH-03, HLTH-04, HLTH-05
**Success Criteria** (what must be TRUE):
  1. Workout data arrives via background delivery when app is backgrounded (within iOS timing constraints)
  2. Observer queries are running for each enabled data type (visible in debug view)
  3. HealthKit samples sync to server with deduplication by external_id
  4. User can see when HealthKit data was last updated (freshness indicator)
**Research**: Completed (patterns identified during planning)
**Research topics**: HKAnchoredObjectQuery with persistent anchors, HKObserverQuery completion handler patterns, background delivery frequency configuration

Plans:
- [x] 02-01: Anchor persistence and background reliability (HKAnchoredObjectQuery with persistent anchors)
- [x] 02-02: Freshness indicators (per-category last update timestamps in UI)
- [x] 02-03: Initial sync performance (30-day default, historical import UI) [gap closure]

### Phase 3: Geofence Reliability
**Goal**: Persistent geofence monitoring that survives iOS lifecycle events
**Depends on**: Phase 1
**Requirements**: GEO-01, GEO-02, GEO-03, GEO-04
**Success Criteria** (what must be TRUE):
  1. Geofences remain active after app is closed for days/weeks
  2. Geofences automatically re-register on app launch and device restart
  3. Enter/exit events are logged even if notification delivery fails
  4. User can see which geofences are registered with iOS vs saved in app
**Research**: Likely (CLMonitor evaluation, iOS 17+ patterns)
**Research topics**: CLMonitor vs CLLocationManager, region monitoring persistence, iOS 17+ geofence improvements
**Plans**: TBD

Plans:
- [x] 03-01: AppDelegate background launch handler
- [x] 03-02: Lifecycle re-registration at launch, activation, and auth changes
- [x] 03-03: Health monitoring dashboard UI

### Phase 4: Code Quality
**Goal**: Clean separation of concerns in HealthKit and Geofence code
**Depends on**: Phase 2, Phase 3
**Requirements**: CODE-01, CODE-03
**Success Criteria** (what must be TRUE):
  1. HealthKitService split into focused modules (<400 lines each)
  2. GeofenceManager has separate concerns (auth, registration, event handling)
  3. No single file handles more than 2 distinct responsibilities
**Research**: Unlikely (internal refactoring, patterns established in Phase 2-3)
**Plans**: TBD

Plans:
- [x] 04-01: HealthKitService decomposition (12 focused extension files)
- [x] 04-02: GeofenceManager decomposition (7 focused extension files)

### Phase 5: Sync Engine
**Goal**: Reliable offline-first sync that never loses data
**Depends on**: Phase 4
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04
**Success Criteria** (what must be TRUE):
  1. User can create/edit/delete events while offline without errors
  2. Offline changes automatically sync when network returns
  3. Pending mutations persist across app restarts
  4. User can see sync state (pending count, last sync time)
**Research**: Likely (SwiftData concurrency with @ModelActor, conflict resolution strategy)
**Research topics**: @ModelActor patterns, PersistentIdentifier passing, mutation queue design, LWW vs explicit conflict handling
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

### Phase 6: Server API
**Goal**: Server-side support for idempotent creates and deduplication
**Depends on**: Phase 5
**Requirements**: API-01, API-02, API-03, API-04
**Success Criteria** (what must be TRUE):
  1. Server accepts events with client-generated UUIDv7 IDs
  2. Duplicate HealthKit samples (same external_id) are rejected gracefully
  3. Server provides sync status endpoint
  4. Error responses are clear and actionable
**Research**: Unlikely (backend extensions using existing patterns)
**Plans**: TBD

Plans:
- [ ] 06-01: TBD

### Phase 7: UX Indicators
**Goal**: Clear sync state visibility for users
**Depends on**: Phase 5, Phase 6
**Requirements**: UX-01, UX-02, UX-03, UX-04
**Success Criteria** (what must be TRUE):
  1. Sync status indicator visible (online/syncing/pending/offline)
  2. Last sync timestamp displayed ("Last synced: 5 min ago")
  3. Sync errors are tappable with explanation (not silent failures)
  4. Sync progress shows deterministic counts ("Syncing 3 of 5")
**Research**: Unlikely (UI additions, patterns established)
**Plans**: TBD

Plans:
- [ ] 07-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7
Note: Phases 2 and 3 can execute in parallel (no dependencies on each other).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 4/4 | Complete | 2026-01-15 |
| 2. HealthKit Reliability | 3/3 | Complete | 2026-01-16 |
| 3. Geofence Reliability | 3/3 | Complete | 2026-01-16 |
| 4. Code Quality | 2/2 | Complete | 2026-01-16 |
| 5. Sync Engine | 0/? | Not started | - |
| 6. Server API | 0/? | Not started | - |
| 7. UX Indicators | 0/? | Not started | - |

---
*Roadmap created: 2026-01-15*
*Requirements coverage: 25/25 (100%)*
