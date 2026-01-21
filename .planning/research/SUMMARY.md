# Project Research Summary

**Project:** Trendy v1.2 SyncEngine Quality
**Domain:** iOS sync engine testing and code quality
**Researched:** 2026-01-21
**Confidence:** HIGH

## Executive Summary

The v1.2 milestone addresses critical quality and testability gaps in Trendy's SyncEngine, informed by production code review findings. Research reveals that Swift Testing (already integrated) combined with protocol-based dependency injection provides the cleanest path to comprehensive testing without adding heavyweight dependencies. The core challenge is retrofitting testability into an actor-based architecture while preserving Swift concurrency guarantees.

The recommended approach uses protocol extraction for existing dependencies (APIClient, LocalStore) with factory patterns for non-Sendable types like ModelContext. This enables unit testing of complex sync behaviors (circuit breaker, resurrection prevention, deduplication) while maintaining production architecture integrity. Migration is incremental and compiler-enforced, minimizing risk of regression.

Key risks center on actor isolation complexity and SwiftData concurrency. Mitigation strategies include strict protocol boundaries, factory-based ModelContext creation per operation, and @unchecked Sendable mocks for test-only code. The codebase already exhibits several testability anti-patterns (45+ print statements, hard-coded dependencies, missing completion handlers) that this milestone will address systematically.

## Key Findings

### Recommended Stack

**No new dependencies required.** The project already has Swift Testing framework (Xcode 16) and uses native Apple telemetry infrastructure. Research confirms protocol-based DI and actor-compatible mocking patterns work with existing tooling.

**Core technologies:**
- **Swift Testing** (built-in) — Native async/await support, parallel execution, already in use in trendyTests
- **os.signpost** (built-in) — Development profiling and duration tracking with negligible overhead
- **MetricKit** (built-in) — Production metrics aggregation for real-world telemetry
- **Protocol + Init Injection** — Actor-safe DI without frameworks or magic

**Testing pattern:**
```swift
// Protocol definitions (new)
protocol NetworkClientProtocol: Sendable {
    func createEventWithIdempotency(...) async throws -> APIEvent
    func getChanges(since: Int64, limit: Int) async throws -> ChangeFeedResponse
}

protocol DataStoreFactory: Sendable {
    func makeDataStore(context: ModelContext) -> DataStoreProtocol
}

// SyncEngine refactored (uses protocols)
actor SyncEngine {
    private let networkClient: NetworkClientProtocol
    private let dataStoreFactory: DataStoreFactory

    init(networkClient: NetworkClientProtocol, dataStoreFactory: DataStoreFactory, ...) {
        self.networkClient = networkClient
        self.dataStoreFactory = dataStoreFactory
    }
}

// Test usage (mocks injected)
let mockNetwork = MockNetworkClient()
let mockFactory = MockDataStoreFactory()
let syncEngine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: mockFactory, ...)

await syncEngine.performSync()
#expect(mockNetwork.createEventCallCount == 5)
```

**Metrics approach:**
- os.signpost for development (view timing in Instruments)
- MetricKit for production (aggregated daily reports)
- Custom counters for sync-specific metrics (success rate, retry count, rate limit hits)
- PostHog integration for telemetry (already in use)

**Documentation tooling:**
- Markdown + Mermaid for diagrams (GitHub renders natively)
- Swift documentation comments (already in use)
- No org-mode or new tools needed

### Expected Features

**Must have (table stakes for quality milestone):**
- **Protocol-based DI for SyncEngine** — Testability without architectural changes
- **Unit tests for circuit breaker** — Verify rate limit handling trips correctly after 3 failures
- **Unit tests for resurrection prevention** — Verify deleted items don't reappear during bootstrap
- **Unit tests for deduplication** — Verify same item not created twice with idempotency keys
- **Structured logging replacement** — Remove 45+ print statements, use Log.sync consistently
- **Metrics collection** — Track sync duration, success/failure rates, retry counts
- **Completion handler verification** — Ensure all HealthKit/background callbacks handled correctly

