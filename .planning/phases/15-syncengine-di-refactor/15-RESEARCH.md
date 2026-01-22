# Phase 15: SyncEngine DI Refactor - Research

**Researched:** 2026-01-21
**Domain:** Swift Actor Constructor Injection with Protocol-Based Dependencies
**Confidence:** HIGH

## Summary

This phase refactors SyncEngine to accept protocol-based dependencies via constructor injection, completing the dependency injection infrastructure established in Phases 13-14. The existing protocols (NetworkClientProtocol, DataStoreProtocol, DataStoreFactory) and their conforming types (APIClient, LocalStore, DefaultDataStoreFactory) are already in place. The refactor involves modifying SyncEngine's init signature and replacing all internal concrete type usage with protocol types.

The standard approach for actor constructor injection in Swift 6 is straightforward: accept Sendable protocol types as parameters, store them as private properties, and use them internally. The key complexity is the factory pattern for ModelContext - since ModelContext is non-Sendable, the DataStoreFactory is passed in and called inside the actor to create DataStore instances.

**Primary recommendation:** Change SyncEngine.init to accept `networkClient: NetworkClientProtocol` and `dataStoreFactory: DataStoreFactory` parameters. Remove direct APIClient and ModelContainer references. Update EventStore to create SyncEngine with the new signature using DefaultDataStoreFactory. All changes compile cleanly due to protocol conformance already in place.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Concurrency | Built-in | Actor isolation | Native language feature |
| Swift Testing | Built-in (Xcode 16+) | Unit testing | Already used in codebase |
| SwiftData | iOS 17+ | ModelContainer (Sendable) | Factory pattern source |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation | Built-in | Sendable types | Protocol requirements |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Protocol injection | Concrete types | Less testable, tighter coupling |
| Factory for DataStore | Direct ModelContext | Non-Sendable can't cross actor boundary |
| Stored property | Computed property | Stored is simpler for immutable deps |

**No new dependencies required.** All infrastructure exists from Phases 13-14.

## Architecture Patterns

### Recommended Init Signature
```swift
actor SyncEngine {
    // MARK: - Dependencies (protocol-based)

    private let networkClient: any NetworkClientProtocol
    private let dataStoreFactory: any DataStoreFactory
    private let syncHistoryStore: SyncHistoryStore?

    // MARK: - Initialization

    init(
        networkClient: any NetworkClientProtocol,
        dataStoreFactory: any DataStoreFactory,
        syncHistoryStore: SyncHistoryStore? = nil
    ) {
        self.networkClient = networkClient
        self.dataStoreFactory = dataStoreFactory
        self.syncHistoryStore = syncHistoryStore

        // Load cursor from UserDefaults
        let cursorKeyValue = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        self.lastSyncCursor = Int64(UserDefaults.standard.integer(forKey: cursorKeyValue))

        Log.sync.info("SyncEngine init with DI", context: .with { ctx in
            ctx.add("cursor_key", cursorKeyValue)
            ctx.add("loaded_cursor", Int(self.lastSyncCursor))
        })
    }
}
```

### Pattern 1: Existential Protocol Storage

**What:** Store protocol types using `any` existential syntax for flexibility.

**When to use:** When the concrete type may vary (testing vs production).

**Example:**
```swift
// Source: Swift Evolution SE-0335 (Existential any)
private let networkClient: any NetworkClientProtocol

// Usage inside actor methods - protocol methods are called directly
let eventTypes = try await networkClient.getEventTypes()
let cursor = try await networkClient.getLatestCursor()
```

**Why not generics:** Generic type parameters on actors add complexity and don't provide meaningful benefits here since we're not composing types. Existentials are simpler and sufficient.

### Pattern 2: Factory-Created DataStore Per Operation

**What:** Call `dataStoreFactory.makeDataStore()` at the start of each operation that needs persistence.

**When to use:** Every method that interacts with SwiftData models.

