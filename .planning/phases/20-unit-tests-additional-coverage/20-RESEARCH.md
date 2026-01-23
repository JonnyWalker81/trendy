# Phase 20: Unit Tests - Additional Coverage - Research

**Researched:** 2026-01-23
**Domain:** Swift Testing for concurrent operations, pagination, bootstrap sync, batch processing, and network health checks
**Confidence:** HIGH

## Summary

Phase 20 tests five critical sync patterns not covered in previous test phases: single-flight request coalescing (preventing duplicate concurrent syncs), cursor-based pagination (hasMore flag and cursor advancement), bootstrap fetch operations (full data download with relationship restoration), batch processing with partial failures (50-event batches), and health checks that detect captive portals.

The research reveals that Swift Testing's async/await support makes testing concurrent operations straightforward — tests are simply marked `async` and use `await` for actor calls. The existing test infrastructure (MockNetworkClient, MockDataStore, test helpers) already provides the foundation needed. Key extensions required: pagination response simulation in mocks, concurrent call tracking for single-flight verification, and batch response queues supporting partial success/failure scenarios.

**Primary recommendation:** Follow the established test pattern from Phases 17-19 (fresh dependencies per test, response queue configuration, structured test names with requirement comments). Use Swift's `withThrowingTaskGroup` for simulating concurrent calls, leverage actor isolation for single-flight verification, and extend MockNetworkClient with pagination state tracking.

## Standard Stack

The established testing stack for this phase:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | Xcode 16+ | Modern test framework | Official Apple framework replacing XCTest, built-in async/await support |
| Swift Concurrency | Swift 5.5+ | Async/await, actors, TaskGroup | Native language feature for testing concurrent operations |
| @testable import | Swift | Access internal types | Standard Swift testing pattern for unit tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockNetworkClient | Custom | Network call spy/stub | Already exists, needs extensions for pagination and batch responses |
| MockDataStore | Custom | SwiftData persistence mock | Already exists, provides seedEvent/seedEventType helpers |
| APIModelFixture | Custom | Test data factory | Already exists, creates valid API models |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift Testing | XCTest | XCTest requires more boilerplate, lacks native async support; Swift Testing is Apple's recommended path forward |
| Custom mocks | Real network/database | Real dependencies make tests slow, non-deterministic, and require external services |

**Installation:**
No additional dependencies needed. Swift Testing ships with Xcode 16+, concurrency is built-in.

## Architecture Patterns

### Recommended Test File Structure
```
trendyTests/SyncEngine/
├── CircuitBreakerTests.swift          # Phase 17 (reference)
├── ResurrectionPreventionTests.swift  # Phase 18 (reference)
├── DeduplicationTests.swift           # Phase 19 (reference)
├── SingleFlightTests.swift            # Phase 20 - NEW
├── PaginationTests.swift              # Phase 20 - NEW
├── BootstrapTests.swift               # Phase 20 - NEW
├── BatchProcessingTests.swift         # Phase 20 - NEW
└── HealthCheckTests.swift             # Phase 20 - NEW
```

### Pattern 1: Testing Concurrent Actor Calls (Single-Flight)
**What:** Verify that concurrent calls to an actor method coalesce into a single execution
**When to use:** SYNC-01 requirement - testing single-flight pattern
**Example:**
```swift
// Source: Swift Concurrency testing patterns + actor isolation
@Test("Concurrent sync calls coalesce to single execution (SYNC-01)")
func concurrentCallsCoalesce() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
    configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

    // Record initial call count
    let callsBefore = mockNetwork.getChangesCalls.count

    // Launch multiple concurrent syncs using TaskGroup
    await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<5 {
            group.addTask {
                await engine.performSync()
            }
        }
    }

    // Verify only ONE set of network calls was made (not 5)
    let callsAfter = mockNetwork.getChangesCalls.count
    let totalCalls = callsAfter - callsBefore
    #expect(totalCalls == 1, "Expected 1 network call, got \(totalCalls)")
}
```

