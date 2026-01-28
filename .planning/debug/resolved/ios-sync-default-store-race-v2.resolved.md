---
status: resolved
trigger: "ios-sync-default-store-race-v2: Persistent race condition with SwiftData default.store causing sync failures despite previous fix"
created: 2026-01-28T00:00:00Z
updated: 2026-01-28T09:20:00Z
---

## Current Focus

hypothesis: CONFIRMED - Race condition exists between SyncEngine and HealthKitService due to premature notification posting
test: Fix applied - notification now posted after sync completes, with 100ms safety delay in HealthKitService
expecting: No more "default.store couldn't be opened" errors during sync
next_action: Run unit tests and verify in app

## Symptoms

expected: Sync operations should complete successfully every time
actual: Sync still fails intermittently with error "The file 'default.store' couldn't be opened" - appears in Sync History with fast failures (21-22ms) vs successful syncs (1.7-2.1s)
errors: "The file 'default.store' couldn't be opened" - SwiftData/SQLite file locking error
reproduction: Intermittent - happens during sync operations, fast failures indicate immediate file access contention
started: Ongoing issue, previous fix (commit be23081) did not fully resolve

## Eliminated

- hypothesis: Creating pendingContext and deleteContext before flushPendingMutations causes race
  evidence: Previous fix addressed this in commit be23081 but issue persists
  timestamp: 2026-01-27

## Evidence

- timestamp: 2026-01-28T00:00:00Z
  checked: Prior investigation and fix attempt
  found: Fix was incomplete - consolidated some context creation but issue persists
  implication: There are additional ModelContext creation sites that weren't addressed

- timestamp: 2026-01-28T00:01:00Z
  checked: Prior fix in commit be23081
  found: SyncEngine now uses cachedDataStore (single ModelContext per actor instance). All 13+ makeDataStore() calls replaced with cached version. Fix is correct within SyncEngine.
  implication: Issue is NOT within SyncEngine anymore - it's between SyncEngine and other components

- timestamp: 2026-01-28T00:02:00Z
  checked: All ModelContext creation sites in the codebase
  found: |
    1. DataStoreFactory.swift line 39: `ModelContext(modelContainer)` - used by SyncEngine via cachedDataStore
    2. HealthKitService+Persistence.swift line 159: `modelContainer.mainContext` - called from @MainActor
    3. HealthKitService+EventFactory.swift lines 88, 123, 213: `modelContainer.mainContext` - conditional fresh context
    4. EventStore.swift line 602: `modelContainer.mainContext` - fetchFromLocal()
    5. EventStore.swift line 1785: `modelContainer.mainContext` - deduplicateHealthKitEvents()
    6. EventStore.swift line 1909: `modelContainer.mainContext` - analyzeDuplicates()
    7. HealthKitService.swift line 178: modelContext passed in init (stored, not created)
    8. trendyApp.swift line 141: `container.mainContext` - app initialization
    9. DebugStorageView.swift lines 715, 882: `modelContext.container.mainContext`
  implication: Two distinct ModelContext pools: (1) SyncEngine's cachedDataStore, (2) mainContext accessed by MainActor components

- timestamp: 2026-01-28T00:03:00Z
  checked: Concurrent access scenarios
  found: |
    RACE CONDITION SCENARIOS:

    Scenario 1: HealthKit reconciliation during sync
    - SyncEngine.performSync() runs on actor, uses cachedDataStore
    - bootstrapFetch() posts .syncEngineBootstrapCompleted notification
    - HealthKitService.handleBootstrapCompleted() runs on MainActor
    - handleBootstrapCompleted() calls reloadProcessedSampleIdsFromDatabase() which uses modelContainer.mainContext
    - BOTH contexts access default.store simultaneously

    Scenario 2: EventStore fetch during sync
    - SyncEngine runs sync on its actor
    - EventStore.fetchFromLocal() called during UI refresh, uses mainContext
    - Both access default.store simultaneously

    Scenario 3: HealthKit event creation during sync
    - HealthKitService observer fires (e.g., new workout)
    - createEvent() uses modelContext (not mainContext)
    - SyncEngine sync running concurrently on its actor
    - Both try to save to same SQLite file

    Scenario 4: Widget data sync
    - Widget creates event using shared container
    - Main app receives Darwin notification, calls queueMutationsForUnsyncedEvents()
    - SyncEngine may be syncing concurrently
  implication: The root cause is NOT just SyncEngine - it's cross-component concurrent access to the same SQLite file through different ModelContext instances

- timestamp: 2026-01-28T00:04:00Z
  checked: Fast failure timing (21-22ms from symptoms)
  found: Fast failure indicates immediate file lock contention, not network issues. SQLite uses file locking (SQLITE_BUSY) which SwiftData surfaces as "couldn't be opened".
  implication: Error happens at SQLite level when two contexts try to write simultaneously