**Example:**
```swift
// Source: SwiftData documentation - ModelContext threading model
private func flushPendingMutations() async throws {
    let dataStore = dataStoreFactory.makeDataStore()
    let mutations = try dataStore.fetchPendingMutations()

    for mutation in mutations {
        // Process mutation using dataStore
        try dataStore.save()
    }
}
```

**Critical insight:** Each sync operation should create a fresh ModelContext via the factory. This ensures:
1. Thread safety - context is created within actor isolation
2. Fresh data - no stale cached objects
3. Proper cleanup - context releases when operation completes

### Pattern 3: EventStore Creates SyncEngine with DI

**What:** EventStore instantiates SyncEngine by creating DefaultDataStoreFactory from ModelContainer.

**When to use:** Production code path (setModelContext method).

**Example:**
```swift
// In EventStore.setModelContext
if let apiClient = apiClient {
    let factory = DefaultDataStoreFactory(modelContainer: context.container)
    self.syncEngine = SyncEngine(
        networkClient: apiClient,
        dataStoreFactory: factory,
        syncHistoryStore: syncHistoryStore
    )
}
```

### Anti-Patterns to Avoid

- **Storing ModelContainer in SyncEngine:** Violates single responsibility. Let factory handle container.
- **Creating ModelContext in init:** Non-Sendable crossing boundary. Create per-operation via factory.
- **Passing DataStoreProtocol to init:** Not Sendable. Pass factory instead.
- **Using concrete APIClient type internally:** Defeats testability. Use protocol type.
- **Backward-compatible deprecated init:** Adds complexity. Clean break per CONTEXT.md decision.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mock network client | Stub each method manually | Actor-based mock class | Thread-safe, reusable |
| Test data persistence | File-based SQLite | In-memory ModelContainer | Faster, isolated per test |
| Dependency container | Global singleton | Constructor injection | Explicit dependencies |
| Thread synchronization | Manual locking | Actor isolation | Compiler-enforced safety |

**Key insight:** The protocols and conformances from Phases 13-14 provide everything needed. No new abstractions required.

## Common Pitfalls

### Pitfall 1: Forgetting to Replace All Concrete Usages
**What goes wrong:** SyncEngine still references `apiClient` or `LocalStore` directly somewhere.
**Why it happens:** Large file (~1900 lines) with many call sites.
**How to avoid:** Global find/replace with verification. Search for "APIClient", "LocalStore(", "modelContainer".
**Warning signs:** Compiler errors about "cannot convert" between protocol and concrete types.

### Pitfall 2: Creating DataStore Once and Reusing
**What goes wrong:** Stale data, context threading violations, or data loss.
**Why it happens:** Performance optimization instinct - "create once, reuse".
**How to avoid:** Create fresh DataStore per operation via factory.
**Warning signs:** "NSManagedObjectContext concurrency" crashes, missing data after sync.

### Pitfall 3: Exposing Internal State for Testing
**What goes wrong:** Breaks encapsulation, creates maintenance burden.
**Why it happens:** Tests need to verify internal state changes.
**How to avoid:** Test through public API behavior. If internal state matters, it should affect observable output.
**Warning signs:** `@testable import` accessing private properties.

### Pitfall 4: Not Updating All SyncEngine Call Sites
**What goes wrong:** Compilation fails or runtime crashes.
**Why it happens:** SyncEngine is created in EventStore but may be referenced elsewhere.
**How to avoid:** Compiler errors guide discovery. Search for "SyncEngine(" across codebase.
**Warning signs:** "Missing argument for parameter" compiler errors.

## Code Examples

### Complete Init Refactor

