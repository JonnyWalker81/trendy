# Phase 16: Test Infrastructure - Research

**Researched:** 2026-01-21
**Domain:** Swift unit testing with protocol mocks and spy pattern
**Confidence:** HIGH

## Summary

This research investigates how to build reusable mock implementations of NetworkClientProtocol and DataStoreProtocol for testing SyncEngine. The goal is manual, lightweight mocks that work with Swift's native Testing framework, support the spy pattern (call tracking), and handle Sendable constraints properly.

**Key findings:**
- Manual mock implementation is the standard approach for Swift protocol testing without heavy frameworks
- Swift Testing framework provides modern #expect macro with better diagnostics than XCTest assertions
- Spy pattern records method calls in arrays with typed structs capturing arguments and timestamps
- SwiftData ModelContainer supports in-memory testing via `isStoredInMemoryOnly: true` configuration
- Response queuing enables sequential behavior testing essential for circuit breaker and retry logic tests
- NetworkClientProtocol is Sendable (24 methods), DataStoreProtocol is NOT Sendable (23 methods)

**Primary recommendation:** Build manual mocks with typed call record structs, property-based response configuration, and response queues for sequential testing. Use existing TestFixtures.swift pattern for test data factories.

## Standard Stack

The established libraries/tools for Swift testing:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | Built-in (Swift 5.9+) | Native testing framework | Apple's modern replacement for XCTest, better async/await support |
| SwiftData | Built-in (iOS 17+) | Data persistence | In-memory ModelContainer for isolated tests |
| Foundation | Built-in | Core types (Date, UUID, etc.) | Standard library, no alternatives |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| XCTest | Built-in | Legacy testing | Only when Swift Testing unavailable (not needed here) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual mocks | Cuckoo/Spry frameworks | Frameworks add complexity, code generation overhead, and dependencies. Manual mocks are simpler for protocol-based DI |
| Swift Testing | XCTest | XCTest is older, requires more boilerplate (XCTAssertEqual vs #expect), and has weaker async support |

**Installation:**
No installation required - all tools are built into Swift 5.9+ and iOS 17+ SDK.

## Architecture Patterns

### Mock Implementation Pattern: Spy with Response Configuration

**Pattern for Sendable protocols (NetworkClientProtocol):**

```swift
// Source: Manual implementation pattern from research
final class MockNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    // MARK: - Call Recording (Spy Pattern)

    struct GetEventTypesCall {
        let timestamp: Date
    }

    struct CreateEventCall {
        let request: CreateEventRequest
        let idempotencyKey: String?
        let timestamp: Date
    }

    private let lock = NSLock()
    private(set) var getEventTypesCalls: [GetEventTypesCall] = []
    private(set) var createEventCalls: [CreateEventCall] = []

    // MARK: - Response Configuration

    var eventTypesToReturn: [APIEventType] = []
    var eventsToReturn: [APIEvent] = []
    var errorToThrow: Error?

    // Response queue for sequential behavior testing
    var getEventTypesResponses: [Result<[APIEventType], Error>] = []

    // MARK: - Protocol Implementation

    func getEventTypes() async throws -> [APIEventType] {
        lock.lock()
        getEventTypesCalls.append(GetEventTypesCall(timestamp: Date()))
        lock.unlock()

        // Check response queue first (for sequential testing)
        if !getEventTypesResponses.isEmpty {
            let result = getEventTypesResponses.removeFirst()
            switch result {
            case .success(let types): return types
            case .failure(let error): throw error
            }
        }

        // Check if configured to throw error
        if let error = errorToThrow {
            throw error
        }

        // Return configured response
        return eventTypesToReturn
    }

    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent {
        lock.lock()
        createEventCalls.append(CreateEventCall(request: request, idempotencyKey: nil, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        // Return first event or throw if none configured
        guard let event = eventsToReturn.first else {
            throw APIError.invalidResponse
        }
        return event
    }

    // MARK: - Test Helpers

    func reset() {
        lock.lock()
        getEventTypesCalls.removeAll()
        createEventCalls.removeAll()
        getEventTypesResponses.removeAll()
        eventTypesToReturn.removeAll()
        eventsToReturn.removeAll()
        errorToThrow = nil
        lock.unlock()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return getEventTypesCalls.count + createEventCalls.count
    }
}
```

**Pattern for non-Sendable protocols (DataStoreProtocol):**

```swift
// Source: Manual implementation with in-memory storage
final class MockDataStore: DataStoreProtocol {
    // MARK: - In-Memory Storage

    private var events: [String: Event] = [:]
    private var eventTypes: [String: EventType] = [:]
    private var geofences: [String: Geofence] = [:]
    private var propertyDefinitions: [String: PropertyDefinition] = [:]
    private var pendingMutations: [PendingMutation] = []

    // MARK: - Call Recording

    struct UpsertEventCall {
        let id: String
        let timestamp: Date
    }

    private(set) var upsertEventCalls: [UpsertEventCall] = []
    private(set) var deleteEventCalls: [String] = []
    private(set) var saveCalls: Int = 0

    // MARK: - Error Injection

    var throwOnSave: Error?
    var throwOnUpsert: Error?

    // MARK: - Protocol Implementation

    func upsertEvent(id: String, configure: (Event) -> Void) throws -> Event {
        upsertEventCalls.append(UpsertEventCall(id: id, timestamp: Date()))

        if let error = throwOnUpsert {
            throw error
        }

        let event = events[id] ?? Event(timestamp: Date(), eventType: EventType(name: "Mock", colorHex: "#000000", iconName: "circle"))
        event.id = id
        configure(event)
        events[id] = event
        return event
    }

    func deleteEvent(id: String) throws {
        deleteEventCalls.append(id)
        events.removeValue(forKey: id)
    }

    func findEvent(id: String) throws -> Event? {
        return events[id]
    }

    func save() throws {
        saveCalls += 1
        if let error = throwOnSave {
            throw error
        }
    }

    // MARK: - Test Helpers

    func reset() {
        events.removeAll()
        eventTypes.removeAll()
        geofences.removeAll()
        propertyDefinitions.removeAll()
        pendingMutations.removeAll()
        upsertEventCalls.removeAll()
        deleteEventCalls.removeAll()
        saveCalls = 0
        throwOnSave = nil
        throwOnUpsert = nil
    }
}
```

**Factory pattern for test injection:**

```swift
// Source: Phase 15 DataStoreFactory pattern
final class MockDataStoreFactory: DataStoreFactory, @unchecked Sendable {
    private let mockStore: MockDataStore

    init(mockStore: MockDataStore) {
        self.mockStore = mockStore
    }

    func makeDataStore() -> any DataStoreProtocol {
        return mockStore
    }
}
```

### Response Queue Pattern for Sequential Testing

**What:** Array-based queue that provides different responses on successive calls
**When to use:** Testing retry logic, circuit breakers, rate limiting, or any sequential state changes

**Example:**
```swift
// Source: Derived from circuit breaker testing research
let mock = MockNetworkClient()

// Configure sequence: fail 3 times, then succeed
mock.getEventTypesResponses = [
    .failure(APIError.httpError(500)),
    .failure(APIError.httpError(500)),
    .failure(APIError.httpError(500)),
    .success([])  // Recovery
]

// Test circuit breaker: should open after 3 failures
for _ in 0..<3 {
    _ = try? await syncEngine.performSync()  // Fails
}

// Circuit should be open now
let state = syncEngine.circuitBreakerState
#expect(state == .open)

// After timeout, should retry and succeed
_ = try await syncEngine.performSync()
#expect(state == .closed)
```

### Test Fixture Organization

**Existing pattern (from TestSupport.swift):**

```swift
// Source: apps/ios/trendyTests/TestSupport.swift
struct APIModelFixture {
    static func makeAPIEventType(
        id: String = "type-1",
        userId: String = "user-1",
        name: String = "Workout",
        color: String = "#FF5733",
        icon: String = "figure.run"
    ) -> APIEventType {
        APIEventType(
            id: id,
            userId: userId,
            name: name,
            color: color,
            icon: icon,
            createdAt: Date(timeIntervalSince1970: 1704067200),
            updatedAt: Date(timeIntervalSince1970: 1704067200)
        )
    }
}
```

**Extend for new models:**

```swift
// Add to APIModelFixture in TestSupport.swift
static func makeChangeFeedResponse(
    changes: [ChangeEntry] = [],
    nextCursor: Int64 = 0,
    hasMore: Bool = false
) -> ChangeFeedResponse {
    ChangeFeedResponse(
        changes: changes,
        nextCursor: nextCursor,
        hasMore: hasMore
    )
}

static func makeChangeEntry(
    id: Int64 = 1,
    entityType: String = "event",
    operation: String = "create",
    entityId: String = "evt-1",
    data: ChangeEntryData? = nil
) -> ChangeEntry {
    ChangeEntry(
        id: id,
        entityType: entityType,
        operation: operation,
        entityId: entityId,
        data: data,
        deletedAt: nil,
        createdAt: Date(timeIntervalSince1970: 1704067200)
    )
}

static func makeBatchCreateEventsResponse(
    created: [APIEvent] = [],
    errors: [BatchError]? = nil,
    total: Int = 0,
    success: Int = 0,
    failed: Int = 0
) -> BatchCreateEventsResponse {
    BatchCreateEventsResponse(
        created: created,
        errors: errors,
        total: total,
        success: success,
        failed: failed
    )
}
```

### Anti-Patterns to Avoid

- **Global mocks:** Don't use singleton mocks - pass fresh instances to each test for isolation
- **Shared state between tests:** Always reset() or create new mock instances in test setup
- **Over-stubbing:** Don't configure responses for methods the test won't call - keep it minimal
- **Ignoring thread safety:** Use NSLock for mutable state in Sendable mocks (@unchecked Sendable requires manual safety)
- **Complex mock logic:** Mocks should be dumb - if logic is complex, you're testing the mock, not the SUT

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| In-memory data persistence | Custom dictionary-based storage layer | SwiftData ModelContainer with `isStoredInMemoryOnly: true` | Handles relationships, migrations, thread safety automatically |
| Async test expectations | Custom semaphores/wait loops | Swift Testing's native async/await support | Built-in timeout handling, cleaner syntax |
| Date determinism | Random dates in tests | DeterministicDate.jan1_2024 from TestSupport.swift | Reproducible tests, easier debugging |
| UUID generation for tests | UUID() in fixtures | DeterministicUUID.uuid(from: seed) or DeterministicUUID.zero | Stable IDs across test runs |

**Key insight:** SwiftData's in-memory container is production-quality code that handles edge cases (cascading deletes, relationship integrity, concurrent access) that a hand-rolled dictionary mock would miss.

## Common Pitfalls

### Pitfall 1: Forgetting @unchecked Sendable Thread Safety
**What goes wrong:** Data races in mock call records when tests run concurrently or when actor boundaries are crossed
**Why it happens:** @unchecked Sendable bypasses compiler checks - you must manually ensure thread safety
**How to avoid:**
- Use NSLock around all mutable state (call arrays, response queues)
- Lock before reading/writing, unlock in defer blocks
- Consider using actors for mocks if complexity grows
**Warning signs:** Random test failures, crashes in CI but not locally, EXC_BAD_ACCESS errors

### Pitfall 2: Response Queue Not Resetting Between Tests
**What goes wrong:** First test consumes response queue, second test gets unexpected responses or empty queue
**Why it happens:** Response queues are mutated during test execution (removeFirst())
**How to avoid:**
- Always call mock.reset() in test tearDown or setUp
- Use separate mock instances per test
- Never share mock instances between tests
**Warning signs:** Tests pass individually but fail when run together, order-dependent failures

### Pitfall 3: Configuring Responses for Unused Methods
**What goes wrong:** Test setup becomes cluttered, unclear what the test actually validates
**Why it happens:** Copy-paste from other tests, defensive over-configuration
**How to avoid:**
- Only configure responses for methods the test will call
- Use call count assertions to verify which methods were actually invoked
- Keep mock configuration close to the test action
**Warning signs:** Test setup is longer than test assertions, unused variables in setup

### Pitfall 4: Testing Mocks Instead of System Under Test
**What goes wrong:** Tests validate mock behavior instead of SyncEngine behavior
**Why it happens:** Complex mock logic that needs its own tests
**How to avoid:**
- Keep mocks simple: record calls, return configured values, throw configured errors
- If mock logic is complex, simplify it or use the real implementation
- Focus assertions on SUT outputs, not mock internal state
**Warning signs:** Assertions check mock.wasCalledWith() but not actual test outcomes

### Pitfall 5: Ignoring Sendable Constraints on DataStoreProtocol
**What goes wrong:** Trying to share MockDataStore across actor boundaries fails to compile
**Why it happens:** DataStoreProtocol is intentionally NOT Sendable (ModelContext is not thread-safe)
**How to avoid:**
- Use MockDataStoreFactory (which IS Sendable) to pass mocks into actors
- Factory creates/returns mock inside actor isolation context
- Never try to add Sendable conformance to MockDataStore
**Warning signs:** Compiler errors about non-Sendable types crossing actor boundaries

### Pitfall 6: Not Handling Optional vs Required Protocol Parameters
**What goes wrong:** Mock implements protocol method with default parameters when protocol doesn't allow them
**Why it happens:** Swift protocols cannot have default parameter values in method signatures
**How to avoid:**
- Protocol methods: no default parameters (e.g., `limit: Int`)
- Implementation can have defaults: `func getEvents(limit: Int = 100)`
- Mock must match protocol signature exactly
**Warning signs:** Compiler error "candidate has non-matching type" when implementing protocol

## Code Examples

Verified patterns from research and existing codebase:

### Swift Testing Assertions

```swift
// Source: Swift Testing framework documentation + APIErrorTests.swift
import Testing
@testable import trendy

@Test("MockNetworkClient tracks method calls")
func test_mockNetworkClient_tracksMethodCalls() async throws {
    let mock = MockNetworkClient()
    mock.eventTypesToReturn = [
        APIModelFixture.makeAPIEventType(id: "type-1", name: "Workout")
    ]

    // Execute operation
    let types = try await mock.getEventTypes()

    // Verify results
    #expect(types.count == 1)
    #expect(types.first?.name == "Workout")

    // Verify spy recorded the call
    #expect(mock.getEventTypesCalls.count == 1)
    #expect(mock.getEventTypesCalls.first?.timestamp != nil)
}

@Test("Response queue enables sequential testing")
func test_responseQueue_sequentialBehavior() async throws {
    let mock = MockNetworkClient()

    // Configure sequence: error, error, success
    mock.getEventTypesResponses = [
        .failure(APIError.httpError(500)),
        .failure(APIError.httpError(500)),
        .success([APIModelFixture.makeAPIEventType()])
    ]

    // First call throws
    await #expect(throws: APIError.self) {
        try await mock.getEventTypes()
    }

    // Second call throws
    await #expect(throws: APIError.self) {
        try await mock.getEventTypes()
    }

    // Third call succeeds
    let types = try await mock.getEventTypes()
    #expect(types.count == 1)
}
```

### In-Memory DataStore Testing

```swift
// Source: SwiftData in-memory configuration research
import Testing
import SwiftData
@testable import trendy

@Test("MockDataStore provides in-memory state")
func test_mockDataStore_inMemoryState() throws {
    let mock = MockDataStore()

    // Create event
    let event = try mock.upsertEvent(id: "evt-1") { event in
        event.notes = "Test event"
    }

    // Verify stored
    let retrieved = try mock.findEvent(id: "evt-1")
    #expect(retrieved != nil)
    #expect(retrieved?.notes == "Test event")

    // Verify spy recorded call
    #expect(mock.upsertEventCalls.count == 1)
    #expect(mock.upsertEventCalls.first?.id == "evt-1")
}

@Test("MockDataStoreFactory creates test-compatible stores")
func test_mockDataStoreFactory_createsStores() {
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)

    // Factory is Sendable, can be passed to actors
    let store = factory.makeDataStore()

    // Store is the mock instance
    #expect(store is MockDataStore)
}
```

### Error Injection for Failure Testing

```swift
// Source: Testing error code paths research
@Test("MockNetworkClient supports error injection")
func test_mockNetworkClient_errorInjection() async throws {
    let mock = MockNetworkClient()

    // Configure to throw error
    mock.errorToThrow = APIError.httpError(429)  // Rate limited

    // Verify error is thrown
    await #expect(throws: APIError.self) {
        try await mock.getEventTypes()
    }

    // Call still recorded despite error
    #expect(mock.getEventTypesCalls.count == 1)
}

@Test("MockDataStore supports save errors")
func test_mockDataStore_saveError() throws {
    let mock = MockDataStore()

    struct SaveError: Error {}
    mock.throwOnSave = SaveError()

    // Save operation throws
    #expect(throws: SaveError.self) {
        try mock.save()
    }

    // Save was still attempted
    #expect(mock.saveCalls == 1)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest framework | Swift Testing framework | Swift 5.9 (2023) | Better async/await support, cleaner syntax (#expect vs XCTAssert) |
| Heavy mocking frameworks (Cuckoo) | Manual protocol-based mocks | Ongoing (2024-2026) | Simpler, no code generation, works with strict concurrency |
| @testable import with internal access | Protocol-based DI | Swift 6 (2024) | Enables true isolation, respects access control |
| Inheritance-based test doubles | Protocol conformance | Swift evolution | Works with actors, value types, and Sendable constraints |

**Deprecated/outdated:**
- XCTest assertions (XCTAssertEqual) → Use #expect macro
- Completion handler testing → Use async/await directly in tests
- Mocking frameworks with reflection → Use protocol-based manual mocks

## Open Questions

Things that couldn't be fully resolved:

1. **Call record granularity: Typed structs vs generic with Any**
   - What we know: Typed structs (GetEventTypesCall, CreateEventCall) provide compile-time safety
   - What's unclear: Whether the overhead of defining 24+ call record types is worth it vs a generic CallRecord<Arguments>
   - Recommendation: Start with typed structs for frequently-called methods (getEventTypes, createEvent), use generic for rare methods

2. **Assertion helpers vs direct #expect**
   - What we know: Swift Testing's #expect provides excellent diagnostics
   - What's unclear: Whether custom helpers like `#expectCallCount(mock.getEventTypesCalls, 2)` add clarity or noise
   - Recommendation: Use direct #expect first, add helpers only if patterns emerge across many tests

3. **Mock reset strategy: reset() vs fresh instances**
   - What we know: Both work, reset() is faster, fresh instances are safer
   - What's unclear: Whether test performance matters enough to prefer reset()
   - Recommendation: Default to fresh instances per test (safer), use reset() only if performance becomes an issue

## Sources

### Primary (HIGH confidence)
- [Swift Testing #expect macro](https://www.avanderlee.com/swift-testing/expect-macro/) - Core assertion patterns
- [Asserting state with #expect](https://www.donnywals.com/asserting-state-with-expect-in-swift-testing/) - Expectation syntax
- [SwiftData ModelContainer in-memory configuration](https://developer.apple.com/documentation/swiftdata/modelconfiguration/isstoredinmemoryonly) - Official Apple docs
- [Practical Swift Concurrency - Actors and Sendable](https://medium.com/@petrachkovsergey/practical-swift-concurrency-actors-isolation-sendability-a51343c2e4db) - Sendable constraints
- apps/ios/trendyTests/APIErrorTests.swift - Production test patterns
- apps/ios/trendyTests/TestSupport.swift - Existing fixture factories

### Secondary (MEDIUM confidence)
- [Test doubles in Swift: dummies, fakes, stubs, and spies](https://mokacoding.com/blog/swift-test-doubles/) - Spy pattern definition
- [Swift Actor in Unit Tests](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631) - Actor testing approaches
- [Testing error code paths in Swift](https://www.swiftbysundell.com/articles/testing-error-code-paths-in-swift/) - Error injection patterns
- [HTTP in Swift: Testing and Mocking](https://davedelong.com/blog/2020/07/03/http-in-swift-part-5-testing-and-mocking/) - MockLoader queue pattern
- [Implementing Retry Logic with Async/Await](https://medium.com/@battello.theo/implementing-retry-logic-with-async-await-in-swift-035ce99ac0d5) - Sequential testing examples

### Tertiary (LOW confidence)
- [Circuit Breaker with Swift and Async-Await](https://medium.com/@gitaeklee/ios-circuitbreaker-with-swift-and-async-await-dbbb2a0cddc3) - Circuit breaker testing concepts
- [Mocking in Swift](https://www.swiftbysundell.com/articles/mocking-in-swift/) - General mocking philosophy

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools are built-in, well-documented by Apple
- Architecture patterns: HIGH - Verified with existing codebase (TestSupport.swift, APIErrorTests.swift)
- Mock implementation: HIGH - Based on protocol requirements from Phase 15, standard Swift patterns
- Response queuing: MEDIUM - Pattern exists in research but not yet implemented in this codebase
- Call recording details: MEDIUM - Typed vs generic approach is a design choice, both work
- Pitfalls: HIGH - Derived from Sendable constraints in codebase, common Swift testing issues

**Research date:** 2026-01-21
**Valid until:** 60 days (stable - Swift Testing and SwiftData APIs are mature)
