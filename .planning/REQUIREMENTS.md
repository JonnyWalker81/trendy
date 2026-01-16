# Requirements: Trendy iOS Data Infrastructure Overhaul

**Defined:** 2026-01-15
**Core Value:** Data capture must be reliable. When a workout ends or a geofence triggers, that event must be recorded — whether online or offline, whether the app is open or not.

**Architecture Principle:** Server does the heavy lifting. iOS client handles platform-specific capture (HealthKit, CoreLocation) and offline storage, then pushes to server for processing, deduplication, and persistence. Keep client thin.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### HealthKit (iOS)

- [ ] **HLTH-01**: User's workout and active energy data is captured via background delivery within iOS timing constraints (1-60 min backgrounded, up to 4 hours if terminated)
- [ ] **HLTH-02**: Observer queries are properly configured for each enabled HealthKit data type
- [ ] **HLTH-03**: Client sends HealthKit samples with external IDs; server handles deduplication
- [ ] **HLTH-04**: User can see when HealthKit data was last updated (freshness indicator)
- [ ] **HLTH-05**: Debug view shows which background delivery queries are actively running

### Geofence (iOS)

- [ ] **GEO-01**: Geofence monitoring persists across app lifecycle (days/weeks without dropping)
- [ ] **GEO-02**: Geofences are re-registered on app launch, device restart, and iOS eviction
- [ ] **GEO-03**: Geofence enter/exit events are logged reliably every time (even if notification delivery fails)
- [ ] **GEO-04**: User can see which geofences are actually registered with iOS vs saved in app (health monitoring)

### Sync Engine (iOS + Server)

- [ ] **SYNC-01**: User can create, edit, and delete events while offline — changes saved locally
- [ ] **SYNC-02**: Offline changes automatically sync when network is restored (no manual action)
- [ ] **SYNC-03**: Client pushes mutations to server; server handles retry/queue persistence (client does simple fire-and-forget with local fallback)
- [ ] **SYNC-04**: User can see sync state (pending count, last sync time, error state)

### Server API

- [ ] **API-01**: Server accepts events with client-generated IDs (UUIDv7) for idempotent creates
- [ ] **API-02**: Server deduplicates HealthKit samples by external_id (same sample not imported twice)
- [ ] **API-03**: Server provides sync status endpoint (pending mutations, last processed timestamp)
- [ ] **API-04**: Server returns clear error responses that client can display to user

### Code Quality (iOS)

- [ ] **CODE-01**: HealthKitService (1,972 lines) is split into focused modules (query management, processors per data type, event factory)
- [ ] **CODE-02**: All print() statements replaced with structured logging (Log.category.level)
- [ ] **CODE-03**: GeofenceManager has clean separation of concerns (auth, registration, event handling)
- [ ] **CODE-04**: Proper error handling and recovery throughout HealthKit and Geofence code paths

### UX Indicators (iOS)

- [ ] **UX-01**: User sees clear sync status indicator (online/syncing/pending/offline)
- [ ] **UX-02**: User can see last sync timestamp ("Last synced: 5 min ago")
- [ ] **UX-03**: Sync errors are surfaced with tappable explanation (not silent failures)
- [ ] **UX-04**: Sync progress shows deterministic counts ("Syncing 3 of 5") not just spinner

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### HealthKit

- **HLTH-V2-01**: Support for additional HealthKit data types beyond current scope

### Geofence

- **GEO-V2-01**: App handles >20 geofences via proximity-based smart rotation (monitor nearest 20, update on significant location change)

### Sync Engine

- **SYNC-V2-01**: Real-time push from backend to iOS (WebSocket/SSE) for instant sync
- **SYNC-V2-02**: Server-side conflict resolution with user notification when local change was overwritten
- **SYNC-V2-03**: Charging-aware sync (more aggressive when device is charging)

### UX

- **UX-V2-01**: User education/onboarding about background limitations and force-quit behavior
- **UX-V2-02**: Background health dashboard showing all system states in one view

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Real-time push (WebSocket/SSE) | Adds complexity; pull-based sync sufficient for now |
| Web app changes | This project focuses on iOS data infrastructure |
| Calendar sync improvements | Separate concern, not part of this overhaul |
| New HealthKit data types | Focus on making existing types reliable first |
| Analytics/insights changes | Downstream of reliable data capture |
| Manual "Sync Now" button | Creates unmet expectations — iOS controls timing |
| Unlimited geofences | iOS hard limit is 20; smart rotation deferred to v2 |
| Continuous location tracking | Massive battery drain; event-driven only |
| Background HealthKit polling | Apple discourages; may break background delivery |
| Silent conflict resolution | User loses changes without knowing |
| Complex client-side retry logic | Server handles queue persistence; client stays thin |

## Traceability

Which phases cover which requirements. Updated by create-roadmap.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HLTH-01 | Phase 2 | Pending |
| HLTH-02 | Phase 2 | Pending |
| HLTH-03 | Phase 2 | Pending |
| HLTH-04 | Phase 2 | Pending |
| HLTH-05 | Phase 2 | Pending |
| GEO-01 | Phase 3 | Pending |
| GEO-02 | Phase 3 | Pending |
| GEO-03 | Phase 3 | Pending |
| GEO-04 | Phase 3 | Pending |
| SYNC-01 | Phase 5 | Pending |
| SYNC-02 | Phase 5 | Pending |
| SYNC-03 | Phase 5 | Pending |
| SYNC-04 | Phase 5 | Pending |
| API-01 | Phase 6 | Pending |
| API-02 | Phase 6 | Pending |
| API-03 | Phase 6 | Pending |
| API-04 | Phase 6 | Pending |
| CODE-01 | Phase 4 | Pending |
| CODE-02 | Phase 1 | Pending |
| CODE-03 | Phase 4 | Pending |
| CODE-04 | Phase 1 | Pending |
| UX-01 | Phase 7 | Pending |
| UX-02 | Phase 7 | Pending |
| UX-03 | Phase 7 | Pending |
| UX-04 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0 ✓

---
*Requirements defined: 2026-01-15*
*Last updated: 2026-01-15 after roadmap creation (all requirements mapped to phases)*
