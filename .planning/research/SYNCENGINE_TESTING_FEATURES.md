# Features Research: SyncEngine Testing Coverage

**Domain:** Offline-first sync engine testing
**Researched:** 2026-01-21
**Confidence:** HIGH

## Executive Summary

Testing a 1,800-line Swift actor sync engine requires comprehensive coverage across five core dimensions: circuit breaker resilience, resurrection prevention, mutation deduplication, cursor-based pagination, and bootstrap synchronization. This research identifies table stakes tests (proving correctness), differentiating tests (proving robustness under edge cases), and anti-features (over-testing patterns to avoid).

**Key finding:** The code review's 3/5 testability rating stems from hard-coded dependencies (APIClient, ModelContainer). Comprehensive testing requires protocol-based dependency injection to enable mocking. Without DI refactoring, testing coverage will remain limited to integration-level tests.

## Test Coverage Categories

### Table Stakes (Must Have)

Essential tests that prove core functionality works correctly. Missing any of these means the sync engine is untested in critical paths.

| Feature | Test Scenarios | Complexity | Notes |
|---------|----------------|------------|-------|
| **Circuit Breaker - Basic States** | Closed → Open → Half-Open transitions | Medium | Requires time manipulation for backoff |
| **Circuit Breaker - Threshold** | Trips after exactly 3 consecutive 429s | Low | Core safety mechanism |
| **Circuit Breaker - Reset** | Success resets consecutive error counter | Low | Prevents false trips |
| **Resurrection Prevention** | Entity with pending DELETE not recreated | Medium | Race condition prevention |
| **Mutation Deduplication** | Duplicate entityId+operation rejected | Low | Prevents retry storms |
| **Single-flight Sync** | Concurrent sync calls result in single execution | Medium | Actor isolation test |
| **Cursor Pagination - Happy Path** | Fetch changes with hasMore=true continues | Low | Core pull mechanism |
| **Cursor Pagination - Empty** | Empty change feed returns hasMore=false | Low | End-of-stream handling |
| **Bootstrap - First Sync** | cursor=0 triggers full fetch | Low | Initial sync verification |
| **Mutation Queue - CRUD** | Create/Update/Delete mutations flush correctly | Medium | Core mutation handling |
| **Batch Processing** | Events batched in groups of 50 | Low | Performance optimization |
| **Error Recovery - Retry Limit** | Mutation marked failed after max attempts | Medium | Prevents infinite retry |
| **Idempotency** | Duplicate requests handled via clientRequestId | Medium | Prevents duplicate creation |

**Total Table Stakes Tests:** ~35-45 test cases

### Differentiators (Nice to Have)

Advanced tests that prove robustness under edge cases. These increase confidence but aren't strictly required for basic correctness.

| Feature | Test Scenarios | Complexity | Value Proposition |
|---------|----------------|------------|-------------------|
| **Circuit Breaker - Exponential Backoff** | Backoff multiplier doubles (30s → 60s → 120s) capped at 300s | High | Proves backoff scales correctly |
| **Circuit Breaker - Mixed Errors** | Rate limit + success + rate limit doesn't trip | Medium | Real-world error patterns |
| **Resurrection - Memory + Disk** | pendingDeleteIds checked in both Set and SwiftData | High | Belt-and-suspenders verification |
| **Cursor Pagination - Mid-Flight Data Changes** | Data added during pagination doesn't break fetch | High | Real-world consistency |
| **Cursor Pagination - Invalid Cursor** | Backend returns error for stale cursor | Medium | Error handling |
| **Batch Processing - Partial Failure** | Some events in batch fail, others succeed | High | Proves granular error handling |
| **Batch Processing - HealthKit Upsert** | Match by healthKitSampleId when ID differs | High | Real-world deduplication |
| **Offline Queue - Persistence** | Pending mutations survive app restart | Medium | Durability guarantee |
| **Network Transitions** | Online → Offline → Online sync resumes | High | Real-world network conditions |
| **Geofence Sync** | Geofences synced independently after pull | Low | Feature completeness |
| **Property Definitions** | Custom properties sync with event types | Medium | Feature completeness |
| **Health Check - Captive Portal** | Sync skipped if health check fails | Medium | Prevents false success |
| **Relationship Restoration** | Event→EventType relationship restored after bootstrap | Medium | Data integrity |
| **Nuclear Cleanup** | Bootstrap deletes ALL local data before repopulating | Low | Clean slate guarantee |

**Total Differentiator Tests:** ~25-35 test cases

### Anti-Features (Avoid)