### Pattern 2: Testing Pagination with hasMore/nextCursor
**What:** Verify cursor-based pagination advances correctly until hasMore=false
**When to use:** SYNC-02 requirement - testing cursor pagination
**Example:**
```swift
// Source: Pagination testing best practices + SyncEngine.pullChanges implementation
@Test("Pagination advances cursor until hasMore is false (SYNC-02)")
func paginationAdvancesCursor() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // Configure multi-page response sequence
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Page 1: cursor 0 → 100, hasMore=true
    // Page 2: cursor 100 → 200, hasMore=true
    // Page 3: cursor 200 → 300, hasMore=false
    mockNetwork.getChangesResponses = [
        .success(ChangeFeedResponse(changes: [], nextCursor: 100, hasMore: true)),
        .success(ChangeFeedResponse(changes: [], nextCursor: 200, hasMore: true)),
        .success(ChangeFeedResponse(changes: [], nextCursor: 300, hasMore: false))
    ]

    await engine.performSync()

    // Verify 3 pages fetched
    #expect(mockNetwork.getChangesCalls.count == 3, "Expected 3 pages fetched")

    // Verify cursor progression
    #expect(mockNetwork.getChangesCalls[0].cursor == 0, "First page starts at 0")
    #expect(mockNetwork.getChangesCalls[1].cursor == 100, "Second page starts at 100")
    #expect(mockNetwork.getChangesCalls[2].cursor == 200, "Third page starts at 200")

    // Verify final cursor saved
    let savedCursor = UserDefaults.standard.object(forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)") as? Int64
    #expect(savedCursor == 300, "Final cursor should be 300")
}
```

### Pattern 3: Testing Bootstrap with Relationship Restoration
**What:** Verify bootstrap downloads all data and restores event→eventType relationships
**When to use:** SYNC-03 requirement - testing bootstrap fetch
**Example:**
```swift
// Source: SyncEngine.bootstrapFetch implementation
@Test("Bootstrap restores event-to-eventType relationships (SYNC-03)")
func bootstrapRestoresRelationships() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // Configure bootstrap responses (cursor=0 triggers bootstrap)
    UserDefaults.standard.set(0, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")

    let eventType1 = APIModelFixture.makeAPIEventType(id: "type-1", name: "Work")
    mockNetwork.getEventTypesResponses = [.success([eventType1])]
    mockNetwork.getGeofencesResponses = [.success([])]

    // getAllEvents returns events with eventTypeId references
    let event1 = APIModelFixture.makeAPIEvent(id: "evt-1", eventTypeId: "type-1")
    mockNetwork.getAllEventsResponses = [.success([event1])]
    mockNetwork.getLatestCursorResponses = [.success(1000)]

    // Seed empty property definitions response
    mockNetwork.getPropertyDefinitionsResponses = [.success([])]

    await engine.performSync()

    // Verify event exists with correct relationship
    let events = try mockStore.fetchAllEvents()
    #expect(events.count == 1, "Should have 1 event")
    #expect(events[0].id == "evt-1", "Event ID should match")
    #expect(events[0].eventType?.id == "type-1", "Event should reference correct EventType")
    #expect(events[0].eventType?.name == "Work", "EventType relationship should be restored")
}
```

### Pattern 4: Testing Batch Processing with Partial Failures
**What:** Verify 50-event batches process correctly, including partial failure scenarios
**When to use:** SYNC-04 requirement - testing batch processing
**Example:**
```swift
// Source: SyncEngine.flushPendingMutations batch processing logic
@Test("Batch processing handles partial failures correctly (SYNC-04)")
func batchPartialFailuresHandled() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
    configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

    // Seed 3 mutations (will be batched together)
    seedEventMutation(mockStore: mockStore, eventId: "evt-1")
    seedEventMutation(mockStore: mockStore, eventId: "evt-2")
    seedEventMutation(mockStore: mockStore, eventId: "evt-3")

    // Configure batch response: 2 succeeded, 1 failed
    mockNetwork.createEventsBatchResponses = [
        .success(APIModelFixture.makeBatchCreateEventsResponse(
            created: [
                APIModelFixture.makeAPIEvent(id: "evt-1"),
                APIModelFixture.makeAPIEvent(id: "evt-3")
            ],
            failed: [
                BatchFailure(clientId: "evt-2", error: "Validation failed")
            ],
            total: 3,
            success: 2,
            failures: 1
        ))
    ]

    await engine.performSync()

    // Verify successful mutations removed from queue
    let pending = try mockStore.fetchPendingMutations()
    #expect(pending.count == 1, "Only failed mutation should remain")
    #expect(pending[0].entityId == "evt-2", "Failed mutation should still be queued")
}
```

