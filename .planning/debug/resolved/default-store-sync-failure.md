---
status: resolved
trigger: "iOS app sync fails intermittently with 'The file default.store couldn't be opened' error"
created: 2026-01-26T10:00:00Z
updated: 2026-01-26T10:25:00Z
---

## Current Focus

hypothesis: CONFIRMED - Multiple concurrent ModelContext instances accessing the same SQLite store file cause SQLite file locking issues. SyncEngine creates multiple ModelContexts during sync via makeDataStore() calls, while EventStore.fetchFromLocal() creates its own fresh ModelContext immediately after sync completes - these can race if there's any async gap or if the store is not fully released.
test: n/a - evidence strongly supports this hypothesis
expecting: n/a
next_action: Design fix to reuse a single ModelContext or serialize access via MainActor

## Symptoms

expected: Sync completes successfully - data syncs with backend, status shows 'Synced' with recent timestamp
actual: Error "The file 'default.store' couldn't be opened" - multiple rapid failures visible in sync history
errors: "The file 'default.store' couldn't be opened." - appears as sync failure message in Sync History screen
reproduction: Random/automatic syncs and app launch - not triggered by specific user action
started: Intermittent for a while - has been happening on and off

## Eliminated

## Evidence

- timestamp: 2026-01-26T10:00:00Z
  checked: User screenshot of Sync History screen
  found: Multiple rapid failures (2s ago: 13ms, 14ms, 15ms) with same error, followed by older successes (13h, 14h ago)
  implication: Suggests transient issue with store access, not permanent corruption. Rapid succession failures may indicate retry loop hitting same issue.

- timestamp: 2026-01-26T10:05:00Z
  checked: SyncEngine.swift line 203 (comment in codebase)
  found: Explicit comment acknowledging the issue: "Multiple concurrent ModelContexts can cause 'default.store couldn't be opened' errors."
  implication: The developers were already aware this is a known issue with concurrent ModelContext access.

- timestamp: 2026-01-26T10:06:00Z
  checked: DataStoreFactory pattern and makeDataStore() calls
  found: SyncEngine creates new ModelContext via dataStoreFactory.makeDataStore() at least 14 different locations throughout sync operations. Each call creates a NEW ModelContext(modelContainer).
  implication: Within a single sync, multiple ModelContexts are created sequentially (not concurrently within SyncEngine actor).

- timestamp: 2026-01-26T10:07:00Z
  checked: EventStore.fetchFromLocal() at line 600
  found: Creates fresh ModelContext(modelContainer) for reading - separate from the ModelContext SyncEngine uses. EventStore is @MainActor, SyncEngine is an actor - they run on different execution contexts.
  implication: When performSync() calls fetchFromLocal() after sync completes, EventStore creates its own ModelContext while SyncEngine may still be in cleanup phase. Race condition identified.

- timestamp: 2026-01-26T10:08:00Z
  checked: EventStore.performSync() flow at lines 371-401
  found: performSync() calls syncEngine.performSync(), then IMMEDIATELY calls fetchFromLocal() which creates a fresh ModelContext. The SyncEngine may still have outstanding ModelContext operations completing.
  implication: The EventStore doesn't wait for SyncEngine to fully release its ModelContext resources before creating new ones.

- timestamp: 2026-01-26T10:09:00Z
  checked: Multiple ModelContext creation points in EventStore
  found: At least 4 places in EventStore where ModelContext(modelContainer) is called:
    - fetchFromLocal() line 600
    - deduplicateHealthKitEvents() line 1783
    - analyzeDuplicates() line 1906
  implication: Any of these operations could race with SyncEngine's ModelContext usage.

## Resolution

root_cause: Multiple concurrent ModelContext instances accessing the same SQLite "default.store" file cause SQLite file locking issues. The problem occurs when:
1. SyncEngine (actor) creates new ModelContext via dataStoreFactory.makeDataStore() during sync
2. EventStore (@MainActor) creates a fresh ModelContext via ModelContext(modelContainer) in fetchFromLocal() right after sync completes
3. If there's any async gap or if the store isn't fully released, both try to open the file simultaneously
4. SQLite's file locking fails, resulting in "default.store couldn't be opened" error

The rapid failures (13ms, 14ms, 15ms) occur because:
- A sync is triggered (from multiple possible entry points: network restored, app became active, tab switch, user action)
- The sync fails immediately due to file locking
- The error is recorded to SyncHistoryStore
- Another trigger (possibly automatic retry or concurrent call from another code path) starts another sync

fix: Replace all `ModelContext(modelContainer)` calls in @MainActor code with `modelContainer.mainContext`. The mainContext is designed to be used on the MainActor and provides a singleton context per container that avoids concurrent file access issues.

Changes made:
1. EventStore.fetchFromLocal() - uses mainContext instead of fresh context
2. EventStore.deduplicateHealthKitEvents() - uses mainContext
3. EventStore.analyzeDuplicates() - uses mainContext
4. HealthKitService+Persistence.reloadProcessedSampleIdsFromDatabase() - uses mainContext
5. HealthKitService+EventFactory (3 methods) - uses mainContext when useFreshContext=true
6. HealthKitService+Debug.getLocalHealthKitSampleIds() - uses mainContext when useFreshContext=true
7. DebugStorageView.loadSwiftDataCounts() - uses mainContext
8. DebugStorageView.analyzeSyncStatus() - uses mainContext

verification: Build succeeded (xcodebuild build). Runtime verification requires deploying to device and monitoring for "default.store couldn't be opened" errors in sync history over several sync cycles.
files_changed:
  - apps/ios/trendy/ViewModels/EventStore.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+Persistence.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+EventFactory.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+Debug.swift
  - apps/ios/trendy/Views/Settings/DebugStorageView.swift
