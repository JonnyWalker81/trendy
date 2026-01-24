# Phase 21: Code Quality Refactoring - Research

**Researched:** 2026-01-23
**Domain:** Swift method extraction and refactoring within actors
**Confidence:** HIGH

## Summary

Phase 21 is a pure refactoring phase focused on splitting two large SyncEngine actor methods (`flushPendingMutations` ~247 lines, `bootstrapFetch` ~222 lines) into smaller, focused functions with each method under 50 lines. The existing unit test suite from Phases 17-20 (CircuitBreakerTests, BootstrapTests, BatchProcessingTests, ResurrectionPreventionTests, DeduplicationTests, SingleFlightTests, PaginationTests, HealthCheckTests) serves as the safety net.

This is low-risk refactoring because:
1. Comprehensive test coverage already exists
2. No behavior changes planned - pure extraction
3. Incremental commits allow easy bisection
4. Existing `flushEventCreateBatch` demonstrates the pattern to follow

**Primary recommendation:** Extract entity-specific methods following the established `flushEventCreateBatch` pattern, using line count (<50 lines per method) as the primary complexity metric since SwiftLint is not configured in this project.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Swift Testing | Latest | Unit test framework | Already used in existing tests (uses `@Test` and `#expect`) |
| SwiftData | Latest | Persistence layer | Already integrated, MockDataStore follows protocol |
| Xcode Refactoring | Built-in | Extract Method tooling | Native IDE support for Swift |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `git bisect` | Find regression commits | If tests fail after refactoring |
| Line counting | Complexity measurement | No SwiftLint configured, use line count |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Line count | SwiftLint cyclomatic_complexity | Would require adding SwiftLint to project - out of scope |
| Manual extraction | Xcode's Extract to Method | IDE automation faster but may not preserve actor semantics correctly |

## Architecture Patterns

### Current Method Structure Analysis

**`flushPendingMutations` (~247 lines, lines 682-928)**
```
1. Circuit breaker check (11 lines)
2. Empty mutations guard (4 lines)
3. Mutation separation by type (3 lines)
4. Progress initialization (2 lines)
5. Event CREATE batch loop (79 lines) <- extract to syncEventCreates()
6. Other mutations loop (124 lines) <- extract to syncNonEventMutations()
7. Save and update (3 lines)
```

**`bootstrapFetch` (~222 lines, lines 1544-1765)**
```
1. Nuclear cleanup (35 lines) <- candidate for extraction (Claude's discretion)
2. EventTypes fetch/upsert (23 lines) <- extract to fetchEventTypes()
3. Geofences fetch/upsert (25 lines) <- extract to fetchGeofences()
4. Events fetch/upsert (48 lines) <- extract to fetchEvents()
5. PropertyDefinitions fetch (40 lines) <- extract to fetchPropertyDefinitions()
6. Save + relationship restore (5 lines)
7. Verification + notification (32 lines)
```

### Recommended Extraction Pattern

Follow the existing `flushEventCreateBatch` pattern (lines 932-1094):
```swift
/// [Brief description of what the method does]
/// - Parameters:
///   - mutations: [Description]
///   - dataStore: [Description]
/// - Returns: [Description]
/// - Throws: [Conditions]
private func syncEventChanges(
    _ mutations: [PendingMutation],
    dataStore: any DataStoreProtocol
) async throws -> Int {
    // Focused, single-responsibility implementation
}
```

### Naming Conventions (from CONTEXT.md)
- Bootstrap methods: `fetch{Entity}s()` - e.g., `fetchEventTypes()`, `fetchGeofences()`, `fetchEvents()`, `fetchPropertyDefinitions()`
- Flush methods: `sync{Entity}Changes()` - e.g., `syncEventChanges()`, `syncGeofenceChanges()`
- Helper methods: descriptive names based on Swift conventions

### Method Ordering in File
Extracted methods should be placed immediately after the calling method to maintain readability:
```swift
// MARK: - Private: Flush Pending Mutations

private func flushPendingMutations() async throws {
    // Calls syncEventCreates, syncNonEventMutations
}

private func syncEventCreates(...) async throws -> Int { }
private func syncNonEventMutations(...) async throws { }

// MARK: - Private: Bootstrap Fetch

private func bootstrapFetch() async throws {
    // Calls fetchEventTypes, fetchGeofences, fetchEvents, fetchPropertyDefinitions
}

private func fetchEventTypes(dataStore:) async throws -> [APIEventType] { }
private func fetchGeofences(dataStore:) async throws { }
private func fetchEvents(dataStore:) async throws { }
private func fetchPropertyDefinitions(dataStore:eventTypes:) async throws { }
```