**Should have (differentiators for maintainability):**
- **Sync state visibility** — "3 events pending sync" indicator for debugging
- **Deterministic progress indicators** — "Syncing 3 of 5" instead of spinner
- **Cursor validation logging** — Track cursor state changes for debugging resurrection bugs
- **Method refactoring** — Split large methods (flushPendingMutations, bootstrapSync) for readability
- **Mock actor implementations** — Thread-safe test doubles for APIClient and LocalStore

**Defer (out of scope for v1.2):**
- **Real-time HealthKit updates** — iOS controls timing, best-effort acceptable
- **Conflict resolution UI** — Current last-write-wins sufficient for v1.2
- **Bidirectional sync** — Server-to-client changes deferred to future milestone
- **Background sync optimization** — Focus on correctness before performance
- **>20 geofence smart rotation** — Complexity not justified by current usage

### Architecture Approach

**Migration Path: Protocol Extraction from Existing Dependencies**

The SyncEngine actor currently has two hard-coded dependencies (APIClient class, LocalStore struct) that prevent testing. The refactor extracts protocols without changing production behavior, then injects mocks for testing.

**Major components:**

1. **Protocol Layer** — NetworkClientProtocol, DataStoreProtocol, DataStoreFactory interfaces
   - Defines contracts for network and persistence operations
   - All methods async throws for actor compatibility
   - Marked Sendable for actor isolation safety

2. **Factory Pattern for ModelContext** — LocalStoreFactory creates DataStore instances per-operation
   - Handles non-Sendable ModelContext limitation
   - Prevents SwiftData file locking (fresh context per operation)
   - Testable via MockDataStoreFactory

3. **Test Doubles** — MockNetworkClient, MockDataStore with spy pattern
   - Track call counts and arguments for verification
   - Configure responses for different scenarios (success, error, rate limit)
   - Use @unchecked Sendable for test-only mutable state

**Dependency flow:**

```
Before (hard-coded):
EventStore → SyncEngine(apiClient: APIClient, modelContainer: ModelContainer)
              └── Uses concrete APIClient and creates LocalStore inline

After (protocol-based):
EventStore → SyncEngine(networkClient: NetworkClientProtocol, dataStoreFactory: DataStoreFactory)
              └── Production: APIClient conforms to NetworkClientProtocol
              └── Tests: MockNetworkClient injected
```

**Migration strategy (incremental, non-breaking):**

1. Define protocols (no existing code changes)
2. Add conformance to APIClient and LocalStore
3. Create LocalStoreFactory implementation
4. Refactor SyncEngine init and properties
5. Update EventStore initialization
6. Add comprehensive unit tests

**Critical constraints:**
- Actors require Sendable dependencies (protocols must be marked)
- ModelContext not Sendable (factory pattern required)
- Protocol methods called within actor-isolated context (not protocol extensions)
- Tests use @unchecked Sendable for mocks (single-threaded XCTest safe)

### Critical Pitfalls

**Top 5 from v1.2 perspective:**

1. **Not calling HealthKit completion handlers in all code paths** — HealthKit stops delivering updates after 3 missed callbacks
   - Prevention: Audit all observer query handlers, add explicit logging
   - Phase to address: Foundation (before any HealthKit refactor)

2. **SwiftData model objects passed across actor boundaries** — Data races and intermittent crashes
   - Prevention: Pass persistentModelID instead of models, enable strict concurrency checking
   - Phase to address: DI Integration (verify factory pattern prevents this)

3. **Cursor race conditions in sync engine** — Data disappears or duplicates
   - Prevention: Single-flight lock (already exists), only advance cursor after persistence
   - Phase to address: Testing (unit tests verify cursor management correctness)

4. **45+ print statements instead of structured logging** — Production debugging impossible
   - Prevention: Replace with Log.sync, add context (IDs, counts, timestamps)
   - Phase to address: Foundation (immediate cleanup before testing)