### Pattern 5: Testing Health Check for Captive Portals
**What:** Verify health check fails behind captive portal, preventing false sync attempts
**When to use:** SYNC-05 requirement - testing health check
**Example:**
```swift
// Source: SyncEngine.performHealthCheck implementation
@Test("Health check detects captive portal and prevents sync (SYNC-05)")
func healthCheckDetectsCaptivePortal() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // Simulate captive portal: getEventTypes returns HTML instead of JSON
    mockNetwork.getEventTypesResponses = [
        .failure(APIError.decodingError("Expected array, got HTML"))
    ]

    // Seed a mutation to ensure sync would attempt if health check passed
    seedEventMutation(mockStore: mockStore, eventId: "evt-1")

    // Record network call count before sync
    let callsBefore = mockNetwork.totalCallCount

    await engine.performSync()

    // Verify sync was blocked (only health check called, no flush operations)
    let callsAfter = mockNetwork.totalCallCount
    let totalCalls = callsAfter - callsBefore
    #expect(totalCalls == 1, "Only health check should be called, got \(totalCalls) calls")

    // Verify mutation still pending (wasn't flushed)
    let pending = try mockStore.fetchPendingMutations()
    #expect(pending.count == 1, "Mutation should remain pending after failed health check")
}
```

### Anti-Patterns to Avoid
- **Testing real time delays:** Use manual `resetCircuitBreaker()` instead of `Task.sleep()` — tests should be fast and deterministic
- **Shared mock state between tests:** Always create fresh dependencies per test to avoid interdependencies
- **Hardcoded timing assertions:** Use wide tolerances (±5s) for backoff timing to avoid flaky tests
- **Testing implementation details:** Focus on observable behavior (network calls, data state) not internal variables unless necessary

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Async test support | Custom continuation wrappers | Swift Testing's native async support | Swift Testing natively supports `async func` tests, no wrappers needed |
| Concurrent call simulation | Manual Task spawning | `withThrowingTaskGroup` | TaskGroup provides structured concurrency with automatic cleanup |
| Mock response sequencing | Random number generators | Response queue arrays | Existing pattern in MockNetworkClient (phases 17-19) is deterministic and debuggable |
| Test data creation | Inline JSON/dictionaries | APIModelFixture | Centralized fixtures prevent copy-paste errors and ensure valid models |
| Actor state verification | Sleep/polling | Direct actor property access with await | Actors guarantee serial execution, no need to wait for state changes |

**Key insight:** Swift Testing was designed for async/await and actors. Trying to work around concurrency features with older patterns (XCTestExpectation, busy-waiting, NSCondition) adds complexity and fragility.

## Common Pitfalls

### Pitfall 1: Assuming Actor Methods Execute Serially in Tests
**What goes wrong:** Tests launch multiple concurrent calls expecting them to queue, but forget actors process them in order — not simultaneously
**Why it happens:** Actor isolation confusion; thinking actors run tasks in parallel when they actually serialize access
**How to avoid:** Remember SyncEngine is an `actor` — concurrent calls WILL queue. Single-flight test should verify the actor's internal coalescing logic (checking if sync is already in progress), not rely on race conditions
**Warning signs:** Flaky tests that sometimes pass/fail; race conditions in test results

### Pitfall 2: Not Resetting UserDefaults Cursor State Between Tests
**What goes wrong:** One test sets cursor to 1000 (to skip bootstrap), next test expects cursor=0 (to trigger bootstrap), but previous value persists
**Why it happens:** UserDefaults persists across tests in the same process unless explicitly cleared
**How to avoid:** Reset cursor in test setup or teardown: `UserDefaults.standard.removeObject(forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")`
**Warning signs:** Tests pass individually but fail when run together; bootstrap skipped unexpectedly

### Pitfall 3: Forgetting Health Check Configuration
**What goes wrong:** Test calls `performSync()` but hangs or fails because health check (getEventTypes) isn't configured
**Why it happens:** SyncEngine always performs health check first; forgetting to mock this response blocks the entire sync
**How to avoid:** ALWAYS configure health check in test setup: `mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]`
**Warning signs:** Test timeouts; log messages showing "Health check failed"

### Pitfall 4: Pagination Response Queue Exhaustion
**What goes wrong:** Test configures 2 pagination responses but SyncEngine requests 3 pages, mock has no response for 3rd call
**Why it happens:** Miscounting pagination iterations; off-by-one errors in hasMore logic
**How to avoid:** Always configure one extra response or set final response with hasMore=false explicitly
**Warning signs:** "Response queue empty" errors; unexpected test failures on pagination edge cases

