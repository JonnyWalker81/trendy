---
status: resolved
trigger: "Comprehensive investigation of race conditions in the iOS app - proactive audit"
created: 2026-01-28T00:00:00Z
updated: 2026-01-28T00:02:00Z
---

## Current Focus

hypothesis: RESOLVED - One race condition found and fixed
test: Build succeeds, all tests pass
expecting: N/A
next_action: Archive session

## Symptoms

expected: All concurrent/async code in the iOS app should be free of race conditions
actual: AIBackgroundTaskScheduler had race condition - mutable properties accessed across isolation domains
errors: None reported - found via proactive audit
reproduction: N/A - audit
started: Ongoing codebase

## Eliminated

- hypothesis: @Observable classes missing @MainActor isolation
  evidence: All 18 @Observable classes have @MainActor annotation. Verified via grep.
  timestamp: 2026-01-28T00:00:30Z

- hypothesis: SwiftData ModelContext threading violations in SyncEngine
  evidence: SyncEngine is an actor with cachedDataStore created via factory inside actor context. DataStoreFactory pattern correctly creates ModelContext within actor isolation.
  timestamp: 2026-01-28T00:00:35Z

- hypothesis: nonisolated(unsafe) Task properties are data races
  evidence: Used only in AppRouter.deinit and SupabaseService.deinit for Task.cancel() which is thread-safe. Tests exist in MainActorDeinitTests.swift confirming safety.
  timestamp: 2026-01-28T00:00:40Z

- hypothesis: APIClient has race conditions as non-isolated class
  evidence: All properties set once in init, never mutated. Effectively immutable. @unchecked Sendable justified.
  timestamp: 2026-01-28T00:00:42Z

- hypothesis: HealthKit observer query callbacks cause race conditions
  evidence: Callbacks create Task { await self.handleNewSamples() } which hops to MainActor. HealthKitService is @MainActor.
  timestamp: 2026-01-28T00:00:45Z

- hypothesis: FileLogger has race conditions with @unchecked Sendable
  evidence: Uses serial DispatchQueue for all state access. Correctly implemented.
  timestamp: 2026-01-28T00:00:47Z

- hypothesis: AppDelegate pending events queue has race conditions
  evidence: Uses NSLock for all access to pendingEvents array. Correctly implemented.
  timestamp: 2026-01-28T00:00:48Z

- hypothesis: SyncMetrics has race conditions with static mutable dictionaries
  evidence: Uses per-metric NSLock for all dictionary access. Correctly implemented.
  timestamp: 2026-01-28T00:00:50Z

## Evidence

- timestamp: 2026-01-28T00:00:10Z
  checked: All @Observable class declarations in trendy/
  found: 18 @Observable classes, ALL have @MainActor annotation
  implication: Observable state mutation from background threads is properly prevented

- timestamp: 2026-01-28T00:00:15Z
  checked: SyncEngine actor isolation and DataStore pattern
  found: SyncEngine is actor, cachedDataStore lazy var creates ModelContext inside actor via factory
  implication: SwiftData threading is correctly handled for sync operations

- timestamp: 2026-01-28T00:00:20Z
  checked: AIBackgroundTaskScheduler class isolation
  found: Plain class (no @MainActor, no actor) with mutable properties. configure() @MainActor but class not. BGTask callbacks run on background queue.
  implication: Data race between configure() writes and BGTask callback reads

- timestamp: 2026-01-28T00:00:25Z
  checked: All @unchecked Sendable classes (APIClient, DefaultDataStoreFactory, FileLogger)
  found: All correctly justified - immutable state, ModelContainer Sendable, serial DispatchQueue
  implication: No issues

- timestamp: 2026-01-28T00:00:30Z
  checked: HKObserverQuery callback pattern
  found: Dispatches to MainActor via Task { await self.handleNewSamples() }
  implication: Safe

- timestamp: 2026-01-28T00:00:35Z
  checked: nonisolated(unsafe) properties in AppRouter and SupabaseService
  found: Used only for Task.cancel() in deinit
  implication: Thread-safe. Tests exist.

- timestamp: 2026-01-28T00:02:00Z
  checked: Build and test verification after fix
  found: Build succeeds with no new errors. MainActorIsolationTests (4 tests) and MainActorDeinitTests (3 tests) all pass.
  implication: Fix is correct and verified

## Resolution

root_cause: AIBackgroundTaskScheduler lacked @MainActor isolation. Its mutable properties (insightsViewModel, eventStore, foundationModelService) were written from @MainActor context via configure() but the class itself was non-isolated. BGTask callbacks run on arbitrary background queues and access self, creating a potential data race when reading these properties.

fix: Added @MainActor isolation to AIBackgroundTaskScheduler class. Made registerTasks() and BGTask handler methods nonisolated since they're called from background queues. Handler methods now dispatch all property access to MainActor via Task { @MainActor in }. Removed redundant @MainActor annotations on methods that inherit isolation from the class.

verification: iOS project builds successfully. All MainActorIsolationTests pass (4 tests including new AIBackgroundTaskScheduler test). All MainActorDeinitTests pass (3 tests). No regressions.

files_changed:
  - apps/ios/trendy/Services/AIBackgroundTaskScheduler.swift
  - apps/ios/trendyTests/MainActorIsolationTests.swift
