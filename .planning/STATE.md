# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-01-15)

**Core value:** Data capture must be reliable. When a workout ends or a geofence triggers, that event must be recorded — whether online or offline, whether the app is open or not.
**Current focus:** Phase 5 — Sync Engine (in progress)

## Current Position

Phase: 5 of 7 (Sync Engine)
Plan: 4 of 4 in phase (05-01, 05-02, 05-04 complete)
Status: In progress
Last activity: 2026-01-16 — Completed 05-04-PLAN.md

Progress: █████████░ 60% (15/25 plans complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 15
- Average duration: 6.5 min
- Total execution time: ~98 minutes

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Foundation | 4/4 | 21 min | 5 min |
| 2. HealthKit Reliability | 2/2 | 23 min | 11.5 min |
| 3. Geofence Reliability | 4/4 | 23 min | 5.75 min |
| 4. Code Quality | 2/2 | 27 min | 13.5 min |
| 5. Sync Engine | 3/4 | 21 min | 7 min |

**Recent Trend:**
- Last 5 plans: 04-01 (17m), 04-02 (10m), 05-02 (5m), 05-01 (12m), 05-04 (4m)
- Trend: Gap closure plans are quick to execute

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

| Phase | Decision | Rationale |
|-------|----------|-----------|
| 01-01 | Used Log.healthKit.* calls | Match existing Logger.swift infrastructure |
| 01-01 | Consolidated multi-line prints | Single Log calls with context metadata are cleaner |
| 01-02 | Entitlements verified as-is | All required keys already present |
| 01-02 | Task 3 reused existing work | verifyAppGroupSetup() already had structured logging from 01-01 commit |
| 01-04 | Used @Observable lastError vs throws | CLLocationManagerDelegate Task context makes throws impractical |
| 01-04 | Added clearError() method | Allows UI to reset error state after displaying alert |
| 01-03 | Callers use do/catch with continue-on-error | Background processing should retry, not crash |
| 01-03 | Non-critical methods kept returning bool/nil | eventExists* and findEvent* use cases accept nil/false on error |
| 02-01 | NSKeyedArchiver with secure coding for anchors | HKQueryAnchor conforms to NSSecureCoding |
| 02-01 | Anchors in App Group UserDefaults | Consistent with existing HealthKit persistence |
| 02-01 | Save anchor after query completion | Ensures anchor reflects latest processed position |
| 02-02 | RelativeDateTimeFormatter for relative time | Native iOS API, auto-localizes, handles edge cases |
| 02-02 | Oldest category update in Dashboard | Quick at-a-glance view of HealthKit sync status |
| 02-02 | Set<HealthDataCategory> for refresh tracking | Allows concurrent refreshes with accurate isRefreshing state |
| 03-01 | AppDelegate's CLLocationManager is separate | Exists only to receive background launch events |
| 03-01 | Events forwarded via NotificationCenter | Decouples from GeofenceManager initialization timing |
| 03-01 | CLAuthorizationStatus.description kept in GeofenceManager | Avoid duplicate extension definition |
| 03-02 | ensureRegionsRegistered fetches from SwiftData | Single source of truth for geofence definitions |
| 03-02 | Normal launch notification for ALL launches | Ensures regions checked on background and foreground launches |
| 03-02 | Scene activation triggers ensureRegionsRegistered immediately | Handles iOS dropping regions under memory pressure |
| 03-03 | GeofenceHealthStatus as top-level struct | Cleaner access from views vs nested type |
| 03-03 | Use regionIdentifier for matching | Handles backend ID when available |
| 03-03 | ensureRegionsRegistered() for Fix action | Uses proper reconciliation instead of full refresh |
| 03-04 | Cast CLRegion to CLCircularRegion | Access center.latitude, center.longitude, radius |
| 03-04 | 4 decimal places for coordinates | Sufficient precision for geofence debugging |
| 03-04 | Sort regions by identifier | Consistent display order since Set has no inherent order |
| 04-01 | Swift extension pattern for decomposition | Each file extends HealthKitService with focused functionality |
| 04-01 | Changed private to internal across extensions | Swift cross-file extensions require internal access |
| 04-01 | Created HealthKit subdirectory | Groups 12 related files, matches existing pattern |
| 04-02 | Changed private to internal for cross-extension access | Swift extensions in separate files need internal access |
| 04-02 | Created Geofence subdirectory | Groups related functionality, matches existing pattern |
| 05-01 | Cached sync state properties in EventStore | SwiftUI binding requires non-async properties |
| 05-01 | refreshSyncStateForUI() after sync operations | Keeps UI in sync without polling |
| 05-01 | RelativeDateTimeFormatter with abbreviated style | Shows '5 min ago' format compactly |
| 05-02 | Use getEventTypes() for health check | Always returns data if connected; lightweight; reliable signal |
| 05-02 | Health check before isSyncing guard | No point setting syncing state if we can't connect |
| 05-02 | Keep QueuedOperationV1 in SchemaV1 | Required for V1->V2 migration support |
| 05-04 | Queue mutation BEFORE save for creates/updates | Ensures PendingMutation persists even if force quit interrupts save |
| 05-04 | Delete operations queue BEFORE delete | Entity must exist when queueing to capture any needed data |
| 05-04 | Error handling: mutation queue failure should not block local save | User's data shouldn't be lost just because queue failed |

### Pending Todos

None.

### Blockers/Concerns

- Build verification passes for simulator destination
- Provisioning profile issues only affect device builds (not blocking)
- **BLOCKING:** App freeze when returning from background after going offline (see debug session)

## Session Continuity

Last session: 2026-01-16
Stopped at: Completed 05-04-PLAN.md (mutation atomicity)
Resume file: None
Next: Complete 05-03 verification tests or proceed to next phase
