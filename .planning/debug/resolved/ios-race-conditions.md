---
status: resolved
trigger: "Comprehensive investigation of race conditions in the iOS app"
created: 2026-01-28T00:00:00Z
updated: 2026-01-28T00:05:00Z
---

## Current Focus

hypothesis: RESOLVED - Two race conditions found and fixed, plus verified existing protections
test: Build + test suite
expecting: All tests pass, no regressions
next_action: Archive session

## Symptoms

expected: All @Observable classes, async operations, and shared state should be thread-safe with proper actor isolation
actual: Two classes had shared mutable state accessed from multiple threads without synchronization
errors: Recent commits had fixed many race conditions, but two remained
reproduction: Audit codebase for concurrent access patterns
started: Ongoing concern - recent commits have been fixing race conditions

## Eliminated

- hypothesis: @Observable classes without @MainActor isolation
  evidence: All 20+ @Observable classes have @MainActor isolation (verified by grep)
  timestamp: 2026-01-28

- hypothesis: SyncEngine has race conditions
  evidence: SyncEngine is a proper Swift actor with serialized access, uses single-flight pattern
  timestamp: 2026-01-28

- hypothesis: GeofenceManager delegate callbacks cause races
  evidence: All CLLocationManagerDelegate methods dispatch to @MainActor via Task { @MainActor in }. processingGeofenceIds uses early claim pattern. handleGeofenceEntry/Exit are @MainActor isolated.
  timestamp: 2026-01-28

- hypothesis: HealthKitService observer query callbacks cause races
  evidence: handleNewSamples is called via Task from HKObserverQuery callback. All mutable state protected by @MainActor.
  timestamp: 2026-01-28

- hypothesis: AppDelegate pending events queue has race condition
  evidence: Uses NSLock properly for thread-safe access to pendingEvents array
  timestamp: 2026-01-28

- hypothesis: AIBackgroundTaskScheduler has race condition
  evidence: Already @MainActor isolated. nonisolated registerTasks() only calls BGTaskScheduler APIs which are thread-safe.
  timestamp: 2026-01-28

- hypothesis: nonisolated(unsafe) Task properties cause race conditions in deinit
  evidence: Used only for Task.cancel() in deinit, which is thread-safe. Tests exist (MainActorDeinitTests.swift).
  timestamp: 2026-01-28

- hypothesis: MetricsSubscriber delegate methods have race conditions
  evidence: Only does logging in delegate methods. No mutable state is modified.
  timestamp: 2026-01-28

- hypothesis: HealthKitService.isUsingAppGroup static var needs external lock
  evidence: Compiler enforces @MainActor isolation on static vars of @MainActor classes. Cannot be accessed from outside actor boundary.
  timestamp: 2026-01-28

- hypothesis: APIClient @unchecked Sendable has race condition
  evidence: All mutable state (encoder/decoder) only accessed within async methods. Immutable config (baseURL, session). Justified rationale in code comments.
  timestamp: 2026-01-28

## Evidence

- timestamp: 2026-01-28
  checked: All @Observable classes (grep for @Observable)
  found: All have @MainActor isolation
  implication: Previous commits comprehensively fixed @Observable isolation

- timestamp: 2026-01-28
  checked: DeviceInfoCollector.currentNetworkStatus
  found: Written from DispatchQueue.global(qos: .utility) in pathUpdateHandler callback, read without synchronization in getNetworkStatus()
  implication: RACE CONDITION - NWPath written from background queue, read from main/async context

- timestamp: 2026-01-28
  checked: FileLogger.isEnabled
  found: Read without queue dispatch in log() guard check, written on queue via setEnabled(). log() called from any thread.
  implication: RACE CONDITION - bare read of isEnabled outside the serial dispatch queue

- timestamp: 2026-01-28
  checked: HealthKitService static vars
  found: Static vars on @MainActor class are compiler-enforced MainActor-isolated. Cannot be accessed off-actor.
  implication: SAFE - compiler prevents access from wrong thread

- timestamp: 2026-01-28
  checked: SyncEngine actor isolation
  found: Proper Swift actor, all state mutations serialized. Uses DataStoreFactory for thread-safe ModelContext creation.
  implication: SAFE - actor provides isolation

- timestamp: 2026-01-28
  checked: GeofenceManager delegate + background notifications
  found: CLLocationManagerDelegate methods use Task { @MainActor in } dispatch. Background notification handlers (@objc) also use Task { @MainActor in }.
  implication: SAFE - all state mutations funneled to MainActor

- timestamp: 2026-01-28
  checked: Build verification
  found: BUILD SUCCEEDED with all fixes applied
  implication: Fixes compile correctly

- timestamp: 2026-01-28
  checked: Thread safety tests
  found: All 3 new tests passed. Full test suite shows no regressions from changes.
  implication: Fixes verified

## Resolution

root_cause: Two race conditions found in utility classes:
1. DeviceInfoCollector.currentNetworkStatus - Written from background DispatchQueue.global(qos: .utility) via NWPathMonitor callback, read from main/async context without synchronization. Added NSLock-based thread-safe property accessor.
2. FileLogger.isEnabled - Read from caller's thread in log() guard check, written on serial dispatch queue via setEnabled(). Added NSLock-based synchronization so the read in log() is thread-safe.

fix:
1. DeviceInfoCollector: Added NSLock-protected computed property for currentNetworkStatus, wrapping private _currentNetworkStatus backing store.
2. FileLogger: Replaced queue-dispatched setEnabled with NSLock-protected direct write. Added lock-guarded read in log() method.
3. HealthKitService.isUsingAppGroup: Investigated but confirmed already safe - compiler enforces @MainActor isolation on static vars of @MainActor classes. Reverted unnecessary lock addition.

verification:
- BUILD SUCCEEDED
- 3 new ThreadSafetyTests all passed (FileLoggerThreadSafetyTests, HealthKitServiceStaticVarTests)
- Full test suite shows no regressions from changes (only pre-existing failures in LoginFlowUITests and AppConfigurationTests)

files_changed:
- apps/ios/trendy/Utilities/DeviceInfoCollector.swift (NSLock for currentNetworkStatus)
- apps/ios/trendy/Utilities/FileLogger.swift (NSLock for isEnabled)
- apps/ios/trendyTests/ThreadSafetyTests.swift (new test file)
