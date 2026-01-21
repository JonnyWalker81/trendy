# Architecture Research: DI Integration with Swift Actor

**Project:** Trendy iOS - SyncEngine DI Refactor
**Researched:** 2026-01-21
**Overall confidence:** HIGH

## Executive Summary

This research addresses how to integrate dependency injection (DI) into the existing SyncEngine actor without breaking the current architecture. The core challenge: SyncEngine is a Swift actor with two hard-coded dependencies (APIClient class, LocalStore struct), and we need to add protocol abstraction for testability while preserving actor isolation guarantees.

**Key finding:** Protocol-based constructor injection is the cleanest approach for actors in Swift 6+. Actors support initializer injection naturally, and protocols work seamlessly across actor boundaries when marked `Sendable`.

**Migration strategy:** Define protocols first → Conform existing types → Update SyncEngine init → Refactor tests. This order prevents breaking changes and allows incremental rollout.

---

## Current State

### Dependency Flow

```
EventStore (@MainActor, @Observable)
    ↓ creates
SyncEngine (actor)
    ↓ owns (hard-coded)
    ├── APIClient (class) - network requests
    └── LocalStore (struct) - SwiftData operations
```

### Initialization Pattern

**EventStore.swift** (lines 337-344):
```swift
func setModelContext(_ context: ModelContext, syncHistoryStore: SyncHistoryStore? = nil) {
    self.modelContext = context
    self.modelContainer = context.container

    if let apiClient = apiClient {
        self.syncEngine = SyncEngine(
            apiClient: apiClient,              // ← Hard-coded class
            modelContainer: context.container,
            syncHistoryStore: syncHistoryStore
        )
    }
}
```

**SyncEngine.swift** (lines 110-126):
```swift
init(apiClient: APIClient, modelContainer: ModelContainer, syncHistoryStore: SyncHistoryStore? = nil) {
    self.apiClient = apiClient           // ← Concrete APIClient
    self.modelContainer = modelContainer
    self.syncHistoryStore = syncHistoryStore
    // LocalStore created on-demand per operation with fresh ModelContext
}
```

**LocalStore usage** (lines 210-213, 437-438, etc.):
```swift
// Created inline with new ModelContext
let localStore = LocalStore(modelContext: preSyncContext)
let pendingDeletes = try localStore.fetchPendingMutations()
```

### Current Constraints

1. **APIClient is a class** - Single instance shared across app, holds URLSession config
2. **LocalStore is a struct** - Lightweight wrapper, created per-operation with fresh ModelContext
3. **ModelContext threading** - Must create fresh context per actor operation to avoid SwiftData file locking
4. **Actor isolation** - SyncEngine state protected by actor, dependencies must be Sendable
5. **EventStore coupling** - EventStore creates SyncEngine, passes real APIClient, no test seam

---

## Target State

### Dependency Flow with DI

```
EventStore (@MainActor, @Observable)
    ↓ creates with protocols
SyncEngine (actor)
    ↓ owns (protocol-abstracted)
    ├── NetworkClient: NetworkClientProtocol (injected) - network operations
    └── DataStore: DataStoreProtocol (injected) - persistence operations
```

### Protocol-Based Initialization

```swift
actor SyncEngine {
    private let networkClient: NetworkClientProtocol
    private let dataStoreFactory: DataStoreFactory

    init(
        networkClient: NetworkClientProtocol,
        dataStoreFactory: DataStoreFactory,
        modelContainer: ModelContainer,
        syncHistoryStore: SyncHistoryStore? = nil
    ) {
        self.networkClient = networkClient
        self.dataStoreFactory = dataStoreFactory
        // ... rest of init
    }

    // Usage:
    private func flushPendingMutations() async throws {
        let context = ModelContext(modelContainer)
        let dataStore = dataStoreFactory.makeDataStore(context: context)
        let mutations = try dataStore.fetchPendingMutations()
        // ...
    }
}
```