Testing patterns that waste effort or create flaky tests.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Testing UI State Directly** | SyncState is MainActor-bound, hard to observe in tests | Test state transitions via mock callbacks, not direct property reads |
| **Over-mocking SwiftData** | Mocking ModelContainer/ModelContext is brittle | Use in-memory ModelContainer with isStoredInMemoryOnly: true |
| **Testing Exact Timing** | Backoff timing tests (30.0s vs 29.9s) are flaky | Test timing ranges or relative ordering, not exact values |
| **Integration-Heavy Tests** | Testing against real Supabase backend in CI | Use protocol-based mocks for APIClient |
| **Testing Internal Logging** | Asserting on Log.sync.info calls | Logging is observability, not behavior |
| **Testing Thread Safety Explicitly** | Actor already guarantees thread safety | Trust Swift concurrency unless debugging a race |
| **Testing Every Error Path** | Every APIError variation (timeout, decode, etc.) | Test error categories (rate limit, duplicate, other) |
| **Snapshot Testing Mutation Queue** | Queue order may vary due to retry backoff | Test queue count and entityId presence, not order |

## Test Scenarios by Component

### 1. Circuit Breaker Tests

**Core Behavior:**
- Trips after 3 consecutive rate limit errors (429 responses)
- Exponential backoff: 30s → 60s → 120s → 240s (capped at 300s)
- Reset on any successful mutation
- Manual reset via resetCircuitBreaker()

**Table Stakes Tests:**
```swift
// 1. Basic state transitions
testCircuitBreakerTripsAfterThreeConsecutive429s()
testCircuitBreakerResetsOnSuccess()
testCircuitBreakerManualReset()

// 2. Backoff behavior
testCircuitBreakerFirstTripBackoff30Seconds()
testCircuitBreakerBackoffCappedAt300Seconds()

// 3. State exposure
testIsCircuitBreakerTrippedReturnsTrueWhenInBackoff()
testCircuitBreakerBackoffRemainingCalculatesCorrectly()
```

**Differentiator Tests:**
```swift
// 1. Mixed error scenarios
testCircuitBreakerDoesNotTripOnNonRateLimitErrors()
testCircuitBreakerCounterResetsOnSuccessBetweenFailures()

// 2. Backoff progression
testCircuitBreakerBackoffMultiplierDoublesEachTrip()
testCircuitBreakerBackoffExponentialProgression()

// 3. User state visibility
testSyncStateShowsRateLimitedWithCorrectRetryAfter()
```

**Dependencies:**
- Mock APIClient returning APIError.rateLimitError
- Controllable time (Date/Clock injection for backoff verification)
- In-memory ModelContainer for pending mutations

**Complexity Notes:**
- Time manipulation HIGH complexity (need Clock protocol or test scheduler)
- State observation MEDIUM (actor isolation + MainActor state)

### 2. Resurrection Prevention Tests

**Core Behavior:**
- Capture pending DELETE mutations before flush
- Skip pullChanges upserts for entities in pendingDeleteIds
- Dual check: in-memory Set + SwiftData persistence
- Clear pendingDeleteIds after successful sync

**Table Stakes Tests:**
```swift
// 1. Core prevention
testPendingDeleteEntityNotRecreatedDuringPull()
testPendingDeleteIdsClearedAfterSuccessfulSync()

// 2. Persistence
testPendingDeleteIdsPersistedToUserDefaults()
testPendingDeleteIdsLoadedOnInit()
```

**Differentiator Tests:**
```swift
// 1. Belt-and-suspenders verification
testResurrectionPreventionUsesInMemorySetFirst()
testResurrectionPreventionFallsBackToSwiftData()

// 2. Edge cases
testPendingDeleteIdsClearedEvenOnSyncFailure()
testMultiplePendingDeletesPreventMultipleResurrections()

// 3. Environment isolation
testPendingDeleteIdsEnvironmentSpecific()
```

**Dependencies:**
- Mock APIClient returning ChangeEntry with CREATE operation
- In-memory ModelContainer with pending DELETE mutations
- UserDefaults mock or real UserDefaults with unique keys

**Complexity Notes:**
- Dual-check verification MEDIUM (both Set and SwiftData)
- Environment-specific keys LOW (just verify cursorKey format)

### 3. Mutation Deduplication Tests

**Core Behavior:**
- queueMutation() checks for existing PendingMutation with same entityId + operation
- Skip insertion if duplicate found
- Log duplicate skip for debugging

**Table Stakes Tests:**
```swift
// 1. Basic deduplication
testDuplicateMutationSkippedWhenSameEntityIdAndOperation()
testDuplicateMutationAllowedForDifferentOperations()
testDuplicateMutationAllowedForDifferentEntities()
```