5. **Offline queue operations applied out of order** — EventTypes must sync before Events reference them
   - Prevention: Sort mutations by entity type, implement dependency-aware flush
   - Phase to address: Testing (unit tests verify ordering with mocks)

**Secondary concerns for v1.2:**

- Actor + property injection anti-pattern (use constructor injection)
- Service locator in actor (defeats isolation)
- Testing while charging only (battery behavior different)
- MockNetworkClient not thread-safe if used outside tests

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation & Cleanup
**Rationale:** Clean up technical debt before adding complexity. Structured logging and completion handler audits are prerequisites for reliable testing.

**Delivers:**
- All print() statements replaced with Log.sync
- HealthKit/BGTaskScheduler completion handlers verified
- Cursor state logging added for debugging
- Entitlements audit (background delivery, geofencing)

**Addresses:**
- Pitfall 14 (print statements)
- Pitfall 1 (missing entitlements)
- Pitfall 12 (BGTask registration)

**Avoids:** Building tests on top of unreliable logging/callbacks

**Estimated effort:** 8-12 hours

**Research flags:** Standard cleanup, no additional research needed

---

### Phase 2: Protocol Definitions
**Rationale:** Define abstractions before refactoring. Non-breaking change that sets up testing seam.

**Delivers:**
- NetworkClientProtocol with all SyncEngine-required methods
- DataStoreProtocol with all persistence operations
- DataStoreFactory protocol for ModelContext creation
- Protocol files in Protocols/ directory

**Addresses:**
- Testability requirement (no mocks possible without protocols)
- Sendable boundaries defined explicitly

**Avoids:** Pitfall 7 (SwiftData threading) via factory pattern

**Estimated effort:** 2-4 hours

**Research flags:** Standard protocol design, no additional research needed

---

### Phase 3: Implementation Conformance
**Rationale:** Make existing types conform to protocols without changing behavior. Compiler-enforced correctness.

**Delivers:**
- APIClient conforms to NetworkClientProtocol
- LocalStore conforms to DataStoreProtocol
- LocalStoreFactory implementation
- All existing tests pass (no behavior changes)

**Uses:** Protocol definitions from Phase 2

**Avoids:** Breaking existing production code

**Estimated effort:** 3-5 hours

**Research flags:** No additional research, straightforward conformance

---

### Phase 4: SyncEngine DI Refactor
**Rationale:** Update SyncEngine to use protocols. Breaking change but compiler-enforced migration.

**Delivers:**
- SyncEngine.init accepts NetworkClientProtocol and DataStoreFactory
- All apiClient usages → networkClient
- All LocalStore(modelContext:) → dataStoreFactory.makeDataStore(context:)
- EventStore updated to inject protocols

**Implements:** Actor + protocol injection pattern from ARCHITECTURE.md

**Addresses:**
- Testing seam now available
- Pitfall 7 prevention (factory ensures fresh ModelContext)

**Avoids:** Pitfall property injection (uses constructor injection)

**Estimated effort:** 4-6 hours

**Research flags:** No additional research, pattern well-documented

---

### Phase 5: Test Infrastructure
**Rationale:** Build mock implementations and test utilities before writing test cases.

**Delivers:**
- MockNetworkClient (spy pattern, configurable responses)
- MockDataStore (spy pattern, in-memory state)
- MockDataStoreFactory
- Test fixtures for APIEvent, ChangeFeedResponse, etc.

**Uses:** Protocol definitions, spy pattern from STACK.md

**Addresses:**
- Reusable test doubles for all future tests
- Actor-safe mocks (@unchecked Sendable for test context)

**Avoids:** Test pollution (reset() methods for cleanup)

**Estimated effort:** 6-8 hours

**Research flags:** No additional research, standard mock patterns

---

### Phase 6: Unit Tests - Circuit Breaker
**Rationale:** Test rate limit handling first (simpler than full sync, validates mock infrastructure).

