# Pitfalls Research: SyncEngine Testing & DI

**Domain:** Swift Actor Testing and Dependency Injection
**Researched:** 2026-01-21
**Confidence:** HIGH (verified with multiple authoritative sources and existing codebase analysis)

## Executive Summary

Adding tests and DI to existing Swift actors is deceptively complex. The primary challenges stem from actor reentrancy, isolation boundaries, and state verification across suspension points. This research identifies critical pitfalls specific to testing SyncEngine (a Swift actor with async methods, internal state, APIClient/LocalStore dependencies, and circuit breaker logic).

**Most Critical Pitfall:** Actor reentrancy causing state mutations across `await` suspension points, leading to flaky tests that pass/fail unpredictably based on timing.

---

## DI Pitfalls

### Pitfall 1: Protocol-Based DI Breaking Actor Isolation

**What goes wrong:**
When protocols are used for DI in actors, any protocol/extension implementation behaves as if executed **outside** the actor's context. Even when applied to actors, protocol extensions do not inherit actor isolation, creating race conditions.

**Why it happens:**
Swift does not deliver compile-time guarantees for actor safety when using protocol-based approaches. Developers assume protocol conformance preserves actor isolation, but it doesn't.

**Warning signs:**
- Strict Concurrency Checker warnings about "nonisolated" protocol methods
- Static properties in actors accessed concurrently without warnings
- Unexpected data races in "actor-isolated" code that uses protocols

**Prevention:**
- **Prefer concrete dependency injection over protocol witnesses** for actors
- Use constructor injection with concrete types: `init(apiClient: APIClient, modelContainer: ModelContainer)`
- If protocols are required, mark protocol requirements as `async` to force suspension points
- Enable Strict Concurrency Checking (`SWIFT_STRICT_CONCURRENCY = complete`) to catch isolation violations early

**Phase:** Phase 1 (DI Setup)
Research whether protocol-based mocking is safe for this actor, or use concrete mocks.

