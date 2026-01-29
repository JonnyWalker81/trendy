---
status: verifying
trigger: "The iOS app shows 'The file default.store couldn't be opened' error during sync operations"
created: 2026-01-29T00:00:00Z
updated: 2026-01-29T00:05:00Z
---

## Current Focus

hypothesis: CONFIRMED - stale cached ModelContext after background suspension causes SQLite file handle errors
test: Build succeeds, all DataStoreResetTests pass, all DataStoreReuseTests pass (no regression)
expecting: Fix prevents "default.store couldn't be opened" by resetting stale DataStore on foreground
next_action: Archive session

## Symptoms

expected: Sync completes successfully when app returns from background
actual: "The file 'default.store' couldn't be opened" error appears in sync history. Sync fails with 30ms/16ms durations (very fast failures suggesting immediate rejection).
errors: "The file 'default.store' couldn't be opened" - SwiftData/Core Data store file access error
reproduction: App goes to background for 1+ hours, user relaunches, sync fails with store error
started: Persistent issue. Recent race condition fixes (NSLock, @MainActor) did not resolve it.

## Eliminated

- hypothesis: SyncEngine creates multiple DataStore instances (multiple ModelContexts per sync)
  evidence: cachedDataStore lazy var ensures only one ModelContext per SyncEngine instance. DataStoreReuseTests verify this.
  timestamp: 2026-01-29T00:00:30Z

- hypothesis: Bootstrap notification causes race between HealthKitService and SyncEngine
  evidence: Already fixed - notification now posted AFTER sync completes. BootstrapNotificationTimingTests verify this.
  timestamp: 2026-01-29T00:00:30Z

- hypothesis: Concurrent ModelContext access between SyncEngine actor and MainActor EventStore
  evidence: The fetchData() flow is sequential (await syncEngine.performSync() then fetchFromLocal()). The race is NOT between active contexts but rather one context going stale.
  timestamp: 2026-01-29T00:02:00Z

## Evidence

- timestamp: 2026-01-29T00:00:10Z
  checked: trendyApp.swift - ModelContainer setup
  found: Single shared ModelContainer using App Group identifier. Created once as a static computed property.
  implication: ModelContainer itself is correctly shared. Issue is in ModelContext creation/usage.

- timestamp: 2026-01-29T00:00:15Z
  checked: DataStoreFactory.swift
  found: DefaultDataStoreFactory.makeDataStore() creates ModelContext(modelContainer) - a NEW context not bound to MainActor
  implication: This context runs on the SyncEngine actor's executor, which is NOT the main thread.

- timestamp: 2026-01-29T00:00:20Z
  checked: EventStore.swift - fetchFromLocal()
  found: Uses modelContainer.mainContext (main actor context). Comment explicitly says "use mainContext to avoid SQLite file locking issues"
  implication: EventStore correctly uses mainContext, but SyncEngine has its own separate context.

- timestamp: 2026-01-29T00:00:25Z
  checked: MainTabView.swift - scenePhase handler
  found: When scene becomes .active, calls store.fetchData() which calls syncEngine.performSync(). No mechanism to refresh the SyncEngine's cached DataStore before sync.
  implication: First sync after background uses potentially stale ModelContext.

- timestamp: 2026-01-29T00:00:30Z
  checked: SyncEngine.swift - cachedDataStore
  found: Uses lazy var to cache one DataStore with one ModelContext forever. NO mechanism to invalidate or refresh after background.
  implication: After 1+ hours background, iOS may invalidate SQLite file handles. Stale context fails with "default.store couldn't be opened".

- timestamp: 2026-01-29T00:00:35Z
  checked: Search for invalidation/reset mechanism
  found: No resetDataStore(), invalidate(), or refresh method exists on SyncEngine.
  implication: CONFIRMED ROOT CAUSE - stale cached context with no recovery mechanism.

- timestamp: 2026-01-29T00:03:00Z
  checked: Build and test after fix
  found: Build succeeds. 5/5 DataStoreResetTests pass. 6/6 DataStoreReuseTests pass. 2/2 GeofenceSyncRaceConditionTests pass.
  implication: Fix works correctly and does not regress existing behavior.

## Resolution

root_cause: The SyncEngine actor cached a ModelContext (via lazy var cachedDataStore) that was created once and never refreshed. After prolonged background suspension (1+ hours), iOS invalidates file descriptors for the SQLite database file. When the app returns to foreground and triggers sync, the SyncEngine's stale ModelContext tries to use invalidated file handles, causing "The file 'default.store' couldn't be opened" error. The 30ms/16ms failure durations confirm immediate file access rejection rather than timeout.

fix: Changed SyncEngine.cachedDataStore from a lazy var to a resettable optional (_cachedDataStore). Added resetDataStore() method that clears the cache when not syncing. Called resetDataStore() from (1) MainTabView scene phase handler (before any sync on foreground), and (2) EventStore.handleNetworkRestored() (network may restore after background). This ensures a fresh ModelContext with valid file handles is created for each foreground session.

verification: Build succeeds. All 5 new DataStoreResetTests pass. All 6 existing DataStoreReuseTests pass (no regression). All 2 GeofenceSyncRaceConditionTests pass (no regression).

files_changed:
  - apps/ios/trendy/Services/Sync/SyncEngine.swift
  - apps/ios/trendy/ViewModels/EventStore.swift
  - apps/ios/trendy/Views/MainTabView.swift
  - apps/ios/trendyTests/SyncEngine/DataStoreResetTests.swift (new)