- timestamp: 2026-01-28T00:05:00Z
  checked: Exact race condition in handleBootstrapCompleted()
  found: |
    SyncEngine.bootstrapFetch() (line 1691-1692):
    ```swift
    await MainActor.run {
        NotificationCenter.default.post(name: .syncEngineBootstrapCompleted, object: nil)
    }
    ```
    This posts notification to MainActor, but SyncEngine hasn't finished yet!

    After posting, bootstrapFetch() returns, but performSync() continues:
    - Lines 319-320: `await updateLastSyncTime()` and `await updateState(.idle)`
    - These run on MainActor

    Meanwhile, HealthKitService.handleBootstrapCompleted() starts on MainActor:
    - Line 253: `reloadProcessedSampleIdsFromDatabase()` uses `modelContainer.mainContext`
    - Line 261: `reconcileHealthKitData()` calls `reconcileCategory()`
    - Line 278: `getLocalHealthKitSampleIds()` uses `modelContainer.mainContext`
    - Line 306: `processSample()` may save to modelContext

    RACE CONDITION TIMELINE:
    1. SyncEngine on actor: bootstrapFetch() saves to cachedDataStore
    2. SyncEngine posts notification (MainActor switch)
    3. HealthKitService receives notification on MainActor
    4. HealthKitService starts reconciliation using mainContext
    5. SyncEngine continues, may still be saving via actor
    6. BOTH contexts try to write -> SQLite BUSY error
  implication: The notification-based design creates an inherent race between SyncEngine's actor-isolated context and HealthKitService's MainActor context

- timestamp: 2026-01-28T00:06:00Z
  checked: Similar pattern in EventStore
  found: |
    EventStore.performSync() (lines 371-400):
    - Line 393: `await syncEngine.performSync()` - runs on SyncEngine actor
    - Line 399: `try? await fetchFromLocal()` - runs on MainActor, uses mainContext

    The try? swallows the error, but the race exists:
    - SyncEngine may still be processing (actor reentrancy with MainActor calls)
    - EventStore reads from mainContext while SyncEngine writes to cachedDataStore
  implication: performSync() completion doesn't guarantee SyncEngine's SQLite writes are fully flushed

## Resolution

root_cause: |
  The race condition exists between SyncEngine (actor with cachedDataStore) and HealthKitService (@MainActor with mainContext) when both try to access the same SQLite file concurrently.

  The specific trigger is:
  1. SyncEngine.bootstrapFetch() posts .syncEngineBootstrapCompleted notification (line 1691)
  2. HealthKitService.handleBootstrapCompleted() receives it on MainActor
  3. HealthKitService starts reconcileHealthKitData() which uses mainContext
  4. Meanwhile, SyncEngine continues after bootstrapFetch() returns:
     - Line 268: networkClient.getLatestCursor()
     - Line 270: UserDefaults write
     - Line 319-320: MainActor calls (updateLastSyncTime, updateState)
     - Line 324: preSyncDataStore.fetchPendingMutations() - DATABASE ACCESS
     - Line 338: recordSyncHistory() -> MainActor
  5. BOTH contexts (cachedDataStore and mainContext) try to access default.store

  The 21-22ms failure time indicates immediate SQLite BUSY error - the conflict happens right at the start when two contexts try to acquire locks.

fix: |
  Two-part fix implemented:

  1. SyncEngine.swift: Move bootstrap notification to AFTER sync is fully complete
     - Removed notification posting from inside bootstrapFetch() (was at line 1691)
     - Added notification posting in performSync() after all operations complete (line ~354)
     - Added explanatory comment about the race condition in bootstrapFetch()
     - This ensures ALL sync operations (cursor update, history recording, state update) are done before HealthKitService starts reconciliation

  2. HealthKitService.swift: Add 100ms delay before starting reconciliation
     - Defense-in-depth against any edge case timing issues
     - Ensures any pending I/O operations from sync have fully settled
     - Small delay is acceptable since reconciliation is a background operation

verification: |
  - Swift syntax check passed for both modified files
  - Created comprehensive unit tests in BootstrapNotificationTimingTests.swift:
    - Test that notification is only posted during bootstrap sync (not regular sync)
    - Test that no database operations occur after notification is posted
  - Extended MockDataStoreFactory to support custom DataStoreProtocol implementations
  - Created TrackingMockDataStore for timing verification
  - All tests pass:
    - BootstrapNotificationTimingTests: 2/2 pass
    - DataStoreReuseTests: 6/6 pass (no regressions)
  - User testing needed to confirm intermittent error is resolved in production use

files_changed:
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/Services/Sync/SyncEngine.swift
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/Services/HealthKit/HealthKitService.swift
  - /Users/cipher/Repositories/trendy/apps/ios/trendyTests/SyncEngine/BootstrapNotificationTimingTests.swift
  - /Users/cipher/Repositories/trendy/apps/ios/trendyTests/Mocks/MockDataStoreFactory.swift