**Sources:**
- [Swift Actors and Protocol Extensions - Pitfalls](https://lucasvandongen.dev/swift_actors_and_protocol_extensions.php) (MEDIUM confidence)
- [GitHub: ProtocolWitness Macro](https://github.com/daltonclaybrook/ProtocolWitness) (LOW confidence - alternative approach)

---

### Pitfall 2: Constructor vs Property Injection in Actors

**What goes wrong:**
Using property injection (setting dependencies after init) in actors causes isolation violations. Mutable properties set from outside the actor require async access, making test setup verbose and error-prone.

**Why it happens:**
Developers accustomed to class-based DI use property injection, but actors serialize all access. Setting a property becomes an async operation, complicating test setup.

**Warning signs:**
- Test setup requires `await actor.dependency = mockClient` patterns
- Cannot initialize actor in synchronous test setup methods
- `setUp()` needs to be marked async but XCTestCase doesn't support async setUp by default

**Prevention:**
- **Use constructor injection exclusively for actors**
- Make dependencies immutable (`let` not `var`)
- Current SyncEngine already follows this pattern correctly:
  ```swift
  init(apiClient: APIClient, modelContainer: ModelContainer, syncHistoryStore: SyncHistoryStore? = nil)
  ```
- Verify dependencies are `let` constants in Phase 1

**Phase:** Phase 1 (DI Setup)
Confirm all dependencies are constructor-injected and immutable.

**Sources:**
- [Dependency Injection in Swift (2025): Clean Architecture](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c) (HIGH confidence - recent, authoritative)
- [Constructor vs Property Injection in Swift](https://medium.com/@techmsy/method-injection-constructor-injection-and-property-injection-in-swift-b719641cd04f) (MEDIUM confidence)

---

### Pitfall 3: URLSession Mocking with Strict Concurrency

**What goes wrong:**
When mocking `URLSession` using `URLProtocol` subclasses, wrapping request handlers in actors causes Sendable and isolation warnings with Swift 6 concurrency compliance.

**Why it happens:**
`URLProtocol` was designed before structured concurrency. Its callbacks expect synchronous, non-isolated closures, but mock implementations need to store state safely.

**Warning signs:**
- Compiler errors: "Non-sendable type cannot be passed to concurrent code"
- Mock URLProtocol handlers causing data races in Thread Sanitizer
- Cannot wrap URLProtocol subclass in actor without isolation violations

**Prevention:**
- **Use protocol-based APIClient abstraction instead of mocking URLSession**
- Define `APIClientProtocol` with async methods matching current `APIClient`
- Create `MockAPIClient` as a concrete type (not URLProtocol-based)
- Store responses in actor-isolated state or use `@unchecked Sendable` carefully
- Alternative: Use lightweight DI pattern without protocols (struct with closures)

**Phase:** Phase 1 (DI Setup)
Design mock strategy that avoids URLProtocol entirely.

**Sources:**
- [Swift Forums: Mock URLProtocol with Strict Swift 6 Concurrency](https://forums.swift.org/t/mock-urlprotocol-with-strict-swift-6-concurrency/77135) (HIGH confidence - official forum, recent)
- [Mocking Network Connections in Swift Tests](https://www.donnywals.com/mocking-a-network-connection-in-your-swift-tests/) (MEDIUM confidence)

---

## Testing Pitfalls

### Pitfall 4: Actor Reentrancy Invalidating Test Assertions

**What goes wrong:**
Tests assume actor state remains unchanged across `await` calls, but reentrancy allows other tasks to interleave, mutating state before the test's next assertion runs. Results in flaky tests that sometimes pass, sometimes fail.

**Why it happens:**
Every `await` in an actor is a suspension point where the actor can process other tasks. Developers write tests assuming serial execution, but actors don't guarantee this.

**Concrete SyncEngine example:**
```swift
// Test code - FLAKY!
await syncEngine.performSync() // isSyncing = true
// SUSPENSION POINT - another task could call performSync() again
let pending = await syncEngine.getPendingCount()
// State may have changed due to reentrancy
XCTAssertEqual(pending, 0) // FLAKY - might be non-zero if reentrant task queued mutations
```

**Warning signs:**
- Tests pass in isolation but fail when run in parallel
- Intermittent failures with message "expected 0, got 5"
- Tests fail more often on faster machines (more likely to interleave)
- Different results when adding `print` statements (timing changes)

**Prevention:**
1. **Test state BEFORE and AFTER each await, not across suspension points**
   ```swift
   let beforeSync = await syncEngine.isSyncing
   XCTAssertFalse(beforeSync)

   await syncEngine.performSync()
   // Don't assert about state mid-operation

   let afterSync = await syncEngine.isSyncing
   XCTAssertFalse(afterSync) // Only assert AFTER operation completes
   ```

2. **Use single-flight pattern verification instead of state assertions**
   ```swift
   // Test that single-flight works by racing two calls
   await withTaskGroup(of: Void.self) { group in
     group.addTask { await syncEngine.performSync() }
     group.addTask { await syncEngine.performSync() }
   }
   // Verify only ONE sync actually ran by checking call count on mock
   ```

3. **Mock dependencies to control timing and prevent actual reentrancy**
   - Mock APIClient with controlled delays
   - Ensure test controls all async work

4. **Avoid asserting internal actor state across multiple await boundaries**

**Phase:** Phase 2 (Test Implementation)
Design tests that account for suspension points. Flag any cross-await assertions for review.

**Sources:**
- [What is Actor Reentrancy and How Can It Cause Problems](https://www.hackingwithswift.com/quick-start/concurrency/what-is-actor-reentrancy-and-how-can-it-cause-problems) (HIGH confidence)
- [Actor Reentrancy in Swift Explained](https://www.donnywals.com/actor-reentrancy-in-swift-explained/) (HIGH confidence)
- [Understanding Actor Reentrancy in Swift Concurrency (April 2025)](https://abdulahd1996.medium.com/understanding-actor-reentrancy-in-swift-concurrency-8a9459bd420a) (HIGH confidence - recent)

---

### Pitfall 5: Flaky Tests from Unstructured Concurrency

**What goes wrong:**
Tests create unstructured tasks (using `Task { }`) that outlive the test scope, causing assertions to run before async work completes. Tests pass/fail randomly based on CPU scheduling.

**Why it happens:**
Async tests can return before all spawned tasks finish. XCTest doesn't wait for unstructured tasks, only the test method's direct async context.

**SyncEngine risk areas:**
- `performSync()` creates tasks internally (if any)
- Background circuit breaker timers
- MainActor state updates via `await MainActor.run { }`

**Warning signs:**
- Test completes but background crashes appear in logs
- Assertions sometimes run before state updates complete
- Adding `Task.sleep` makes tests pass reliably
- Different behavior on Debug vs Release builds

**Prevention:**
1. **Use structured concurrency in tests**
   ```swift
   func testSync() async throws {
     await withTaskGroup(of: Void.self) { group in
       group.addTask { await syncEngine.performSync() }
       // Group waits for all tasks to complete
     }
     // NOW safe to assert
   }
   ```

2. **Avoid XCTestExpectation with async/await**
   - Expectations are legacy from pre-async/await era
   - Use structured concurrency instead

3. **For SyncEngine specifically:**
   - Use `withMainSerialExecutor` from PointFree's Swift Concurrency Extras
   - Run all tests on serial executor to eliminate timing-based flakiness
   - Tests become deterministic and fast

**Phase:** Phase 2 (Test Implementation)
Introduce Swift Concurrency Extras dependency for serial executor testing.

**Sources:**
- [Swift Concurrency Testing: Writing Safe and Fast Async Unit Tests](https://commitstudiogs.medium.com/swift-concurrency-testing-writing-safe-and-fast-async-unit-tests-0a511117a4c4) (HIGH confidence - August 2025)
- [Reliably Testing Async Code in Swift](https://www.pointfree.co/blog/posts/110-reliably-testing-async-code-in-swift) (HIGH confidence - PointFree)

---

### Pitfall 6: @MainActor Isolation in XCTest

**What goes wrong:**
SyncEngine has `@MainActor` properties (`state`, `pendingCount`, `lastSyncTime`). Accessing these from non-MainActor test methods causes strict concurrency warnings. Marking test class `@MainActor` conflicts with XCTestCase's nonisolated superclass.

**Why it happens:**
Swift 6 strict concurrency checking enforces actor isolation. XCTestCase is nonisolated by default, creating isolation mismatches when testing MainActor-isolated properties.

**Warning signs:**
- Compiler error: "Main actor-isolated initializer 'init()' has different actor isolation from nonisolated overridden instance method"
- Warning: "Expression is 'async' but is not marked with 'await'"
- Cannot mark `final class SyncEngineTests: XCTestCase` as `@MainActor`

**Prevention:**
1. **Mark individual test methods as @MainActor, not the test class**
   ```swift
   @MainActor
   func testStateUpdates() async throws {
     // Can access syncEngine.state directly
     XCTAssertEqual(syncEngine.state, .idle)
   }
   ```

2. **For non-MainActor tests, use await for MainActor property access**
   ```swift
   func testSync() async throws {
     await syncEngine.performSync()
     let state = await syncEngine.state
     XCTAssertEqual(state, .idle)
   }
   ```

3. **Xcode 16+ allows @MainActor on test classes if also marked Sendable**
   ```swift
   @MainActor final class SyncEngineTests: XCTestCase, @unchecked Sendable {
     // All tests run on MainActor
   }
   ```
   - Use with caution - `@unchecked Sendable` bypasses safety checks

**Phase:** Phase 2 (Test Implementation)
Decide on MainActor strategy per test. Use `@MainActor` on individual methods initially.

**Sources:**
- [XCTest Meets @MainActor: How to Fix Strict Concurrency Warnings](https://qualitycoding.org/xctest-mainactor/) (HIGH confidence)
- [Swift Forums: Swift 5.10 Concurrency and XCTest](https://forums.swift.org/t/swift-5-10-concurrency-and-xctest/69929) (HIGH confidence - official forum)
- [Unit Testing async/await Swift Code](https://www.avanderlee.com/concurrency/unit-testing-async-await/) (HIGH confidence)

---

### Pitfall 7: Testing Internal Actor State

**What goes wrong:**
Actor properties are isolated - tests cannot directly access internal state like `isSyncing`, `consecutiveRateLimitErrors`, or `lastSyncCursor` without making them public. Making them public just for testing breaks encapsulation.

**Why it happens:**
Swift actors enforce strict isolation. Internal properties are not accessible from outside the actor, even in tests. Unlike classes, you can't use `@testable import` to bypass `private`.

**Warning signs:**
- Test needs to verify circuit breaker state but can't access `consecutiveRateLimitErrors`
- Cannot check `isSyncing` flag directly to verify single-flight behavior
- Must infer internal state from public API behavior (indirect testing)

**Prevention:**
1. **Test behavior, not implementation**
   - Don't test `isSyncing` directly
   - Test that calling `performSync()` twice only syncs once (verify via mock call count)

2. **Add public query methods for testable state**
   ```swift
   // In SyncEngine
   var isCircuitBreakerTripped: Bool { ... } // Already exists
   var circuitBreakerBackoffRemaining: TimeInterval { ... } // Already exists
   ```
   - SyncEngine already has this for circuit breaker - good pattern

3. **Use mock dependencies to observe behavior**
   - Mock APIClient counts how many times `createEvent` was called
   - Verify indirectly: "If single-flight works, API should be called once even when performSync called twice"

4. **For state machines, test state transitions via public API**
   ```swift
   // Test circuit breaker trip
   // Simulate 3 consecutive rate limit errors
   mockAPI.nextError = .rateLimitError
   await syncEngine.performSync() // 1st failure
   await syncEngine.performSync() // 2nd failure
   await syncEngine.performSync() // 3rd failure - trips breaker

   // Verify via public property
   XCTAssertTrue(await syncEngine.isCircuitBreakerTripped)
   ```

**Phase:** Phase 3 (State Machine Testing)
Map internal state to public query methods. Add public methods if critical state is untestable.

**Sources:**
- [How to Test Code in Swift Using Actor](https://medium.com/@igorgcustodio/how-to-test-code-in-swift-using-actor-71b0dad2e252) (MEDIUM confidence)
- [Swift Actor in Unit Tests - Thumbtack Engineering](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631) (HIGH confidence)

---

## Actor-Specific Pitfalls

### Pitfall 8: Busy-Wait Polling in Actor Tests

**What goes wrong:**
Code like `while isSyncing { try? await Task.sleep(nanoseconds: 100_000_000) }` creates busy-wait loops that waste CPU and make tests slow. Worse, tests may timeout if the condition never becomes false.

**Why it happens:**
Developers want to wait for actor state to change but don't have an async notification mechanism, so they poll.

**Current SyncEngine Issue:**
Line 367-370 in `forceFullResync()`:
```swift
while isSyncing {
    Log.sync.debug("Waiting for in-progress sync to complete...")
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
}
```
This is a production code smell AND a testing red flag.

**Warning signs:**
- Tests take unnecessarily long (100ms per poll iteration)
- High CPU usage during tests
- Tests timeout waiting for condition
- Production code has polling loops

**Prevention:**
1. **Replace busy-wait with async notification**
   ```swift
   // Use AsyncStream or Continuation
   private var syncCompletionContinuations: [CheckedContinuation<Void, Never>] = []

   func waitForSyncCompletion() async {
     await withCheckedContinuation { continuation in
       if !isSyncing {
         continuation.resume()
       } else {
         syncCompletionContinuations.append(continuation)
       }
     }
   }

   // In performSync(), when sync completes:
   defer {
     syncCompletionContinuations.forEach { $0.resume() }
     syncCompletionContinuations.removeAll()
   }
   ```

2. **For tests, use mock dependencies to control timing**
   - Don't wait for state changes, control when they happen
   - Mock APIClient can return immediately or after delay

3. **Use structured concurrency to await operations directly**
   ```swift
   // Instead of:
   await syncEngine.performSync()
   while await syncEngine.isSyncing { ... } // BAD

   // Do:
   await syncEngine.performSync() // Already waits for completion
   ```

**Phase:** Phase 4 (Cleanup)
Refactor `forceFullResync()` to use continuation-based waiting. Fix in production code benefits tests.

**Sources:**
- Analysis of existing SyncEngine code (HIGH confidence)
- [Swift Concurrency: AsyncStream and Continuation](https://developer.apple.com/documentation/swift/asyncstream) (HIGH confidence - Apple docs)

---

### Pitfall 9: ModelContainer Thread Safety in Tests

**What goes wrong:**
Creating multiple `ModelContext` instances concurrently causes SQLite file locking errors: `"default.store couldn't be opened"`. Tests crash with database lock errors when parallel tests access SwiftData.

**Why it happens:**
SwiftData's `ModelContainer` is not designed for heavy concurrent access. Multiple concurrent `ModelContext` creations compete for file locks.

**Current SyncEngine Protection:**
Line 200-202 comment shows awareness:
```swift
// Create a single context for pre-sync operations to avoid SQLite file locking issues.
// Multiple concurrent ModelContexts can cause "default.store couldn't be opened" errors.
let preSyncContext = ModelContext(modelContainer)
```

**Warning signs:**
- Tests fail with SQLite error codes -1 or 14 (SQLITE_LOCKED)
- Error: "database is locked"
- Tests pass individually but fail when run in suite
- Flaky failures on CI (more parallel execution)

**Prevention:**
1. **Use in-memory ModelContainer for tests**
   ```swift
   let container = try ModelContainer(
     for: Event.self, EventType.self,
     configurations: ModelConfiguration(isStoredInMemoryOnly: true)
   )
   ```
   - Isolated per test
   - No file locking issues
   - Fast (no disk I/O)

2. **Serialize tests that use shared ModelContainer**
   ```swift
   // In Swift Testing framework
   @Test(.serialized)
   func testSync() async throws { ... }
   ```

3. **Create ONE ModelContext per actor lifetime in tests**
   - Don't create new contexts in loops
   - Reuse context from LocalStore

4. **For XCTest, disable parallel execution**
   ```swift
   // In test plan
   testExecutionOrdering: .random
   parallel: false
   ```

**Phase:** Phase 1 (DI Setup)
Configure in-memory ModelContainer for tests. Document thread safety expectations.

**Sources:**
- [Swift Forums: SwiftData Concurrency Issues](https://developer.apple.com/forums/tags/swiftdata) (MEDIUM confidence - community reports)
- Analysis of existing SyncEngine code comments (HIGH confidence)

---

## Integration Pitfalls

### Pitfall 10: Circuit Breaker State Reset in Tests

**What goes wrong:**
Circuit breaker state (`consecutiveRateLimitErrors`, `rateLimitBackoffUntil`, `rateLimitBackoffMultiplier`) persists across tests if the same SyncEngine instance is reused, causing test interdependence. Test order affects pass/fail.

**Why it happens:**
Circuit breaker is stateful by design. Tests must explicitly reset state or create new instances.

**Warning signs:**
- Test A trips circuit breaker, Test B fails because breaker is still tripped
- Tests pass when run individually, fail in suite
- Test results depend on execution order

**Prevention:**
1. **Create fresh SyncEngine instance per test**
   ```swift
   override func setUp() async throws {
     mockAPI = MockAPIClient()
     container = try ModelContainer(for: Event.self, ...)
     syncEngine = SyncEngine(apiClient: mockAPI, modelContainer: container)
   }
   ```

2. **Call resetCircuitBreaker() in setUp**
   ```swift
   override func setUp() async throws {
     await syncEngine.resetCircuitBreaker()
   }
   ```

3. **Test circuit breaker isolation explicitly**
   ```swift
   func testCircuitBreakerDoesNotAffectNextTest() async {
     // Trip breaker
     await tripCircuitBreaker()
     XCTAssertTrue(await syncEngine.isCircuitBreakerTripped)

     // Reset
     await syncEngine.resetCircuitBreaker()
     XCTAssertFalse(await syncEngine.isCircuitBreakerTripped)
   }
   ```

**Phase:** Phase 3 (State Machine Testing)
Verify circuit breaker reset between tests. Add explicit reset to setUp.

**Sources:**
- [API Circuit Breaker in iOS: A Beginner's Guide](https://medium.com/@adarsh.ranjan/api-circuit-breaker-in-ios-a-beginners-comprehensive-guide-7973e6d3ebd5) (MEDIUM confidence)
- Analysis of SyncEngine circuit breaker implementation (HIGH confidence)

---

### Pitfall 11: Time-Based Test Flakiness (Exponential Backoff)

**What goes wrong:**
Circuit breaker uses real `Date()` for backoff timing. Tests that verify backoff behavior are flaky because:
- Real time passes during test execution
- Tests may timeout waiting for 30-300 second backoffs
- Time-dependent assertions fail intermittently

**Why it happens:**
Production code uses system clock. Tests don't control time progression.

**SyncEngine risk areas:**
- `rateLimitBackoffUntil: Date?` - uses real Date()
- `circuitBreakerBackoffRemaining: TimeInterval` - calculates from Date()
- Backoff durations: 30s base, up to 300s max

**Warning signs:**
- Tests that verify backoff timing occasionally fail
- Tests take many seconds to run
- Different results on fast vs slow machines
- Failures with "expected backoff to be 30, got 29.5"

**Prevention:**
1. **Inject clock/time dependency (preferred)**
   ```swift
   protocol Clock {
     func now() -> Date
     func sleep(for duration: TimeInterval) async throws
   }

   struct SystemClock: Clock { ... }
   struct MockClock: Clock {
     var currentTime: Date
     mutating func advance(by: TimeInterval) { ... }
   }
   ```

2. **Use PointFree's Clocks library**
   - Provides `TestClock` for deterministic time control
   - Compatible with structured concurrency

3. **For SyncEngine, add clock parameter**
   ```swift
   init(apiClient: APIClient,
        modelContainer: ModelContainer,
        clock: Clock = SystemClock())
   ```

4. **Verify backoff LOGIC, not timing**
   ```swift
   // Don't test actual 30-second wait
   // Test that backoff duration is calculated correctly
   let backoff = syncEngine.calculateBackoff(attempts: 3)
   XCTAssertEqual(backoff, 30.0 * pow(2, 3)) // Formula test
   ```

**Phase:** Phase 3 (State Machine Testing)
Add clock dependency. Test backoff calculation separately from time passage.

**Sources:**
- [PointFree Episode #111: Designing Dependencies - Modularization](https://www.pointfree.co/episodes/ep111-designing-dependencies-modularization) (HIGH confidence)
- [Exponential Backoff and Retry Patterns in Mobile](https://www.yaircarreno.com/2021/03/exponential-backoff-and-retry-patterns.html) (MEDIUM confidence)

---

### Pitfall 12: Missing Error Scenarios in Tests

**What goes wrong:**
Tests focus on happy path (successful sync) but miss error scenarios that production code handles:
- Network timeouts
- Rate limit errors
- Duplicate errors
- Batch operation failures
- Decoding failures

SyncEngine has robust error handling (lines 812-898), but without tests, regressions go unnoticed.

**Why it happens:**
Error path testing requires more setup (mocking error responses). Developers skip it due to complexity.

**Warning signs:**
- High code coverage on happy path, low coverage on error handlers
- Production errors that "should never happen" according to comments
- Defensive code with `try?` that silently swallows errors

**Prevention:**
1. **Create error scenario test suite**
   ```swift
   func testRateLimitError() async throws {
     mockAPI.nextError = .rateLimitError
     await syncEngine.performSync()
     XCTAssertEqual(await syncEngine.state, .rateLimited(...))
   }

   func testDuplicateError() async throws {
     mockAPI.nextError = .duplicateError
     await syncEngine.performSync()
     // Verify duplicate was deleted from local store
   }
   ```

2. **Test circuit breaker trip sequence**
   ```swift
   func testCircuitBreakerTripsAfterThreeRateLimits() async {
     for i in 1...3 {
       mockAPI.nextError = .rateLimitError
       await syncEngine.performSync()
     }
     XCTAssertTrue(await syncEngine.isCircuitBreakerTripped)
   }
   ```

3. **Test error recovery**
   ```swift
   func testRecoveryAfterNetworkError() async {
     mockAPI.nextError = .networkError
     await syncEngine.performSync()
     XCTAssertEqual(await syncEngine.state, .error(...))

     mockAPI.nextError = nil
     await syncEngine.performSync()
     XCTAssertEqual(await syncEngine.state, .idle)
   }
   ```

4. **Use mutation attempt count logic**
   - Verify mutations are retried with exponential backoff
   - Verify mutations exceeding retry limit are marked failed

**Phase:** Phase 3 (State Machine Testing)
Create comprehensive error scenario test suite covering all APIError cases.

**Sources:**
- Analysis of SyncEngine error handling code (HIGH confidence)
- [Unit Testing Best Practices](https://www.swiftbysundell.com/basics/unit-testing/) (MEDIUM confidence)

---

## Summary: Phase Mapping

| Phase | Key Pitfalls to Address |
|-------|------------------------|
| **Phase 1: DI Setup** | #1 (Protocol Isolation), #2 (Constructor DI), #3 (URLSession Mocking), #9 (ModelContainer Thread Safety) |
| **Phase 2: Test Implementation** | #4 (Reentrancy), #5 (Unstructured Concurrency), #6 (@MainActor Isolation), #7 (Internal State) |
| **Phase 3: State Machine Testing** | #10 (Circuit Breaker Reset), #11 (Time-Based Flakiness), #12 (Error Scenarios) |
| **Phase 4: Cleanup** | #8 (Busy-Wait Polling) |

---

## Critical Success Criteria

- [ ] Use constructor injection with immutable dependencies
- [ ] Create protocol abstraction for APIClient, avoid URLProtocol mocking
- [ ] Use in-memory ModelContainer for tests
- [ ] Add serial executor (Swift Concurrency Extras) to eliminate timing flakiness
- [ ] Never assert state across `await` suspension points
- [ ] Mark tests with @MainActor or use await for MainActor property access
- [ ] Test behavior via public API, not internal state
- [ ] Inject clock dependency for time-based logic
- [ ] Create fresh SyncEngine per test or reset circuit breaker in setUp
- [ ] Test all error scenarios (rate limit, duplicate, network failure, timeout)

---

## Sources

### High Confidence
- [Actor Reentrancy - Hacking with Swift](https://www.hackingwithswift.com/quick-start/concurrency/what-is-actor-reentrancy-and-how-can-it-cause-problems)
- [Actor Reentrancy in Swift Explained - Donny Wals](https://www.donnywals.com/actor-reentrancy-in-swift-explained/)
- [Understanding Actor Reentrancy (April 2025)](https://abdulahd1996.medium.com/understanding-actor-reentrancy-in-swift-concurrency-8a9459bd420a)
- [Swift Concurrency Testing (August 2025)](https://commitstudiogs.medium.com/swift-concurrency-testing-writing-safe-and-fast-async-unit-tests-0a511117a4c4)
- [XCTest Meets @MainActor](https://qualitycoding.org/xctest-mainactor/)
- [Unit Testing async/await Swift Code - SwiftLee](https://www.avanderlee.com/concurrency/unit-testing-async-await/)
- [Reliably Testing Async Code - PointFree](https://www.pointfree.co/blog/posts/110-reliably-testing-async-code-in-swift)
- [Swift Forums: Mock URLProtocol with Strict Swift 6 Concurrency](https://forums.swift.org/t/mock-urlprotocol-with-strict-swift-6-concurrency/77135)
- [Swift Forums: Swift 5.10 Concurrency and XCTest](https://forums.swift.org/t/swift-5-10-concurrency-and-xctest/69929)
- [Swift Actor in Unit Tests - Thumbtack Engineering](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631)
- [Dependency Injection in Swift (2025)](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c)

### Medium Confidence
- [Swift Actors and Protocol Extensions - Pitfalls](https://lucasvandongen.dev/swift_actors_and_protocol_extensions.php)
- [Mocking Network Connections - Donny Wals](https://www.donnywals.com/mocking-a-network-connection-in-your-swift-tests/)
- [How to Test Code in Swift Using Actor](https://medium.com/@igorgcustodio/how-to-test-code-in-swift-using-actor-71b0dad2e252)
- [API Circuit Breaker in iOS](https://medium.com/@adarsh.ranjan/api-circuit-breaker-in-ios-a-beginners-comprehensive-guide-7973e6d3ebd5)
- [Exponential Backoff and Retry Patterns](https://www.yaircarreno.com/2021/03/exponential-backoff-and-retry-patterns.html)
- [Constructor vs Property Injection](https://medium.com/@techmsy/method-injection-constructor-injection-and-property-injection-in-swift-b719641cd04f)

### Code Analysis (High Confidence)
- SyncEngine.swift (lines 367-370: busy-wait polling)
- SyncEngine.swift (lines 200-202: ModelContainer thread safety comment)
- SyncEngine.swift (lines 812-898: comprehensive error handling)
- APIClient.swift (timeout configuration)
- LocalStore.swift (ModelContext usage patterns)
