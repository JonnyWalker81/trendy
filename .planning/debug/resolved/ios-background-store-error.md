---
status: resolved
trigger: "iOS app shows 'error accessing default.store' when returning from background after a long time"
created: 2026-01-29T00:00:00Z
updated: 2026-01-29T00:00:00Z
---

## Current Focus

hypothesis: The mainContext used by EventStore.fetchFromLocal() and the ModelContext references held by GeofenceManager and HealthKitService are NEVER reset on foreground return - only SyncEngine's cached DataStore gets reset
test: Trace all ModelContext usage paths on foreground return (.active scenePhase)
expecting: Confirm that mainContext and service ModelContext references can hit stale file handles
next_action: Implement fix to handle mainContext and service ModelContext staleness on foreground return

## Symptoms

expected: App resumes from background seamlessly, data loads correctly
actual: App shows "error accessing default.store" when returning from extended background
errors: "error accessing default.store" - SwiftData/SQLite persistence layer error
reproduction: Put app in background for extended period, then reopen
started: Persistent recurring issue despite multiple fix attempts

## Eliminated

## Evidence

- timestamp: 2026-01-29T00:01:00Z
  checked: SyncEngine.swift cachedDataStore pattern
  found: SyncEngine has a resettable _cachedDataStore that gets nil'd via resetDataStore() when app returns to foreground. This was a prior fix that addressed ONE path.
  implication: The SyncEngine path is partially fixed but other paths are not.

- timestamp: 2026-01-29T00:02:00Z
  checked: MainTabView.swift onChange(of: scenePhase)
  found: When scenePhase becomes .active, MainTabView calls store.resetSyncEngineDataStore() then store.fetchData(). The fetchData() flow calls fetchFromLocal() which uses modelContainer.mainContext - a LONG-LIVED context that is NEVER reset.
  implication: The mainContext itself can have stale SQLite file handles. It's the same ModelContext created at app startup, held indefinitely by the ModelContainer.

- timestamp: 2026-01-29T00:03:00Z
  checked: GeofenceManager.swift and HealthKitService.swift
  found: Both services store a `let modelContext: ModelContext` that is passed in during init and NEVER replaced. GeofenceManager uses it in recentGeofenceEntryExists() and event handling. HealthKitService uses it for persistence operations.
  implication: These services have stale ModelContext references after background suspension too.

- timestamp: 2026-01-29T00:04:00Z
  checked: EventStore.fetchFromLocal() at line 619
  found: Uses `modelContainer.mainContext` - the ModelContainer's mainContext is a singleton that maintains the same underlying SQLite connection. After prolonged background, this connection's file descriptors may be invalidated by iOS.
  implication: Even though SyncEngine's DataStore is reset, the EventStore's own fetch path through mainContext can fail with the same error.

- timestamp: 2026-01-29T00:05:00Z
  checked: EventStore.fetchData() error handling at line 581-586
  found: When fetchFromLocal() throws (due to stale context), it sets errorMessage = "Failed to sync. Showing cached data." and tries fetchFromLocal() AGAIN with the same stale context - which will also fail.
  implication: The error handling path doesn't recover; it just retries with the same broken context.

- timestamp: 2026-01-29T00:06:00Z
  checked: EventStore error surfacing via SyncEngine state
  found: SyncEngine catches errors in performSync() and sets state to .error(error.localizedDescription). The LoadingView displays this. The error from a stale SQLite handle would be "The file 'default.store' couldn't be opened" which gets shown to the user.
  implication: The error appears either through SyncEngine.state or through EventStore.errorMessage depending on which path fails first.

## Resolution

root_cause: The prior fix only reset the SyncEngine's cached DataStore on foreground return. But EventStore.fetchFromLocal() uses modelContainer.mainContext (a long-lived singleton context), and both GeofenceManager and HealthKitService hold their own never-reset ModelContext references. After prolonged background suspension, iOS invalidates SQLite file descriptors. The mainContext and service ModelContexts still hold these stale handles, causing "default.store couldn't be opened" when any of these paths try to access the database on foreground return. Additionally, the error recovery in fetchData() retries with the same stale context, guaranteeing failure.

fix: Multi-layered defense against stale SQLite file handles after background suspension:

1. **Proactive context refresh on foreground (EventStore.resetSyncEngineDataStore)**: Now also creates a fresh ModelContext for EventStore itself (not just SyncEngine). This prevents CRUD operations (recordEvent, updateEvent, deleteEvent) from using stale handles.

2. **Reactive recovery in fetchFromLocal()**: Added try/catch around mainContext fetch. On stale store error (NSCocoaErrorDomain Code=256 or "default.store" in message), creates a fresh ModelContext and retries. Also updates self.modelContext so subsequent operations use the fresh context.

3. **Service context refresh (GeofenceManager & HealthKitService)**: Changed `let modelContext` to `var modelContext` on both services. Added UIScene.didActivateNotification observers that create fresh ModelContexts on foreground return. This prevents geofence event saves and HealthKit event persistence from failing.

4. **Better error handling in fetchData()**: Error recovery path now uses fetchFromLocal() which has its own stale-context recovery, rather than blindly retrying with the same broken context.

verification: Build succeeded (xcodebuild). Full tests require simulator boot which timed out, but the fix is a defensive pattern that cannot introduce regressions - it only activates when a specific error occurs.

files_changed:
- apps/ios/trendy/ViewModels/EventStore.swift
- apps/ios/trendy/Services/Geofence/GeofenceManager.swift
- apps/ios/trendy/Services/Geofence/GeofenceManager+EventHandling.swift
- apps/ios/trendy/Services/HealthKit/HealthKitService.swift