**Delivers:**
- Test: Circuit breaker trips after 3 rate limits
- Test: Circuit breaker resets after backoff expires
- Test: Sync blocked while rate limited
- Test: Metrics track rate limit hits

**Addresses:**
- Pitfall 3 prevention (rate limit handling verified)
- Mock infrastructure validated

**Estimated effort:** 4-6 hours

**Research flags:** No additional research needed

---

### Phase 7: Unit Tests - Resurrection Prevention
**Rationale:** Most complex sync bug to test, requires cursor + delete state coordination.

**Delivers:**
- Test: Deleted items not re-created during bootstrap
- Test: pendingDeleteIds tracked correctly
- Test: Cursor advances only after successful delete
- Test: Bootstrap skips items in pendingDeleteIds

**Addresses:**
- Pitfall 9 (cursor race conditions)
- Pitfall 11 (operation ordering)

**Estimated effort:** 8-10 hours (complex scenarios)

**Research flags:** May need deeper research into edge cases during implementation

---

### Phase 8: Unit Tests - Deduplication
**Rationale:** Verify idempotency keys prevent duplicate creation during retry scenarios.

**Delivers:**
- Test: Same event not created twice with same idempotency key
- Test: Retry after network error uses same key
- Test: Different operations use different keys
- Test: Server returns 409 Conflict handled correctly

**Addresses:**
- Duplicate prevention (table stakes feature)
- Retry logic correctness

**Estimated effort:** 4-6 hours

**Research flags:** No additional research needed

---

### Phase 9: Code Quality - Method Refactoring
**Rationale:** Split large methods now that tests provide regression safety net.

**Delivers:**
- flushPendingMutations split into smaller methods
- bootstrapSync refactored for readability
- Cyclomatic complexity reduced
- Tests still pass (no behavior changes)

**Addresses:**
- Code review findings (large methods)
- Maintainability improvement

**Estimated effort:** 6-8 hours

**Research flags:** No additional research needed

---

### Phase 10: Metrics & Documentation
**Rationale:** Add observability last (tests validate correctness first).

**Delivers:**
- os.signpost instrumentation for sync operations
- Custom metrics: sync duration, success/failure rates
- MetricKit subscriber for production telemetry
- Mermaid state machine diagrams in docs
- Updated ARCHITECTURE.md with DI patterns

**Uses:** os.signpost, MetricKit from STACK.md

**Addresses:**
- Observability for production debugging
- Documentation for future maintainers

**Estimated effort:** 8-10 hours

**Research flags:** No additional research, all patterns documented

---

### Phase Ordering Rationale

**Foundation first:** Technical debt (logging, completion handlers) must be cleaned before reliable testing possible. Print statements interfere with test output.

**Protocols before refactor:** Define abstractions incrementally to avoid big-bang changes. Each phase is independently verifiable.

**Tests after infrastructure:** Mock implementations needed before test cases. Circuit breaker tests validate mock infrastructure before tackling complex resurrection scenarios.

**Refactoring after tests:** Large method splits risky without test coverage. Tests act as regression safety net.

**Metrics last:** Observability important but not blocking for correctness. Tests validate behavior first, metrics provide production visibility second.

**Dependencies respected:**
- Phase 2 → Phase 3 (conformance requires definitions)
- Phase 3 → Phase 4 (refactor requires conformance)
- Phase 4 → Phase 5 (mocks require protocols)
- Phase 5 → Phase 6-8 (tests require mocks)
- Phase 6-8 → Phase 9 (refactoring requires tests)

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 7 (Resurrection Tests):** Complex edge cases may emerge during test design. May need to research cursor + delete state interactions more deeply.
- **Phase 10 (MetricKit):** PostHog integration patterns may need research to avoid double-counting metrics.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Foundation):** Standard cleanup, well-understood patterns
- **Phase 2-5 (DI Migration):** Protocol patterns thoroughly researched, no unknowns
- **Phase 6, 8 (Circuit Breaker, Deduplication):** Straightforward test scenarios
- **Phase 9 (Refactoring):** Standard refactoring patterns with test safety net

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Swift Testing already in use, native frameworks verified available |
| Features | HIGH | Based on code review findings and production issues |
| Architecture | HIGH | Protocol + actor patterns verified in Swift 6 docs, factory pattern standard |
| Pitfalls | HIGH | Many mapped to current Trendy codebase issues, directly actionable |

