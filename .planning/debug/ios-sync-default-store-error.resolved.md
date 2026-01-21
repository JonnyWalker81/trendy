---
status: verifying
trigger: "iOS sync fails with 'The file default.store couldn't be opened' error"
created: 2026-01-21T00:00:00Z
updated: 2026-01-21T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED - Multiple concurrent ModelContext instances causing SQLite file locking
test: N/A - Fix applied
expecting: N/A
next_action: Verify fix compiles and test in app

## Symptoms

expected: Sync operations should complete successfully
actual: Sync fails with error "The file 'default.store' couldn't be opened" - occurs intermittently
errors: "The file 'default.store' couldn't be opened" - appears in Sync History screen at 8:33 PM (42ms duration)
reproduction: Intermittent - happens often but exact trigger unknown. Most syncs succeed (shown as green checkmarks with 388ms-1.8s duration), but occasionally fails
started: Happens often, user unsure of exact cause

## Eliminated

## Evidence

- timestamp: 2026-01-21T00:01:00Z
  checked: ModelContainer initialization in trendyApp.swift
  found: Single shared ModelContainer created at app launch (line 57). Uses App Group container with explicit CloudKit=none. Container is passed to SyncEngine via EventStore.setModelContext()
  implication: Single ModelContainer - so issue is not multiple containers, but multiple ModelContexts

- timestamp: 2026-01-21T00:02:00Z
  checked: SyncEngine.swift ModelContext creation patterns
  found: |
    Multiple `ModelContext(modelContainer)` calls throughout SyncEngine:
    - Line 139: loadInitialState() creates context
    - Line 201: performSync() creates pendingContext
    - Line 207: performSync() creates deleteContext
    - Line 392: skipToLatestCursor() creates context
    - Line 435: syncGeofences() creates context
    - Line 470: getLocalGeofenceCount() creates context
    - Line 484: queueMutation() creates context
    - Line 531: getPendingCount() creates context
    - Line 543: clearPendingMutations() creates context
    - Line 648: flushPendingMutations() creates context
    - Line 1273: applyChanges() creates context
    - Line 1506: bootstrapFetch() creates context

    Many of these call context.save() - see lines 460, 519, 567, 704, 891, 1289, etc.
  implication: CRITICAL - performSync() creates 2 contexts (lines 201, 207), then calls flushPendingMutations() which creates another context (line 648). If any of these overlap in their save() calls, SQLite file locking can cause "couldn't be opened" errors.

- timestamp: 2026-01-21T00:03:00Z
  checked: HealthKitService ModelContext usage
  found: |
    HealthKitService+EventFactory.swift uses `useFreshContext` parameter:
    - Line 86: `let context = useFreshContext ? ModelContext(modelContainer) : modelContext`
    - Line 120: Same pattern
    - Line 209: Same pattern

    When useFreshContext=true, creates new ModelContext from modelContainer.
    HealthKitService can run concurrently with SyncEngine during bootstrap notification handling.
  implication: HealthKit reconciliation after bootstrap (handleBootstrapCompleted) runs async and creates fresh contexts that could conflict with ongoing sync operations

- timestamp: 2026-01-21T00:04:00Z
  checked: Error timing context
  found: The error occurs with 42ms duration - extremely fast failure. Successful syncs take 388ms-1.8s. This suggests the error happens immediately when trying to access the store, consistent with file locking.
  implication: Error is likely a SQLite SQLITE_BUSY or file lock error wrapped by SwiftData as "couldn't be opened"

- timestamp: 2026-01-21T00:05:00Z
  checked: flushPendingMutations() calling getPendingCount()
  found: |
    At line 697, flushPendingMutations() calls `getPendingCount()` which creates a SECOND context at line 531:
    ```
    func getPendingCount() async -> Int {
        let context = ModelContext(modelContainer)  // ANOTHER context!
        let descriptor = FetchDescriptor<PendingMutation>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }
    ```
    So during batch processing in flushPendingMutations:
    1. context created at line 648
    2. getPendingCount() creates another context at line 697->531
    3. Both may be active simultaneously
  implication: Confirmed root cause - nested context creation within the same sync operation

## Resolution

root_cause: SyncEngine creates multiple short-lived ModelContexts within a single sync operation. When one context calls save() while another context (from a concurrent operation or the same sync flow) is also accessing the underlying SQLite store, SwiftData throws "The file 'default.store' couldn't be opened". This is a classic SQLite file locking issue exacerbated by:
1. performSync() creating pendingContext and deleteContext before calling flushPendingMutations()
2. flushPendingMutations() creating yet another context, then calling getPendingCount() which creates yet another
3. HealthKitService background operations potentially creating contexts concurrently
4. The SyncEngine is an actor, but creating new ModelContexts inside actor methods doesn't provide thread-safety for the underlying SQLite file

fix: Refactored SyncEngine to reduce concurrent ModelContext usage:
1. Added `getPendingCountFromContext(_ context: ModelContext)` helper method that reuses existing context
2. In `flushPendingMutations()`, now calls `getPendingCountFromContext(context)` instead of `getPendingCount()` to avoid creating concurrent contexts
3. In `performSync()`, consolidated `pendingContext` and `deleteContext` into a single `preSyncContext` with comment explaining why

verification: |
  - Swift syntax check passed (swiftc -parse)
  - Full build failed due to unrelated PostHog dependency issue (libwebp compile error)
  - Code changes are minimal and focused on the identified issue
  - User testing needed to confirm intermittent error is resolved

files_changed:
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/Services/Sync/SyncEngine.swift