### Testing Seam

```swift
// In tests:
let mockNetwork = MockNetworkClient()
let mockFactory = MockDataStoreFactory()
let syncEngine = SyncEngine(
    networkClient: mockNetwork,
    dataStoreFactory: mockFactory,
    modelContainer: testContainer
)

await syncEngine.performSync()
XCTAssertEqual(mockNetwork.createEventCallCount, 5)
```

---

## Protocol Definitions

### NetworkClientProtocol

**Purpose:** Abstract network operations for SyncEngine (currently performed by APIClient)

**File:** `apps/ios/trendy/Protocols/NetworkClientProtocol.swift` (new)

**Methods Required:**
```swift
protocol NetworkClientProtocol: Sendable {
    // Event CRUD
    func createEventWithIdempotency(_ request: CreateEventRequest, idempotencyKey: String) async throws -> APIEvent
    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> APIEvent
    func deleteEvent(id: String) async throws
    func createEventsBatch(_ events: [CreateEventRequest]) async throws -> BatchCreateEventsResponse
    func getAllEvents(batchSize: Int) async throws -> [APIEvent]

    // EventType CRUD
    func createEventTypeWithIdempotency(_ request: CreateEventTypeRequest, idempotencyKey: String) async throws -> APIEventType
    func updateEventType(id: String, _ request: UpdateEventTypeRequest) async throws -> APIEventType
    func deleteEventType(id: String) async throws
    func getEventTypes() async throws -> [APIEventType]

    // Geofence CRUD
    func createGeofenceWithIdempotency(_ request: CreateGeofenceRequest, idempotencyKey: String) async throws -> APIGeofence
    func updateGeofence(id: String, _ request: UpdateGeofenceRequest) async throws -> APIGeofence
    func deleteGeofence(id: String) async throws
    func getGeofences(activeOnly: Bool) async throws -> [APIGeofence]

    // PropertyDefinition CRUD
    func createPropertyDefinitionWithIdempotency(_ request: CreatePropertyDefinitionRequest, idempotencyKey: String) async throws -> APIPropertyDefinition
    func updatePropertyDefinition(id: String, _ request: UpdatePropertyDefinitionRequest) async throws -> APIPropertyDefinition
    func deletePropertyDefinition(id: String) async throws
    func getPropertyDefinitions(eventTypeId: String) async throws -> [APIPropertyDefinition]

    // Sync operations
    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse
    func getLatestCursor() async throws -> Int64
}
```

**Why these methods:**
- SyncEngine currently calls these on `apiClient` (see lines 258, 441, 570, 953, etc.)
- All async/throws to match actor context
- Marked `Sendable` for actor isolation safety

---

### DataStoreProtocol

**Purpose:** Abstract persistence operations for SyncEngine (currently performed by LocalStore)

**File:** `apps/ios/trendy/Protocols/DataStoreProtocol.swift` (new)

**Methods Required:**
```swift
protocol DataStoreProtocol: Sendable {
    // Upsert operations
    func upsertEvent(id: String, configure: @Sendable (Event) -> Void) throws -> Event
    func upsertEventType(id: String, configure: @Sendable (EventType) -> Void) throws -> EventType
    func upsertGeofence(id: String, configure: @Sendable (Geofence) -> Void) throws -> Geofence
    func upsertPropertyDefinition(id: String, eventTypeId: String, configure: @Sendable (PropertyDefinition) -> Void) throws -> PropertyDefinition

    // Delete operations
    func deleteEvent(id: String) throws
    func deleteEventType(id: String) throws
    func deleteGeofence(id: String) throws
    func deletePropertyDefinition(id: String) throws

    // Lookup operations
    func findEventType(id: String) throws -> EventType?

    // Pending operations
    func fetchPendingMutations() throws -> [PendingMutation]

    // Sync status updates
    func markEventSynced(id: String) throws
    func markEventTypeSynced(id: String) throws
    func markGeofenceSynced(id: String) throws
    func markPropertyDefinitionSynced(id: String) throws

    // Save
    func save() throws
}
```