### Anti-Patterns to Avoid
- **Extracting too granularly:** Don't create methods with 5-10 lines that are only called once - aim for logical groupings
- **Breaking actor isolation:** All extracted methods must remain within the actor - no extracting to free functions
- **Changing method signatures:** Keep parameters minimal, pass `dataStore` reference rather than creating new contexts
- **Modifying behavior:** This is PURE refactoring - if tests fail, the refactoring is incorrect

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Method extraction | Manual copy-paste | Xcode's Extract to Method | IDE handles scope, captures, and signatures |
| Complexity metrics | Custom line counter | Manual count or SwiftLint | Not worth automation for one-time task |
| Test runner | Custom scripts | `just test-backend` or Xcode test | Already configured |

**Key insight:** This phase is about code organization, not adding new functionality. All necessary infrastructure (mocks, test fixtures, DataStoreProtocol) already exists.

## Common Pitfalls

### Pitfall 1: Breaking Actor Isolation
**What goes wrong:** Extracting a method as a free function or to an extension that loses actor context
**Why it happens:** Xcode's Extract to Method may suggest non-actor scope
**How to avoid:** Keep all extracted methods as `private func` within the `actor SyncEngine` body
**Warning signs:** Compiler errors about async/await or `self` references

### Pitfall 2: Creating Multiple DataStore Instances
**What goes wrong:** Each extracted method creates its own `dataStoreFactory.makeDataStore()` causing SQLite file locking
**Why it happens:** Copying the pattern from method start without understanding context
**How to avoid:** Pass `dataStore` as a parameter from the calling method; only one `makeDataStore()` call per operation
**Warning signs:** "default.store couldn't be opened" errors in tests

### Pitfall 3: Changing Error Handling Behavior
**What goes wrong:** Extracted method swallows errors or throws different types
**Why it happens:** Refactoring `do-catch` blocks incorrectly
**How to avoid:** Preserve exact error propagation; if original code had `try?`, extracted code should too
**Warning signs:** Tests fail with different error behaviors

### Pitfall 4: Duplicating Circuit Breaker Checks
**What goes wrong:** Circuit breaker check appears in both parent and extracted method
**Why it happens:** Defensive over-extraction
**How to avoid:** Circuit breaker checks stay in `flushPendingMutations` only; extracted methods trust the caller
**Warning signs:** Rate limit counter incremented multiple times per failure

### Pitfall 5: Not Preserving Loop State Updates
**What goes wrong:** `syncedCount` or other state not updated correctly after extraction
**Why it happens:** Method returns value but caller doesn't accumulate
**How to avoid:** Extracted methods return counts/state; callers accumulate: `syncedCount += try await syncEventCreates(...)`
**Warning signs:** Progress UI shows wrong counts; tests fail on count assertions

## Code Examples

### Example 1: Bootstrap Method Extraction Pattern
```swift
// BEFORE: Inline in bootstrapFetch()
Log.sync.info("Bootstrap: fetching event types")
let eventTypes = try await networkClient.getEventTypes()
for apiEventType in eventTypes {
    try dataStore.upsertEventType(id: apiEventType.id) { eventType in
        eventType.name = apiEventType.name
        eventType.colorHex = apiEventType.color
        eventType.iconName = apiEventType.icon
    }
}
try dataStore.save()

// AFTER: Extracted method
private func fetchEventTypes(dataStore: any DataStoreProtocol) async throws -> [APIEventType] {
    Log.sync.info("Bootstrap: fetching event types")
    let eventTypes = try await networkClient.getEventTypes()
    Log.sync.info("Bootstrap: received event types", context: .with { ctx in
        ctx.add("count", eventTypes.count)
    })

    for apiEventType in eventTypes {
        try dataStore.upsertEventType(id: apiEventType.id) { eventType in
            eventType.name = apiEventType.name
            eventType.colorHex = apiEventType.color
            eventType.iconName = apiEventType.icon
        }
    }

    try dataStore.save()
    return eventTypes
}
```

### Example 2: Flush Method Extraction Pattern
```swift
// BEFORE: Inline loop in flushPendingMutations()
for mutation in otherMutations {
    // Check circuit breaker
    // Process mutation
    // Handle errors
    // Update counts
}

// AFTER: Extracted method returning synced count
private func syncNonEventMutations(
    _ mutations: [PendingMutation],
    dataStore: any DataStoreProtocol,
    startingCount: Int,
    totalPending: Int
) async throws -> Int {
    var syncedCount = startingCount

    for mutation in mutations {
        // Check circuit breaker before each mutation
        if consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold {
            tripCircuitBreaker()
            // ... update state and return early
            return syncedCount
        }

        // ... rest of processing
        syncedCount += 1
        await updateState(.syncing(synced: syncedCount, total: totalPending))
    }

    return syncedCount
}
```

