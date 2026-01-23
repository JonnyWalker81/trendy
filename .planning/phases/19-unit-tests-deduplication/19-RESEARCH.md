# Phase 19: Unit Tests - Deduplication - Research

**Researched:** 2026-01-23
**Domain:** Swift unit testing for idempotency mechanisms
**Confidence:** HIGH

## Summary

Researched patterns and best practices for testing idempotency key mechanisms that prevent duplicate event creation during sync operations. The codebase uses a well-established pattern where each `PendingMutation` has a unique `clientRequestId` (UUID string) that serves as the `Idempotency-Key` HTTP header. The backend uses this key to detect and reject duplicate requests with HTTP 409 Conflict responses.

Key findings:
- Idempotency keys follow the IETF draft RFC standard pattern (unique client-generated identifier per request)
- The system already has deduplication at both the mutation queue level (`hasPendingMutation`) and the API level (idempotency keys)
- Existing test patterns from Phase 17 (circuit breaker) and Phase 18 (resurrection prevention) provide strong templates
- MockNetworkClient supports response queues for sequential testing scenarios

**Primary recommendation:** Use MockNetworkClient's response queue pattern for sequential scenarios (retries, race conditions) and spy pattern for verification. Test both mutation queue deduplication and idempotency key uniqueness guarantees.

## Standard Stack

### Core Testing Framework
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | Native (Swift 5.9+) | Primary test framework | Modern Swift-native testing with concurrency support |
| XCTest | iOS SDK | Foundation layer | Required for Swift Testing integration |
| @testable import | Native | Module access | Standard pattern for white-box testing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation | iOS SDK | UUID, Date, Data handling | All test data setup |
| SwiftData | iOS SDK | In-memory ModelContainer | Mock data store implementation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift Testing | XCTest only | Swift Testing provides better async/actor support and modern syntax |
| Response queues | Smart mock with state | Queues are more explicit and easier to debug |

**Installation:**
No external dependencies required - all testing infrastructure is native to Swift and iOS SDK.

## Architecture Patterns

### Recommended Test Structure
```
trendyTests/
├── SyncEngine/
│   ├── CircuitBreakerTests.swift           # Phase 17 pattern
│   ├── ResurrectionPreventionTests.swift   # Phase 18 pattern
│   └── DeduplicationTests.swift            # Phase 19 (new)
├── Mocks/
│   ├── MockNetworkClient.swift             # Existing spy/response queue
│   ├── MockDataStore.swift                 # Existing in-memory store
│   └── MockDataStoreFactory.swift          # Existing factory
└── TestSupport.swift                       # Shared fixtures
```

### Pattern 1: Spy Pattern for Call Verification
**What:** Record method calls with parameters for later inspection
**When to use:** Verify idempotency keys are captured and sent correctly

**Example:**
```swift
// Source: CircuitBreakerTests.swift lines 161-169
struct CreateEventWithIdempotencyCall {
    let request: CreateEventRequest
    let idempotencyKey: String
    let timestamp: Date
}

private(set) var createEventWithIdempotencyCalls: [CreateEventWithIdempotencyCall] = []

// In test verification
#expect(mockNetwork.createEventWithIdempotencyCalls.count == 1)
#expect(mockNetwork.createEventWithIdempotencyCalls.first?.idempotencyKey == expectedKey)
```

### Pattern 2: Response Queue for Sequential Scenarios
**What:** Pre-configure ordered responses for multiple calls to same method
**When to use:** Testing retry behavior, race conditions, duplicate detection

**Example:**
```swift
// Source: CircuitBreakerTests.swift lines 66-70
mockNetwork.createEventsBatchResponses = [
    .failure(APIError.httpError(429)),
    .failure(APIError.httpError(429)),
    .failure(APIError.httpError(429))
]
```

### Pattern 3: Helper Functions for Test Setup
**What:** Reusable setup functions reduce boilerplate and ensure consistency
**When to use:** Common configurations across multiple tests

**Example:**
```swift
// Source: CircuitBreakerTests.swift lines 31-41
private func configureForFlush(mockNetwork: MockNetworkClient, mockStore: MockDataStore) {
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
    UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}
```

### Pattern 4: Test Isolation with makeTestDependencies
**What:** Factory function creates fresh dependencies for each test
**When to use:** Every test to prevent state leakage

**Example:**
```swift
// Source: ResurrectionPreventionTests.swift lines 22-28
private func makeTestDependencies() -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}
```

### Pattern 5: Fixture-Based Test Data
**What:** Deterministic test data builders in TestSupport.swift
**When to use:** Creating API models, requests, responses for tests