### Pitfall 5: Batch Size Mismatch in Bootstrap Tests
**What goes wrong:** Bootstrap test expects getAllEvents to be called once, but it's called multiple times due to pagination
**Why it happens:** getAllEvents uses internal pagination (batchSize=50 by default), multiple calls expected for large datasets
**How to avoid:** Configure getAllEventsResponses queue to handle pagination OR mock with small dataset that fits in one batch
**Warning signs:** "Response queue exhausted" errors; getAllEvents called more times than expected

### Pitfall 6: Mock Call Count Assertions Without Reset
**What goes wrong:** Test expects 3 network calls but assertion fails with 5 because previous operations weren't accounted for
**Why it happens:** Not recording call count BEFORE the operation being tested; asserting absolute count instead of delta
**How to avoid:** Record `callsBefore = mock.someCallArray.count` before operation, then check `callsAfter - callsBefore`
**Warning signs:** Assertion failures with "expected 3 calls, got 5"; fragile tests that break when setup changes

## Code Examples

Verified patterns from existing test infrastructure and Swift concurrency documentation:

### Fresh Dependencies Per Test
```swift
// Source: CircuitBreakerTests.swift, DeduplicationTests.swift
// Pattern used in phases 17-19, proven reliable
private func makeTestDependencies() -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}
```

### Configure for Flush Operations (Skip Bootstrap)
```swift
// Source: CircuitBreakerTests.swift lines 32-41
// Reusable helper for tests that focus on flush behavior
private func configureForFlush(mockNetwork: MockNetworkClient, mockStore: MockDataStore) {
    // Health check passes (required before any sync operations)
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Set cursor to non-zero to skip bootstrap
    UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")

    // Configure empty change feed to skip pullChanges processing
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}
```

### Concurrent Calls with TaskGroup
```swift
// Source: Swift Concurrency documentation + SyncEngine actor isolation
// Test concurrent sync calls coalesce to single execution
await withThrowingTaskGroup(of: Void.self) { group in
    for i in 0..<5 {
        group.addTask {
            await engine.performSync()
        }
    }
    // All tasks complete before continuing
}

// Verify single-flight behavior via network call count
let calls = mockNetwork.getChangesCalls.count
#expect(calls == 1, "Expected 1 network call from 5 concurrent syncs")
```

### Pagination Response Queue
```swift
// Source: MockNetworkClient response queue pattern + SyncEngine.pullChanges
// Configure sequential pagination responses
mockNetwork.getChangesResponses = [
    .success(ChangeFeedResponse(changes: [], nextCursor: 100, hasMore: true)),
    .success(ChangeFeedResponse(changes: [], nextCursor: 200, hasMore: true)),
    .success(ChangeFeedResponse(changes: [], nextCursor: 300, hasMore: false))
]

// SyncEngine will consume these in order until hasMore=false
await engine.performSync()

// Verify all pages processed
#expect(mockNetwork.getChangesCalls.count == 3, "All 3 pages should be fetched")
```

### Batch Response with Partial Failures
```swift
// Source: SyncEngine batch processing + APIModelFixture patterns
// Mock batch response: some succeeded, some failed
let batchResponse = BatchCreateEventsResponse(
    created: [
        APIModelFixture.makeAPIEvent(id: "evt-1"),
        APIModelFixture.makeAPIEvent(id: "evt-3")
    ],
    failed: [
        BatchFailure(clientId: "evt-2", error: "Validation failed", errorCode: "INVALID_FIELD")
    ],
    total: 3,
    success: 2,
    failures: 1
)

mockNetwork.createEventsBatchResponses = [.success(batchResponse)]

await engine.performSync()

// Verify successful items removed, failed items remain
let pending = try mockStore.fetchPendingMutations()
let pendingIds = pending.map { $0.entityId }
#expect(pendingIds == ["evt-2"], "Only failed mutation should remain pending")
```