**Why these methods:**
- All methods currently called on LocalStore instances in SyncEngine
- `@Sendable` closures required for actor isolation
- `Sendable` protocol for safe actor boundary crossing

**CRITICAL:** LocalStore is a struct with a ModelContext. Cannot pass struct across actor boundary directly (ModelContext is not Sendable). Need factory pattern instead of direct protocol conformance.

---

### DataStoreFactory Protocol

**Purpose:** Create DataStore instances with fresh ModelContext per operation (avoids SwiftData file locking)

**File:** `apps/ios/trendy/Protocols/DataStoreFactory.swift` (new)

```swift
protocol DataStoreFactory: Sendable {
    func makeDataStore(context: ModelContext) -> DataStoreProtocol
}
```

**Why factory pattern:**
- SyncEngine creates new `ModelContext(modelContainer)` for each operation (see lines 202, 283, 394, 437, etc.)
- Cannot store ModelContext in actor (not Sendable)
- Factory allows actor to create DataStore on-demand with fresh context
- Mockable for tests

---

## File Organization

### New Protocol Files

Create directory: `apps/ios/trendy/Protocols/`

```
apps/ios/trendy/Protocols/
├── NetworkClientProtocol.swift    # NetworkClient abstraction
├── DataStoreProtocol.swift        # DataStore abstraction
└── DataStoreFactory.swift         # Factory for creating DataStore instances
```

**Why separate directory:**
- Clear separation between protocols and implementations
- Easy to locate abstractions
- Follows Swift package organization patterns
- Makes dependency graph explicit

### Implementation Files (Modified)

```
apps/ios/trendy/Services/
├── APIClient.swift                # Add: extension APIClient: NetworkClientProtocol
└── Sync/
    ├── LocalStore.swift           # Add: extension LocalStore: DataStoreProtocol
    ├── LocalStoreFactory.swift    # NEW: Factory implementation
    └── SyncEngine.swift           # MODIFY: Use protocols in init
```

### Test Files (New)

```
apps/ios/trendyTests/Mocks/
├── MockNetworkClient.swift        # Mock NetworkClientProtocol
├── MockDataStore.swift            # Mock DataStoreProtocol
├── MockDataStoreFactory.swift    # Mock factory
└── SyncEngineTests.swift          # NEW: Unit tests using mocks
```

---

## Migration Path

### Phase 1: Define Protocols (Non-Breaking)

**Goal:** Create protocol definitions without changing existing code

**Files to create:**
1. `Protocols/NetworkClientProtocol.swift`
2. `Protocols/DataStoreProtocol.swift`
3. `Protocols/DataStoreFactory.swift`

**Verification:** Code compiles, no behavior changes

**Estimated effort:** 1-2 hours

**Risks:** None (additive only)

---

### Phase 2: Conform Existing Types (Non-Breaking)

**Goal:** Make APIClient and LocalStore conform to protocols

**Files to modify:**

**2.1: APIClient conformance**
```swift
// apps/ios/trendy/Services/APIClient.swift
// Add at bottom of file:

extension APIClient: NetworkClientProtocol {
    // No implementation needed - all methods already exist
    // Swift will automatically recognize conformance
}
```

**2.2: LocalStore conformance**
```swift
// apps/ios/trendy/Services/Sync/LocalStore.swift
// Add at bottom of file:

extension LocalStore: DataStoreProtocol {
    // No implementation needed - all methods already exist
    // Just need to add @Sendable to configure closures (compiler will warn)
}
```

**2.3: Create LocalStoreFactory**
```swift
// apps/ios/trendy/Services/Sync/LocalStoreFactory.swift
// NEW FILE

struct LocalStoreFactory: DataStoreFactory {
    func makeDataStore(context: ModelContext) -> DataStoreProtocol {
        return LocalStore(modelContext: context)
    }
}
```