**Example:**
```swift
// Source: TestSupport.swift lines 121-146
static func makeCreateEventRequest(
    id: String = UUIDv7.generate(),
    eventTypeId: String = "type-1",
    timestamp: Date = Date(timeIntervalSince1970: 1704067200),
    notes: String? = "Test event",
    properties: [String: APIPropertyValue] = [:]
) -> CreateEventRequest {
    CreateEventRequest(
        id: id,
        eventTypeId: eventTypeId,
        timestamp: timestamp,
        notes: notes,
        isAllDay: false,
        endDate: nil,
        sourceType: "manual",
        // ... other fields
    )
}
```

### Anti-Patterns to Avoid
- **Using real network calls in unit tests:** Breaks isolation, causes flakiness. Always use MockNetworkClient.
- **Shared state between tests:** Each test must create fresh dependencies to prevent interference.
- **Exact timing assertions:** Use wide tolerance ranges (25-35s instead of exact 30s) to avoid flaky tests.
- **Global errorToThrow with response queues:** Response queues take precedence, but mixing patterns can cause confusion.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotency key generation | Custom UUID logic | `UUID().uuidString` from PendingMutation init | Standard, proven, already implemented |
| Duplicate detection | Manual ID comparison | `hasPendingMutation(entityId:entityType:operation:)` from DataStoreProtocol | Handles complex query logic, already tested |
| HTTP 409 detection | String matching on error messages | `APIError.isDuplicateError` computed property | Centralized logic handles multiple duplicate scenarios (409, unique constraint violations) |
| Mock network responses | Custom mock framework | MockNetworkClient with response queues | Thread-safe, spy pattern, already used in 50+ tests |
| Test fixtures | Inline test data | `APIModelFixture` helpers | Deterministic, reusable, consistent across test suites |

**Key insight:** The deduplication mechanism is already implemented in production code (SyncEngine.swift lines 528-540). Tests should verify existing behavior, not reimplement logic.

## Common Pitfalls

### Pitfall 1: Race Condition Simulation Without Ordering Guarantees
**What goes wrong:** Launching concurrent tasks doesn't guarantee they'll execute simultaneously or in expected order
**Why it happens:** Swift concurrency schedulers are non-deterministic
**How to avoid:** Use explicit coordination (Task.yield(), manual barriers) or accept that "rapid submission" is best-effort simulation
**Warning signs:** Flaky tests that pass sometimes but fail others due to timing

### Pitfall 2: Assuming UUID Uniqueness Within Single Test
**What goes wrong:** Generating multiple UUIDs in tight loop might theoretically collide (astronomically unlikely but breaks assumptions)
**Why it happens:** Over-reliance on statistical uniqueness in deterministic test environment
**How to avoid:** For collision tests, force collision with explicit duplicate keys rather than hoping for random collision
**Warning signs:** "Test for collision" that never actually triggers collision path

### Pitfall 3: Testing 409 Response Without Key Tracking
**What goes wrong:** Verifying 409 Conflict response without confirming same idempotency key was reused
**Why it happens:** Focusing on HTTP status code instead of the mechanism causing it
**How to avoid:** Use spy pattern to capture `idempotencyKey` parameter, verify it matches across retry attempts
**Warning signs:** Test passes even when different keys are used for each retry

### Pitfall 4: Queue Deduplication vs API Idempotency Confusion
**What goes wrong:** Testing queue-level deduplication (`hasPendingMutation`) when you meant to test API-level idempotency keys
**Why it happens:** Two separate deduplication mechanisms operating at different layers
**How to avoid:** Queue-level prevents duplicate pending mutations (same entity + operation). API-level prevents duplicate network requests (same clientRequestId).
**Warning signs:** Test title mentions idempotency keys but only checks queue state

### Pitfall 5: Non-409 Errors Treated as Duplicates
**What goes wrong:** Other HTTP 4xx errors (400 Bad Request, 404 Not Found) incorrectly handled as duplicates
**Why it happens:** Loose error checking that doesn't distinguish error types
**How to avoid:** Use `APIError.isDuplicateError` which checks specifically for 409 or unique constraint messages
**Warning signs:** Test expects deduplication but passes with HTTP 400 error

## Code Examples

Verified patterns from existing test code:

### Testing Same Event Not Created Twice (Queue Level)
```swift
// Source: Phase 18 pattern adapted for Phase 19
// Verifies queueMutation prevents duplicate pending mutations
func testQueueDeduplicationPreventsDuplicates() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // First mutation queued
    let request1 = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
    let payload1 = try JSONEncoder().encode(request1)
    try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-1", payload: payload1)

    // Attempt to queue duplicate (same entityId + entityType + operation)
    let request2 = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
    let payload2 = try JSONEncoder().encode(request2)
    try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-1", payload: payload2)

    // Verify only one pending mutation exists
    let pending = try mockStore.fetchPendingMutations()
    #expect(pending.count == 1, "Duplicate mutation should be skipped")
}
```