```swift
// File: Services/Sync/SyncEngine.swift
// Source: Phase 15 requirements

actor SyncEngine {
    // MARK: - Dependencies (protocol-based)

    private let networkClient: any NetworkClientProtocol
    private let dataStoreFactory: any DataStoreFactory
    private let syncHistoryStore: SyncHistoryStore?

    // MARK: - State (unchanged from current)

    private var lastSyncCursor: Int64 = 0
    private var isSyncing = false
    // ... other state properties

    // MARK: - Initialization

    init(
        networkClient: any NetworkClientProtocol,
        dataStoreFactory: any DataStoreFactory,
        syncHistoryStore: SyncHistoryStore? = nil
    ) {
        self.networkClient = networkClient
        self.dataStoreFactory = dataStoreFactory
        self.syncHistoryStore = syncHistoryStore

        // UserDefaults cursor loading (same as before)
        let cursorKeyValue = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        self.lastSyncCursor = Int64(UserDefaults.standard.integer(forKey: cursorKeyValue))

        Log.sync.info("SyncEngine init", context: .with { ctx in
            ctx.add("cursor_key", cursorKeyValue)
            ctx.add("loaded_cursor", Int(self.lastSyncCursor))
            ctx.add("environment", AppEnvironment.current.rawValue)
        })
    }
}
```

### Method Migration Example

```swift
// BEFORE (current):
private func flushPendingMutations() async throws {
    let context = ModelContext(modelContainer)  // Concrete type
    let localStore = LocalStore(modelContext: context)  // Concrete type
    let mutations = try localStore.fetchPendingMutations()
    // ... uses apiClient directly
}

// AFTER (refactored):
private func flushPendingMutations() async throws {
    let dataStore = dataStoreFactory.makeDataStore()  // Protocol type
    let mutations = try dataStore.fetchPendingMutations()
    // ... uses networkClient (protocol) instead of apiClient
}
```

### EventStore Integration

```swift
// File: ViewModels/EventStore.swift
// In setModelContext method

func setModelContext(_ context: ModelContext, syncHistoryStore: SyncHistoryStore? = nil) {
    self.modelContext = context
    self.modelContainer = context.container
    self.syncHistoryStore = syncHistoryStore

    // Initialize SyncEngine with protocol-based DI
    if let apiClient = apiClient {
        let factory = DefaultDataStoreFactory(modelContainer: context.container)
        self.syncEngine = SyncEngine(
            networkClient: apiClient,         // Conforms to NetworkClientProtocol
            dataStoreFactory: factory,        // Conforms to DataStoreFactory
            syncHistoryStore: syncHistoryStore
        )
    }

    // Load initial state
    if let syncEngine = syncEngine {
        Task {
            await syncEngine.loadInitialState()
            await queueMutationsForUnsyncedEvents()
            await refreshSyncStateForUI()
        }
    }
}
```

### Test Mock Example (for future Phase 16)