**Verification:** Code compiles, tests pass, no behavior changes

**Estimated effort:** 2-3 hours

**Risks:** Low (compiler enforces protocol conformance)

---

### Phase 3: Refactor SyncEngine (Breaking Change)

**Goal:** Update SyncEngine to use protocols instead of concrete types

**Files to modify:**

**3.1: Update SyncEngine properties and init**
```swift
// apps/ios/trendy/Services/Sync/SyncEngine.swift
// Lines 51-54 (OLD):
actor SyncEngine {
    private let apiClient: APIClient
    private let modelContainer: ModelContainer
    private let syncHistoryStore: SyncHistoryStore?

// Lines 51-54 (NEW):
actor SyncEngine {
    private let networkClient: NetworkClientProtocol
    private let dataStoreFactory: DataStoreFactory
    private let modelContainer: ModelContainer
    private let syncHistoryStore: SyncHistoryStore?

// Lines 110-126 (OLD):
init(apiClient: APIClient, modelContainer: ModelContainer, syncHistoryStore: SyncHistoryStore? = nil) {
    self.apiClient = apiClient
    // ...

// Lines 110-126 (NEW):
init(
    networkClient: NetworkClientProtocol,
    dataStoreFactory: DataStoreFactory,
    modelContainer: ModelContainer,
    syncHistoryStore: SyncHistoryStore? = nil
) {
    self.networkClient = networkClient
    self.dataStoreFactory = dataStoreFactory
    // ...
```

**3.2: Update all usage sites in SyncEngine**

Replace `apiClient.` with `networkClient.` (58 occurrences based on file analysis)
Replace `LocalStore(modelContext:)` with `dataStoreFactory.makeDataStore(context:)` (21 occurrences)

**Example changes:**
```swift
// Line 258 (OLD):
let latestCursor = try await apiClient.getLatestCursor()

// Line 258 (NEW):
let latestCursor = try await networkClient.getLatestCursor()

// Line 210 (OLD):
let localStore = LocalStore(modelContext: preSyncContext)

// Line 210 (NEW):
let localStore = dataStoreFactory.makeDataStore(context: preSyncContext)
```

**Verification:** Compiler errors in EventStore (expected - next step fixes)

**Estimated effort:** 3-4 hours

**Risks:** Medium (many call sites, but compiler catches all issues)

---

### Phase 4: Update EventStore Initialization (Breaking Change)

**Goal:** Update EventStore to inject protocols into SyncEngine

**Files to modify:**

**4.1: Create factory in EventStore**
```swift
// apps/ios/trendy/ViewModels/EventStore.swift
// Lines 337-344 (NEW):
func setModelContext(_ context: ModelContext, syncHistoryStore: SyncHistoryStore? = nil) {
    self.modelContext = context
    self.modelContainer = context.container
    self.syncHistoryStore = syncHistoryStore

    if let apiClient = apiClient {
        let factory = LocalStoreFactory()
        self.syncEngine = SyncEngine(
            networkClient: apiClient,              // ← Conforms to protocol
            dataStoreFactory: factory,
            modelContainer: context.container,
            syncHistoryStore: syncHistoryStore
        )
    }
}
```

**Verification:** App compiles, runs, all existing tests pass

**Estimated effort:** 1 hour

**Risks:** Low (minimal change, type system enforces correctness)

---

### Phase 5: Add Tests (Non-Breaking)

**Goal:** Create unit tests for SyncEngine using mocks

**Files to create:**

**5.1: Mock implementations** (see Test Architecture section below)