**Differentiator Tests:**
```swift
// 1. Edge cases
testMultipleDuplicatesSkippedCorrectly()
testDeduplicationWorksAcrossEntityTypes()

// 2. Pending count accuracy
testPendingCountDoesNotIncreaseForDuplicates()
```

**Dependencies:**
- In-memory ModelContainer for PendingMutation queries
- No APIClient needed (local-only logic)

**Complexity Notes:**
- Low complexity (straightforward SwiftData predicate logic)

### 4. Cursor-Based Pagination Tests

**Core Behavior:**
- Fetch changes with limit=100
- Continue while hasMore=true
- Update cursor only if nextCursor > lastSyncCursor
- Persist cursor to environment-specific UserDefaults key

**Table Stakes Tests:**
```swift
// 1. Basic pagination
testPullChangesWithHasMoreTrueContinuesFetching()
testPullChangesWithHasMoreFalseStops()
testCursorUpdatesOnlyWhenAdvancing()

// 2. Empty response
testPullChangesWithEmptyChangeFeedReturnsImmediately()

// 3. Cursor persistence
testCursorPersistedToUserDefaults()
testCursorLoadedFromUserDefaultsOnInit()
```

**Differentiator Tests:**
```swift
// 1. Edge cases
testCursorNotResetToZeroAfterBootstrap()
testMultiplePagesFetchedUntilHasMoreFalse()
testInvalidCursorHandledGracefully()

// 2. Data consistency
testDataAddedDuringPaginationDoesNotCauseDuplicates()
```

**Dependencies:**
- Mock APIClient returning ChangeFeedResponse with hasMore flag
- In-memory ModelContainer for applying changes
- UserDefaults mock or real with unique keys

**Complexity Notes:**
- Pagination loop MEDIUM (mock multiple responses)
- Cursor advancement LOW (numeric comparison)

### 5. Bootstrap Fetch Tests

**Core Behavior:**
- Triggered when cursor=0 or forceBootstrapOnNextSync=true
- Nuclear cleanup: DELETE ALL local data first
- Fetch order: EventTypes → Geofences → Events → PropertyDefinitions
- Restore Event→EventType relationships
- Skip pullChanges after bootstrap
- Set cursor to latest after bootstrap

**Table Stakes Tests:**
```swift
// 1. Bootstrap trigger
testBootstrapTriggeredWhenCursorIsZero()
testBootstrapTriggeredWhenForceBootstrapFlagSet()

// 2. Nuclear cleanup
testBootstrapDeletesAllLocalDataBeforeRepopulating()

// 3. Fetch order
testBootstrapFetchesEventTypesFirst()
testBootstrapFetchesEventsAfterEventTypes()

// 4. Cursor advancement
testBootstrapSetsCursorToLatestAfterCompletion()
```

**Differentiator Tests:**
```swift
// 1. Relationship restoration
testBootstrapRestoresEventToEventTypeRelationships()
testBootstrapLogsOrphanedEventsWithMissingEventTypes()

// 2. Post-bootstrap behavior
testPullChangesSkippedAfterBootstrap()
testForceBootstrapFlagResetAfterExecution()

// 3. HealthKit notification
testBootstrapPostsCompletedNotification()
```

**Dependencies:**
- Mock APIClient returning all entity types (EventTypes, Events, Geofences, PropertyDefinitions)
- In-memory ModelContainer (verify nuclear cleanup)
- NotificationCenter observation (bootstrap completion)

**Complexity Notes:**
- Nuclear cleanup verification HIGH (verify all entities deleted)
- Fetch order verification MEDIUM (sequential async calls)
- Relationship restoration MEDIUM (SwiftData relationship setup)

### 6. Batch Processing Tests

**Core Behavior:**
- Group Event CREATE mutations in batches of 50
- Call apiClient.createEventsBatch()
- Handle partial failures (some succeed, some fail)
- Match HealthKit events by healthKitSampleId for upserts
- Mark succeeded events as synced, retry failed events

**Table Stakes Tests:**
```swift
// 1. Basic batching
testEventCreateMutationsBatchedInGroupsOf50()
testBatchCreateRequestSentToAPIClient()

// 2. Success handling
testSuccessfulBatchMarksEventsSynced()
testSuccessfulBatchDeletesMutations()
```

**Differentiator Tests:**
```swift
// 1. Partial failures
testPartialBatchFailureRetryFailedEventsOnly()
testBatchErrorsRecordedPerMutation()

// 2. HealthKit upsert matching
testHealthKitEventMatchedBySampleIdWhenIdDiffers()
testLocalDuplicateDeletedAfterHealthKitUpsert()

// 3. Duplicate detection
testBatchItemDuplicateHandledAsSuccess()
```