### Structured Test Names with Requirement Comments
```swift
// Source: Phase 20 CONTEXT.md decisions + existing test patterns
@Suite("Single Flight Pattern")
struct SingleFlightTests {

    @Test("Concurrent sync calls coalesce to single execution (SYNC-01)")
    func testSYNC01_ConcurrentCallsCoalesce() async throws {
        // Covers SYNC-01: Test single-flight pattern (concurrent sync calls coalesced)
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
        // ... test implementation
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest async with expectations | Swift Testing with async/await | WWDC 2024 | Tests are simpler, no continuation wrappers needed |
| URLProtocol stubbing | Protocol-based mock injection | Phase 13-16 (Jan 2026) | Full control over responses, no global state |
| Manual task spawning | TaskGroup structured concurrency | Swift 5.5 (2021) | Automatic cleanup, better error handling |
| Global mock state | Fresh mocks per test | Phase 17-19 (Jan 2026) | Tests isolated, no interdependencies |
| print() debugging in tests | Log.sync structured logging | Phase 12 (Jan 2026) | Consistent logging in tests and production |

**Deprecated/outdated:**
- XCTestExpectation for async: Use `async func` tests instead
- DispatchQueue for test concurrency: Use TaskGroup instead
- Shared mock instances: Create fresh per test

## Open Questions

Things that couldn't be fully resolved:

1. **Single-Flight Implementation Details**
   - What we know: SyncEngine is an actor, providing serial execution guarantee
   - What's unclear: Does SyncEngine have explicit single-flight logic (checking `isSyncing` flag) or rely solely on actor serialization?
   - Recommendation: Review SyncEngine.performSync for early-return if sync already in progress; test BOTH concurrent call serialization AND explicit coalescing

2. **Bootstrap Relationship Restoration Verification**
   - What we know: Bootstrap downloads EventTypes then Events, Events reference EventTypes by ID
   - What's unclear: How to verify SwiftData relationships are correctly restored (not just IDs stored)
   - Recommendation: Test by fetching events and accessing `event.eventType?.name` — if relationship isn't restored, this would be nil

3. **Captive Portal Simulation Depth**
   - What we know: Health check calls getEventTypes; captive portals return HTML or redirect
   - What's unclear: Should test simulate HTTP redirects, HTML responses, or just decoding errors?
   - Recommendation: Start with decoding error simulation (simplest, sufficient for SYNC-05); can expand later if needed

4. **Batch Partial Failure Response Format**
   - What we know: SyncEngine uses BatchCreateEventsResponse with created/failed arrays
   - What's unclear: Does MockNetworkClient need special handling for partial failures or just return the response as-is?
   - Recommendation: Check if MockNetworkClient.createEventsBatchResponses queue exists; if yes, use it; if no, add it following the established response queue pattern

## Sources

### Primary (HIGH confidence)
- Swift Testing Official Documentation — https://developer.apple.com/documentation/testing
- Swift Concurrency Documentation — https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
- SyncEngine.swift — lines 176-179 (health check), 223-265 (bootstrap), 680-779 (batch processing), 1266-1294 (pagination)
- CircuitBreakerTests.swift — test helper patterns (makeTestDependencies, configureForFlush)
- DeduplicationTests.swift — response queue patterns, structured test names
- MockNetworkClient.swift — response queue implementation

### Secondary (MEDIUM confidence)
- [Swift Testing parameterized tests](https://developer.apple.com/documentation/testing/parameterizedtesting) — official docs on @Test arguments parameter
- [Mastering Swift Concurrency using TaskGroup](https://medium.com/@khmannaict13/mastering-swift-concurrency-using-async-await-actors-mainactor-task-and-taskgroup-in-swift-ios-d5638c91c3c4) — TaskGroup patterns for concurrent operations
- [Modern Concurrency in Swift: Testing Asynchronous Code](https://www.kodeco.com/books/modern-concurrency-in-swift/v1.0/chapters/6-testing-asynchronous-code) — async testing best practices
- [How to Check Internet Connectivity in iOS Using Swift and Network Framework](https://www.fromdev.com/2025/04/how-to-check-internet-connectivity-in-ios-using-swift-and-network-framework.html) — captive portal detection patterns

### Tertiary (LOW confidence)
- [Understanding the Singleflight Pattern](https://compositecode.blog/2025/07/03/go-concurrency-patternssingleflight-pattern/) — Go implementation, concepts transferable to Swift
- [Solving the Captive Portal Problem on iOS](https://medium.com/@rwbutler/solving-the-captive-portal-problem-on-ios-9a53ba2b381e) — captive portal detection strategies (Medium article)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Swift Testing is official Apple framework, existing mock infrastructure proven in phases 17-19
- Architecture: HIGH — Test patterns verified in existing codebase, Swift concurrency docs authoritative
- Pitfalls: HIGH — Based on direct code review of SyncEngine implementation and existing test patterns
- Code examples: HIGH — Extracted from actual test files (CircuitBreakerTests, DeduplicationTests) and SyncEngine source

**Research date:** 2026-01-23
**Valid until:** ~60 days (stable domain; Swift Testing and concurrency APIs unlikely to change rapidly)