### Example 3: Circuit Breaker Helper (Optional Extraction)
```swift
// If 3+ call sites have similar circuit breaker checks, extract:
private func shouldTripCircuitBreaker() -> Bool {
    consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold
}

private func handleCircuitBreakerTrip(dataStore: any DataStoreProtocol) async {
    tripCircuitBreaker()
    let remaining = circuitBreakerBackoffRemaining
    let pendingNow = getPendingCountFromDataStore(dataStore)
    Log.sync.warning("Circuit breaker tripped", context: .with { ctx in
        ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
        ctx.add("backoff_seconds", Int(remaining))
        ctx.add("pending_remaining", pendingNow)
    })
    await updateState(.rateLimited(retryAfter: remaining, pending: pendingNow))
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest | Swift Testing (`@Test`, `#expect`) | Swift 5.9+ | Already migrated - tests use new framework |
| `XCTAssert*` | `#expect()` macro | Swift 5.9+ | All assertions use modern syntax |

**No deprecated approaches in scope:** The SyncEngine uses modern Swift concurrency (actors, async/await) and SwiftData - no migration needed.

## Open Questions

### 1. Nuclear Cleanup Extraction
- **What we know:** Nuclear cleanup in `bootstrapFetch` is 35 lines (lines 1548-1582)
- **What's unclear:** Whether it improves clarity to extract or adds unnecessary indirection
- **Recommendation:** Extract if it pushes `bootstrapFetch` over 50 lines after other extractions; otherwise leave inline (Claude's discretion per CONTEXT.md)

### 2. Retry-Exceeded Logic Consolidation
- **What we know:** Retry-exceeded handling appears in multiple places (batch processing, individual mutation processing)
- **What's unclear:** Whether there are truly 3+ duplications warranting extraction
- **Recommendation:** Count occurrences during implementation; extract if >= 3 (Claude's discretion per CONTEXT.md)

### 3. Xcode Extract to Method vs Manual
- **What we know:** Xcode has built-in refactoring
- **What's unclear:** Whether it handles actor methods correctly
- **Recommendation:** Test on a small extraction first; fall back to manual if actor semantics are broken

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `/Users/cipher/Repositories/trendy/apps/ios/trendy/Services/Sync/SyncEngine.swift` (1876 lines)
- Test suite: `/Users/cipher/Repositories/trendy/apps/ios/trendyTests/SyncEngine/` (8 test files)
- Mock infrastructure: `/Users/cipher/Repositories/trendy/apps/ios/trendyTests/Mocks/MockDataStore.swift`

### Secondary (MEDIUM confidence)
- [SwiftLint Cyclomatic Complexity Rule](https://realm.github.io/SwiftLint/cyclomatic_complexity.html) - Default thresholds: warning at 10, error at 20
- [Swift Local Refactoring (swift.org)](https://www.swift.org/blog/swift-local-refactoring/) - Official Swift refactoring documentation
- [Refactoring Swift: Best Practices (SwiftLee)](https://www.avanderlee.com/optimization/refactoring-swift-best-practices/) - Industry best practices

### Tertiary (LOW confidence)
- [Cyclomatic Complexity in Swift (Holy Swift)](https://holyswift.app/how-to-reduce-cyclomatic-complexity-in-swift/) - General complexity reduction techniques
- [CodeSignal Extract Method Tutorial](https://codesignal.com/learn/courses/refactoring-by-leveraging-your-tests-with-swift-and-xctest/lessons/refactoring-in-swift-extract-method-for-improved-code-maintainability) - TDD refactoring workflow

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using existing project tools, no new dependencies
- Architecture: HIGH - Pattern established by existing `flushEventCreateBatch` method
- Pitfalls: HIGH - Based on actual codebase analysis and documented patterns (SQLite locking, actor isolation)

**Research date:** 2026-01-23
**Valid until:** 2026-02-23 (30 days - stable refactoring patterns)

## Test Coverage Summary

Existing test coverage provides safety net:

| Test File | Coverage Area | Tests |
|-----------|--------------|-------|
| CircuitBreakerTests.swift | Rate limit handling, exponential backoff | 10 tests |
| BootstrapTests.swift | Full data download, relationship restoration | 8 tests |
| BatchProcessingTests.swift | 50-event batches, partial failure handling | 9 tests |
| ResurrectionPreventionTests.swift | Deleted items not re-created | 10 tests |
| DeduplicationTests.swift | Duplicate mutation prevention | Tests exist |
| SingleFlightTests.swift | Concurrent sync prevention | Tests exist |
| PaginationTests.swift | Change feed pagination | Tests exist |
| HealthCheckTests.swift | Captive portal detection | Tests exist |

**All tests use Swift Testing framework** with `@Test` attributes and `#expect()` assertions, backed by `MockDataStore` and `MockNetworkClient` infrastructure.