**Dependencies:**
- Mock APIClient returning CreateEventsBatchResponse
- In-memory ModelContainer with PendingMutation and Event entities
- LocalStore mock or real (for markEventSynced)

**Complexity Notes:**
- Partial failure handling HIGH (selective mutation deletion)
- HealthKit matching HIGH (secondary lookup by sample ID)

### 7. Single-Flight Sync Tests

**Core Behavior:**
- isSyncing flag prevents concurrent performSync() calls
- Second call returns immediately if first is in progress
- Actor isolation ensures thread safety

**Table Stakes Tests:**
```swift
// 1. Basic single-flight
testConcurrentPerformSyncCallsResultInSingleExecution()
testSecondSyncCallSkippedWhileFirstInProgress()
testSyncFlagResetAfterCompletion()
```

**Differentiator Tests:**
```swift
// 1. Edge cases
testSyncFlagResetEvenAfterError()
testManualRetrySyncAfterFailure()
```

**Dependencies:**
- Mock APIClient (slow response to simulate in-flight sync)
- Actor isolation verification (Swift concurrency test)

**Complexity Notes:**
- Concurrency testing MEDIUM (actor + async/await)
- Timing coordination MEDIUM (ensure first sync still running)

## Dependencies and Test Infrastructure

### Required Dependency Injection Changes

The SyncEngine currently has hard-coded dependencies that prevent unit testing:

```swift
// Current (3/5 testability)
actor SyncEngine {
    private let apiClient: APIClient
    private let modelContainer: ModelContainer
}

// Recommended (5/5 testability)
protocol APIClientProtocol {
    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse
    func createEventsBatch(_ requests: [CreateEventRequest]) async throws -> CreateEventsBatchResponse
    // ... all other API methods
}

actor SyncEngine {
    private let apiClient: APIClientProtocol
    private let modelContainer: ModelContainer
}
```

**Refactoring scope:** Extract APIClient protocol (~20-30 method signatures)

### Test Infrastructure Components

| Component | Purpose | Implementation |
|-----------|---------|----------------|
| **MockAPIClient** | Simulate backend responses | Conforms to APIClientProtocol, returns configurable responses |
| **InMemoryModelContainer** | Isolated SwiftData storage | ModelConfiguration(isStoredInMemoryOnly: true) |
| **TestClock** | Controllable time for backoff tests | Protocol-based Clock injection (Date replacement) |
| **NotificationObserver** | Capture bootstrap notifications | XCTestExpectation-based notification listener |
| **LocalStoreMock** | Optional (can use real with in-memory container) | Mock or use real LocalStore with test container |

### Test Helper Patterns

```swift
// 1. Actor-based test setup
@MainActor
class SyncEngineTests: XCTestCase {
    var mockAPIClient: MockAPIClient!
    var testContainer: ModelContainer!
    var sut: SyncEngine!

    override func setUp() async throws {
        mockAPIClient = MockAPIClient()
        testContainer = try ModelContainer(
            for: Event.self, EventType.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        sut = SyncEngine(apiClient: mockAPIClient, modelContainer: testContainer)
        await sut.loadInitialState()
    }
}

// 2. Mock API responses
class MockAPIClient: APIClientProtocol {
    var getChangesResponses: [ChangeFeedResponse] = []
    var getChangesCallCount = 0

    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse {
        defer { getChangesCallCount += 1 }
        return getChangesResponses[getChangesCallCount]
    }
}

// 3. Time-based testing
protocol ClockProtocol {
    func now() -> Date
}

struct TestClock: ClockProtocol {
    var currentDate: Date
    func now() -> Date { currentDate }
}
```

## Complexity Assessment

| Test Category | Low | Medium | High |
|---------------|-----|--------|------|
| Circuit Breaker | 3 tests | 2 tests | 2 tests (time control) |
| Resurrection Prevention | 2 tests | 3 tests | 2 tests (dual-check) |
| Mutation Deduplication | 3 tests | 1 test | 0 tests |
| Cursor Pagination | 3 tests | 2 tests | 2 tests (consistency) |
| Bootstrap Fetch | 2 tests | 3 tests | 2 tests (nuclear cleanup) |
| Batch Processing | 2 tests | 1 test | 3 tests (partial failures) |
| Single-flight Sync | 2 tests | 2 tests | 0 tests |

