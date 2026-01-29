---
status: resolved
trigger: "iOS app throws default.store error when returning from background after extended period"
created: 2026-01-29T00:00:00Z
updated: 2026-01-29T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED - Multiple defense gaps in background-return context refresh strategy
test: Implemented comprehensive fixes and tests
expecting: All stale context paths now have recovery mechanisms
next_action: Archive session

## Symptoms

expected: App resumes from background normally without errors, data loads correctly
actual: default.store error occurs - SwiftData ModelContext/ModelContainer issue where SQLite connection becomes stale
errors: "default.store" error indicating persistent store unavailable or bad state
reproduction: Put iOS app in background for extended period (hours), then foreground
started: Persistent recurring issue

## Eliminated

## Evidence

- timestamp: 2026-01-29T00:01:00Z
  checked: Existing fix history (commits be23081, 8e5cf0c, 04cd918)
  found: Three progressive fixes addressed SyncEngine DataStore caching, resettable DataStore, and ModelContext refresh for EventStore/GeofenceManager/HealthKitService
  implication: Core fix pattern is correct but had remaining gaps

- timestamp: 2026-01-29T00:02:00Z
  checked: EventStore CRUD operations
  found: recordEvent, updateEvent, deleteEvent, createEventType, etc. all use self.modelContext directly without validating it first. The resetSyncEngineDataStore() runs asynchronously in a Task, so a user could tap a button before the refresh completes.
  implication: CRUD operations need proactive context validation

- timestamp: 2026-01-29T00:03:00Z
  checked: SyncEngine.resetDataStore() guard
  found: Had `guard !isSyncing` that skipped the reset if sync was in progress. After prolonged background, the sync's file handles are ALSO stale, so skipping the reset leaves the engine permanently broken.
  implication: Must always reset, and also clear isSyncing flag to prevent stuck state

- timestamp: 2026-01-29T00:04:00Z
  checked: GeofenceManager background event handlers
  found: handleGeofenceEntry/Exit use modelContext for fetch and save. Background geofence events can arrive before UIScene.didActivateNotification fires.
  implication: Need proactive context validation before geofence event handling

- timestamp: 2026-01-29T00:05:00Z
  checked: HealthKitService event factory
  found: createEvent() inserts and saves to modelContext. HealthKit observer queries can fire in background before UIScene.didActivateNotification.
  implication: Need proactive context validation before HealthKit event creation

## Resolution

root_cause: After prolonged background suspension, iOS invalidates SQLite file descriptors. The prior fixes addressed SOME paths but left gaps:
1. EventStore CRUD operations had no stale-context recovery
2. SyncEngine.resetDataStore() was skipped during sync (but sync was also broken)
3. GeofenceManager background event handlers had no pre-operation validation
4. HealthKitService event creation had no pre-operation validation

fix: Defense-in-depth approach with proactive context validation:

1. **EventStore.ensureValidModelContext()**: New method that performs a lightweight fetchCount probe before CRUD operations. If the probe detects stale file handles (NSCocoaErrorDomain Code=256 or "default.store" in error), it creates a fresh ModelContext transparently. Added to all 14 CRUD methods (recordEvent, updateEvent, deleteEvent, createEventType, updateEventType, deleteEventType, createGeofence, updateGeofence, deleteGeofence, syncEventToBackend, syncHealthKitEventUpdate, syncEventTypeToBackend, syncGeofenceToBackend, resyncHealthKitEvents).

2. **SyncEngine.resetDataStore()**: Removed the `guard !isSyncing` skip. Now always clears the cached DataStore. Also resets `isSyncing = false` to prevent the engine from being stuck in a "syncing" state from a pre-background sync that will never complete.

3. **GeofenceManager.ensureValidModelContext()**: New method with same probe pattern. Called at the start of handleGeofenceEntry() and handleGeofenceExit() to handle background geofence events arriving before UIScene.didActivateNotification.

4. **HealthKitService.ensureValidModelContext()**: New method with same probe pattern. Called at the start of createEvent() to handle HealthKit observer queries firing in background.

verification: All 14 new and updated tests pass:
- StaleStoreErrorDetectionTests: 3/3 passed
- SyncEngineResetAlwaysClearsTests: 3/3 passed
- BackgroundForegroundLifecycleTests: 3/3 passed
- DataStoreResetTests: 5/5 passed (including updated resetAlwaysClearsCache)

files_changed:
- apps/ios/trendy/ViewModels/EventStore.swift (ensureValidModelContext + 14 CRUD call sites)
- apps/ios/trendy/Services/Sync/SyncEngine.swift (resetDataStore always clears + resets isSyncing)
- apps/ios/trendy/Services/Geofence/GeofenceManager+EventHandling.swift (ensureValidModelContext + entry/exit handlers)
- apps/ios/trendy/Services/HealthKit/HealthKitService.swift (ensureValidModelContext)
- apps/ios/trendy/Services/HealthKit/HealthKitService+EventFactory.swift (probe before createEvent)
- apps/ios/trendyTests/SyncEngine/DataStoreResetTests.swift (updated resetSkippedDuringSync)
- apps/ios/trendyTests/SyncEngine/StaleContextRecoveryTests.swift (new: 9 tests)