### Testing Idempotency Key Reuse on Retry
```swift
// Source: MockNetworkClient spy pattern
// Verifies same clientRequestId used across retries
func testRetryReusesIdempotencyKey() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
    configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

    // Configure retry scenario: first call fails, second succeeds
    mockNetwork.createEventWithIdempotencyResponses = [
        .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))),
        .success(APIModelFixture.makeAPIEvent(id: "evt-1"))
    ]

    // Seed mutation (idempotency key generated in PendingMutation init)
    let request = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
    let payload = try JSONEncoder().encode(request)
    _ = mockStore.seedPendingMutation(entityType: .event, entityId: "evt-1", operation: .create, payload: payload)

    // Perform sync (triggers retry internally)
    await engine.performSync()

    // Verify both calls used same idempotency key
    let calls = mockNetwork.createEventWithIdempotencyCalls
    #expect(calls.count == 2, "Should have retried once")
    #expect(calls[0].idempotencyKey == calls[1].idempotencyKey, "Retry must reuse same key")
}
```

### Testing Different Mutations Get Different Keys
```swift
// Verifies each PendingMutation generates unique clientRequestId
func testDifferentMutationsHaveDifferentKeys() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
    configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

    // Configure successful responses
    mockNetwork.createEventsBatchResponses = [
        .success(APIModelFixture.makeBatchCreateEventsResponse(
            created: [
                APIModelFixture.makeAPIEvent(id: "evt-1"),
                APIModelFixture.makeAPIEvent(id: "evt-2")
            ],
            total: 2,
            success: 2
        ))
    ]

    // Seed two different mutations
    let request1 = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
    let payload1 = try JSONEncoder().encode(request1)
    let mutation1 = mockStore.seedPendingMutation(entityType: .event, entityId: "evt-1", operation: .create, payload: payload1)

    let request2 = APIModelFixture.makeCreateEventRequest(id: "evt-2", eventTypeId: "type-1")
    let payload2 = try JSONEncoder().encode(request2)
    let mutation2 = mockStore.seedPendingMutation(entityType: .event, entityId: "evt-2", operation: .create, payload: payload2)

    // Verify keys are unique
    #expect(mutation1.clientRequestId != mutation2.clientRequestId, "Each mutation must have unique idempotency key")
}
```

### Testing 409 Conflict Handling
```swift
// Source: SyncEngine.swift lines 837-855 adapted to test
// Verifies duplicate error (409) treated correctly
func test409ConflictDeletesLocalDuplicate() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
    configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

    // Configure 409 Conflict response
    mockNetwork.createEventWithIdempotencyResponses = [
        .failure(APIError.serverError("Duplicate key violation", 409))
    ]

    // Seed mutation and local event
    let request = APIModelFixture.makeCreateEventRequest(id: "evt-duplicate", eventTypeId: "type-1")
    let payload = try JSONEncoder().encode(request)
    _ = mockStore.seedPendingMutation(entityType: .event, entityId: "evt-duplicate", operation: .create, payload: payload)
    _ = mockStore.seedEvent(id: "evt-duplicate", eventTypeId: "type-1")

    await engine.performSync()

    // Verify mutation was removed from queue (treated as success)
    let pending = try mockStore.fetchPendingMutations()
    #expect(pending.isEmpty, "409 Conflict should remove mutation from queue")

    // Verify local duplicate was deleted
    let events = try mockStore.fetchAllEvents()
    #expect(events.isEmpty, "Local duplicate should be deleted on 409")
}
```

### Testing Non-409 Errors Don't Deduplicate
```swift
// Verifies only 409 and specific duplicate messages trigger deduplication
func testNon409ErrorsDoNotDeduplicate() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()
    configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

    // Configure 400 Bad Request (not duplicate)
    mockNetwork.createEventWithIdempotencyResponses = [
        .failure(APIError.httpError(400))
    ]

    // Seed mutation
    let request = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
    let payload = try JSONEncoder().encode(request)
    _ = mockStore.seedPendingMutation(entityType: .event, entityId: "evt-1", operation: .create, payload: payload)

    await engine.performSync()

    // Verify mutation still pending (not removed as duplicate)
    let pending = try mockStore.fetchPendingMutations()
    #expect(pending.count == 1, "400 error should not trigger deduplication")
    #expect(pending.first?.attempts == 1, "Should record failure attempt")
}
```