```swift
// File: trendyTests/Mocks/MockNetworkClient.swift
// Source: Swift Testing patterns from existing test suite

actor MockNetworkClient: NetworkClientProtocol {
    // Stubbed responses
    var stubbedEventTypes: [APIEventType] = []
    var stubbedEvents: [APIEvent] = []
    var stubbedChanges: ChangeFeedResponse = ChangeFeedResponse(
        changes: [],
        nextCursor: 0,
        hasMore: false
    )
    var stubbedLatestCursor: Int64 = 0

    // Call tracking
    var getEventTypesCalled = false
    var createEventCalls: [CreateEventRequest] = []
    var deleteEventCalls: [String] = []

    // Error injection
    var errorToThrow: Error?

    // Protocol implementation
    func getEventTypes() async throws -> [APIEventType] {
        getEventTypesCalled = true
        if let error = errorToThrow { throw error }
        return stubbedEventTypes
    }

    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse {
        if let error = errorToThrow { throw error }
        return stubbedChanges
    }

    // ... other protocol methods
}

// File: trendyTests/Mocks/MockDataStoreFactory.swift
final class MockDataStoreFactory: DataStoreFactory {
    private let mockDataStore: MockDataStore

    init(mockDataStore: MockDataStore = MockDataStore()) {
        self.mockDataStore = mockDataStore
    }

    func makeDataStore() -> any DataStoreProtocol {
        return mockDataStore
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Concrete type dependencies | Protocol-based DI | Swift 5.5+ actors | Testability |
| @unchecked Sendable hacks | Proper protocol design | Swift 6 strict | Compile-time safety |
| Property injection | Constructor injection | Best practice 2023+ | Immutability, clarity |
| Global singletons | Injected dependencies | Modern Swift | Explicit dependencies |
| ModelContext passed to actor | Factory pattern | SwiftData 2023+ | Thread safety |

**Current best practice:** Constructor injection with protocol types. Factory pattern for non-Sendable resources. Existential types (`any Protocol`) for storage.

## Open Questions

1. **Should syncHistoryStore also be protocol-based?**
   - What we know: It's an optional dependency, used only for metrics recording
   - What's unclear: Whether it needs testability in Phase 16 tests
   - Recommendation: Keep as concrete type for now. Can be extracted if testing requires.

2. **How many DataStore instances per sync cycle?**
   - What we know: Current code creates ModelContext at start of each major operation
   - What's unclear: Whether creating multiple DataStores per sync is problematic
   - Recommendation: Match current behavior - one DataStore per logical operation (flushMutations, pullChanges, bootstrap). Fresh context per operation is safest.

3. **Should loadInitialState use injected DataStore?**
   - What we know: loadInitialState accesses UserDefaults and SwiftData
   - What's unclear: Whether this operation needs isolation from main sync
   - Recommendation: Yes, use factory for consistency. Create DataStore at method start.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `apps/ios/trendy/Services/Sync/SyncEngine.swift` - current implementation (1926 lines)
- Existing codebase: `apps/ios/trendy/Protocols/NetworkClientProtocol.swift` - 53 lines, 24 methods
- Existing codebase: `apps/ios/trendy/Protocols/DataStoreProtocol.swift` - 87 lines, 18 methods
- Existing codebase: `apps/ios/trendy/Protocols/DataStoreFactory.swift` - factory pattern
- Phase 13-14 work: Protocol definitions and conformance already complete
- Phase 15 CONTEXT.md: User decisions on migration strategy (all-at-once)

### Secondary (MEDIUM confidence)
- [Swift 6 Sendable patterns](https://www.avanderlee.com/swift/sendable-protocol-closures/) - @unchecked Sendable usage
- [Dependency Injection in Swift with Protocols](https://swiftwithmajid.com/2019/03/06/dependency-injection-in-swift-with-protocols/) - Protocol-based DI
- [Swift 6 Concurrency Guide](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/) - Actor isolation patterns
- [Sendable and Strict Concurrency](https://fatbobman.com/en/posts/sendable-sending-nonsending/) - Deep dive on Sendable

### Tertiary (LOW confidence)
- WebSearch: General dependency injection patterns - confirmed existing research

## Metadata

**Confidence breakdown:**
- Init signature design: HIGH - Direct application of established patterns
- Internal migration: HIGH - Straightforward find/replace with verification
- EventStore integration: HIGH - Single call site, clear changes needed
- Testing implications: MEDIUM - Mock patterns clear, but not implemented until Phase 16

**Research date:** 2026-01-21
**Valid until:** 90 days (stable Swift 6 patterns, no framework changes expected)

## Verification Checklist

Before planning, verify these conditions are met:

- [x] NetworkClientProtocol exists with all 24 methods
- [x] DataStoreProtocol exists with all 18 methods
- [x] DataStoreFactory exists with makeDataStore() method
- [x] DefaultDataStoreFactory creates LocalStore instances
- [x] APIClient conforms to NetworkClientProtocol
- [x] LocalStore conforms to DataStoreProtocol
- [x] SyncEngine is the only place that needs refactoring
- [x] EventStore is the only place that creates SyncEngine