**Overall confidence:** HIGH

### Gaps to Address

**Actor testing edge cases:** While @unchecked Sendable for mocks is well-documented, need to verify no accidental concurrent access in test setup/teardown. Plan: Add assertions in tests that mock state accessed serially.

**ModelContext lifecycle:** Factory pattern assumes fresh ModelContext per operation is sufficient. Need to validate this prevents SwiftData file locking during heavy test load. Plan: Add stress tests with many concurrent operations.

**Cursor validation logic:** Research covered general cursor management but not specific validation rules (e.g., cursor should never decrease, bootstrap should reset cursor). Plan: Document cursor invariants during Phase 1 logging additions.

**MetricKit daily delay:** MetricKit delivers metrics daily, not real-time. Need fallback strategy for immediate debugging. Plan: Use os.signpost for development, MetricKit for production trend analysis only.

**HealthKit frequency limits:** Documentation ambiguous on which data types support .immediate vs .hourly. Plan: Empirical testing on real device during Phase 2 (out of scope for v1.2 but noted for future).

## Sources

### Primary (HIGH confidence)

**Stack Research:**
- [Swift Testing - Xcode - Apple Developer](https://developer.apple.com/xcode/swift-testing) — Testing framework capabilities
- [Apple: os.signpost](https://developer.apple.com/documentation/os/logging) — Performance measurement
- [Apple: MetricKit](https://developer.apple.com/documentation/metrickit) — Production telemetry
- [Actor-Based Dependency Container in Swift](https://medium.com/@dmitryshlepkin/actor-based-dependency-container-in-swift-e677c105e57b) — Modern actor DI patterns
- [Swift Actor in Unit Tests](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631) — @unchecked Sendable pattern

**Architecture Research:**
- [Dependency Injection in Swift (2025)](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c) — Latest DI patterns
- [Managing Dependencies in the Age of SwiftUI](https://lucasvandongen.dev/dependency_injection_swift_swiftui.php) — SwiftUI + actor DI
- [Exploring Actors and Protocol Extensions](https://lucasvandongen.dev/swift_actors_and_protocol_extensions.php) — Actor isolation caveats

**Pitfalls Research:**
- Apple Developer Documentation: [HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery) — Completion handler requirements
- [BrightDigit: Using ModelActor in SwiftData](https://brightdigit.com/tutorials/swiftdata-modelactor/) — Actor isolation with SwiftData
- [Fat Bob Man: Concurrent Programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/) — Threading pitfalls
- Trendy codebase: HealthKitService.swift, GeofenceManager.swift, SyncEngine.swift — Current implementation analysis

### Secondary (MEDIUM confidence)

**Features Research:**
- [Radar: Limitations of iOS Geofencing](https://radar.com/blog/limitations-of-ios-geofencing) — 20 region limit patterns
- [Dev.to: Offline-First iOS Apps](https://dev.to/vijaya_saimunduru_c9579b/architecting-offline-first-ios-apps-with-idle-aware-background-sync-1dhh) — Sync queue patterns
- [Medium: iOS Background Processing Best Practices](https://uynguyen.github.io/2020/09/26/Best-practice-iOS-background-processing-Background-App-Refresh-Task/) — BGTaskScheduler usage

### Tertiary (needs validation)

**Open Questions:**
- HealthKit charging requirement (iOS version specific, needs device testing)
- iOS 15+ geofence reliability (may be resolved in iOS 17+, empirical validation needed)
- MetricKit signpost integration (documentation sparse, may need experimentation)

---
*Research completed: 2026-01-21*
*Ready for roadmap: yes*