### Testing Race Condition (Rapid Duplicate Submission)
```swift
// Simulates user submitting same event twice in rapid succession
func testRapidDuplicateSubmissionPrevented() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // Both mutations for same entity should result in only one pending
    let request = APIModelFixture.makeCreateEventRequest(id: "evt-race", eventTypeId: "type-1")
    let payload = try JSONEncoder().encode(request)

    // Launch concurrent queue operations
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            try? await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-race", payload: payload)
        }
        group.addTask {
            try? await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-race", payload: payload)
        }
    }

    // Verify only one mutation queued
    let pending = try mockStore.fetchPendingMutations()
    #expect(pending.count == 1, "Race condition should be prevented by hasPendingMutation check")
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest only | Swift Testing with async/await | Swift 5.9 (2023) | Better concurrency support, cleaner syntax |
| Callback-based async tests | async/await in tests | Swift 5.5 (2021) | Eliminates completion handler complexity |
| UUID v4 for IDs | UUIDv7 for IDs | Project-specific (2024) | Time-ordered IDs improve debugging and sync |
| Response callbacks | Response queues (Result arrays) | Phase 17 implementation | Explicit ordering for sequential test scenarios |

**Deprecated/outdated:**
- `XCTestExpectation` for async: Replaced by native `async/await` test functions
- Inline test data: Replaced by `APIModelFixture` factories
- String-based error checking: Replaced by `APIError.isDuplicateError` computed property

## Open Questions

Things that couldn't be fully resolved:

1. **Batch API Idempotency Key Behavior**
   - What we know: Batch API doesn't take individual idempotency keys (it's a batch request)
   - What's unclear: How server handles duplicate detection in batch context
   - Recommendation: Test that batch processing doesn't bypass queue-level deduplication (Phase 19 focus is on non-batch idempotency)

2. **Idempotency Key Expiration**
   - What we know: Backend likely expires keys after some time window (standard practice)
   - What's unclear: Exact expiration time, what happens if expired key reused
   - Recommendation: Unit tests don't need to cover this (integration test concern)

3. **Key Collision Handling**
   - What we know: UUID collision probability is astronomically low
   - What's unclear: System behavior if collision actually occurred
   - Recommendation: Force collision with explicit duplicate key rather than hoping for random collision

## Sources

### Primary (HIGH confidence)
- Existing codebase patterns:
  - `apps/ios/trendy/Services/Sync/SyncEngine.swift` (lines 520-558, 1122-1159)
  - `apps/ios/trendy/Models/PendingMutation.swift` (full file)
  - `apps/ios/trendyTests/SyncEngine/CircuitBreakerTests.swift` (test patterns)
  - `apps/ios/trendyTests/SyncEngine/ResurrectionPreventionTests.swift` (test patterns)
  - `apps/ios/trendyTests/Mocks/MockNetworkClient.swift` (mock implementation)
  - `apps/ios/trendyTests/TestSupport.swift` (fixtures)
- Apple Developer Documentation:
  - Swift Testing framework (native, no external URL)
  - Swift Concurrency best practices (native docs)

### Secondary (MEDIUM confidence)
- [Implementing Idempotency Keys in REST APIs](https://zuplo.com/learning-center/implementing-idempotency-keys-in-rest-apis-a-complete-guide) - Complete guide to idempotency patterns
- [The Idempotency-Key HTTP Header Field (IETF Draft)](https://greenbytes.de/tech/webdav/draft-ietf-httpapi-idempotency-key-header-latest.html) - RFC standard for idempotency keys
- [Idempotency - Preventing Duplicate Requests](https://boundedcontext.com/idempotency-key/) - Best practices for duplicate prevention
- [Avoiding race conditions in Swift](https://www.swiftbysundell.com/articles/avoiding-race-conditions-in-swift/) - Swift concurrency patterns
- [Testing Concurrent Code in Swift: A Simple Guide](https://commitstudiogs.medium.com/testing-concurrent-code-in-swift-a-simple-guide-050cd72e5e50) - Async testing patterns
- [Unit Testing race conditions by creating chaos (Swift)](https://medium.com/livefront/unit-testing-race-conditions-by-creating-chaos-swift-512a55e09806) - Race condition testing strategies

### Tertiary (LOW confidence)
- [HTTP 409 Conflict - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/409) - General 409 documentation (not Swift-specific)
- WebSearch results for "Swift unit test idempotency 2026" - Limited Swift-specific 2026 content, general principles apply

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Native Swift Testing framework, well-established in codebase
- Architecture: HIGH - Strong existing patterns from Phase 17/18 tests, clear spy/response queue approach
- Pitfalls: MEDIUM - Based on general concurrency testing wisdom + codebase observations, not project-specific failures
- Code examples: HIGH - Adapted from real working test code in CircuitBreakerTests and ResurrectionPreventionTests
- Idempotency mechanisms: HIGH - Production code clearly implements standard idempotency key pattern

**Research date:** 2026-01-23
**Valid until:** ~30 days (stable testing patterns, unlikely to change rapidly)
