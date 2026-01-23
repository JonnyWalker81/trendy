# Phase 17: Unit Tests - Circuit Breaker - Research

**Researched:** 2026-01-22
**Domain:** Swift Testing framework, SyncEngine circuit breaker behavior
**Confidence:** HIGH

## Summary

Phase 17 requires unit tests verifying SyncEngine's circuit breaker behavior. The circuit breaker trips after 3 consecutive rate limit errors (HTTP 429), enters exponential backoff (30s -> 60s -> 120s -> max 300s), and blocks sync operations while tripped. The rate limit counter resets on any successful sync operation.

Research reveals that the test infrastructure from Phase 16 (MockNetworkClient with response queues, MockDataStore with in-memory ModelContainer) provides all necessary capabilities. The project uses Swift Testing framework (@Test, @Suite, #expect) with consistent naming patterns. Tests should focus on behavior verification (sync blocked/allowed, state transitions) rather than internal state inspection.

**Primary recommendation:** Create fresh SyncEngine per test with time-controllable backoff verification using spy call counts rather than actual time delays. Use MockNetworkClient response queues to simulate sequential success/failure patterns.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | 6.0+ | Test framework | Native Swift testing framework with @Test, @Suite macros |
| @testable import | N/A | Module access | Access internal APIs for testing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockNetworkClient | Local | Network call stubbing | All network operations in SyncEngine tests |
| MockDataStore | Local | SwiftData persistence stubbing | All data operations in SyncEngine tests |
| MockDataStoreFactory | Local | Factory injection | Required for actor boundary crossing |
| TestSupport | Local | Fixture factories | Creating test data (APIModelFixture, DeterministicDate) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift Testing | XCTest | XCTest is older; project already uses Swift Testing |
| Response queues | Global error injection | Queues enable sequential failure simulation |

**Installation:**
No additional dependencies required - all test infrastructure exists in `trendyTests/`.

## Architecture Patterns

### Recommended Test File Structure
```
trendyTests/
├── SyncEngine/
│   └── CircuitBreakerTests.swift  # All CB tests in single focused file
├── Mocks/
│   ├── MockNetworkClient.swift     # Existing (Phase 16)
│   ├── MockDataStore.swift         # Existing (Phase 16)
│   └── MockDataStoreFactory.swift  # Existing (Phase 16)
└── TestSupport.swift               # Existing fixtures
```

### Pattern 1: Fresh Actor Per Test
**What:** Create new SyncEngine instance for each test to ensure isolation
**When to use:** Every circuit breaker test
**Example:**
```swift
// Source: Existing project pattern
@Test("Circuit breaker trips after 3 consecutive rate limit errors")
func test_circuitBreaker_tripsAfterThreeRateLimits() async throws {
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

    // Configure response queue for sequential failures
    mockNetwork.createEventsBatchResponses = [
        .failure(APIError.httpError(429)),
        .failure(APIError.httpError(429)),
        .failure(APIError.httpError(429))
    ]

    // ... test body
}
```

### Pattern 2: Response Queues for Sequential Testing
**What:** Use MockNetworkClient's response queue arrays to control call-by-call behavior
**When to use:** Simulating sequences like "fail, fail, fail, succeed"
**Example:**
```swift
// Source: MockNetworkClient.swift lines 196-211
mockNetwork.createEventsBatchResponses = [
    .failure(APIError.httpError(429)),  // 1st call: rate limit
    .failure(APIError.httpError(429)),  // 2nd call: rate limit
    .failure(APIError.httpError(429)),  // 3rd call: rate limit (trips CB)
    .success(BatchCreateEventsResponse(created: [], errors: nil, total: 0, success: 0, failed: 0))  // 4th: blocked
]
```

### Pattern 3: Spy Call Counting for Verification
**What:** Verify behavior by counting calls made to mocks
**When to use:** Verifying sync was blocked (no calls made)
**Example:**
```swift
// Verify sync was blocked - no additional batch calls
let callsBefore = mockNetwork.createEventsBatchCalls.count
await engine.performSync()
let callsAfter = mockNetwork.createEventsBatchCalls.count
#expect(callsAfter == callsBefore, "No calls should be made while circuit breaker is tripped")
```

### Pattern 4: PendingMutation Seeding
**What:** Seed pending mutations to trigger flush behavior during sync
**When to use:** Testing circuit breaker during mutation flush
**Example:**
```swift
// Source: MockDataStore.swift line 570
let payload = try! JSONEncoder().encode(APIModelFixture.makeCreateEventRequest())
mockStore.seedPendingMutation(
    entityType: .event,
    entityId: "evt-1",
    operation: .create,
    payload: payload
)
```

### Anti-Patterns to Avoid
- **Real time delays:** Never use `Task.sleep` to wait for backoff - use behavior verification instead
- **Shared SyncEngine:** Never share SyncEngine between tests - create fresh instance each time
- **Internal state access:** Avoid accessing private properties - verify through behavior (calls made/not made)
- **Global error injection:** Avoid `errorToThrow` for sequential failure simulation - use response queues

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rate limit error simulation | Custom error type | `APIError.httpError(429)` | Already exists, has `isRateLimitError` property |
| Sequential response control | Stateful counters | MockNetworkClient response queues | Built into mock (e.g., `createEventsBatchResponses`) |
| Pending mutation creation | Manual model init | `mockStore.seedPendingMutation()` | Handles ModelContext insertion |
| API fixture creation | Raw dictionaries | `APIModelFixture.makeCreateEventRequest()` | Type-safe, handles all required fields |
| Time control for backoff | Injecting Clock | Verify via call counts | Actor boundary makes clock injection complex |

**Key insight:** The mock infrastructure from Phase 16 is comprehensive - use response queues and spy patterns rather than building custom solutions.

## Common Pitfalls

### Pitfall 1: Health Check Blocks Sync
**What goes wrong:** `performSync()` returns early if health check fails
**Why it happens:** SyncEngine calls `performHealthCheck()` before any sync operations
**How to avoid:** Configure `getEventTypesResponses` with success response for health check
**Warning signs:** Sync completes instantly with no mutation flush calls

```swift
// REQUIRED for any performSync test:
mockNetwork.eventTypesToReturn = [APIModelFixture.makeAPIEventType()]
// OR use response queue:
mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
```

### Pitfall 2: Actor Isolation with SyncEngine Properties
**What goes wrong:** Cannot directly read circuit breaker state from test
**Why it happens:** `consecutiveRateLimitErrors`, `rateLimitBackoffUntil` are private actor-isolated
**How to avoid:** Use public computed properties: `isCircuitBreakerTripped`, `circuitBreakerBackoffRemaining`
**Warning signs:** Compiler errors about actor isolation when accessing properties

```swift
// CORRECT: Use public computed properties (actor-isolated read)
let isTripped = await engine.isCircuitBreakerTripped
let backoffRemaining = await engine.circuitBreakerBackoffRemaining

// INCORRECT: Cannot access private properties
// engine.consecutiveRateLimitErrors  // Compiler error
```

### Pitfall 3: Response Queue Consumed Too Early
**What goes wrong:** Health check consumes first queue entry intended for mutation
**Why it happens:** `getEventTypes()` is called during health check AND potentially during bootstrap
**How to avoid:** Queue sufficient success responses before failures
**Warning signs:** First "failure" doesn't produce expected effect

```swift
// Configure health check to pass, then failures for mutations
mockNetwork.getEventTypesResponses = [
    .success([APIModelFixture.makeAPIEventType()]),  // Health check
    .success([])  // Bootstrap (if cursor == 0)
]
mockNetwork.createEventsBatchResponses = [
    .failure(APIError.httpError(429)),
    .failure(APIError.httpError(429)),
    .failure(APIError.httpError(429))
]
```

### Pitfall 4: Backoff Timing Verification
**What goes wrong:** Tests become flaky or slow when verifying exponential backoff
**Why it happens:** Actual time-based backoff (30s, 60s, etc.) is impractical in tests
**How to avoid:** Verify backoff progression via `circuitBreakerBackoffRemaining` ranges
**Warning signs:** Tests timeout or produce inconsistent results

```swift
// CORRECT: Verify backoff is in expected range (not exact value)
let backoff = await engine.circuitBreakerBackoffRemaining
#expect(backoff > 25 && backoff <= 30, "First backoff should be ~30s")

// BETTER: Verify backoff increases between trips
let backoff1 = await engine.circuitBreakerBackoffRemaining
await engine.resetCircuitBreaker()
// ... trigger circuit breaker again
let backoff2 = await engine.circuitBreakerBackoffRemaining
#expect(backoff2 > backoff1, "Backoff should increase exponentially")
```

### Pitfall 5: Bootstrap vs Incremental Sync
**What goes wrong:** Test expects mutation flush but bootstrap wipes local data
**Why it happens:** When cursor == 0, SyncEngine does full bootstrap which clears data
**How to avoid:** Set initial cursor to non-zero value via UserDefaults OR accept bootstrap behavior
**Warning signs:** Mutations disappear, no flush calls despite pending mutations

```swift
// Set cursor to skip bootstrap (for mutation-focused tests)
let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
UserDefaults.standard.set(1000, forKey: cursorKey)
```

## Code Examples

Verified patterns from codebase analysis:

### Creating SyncEngine with Mocks
```swift
// Source: MockDataStoreFactory.swift usage pattern
let mockNetwork = MockNetworkClient()
let mockStore = MockDataStore()
let factory = MockDataStoreFactory(mockStore: mockStore)
let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
```

### Simulating Rate Limit Sequence
```swift
// Source: MockNetworkClient.swift response queue pattern
mockNetwork.createEventsBatchResponses = [
    .failure(APIError.httpError(429)),
    .failure(APIError.httpError(429)),
    .failure(APIError.httpError(429))
]
```

### Seeding Pending Mutations
```swift
// Source: MockDataStore.swift seedPendingMutation
let request = APIModelFixture.makeCreateEventRequest(
    id: "evt-1",
    eventTypeId: "type-1"
)
let payload = try! JSONEncoder().encode(request)
mockStore.seedPendingMutation(
    entityType: .event,
    entityId: "evt-1",
    operation: .create,
    payload: payload
)
```

### Verifying Circuit Breaker State
```swift
// Source: SyncEngine.swift lines 622-635
let isTripped = await engine.isCircuitBreakerTripped
let remaining = await engine.circuitBreakerBackoffRemaining
#expect(isTripped == true, "Circuit breaker should be tripped")
#expect(remaining > 0, "Backoff should be active")
```

### Verifying Sync Blocked
```swift
// Behavior verification via spy call counts
let callsBefore = mockNetwork.createEventsBatchCalls.count
await engine.performSync()
let callsAfter = mockNetwork.createEventsBatchCalls.count
#expect(callsAfter == callsBefore, "No flush calls while CB tripped")
```

### Resetting Circuit Breaker
```swift
// Source: SyncEngine.swift resetCircuitBreaker()
await engine.resetCircuitBreaker()
#expect(await engine.isCircuitBreakerTripped == false, "CB should be reset")
```

### Verifying Counter Reset on Success
```swift
// Configure: 2 failures, then success, then 2 more failures
mockNetwork.createEventsBatchResponses = [
    .failure(APIError.httpError(429)),  // +1
    .failure(APIError.httpError(429)),  // +2
    .success(successResponse),           // reset to 0
    .failure(APIError.httpError(429)),  // +1
    .failure(APIError.httpError(429))   // +2 (not 4, so no trip)
]
// After all syncs, CB should NOT be tripped (never hit 3 consecutive)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest with setUp/tearDown | Swift Testing @Test | Swift 5.9+ | Simpler test structure |
| XCTAssert macros | #expect | Swift Testing | More expressive assertions |
| Mock injection via subclass | Protocol + factory injection | Phase 13-16 | Actor-safe dependency injection |

**Deprecated/outdated:**
- XCTest: Still supported but project uses Swift Testing
- Global mock state: Replaced with per-test instance creation

## Open Questions

Things that couldn't be fully resolved:

1. **Exact Backoff Timing Tolerance**
   - What we know: Base backoff is 30s, doubles each trip, max 300s
   - What's unclear: Acceptable tolerance for test assertions (timing drift)
   - Recommendation: Use range checks (e.g., 25-35s) rather than exact values

2. **HealthKit/Calendar ID Fields in Test Fixtures**
   - What we know: APIModelFixture.makeCreateEventRequest doesn't set healthKitSampleId
   - What's unclear: Whether tests need these fields populated
   - Recommendation: Keep simple fixtures; add specific fields only if tests require them

## Sources

### Primary (HIGH confidence)
- SyncEngine.swift lines 62-80 (circuit breaker state)
- SyncEngine.swift lines 621-644 (public CB API)
- SyncEngine.swift lines 728-742 (CB trip check during batch)
- SyncEngine.swift lines 1096-1108 (tripCircuitBreaker implementation)
- MockNetworkClient.swift (response queue pattern)
- MockDataStore.swift (seed methods)

### Secondary (MEDIUM confidence)
- APIErrorTests.swift (test patterns)
- EventModelTests.swift (Swift Testing conventions)
- MockNetworkClientTests.swift (mock usage examples)

### Tertiary (LOW confidence)
- None - all findings verified from codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from existing test files
- Architecture: HIGH - patterns from Phase 16 mocks and existing tests
- Pitfalls: HIGH - derived from SyncEngine implementation analysis

**Research date:** 2026-01-22
**Valid until:** Stable - patterns well-established in codebase

## Circuit Breaker Implementation Summary

For reference, here are the key implementation details from SyncEngine:

| Constant | Value | Purpose |
|----------|-------|---------|
| `rateLimitCircuitBreakerThreshold` | 3 | Consecutive 429s before trip |
| `rateLimitBaseBackoff` | 30.0 seconds | Initial backoff duration |
| `rateLimitMaxBackoff` | 300.0 seconds (5 min) | Maximum backoff cap |
| `rateLimitBackoffMultiplier` | Starts at 1.0, doubles each trip | Exponential growth |

**State transitions:**
1. Each rate limit error increments `consecutiveRateLimitErrors`
2. Any successful operation resets `consecutiveRateLimitErrors` to 0
3. When counter reaches threshold, `tripCircuitBreaker()` is called
4. Backoff duration = min(baseBackoff * multiplier, maxBackoff)
5. Multiplier doubles after each trip (capped at 10x)
6. `isCircuitBreakerTripped` returns true while `Date() < rateLimitBackoffUntil`

**Test requirements mapping:**
| Requirement | Verifies |
|-------------|----------|
| CB-01 | Counter increments and trips at 3 |
| CB-02 | `isCircuitBreakerTripped` becomes false after backoff expires |
| CB-03 | No network calls made while CB tripped |
| CB-04 | Backoff progression: 30 -> 60 -> 120 -> 240 -> 300 (capped) |
| CB-05 | Counter resets to 0 after successful operation |