**Total Distribution:**
- **Low Complexity (17 tests):** Straightforward assertions, no time control needed
- **Medium Complexity (14 tests):** Multi-step setup, SwiftData verification
- **High Complexity (11 tests):** Time manipulation, partial failures, dual-check verification

## Test Execution Strategy

### Phase 1: Foundation (Table Stakes)
**Goal:** Prove core functionality works
**Tests:** 35-45 tests
**Timeline:** 1-2 weeks
**Dependencies:** APIClient protocol extraction, MockAPIClient, InMemoryModelContainer

### Phase 2: Robustness (Differentiators)
**Goal:** Prove edge case handling
**Tests:** 25-35 tests
**Timeline:** 1-2 weeks
**Dependencies:** TestClock for time control, advanced mocks for partial failures

### Phase 3: Cleanup (Remove Anti-Features)
**Goal:** Remove flaky/brittle tests
**Timeline:** 3-5 days
**Focus:** Replace integration tests with unit tests, remove timing-sensitive assertions

## Success Metrics

| Metric | Target | Rationale |
|--------|--------|-----------|
| Code Coverage | 80%+ | SyncEngine is critical path, needs high coverage |
| Test Execution Time | <5s total | Fast feedback loop for TDD |
| Flaky Test Rate | 0% | No timing-sensitive assertions |
| Mock Complexity | <200 LOC | Simple mocks reduce maintenance |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **APIClient protocol extraction breaks existing code** | High | Extract incrementally, verify with integration tests |
| **In-memory SwiftData behaves differently than persistent** | Medium | Run critical tests against both configurations |
| **Time-based tests are flaky** | Medium | Use TestClock protocol, not real Date() |
| **Actor isolation makes state observation hard** | Low | Use async test helpers, avoid direct state reads |

## Sources

### Sync Engine Testing
- [Building an offline realtime sync engine](https://gist.github.com/pesterhazy/3e039677f2e314cb77ffe3497ebca07b)
- [Offline-First Done Right: Sync Patterns for Real-World Mobile Networks](https://developersvoice.com/blog/mobile/offline-first-sync-patterns/)
- [Building a Flutter Offline-First Sync Engine with Conflict Resolution](https://medium.com/@pravinkunnure9/building-a-flutter-offline-first-app-flutter-sync-engine-with-conflict-resolution-5a087f695104)

### Circuit Breaker Testing
- [Circuit Breaker Pattern - Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker)
- [Circuit Breaker Pattern: How It Works, Benefits, Best Practices](https://www.groundcover.com/learn/performance/circuit-breaker-pattern)
- [How to Implement Retry Logic with Exponential Backoff in gRPC](https://oneuptime.com/blog/post/2026-01-08-grpc-retry-exponential-backoff/view)

### Swift Testing Patterns
- [Swift Actor in Unit Tests](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631)
- [Writing unit tests with mocked dependencies in Swift](https://dev.to/davidvanerkelens/writing-unit-tests-with-mocked-dependencies-in-swift-2doh)
- [Mocking in Swift | Swift by Sundell](https://www.swiftbysundell.com/articles/mocking-in-swift/)
- [Advanced Unit Testing in Swift: Protocols, Dependency Injection, and HealthKit](https://medium.com/@azharanwar/advanced-unit-testing-in-swift-protocols-dependency-injection-and-healthkit-4795ef4f33ec)

### SwiftData Testing
- [How to write unit tests for your SwiftData code](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-write-unit-tests-for-your-swiftdata-code)
- [SwiftData Architecture Patterns And Practices](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html)
- [Testing SwiftData and the Query property wrapper through an example](https://medium.com/@mgomolka/testing-swiftdata-and-the-query-property-wrapper-through-an-example-3965816b216f)

### Mutation Queue & CRDT Testing
- [The Cascading Complexity of Offline-First Sync: Why CRDTs Alone Aren't Enough](https://dev.to/biozal/the-cascading-complexity-of-offline-first-sync-why-crdts-alone-arent-enough-2gf)
- [TypeScript CRDT Toolkits for Offline-First Apps](https://medium.com/@2nick2patel2/typescript-crdt-toolkits-for-offline-first-apps-conflict-free-sync-without-tears-df456c7a169b)

### Cursor Pagination Testing
- [Understanding Cursor Pagination and Why It's So Fast](https://www.milanjovanovic.tech/blog/understanding-cursor-pagination-and-why-its-so-fast-deep-dive)
- [Cursor pagination: how it works and its pros and cons](https://www.merge.dev/blog/cursor-pagination)
- [Paginating large datasets in production: Why OFFSET fails and cursors win](https://blog.sentry.io/paginating-large-datasets-in-production-why-offset-fails-and-cursors-win/)