**5.2: SyncEngine unit tests**
```swift
// apps/ios/trendyTests/SyncEngineTests.swift
@testable import trendy
import XCTest

final class SyncEngineTests: XCTestCase {
    func testPerformSync_pushesLocalMutations() async throws {
        // Given
        let mockNetwork = MockNetworkClient()
        let mockFactory = MockDataStoreFactory()
        let testContainer = makeTestContainer()

        let syncEngine = SyncEngine(
            networkClient: mockNetwork,
            dataStoreFactory: mockFactory,
            modelContainer: testContainer
        )

        // When
        await syncEngine.performSync()

        // Then
        XCTAssertTrue(mockNetwork.createEventCalled)
        XCTAssertEqual(mockFactory.makeDataStoreCallCount, 2)
    }
}
```

**Verification:** Tests run, pass, achieve >80% coverage of SyncEngine

**Estimated effort:** 8-12 hours (comprehensive test suite)

**Risks:** Low (tests validate refactor correctness)

---

## Test Architecture

### Mock NetworkClient

**File:** `apps/ios/trendyTests/Mocks/MockNetworkClient.swift`

**Pattern:** Spy pattern - record calls, return configurable responses

```swift
final class MockNetworkClient: NetworkClientProtocol, @unchecked Sendable {
    // Call tracking
    var createEventCallCount = 0
    var createEventRequests: [CreateEventRequest] = []
    var createEventBatchCallCount = 0
    var getChangesCallCount = 0
    var getChangesSinceCursors: [Int64] = []

    // Response configuration
    var createEventResponse: APIEvent?
    var createEventError: Error?
    var createEventBatchResponse: BatchCreateEventsResponse?
    var getChangesResponse: ChangeFeedResponse?

    // Implementations
    func createEventWithIdempotency(_ request: CreateEventRequest, idempotencyKey: String) async throws -> APIEvent {
        createEventCallCount += 1
        createEventRequests.append(request)
        if let error = createEventError { throw error }
        return createEventResponse ?? defaultAPIEvent()
    }

    func createEventsBatch(_ events: [CreateEventRequest]) async throws -> BatchCreateEventsResponse {
        createEventBatchCallCount += 1
        if let response = createEventBatchResponse { return response }
        return BatchCreateEventsResponse(total: events.count, success: events.count, failed: 0, created: [], errors: nil)
    }

    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse {
        getChangesCallCount += 1
        getChangesSinceCursors.append(cursor)
        return getChangesResponse ?? ChangeFeedResponse(changes: [], nextCursor: cursor, hasMore: false)
    }

    // ... implement all NetworkClientProtocol methods

    // Reset for each test
    func reset() {
        createEventCallCount = 0
        createEventRequests = []
        // ... reset all state
    }

    private func defaultAPIEvent() -> APIEvent {
        APIEvent(
            id: UUID().uuidString,
            eventTypeId: UUID().uuidString,
            timestamp: Date(),
            notes: nil,
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",
            externalId: nil,
            originalTitle: nil,
            geofenceId: nil,
            locationLatitude: nil,
            locationLongitude: nil,
            locationName: nil,
            healthKitSampleId: nil,
            healthKitCategory: nil,
            properties: nil
        )
    }
}
```

**Why spy pattern:**
- Track method calls and arguments (essential for actor testing where state is hidden)
- Configure responses for different scenarios (success, error, rate limit)
- Reset state between tests (avoid test pollution)

**Why `@unchecked Sendable`:**
- Mock contains mutable state (call counts, recorded arguments)
- Only used in single-threaded test context (XCTest runs tests serially by default)
- Cleaner than wrapping everything in `@MainActor`

---

### Mock DataStoreFactory

**File:** `apps/ios/trendyTests/Mocks/MockDataStoreFactory.swift`

**Pattern:** Returns same mock instance for all calls (spy pattern)

```swift
final class MockDataStoreFactory: DataStoreFactory, @unchecked Sendable {
    let mockStore = MockDataStore()
    var makeDataStoreCallCount = 0

    func makeDataStore(context: ModelContext) -> DataStoreProtocol {
        makeDataStoreCallCount += 1
        return mockStore
    }

    func reset() {
        makeDataStoreCallCount = 0
        mockStore.reset()
    }
}
```

**Why return same instance:**
- Track state changes across multiple factory calls
- Easier to verify behavior (single source of truth)
- Matches test pattern: "Given store has X, when sync runs, then store has Y"

---

## Architecture Patterns

### Pattern 1: Actor + Protocol Injection

**What:** Actors accept protocols in initializer, store as properties

**When:** Actor needs testable dependencies with async operations

**Why works:**
- Protocols marked `Sendable` can cross actor boundaries
- Initializer injection ensures immutability (actor properties are private let)
- Type system enforces all dependencies provided at creation

**Tradeoffs:**
- ✅ Type-safe, compiler-enforced
- ✅ Immutable dependencies (cannot swap at runtime)
- ❌ Requires protocol for every dependency
- ❌ More files to maintain

**Source:** [Actor-Based Dependency Container in Swift](https://medium.com/@dmitryshlepkin/actor-based-dependency-container-in-swift-e677c105e57b)

---

### Pattern 2: Factory for Non-Sendable Types

**What:** Create per-operation instances of non-Sendable types via factory

**When:** Dependency (like ModelContext) cannot be stored in actor but needed per-operation

**Why works:**
- Factory is Sendable (no mutable state)
- Actor creates dependency on-demand with fresh context
- Each operation gets isolated instance (avoids shared mutable state)

**Tradeoffs:**
- ✅ Handles non-Sendable dependencies
- ✅ Prevents shared mutable state bugs
- ✅ Testable (mock factory returns mock store)
- ❌ Slightly more complex than direct injection
- ❌ One extra protocol layer

**Source:** [Managing Dependencies in the Age of SwiftUI](https://lucasvandongen.dev/dependency_injection_swift_swiftui.php)

---

### Pattern 3: @unchecked Sendable for Test Mocks

**What:** Mark mocks as `@unchecked Sendable` to bypass compiler checks

**When:** Mock contains mutable state (call counts, recorded values) but only used in single-threaded tests

**Why works:**
- Tests run serially in XCTest (no concurrent access to mock state)
- Mock state only accessed from test thread (controlled environment)
- Avoids complexity of wrapping everything in locks/actors

**Tradeoffs:**
- ✅ Simpler mock code
- ✅ Clearer test assertions (direct state access)
- ❌ Bypasses compiler safety (use carefully)
- ❌ Breaks if mock used in real concurrent context

**Source:** [Swift Actor in Unit Tests](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631)

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Service Locator in Actor

**What goes wrong:** Global singleton registry accessed from actor

**Why bad:**
- Defeats actor isolation (shared mutable state accessed from actor)
- Harder to test (global state persists between tests)
- Runtime errors instead of compile-time safety

**Instead:**
- Use constructor injection with protocols
- Pass dependencies explicitly at initialization

**Source:** [Dependency Injection Strategies in Swift](https://quickbirdstudios.com/blog/swift-dependency-injection-service-locators/)

---

### Anti-Pattern 2: Property Injection for Actor Dependencies

**What goes wrong:** Actor exposes `var` properties for dependency injection

**Why bad:**
- Dependencies can change mid-operation (race condition)
- Nil checks required everywhere (boilerplate)
- Cannot guarantee dependency availability

**Instead:**
- Use initializer injection with non-optional properties
- Enforce dependency availability at compile time

**Source:** [Dependency Injection in Swift (2025)](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c)

---

### Anti-Pattern 3: Passing Non-Sendable Types to Actor

**What goes wrong:** Pass ModelContext directly to actor

**Why bad:**
- Compiler error (ModelContext is not Sendable)
- If forced with `@unchecked Sendable`, causes data races

**Instead:**
- Use factory pattern to create non-Sendable types per-operation
- Store Sendable container, create context on-demand

**Source:** Swift Concurrency documentation (Apple)

---

## Build Order

### Step 1: Define Protocols (Day 1, Morning)

**Dependencies:** None

**Files:**
1. `Protocols/NetworkClientProtocol.swift`
2. `Protocols/DataStoreProtocol.swift`
3. `Protocols/DataStoreFactory.swift`

**Validation:** `swift build` succeeds

---

### Step 2: Conform Existing Types (Day 1, Afternoon)

**Dependencies:** Step 1 complete

**Files:**
1. `Services/APIClient.swift` - add conformance
2. `Services/Sync/LocalStore.swift` - add conformance
3. `Services/Sync/LocalStoreFactory.swift` - NEW

**Validation:** `swift build` succeeds, `swift test` passes

---

### Step 3: Refactor SyncEngine (Day 2, Morning)

**Dependencies:** Step 2 complete

**Files:**
1. `Services/Sync/SyncEngine.swift` - update init, replace usages

**Validation:** Compiler errors in EventStore (expected, fixed in Step 4)

---

### Step 4: Update EventStore (Day 2, Afternoon)

**Dependencies:** Step 3 complete

**Files:**
1. `ViewModels/EventStore.swift` - update `setModelContext`

**Validation:** `swift build` succeeds, app runs, manual smoke test

---

### Step 5: Add Tests (Day 3-4)

**Dependencies:** Step 4 complete (app working)

**Files:**
1. `trendyTests/Mocks/MockNetworkClient.swift`
2. `trendyTests/Mocks/MockDataStore.swift`
3. `trendyTests/Mocks/MockDataStoreFactory.swift`
4. `trendyTests/SyncEngineTests.swift`

**Validation:** `swift test` passes, >80% coverage of SyncEngine

---

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| Protocol design | HIGH | Based on Swift official patterns, widely used in production |
| Actor compatibility | HIGH | Protocols marked Sendable work with actors (verified in docs) |
| Migration path | HIGH | Incremental, compiler-enforced, low risk |
| Test architecture | MEDIUM | @unchecked Sendable pattern well-documented but requires care |
| Build order | HIGH | Dependencies explicit, can validate each step |

**Overall confidence: HIGH** - Architecture is sound, migration is incremental, risks are mitigated.

---

## Sources

### Swift Actor + DI Patterns
- [Actor-Based Dependency Container in Swift](https://medium.com/@dmitryshlepkin/actor-based-dependency-container-in-swift-e677c105e57b) - Modern actor DI patterns
- [Dependency Injection in Swift with Protocols](https://swiftwithmajid.com/2019/03/06/dependency-injection-in-swift-with-protocols/) - Protocol-based DI fundamentals
- [Different flavors of dependency injection in Swift](https://www.swiftbysundell.com/articles/different-flavors-of-dependency-injection-in-swift/) - Constructor vs property vs parameter injection

### Testing Actors with Mocks
- [Swift Actor in Unit Tests](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631) - @unchecked Sendable pattern for mocks
- [Advanced Unit Testing in Swift: Protocols, Dependency Injection, and HealthKit](https://medium.com/@azharanwar/advanced-unit-testing-in-swift-protocols-dependency-injection-and-healthkit-4795ef4f33ec) - Mock architecture patterns
- [Writing unit tests with mocked dependencies in Swift](https://dev.to/davidvanerkelens/writing-unit-tests-with-mocked-dependencies-in-swift-2doh) - Mock implementation strategies

### Best Practices (2025-2026)
- [Dependency Injection in Swift (2025): Clean Architecture, Better Testing](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c) - Modern DI patterns with latest Swift features
- [Managing Dependencies in the Age of SwiftUI](https://lucasvandongen.dev/dependency_injection_swift_swiftui.php) - SwiftUI + actor DI integration
- [Dependency Injection Strategies in Swift](https://quickbirdstudios.com/blog/swift-dependency-injection-service-locators/) - Anti-patterns to avoid
