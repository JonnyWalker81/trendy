# Phase 13: Protocol Definitions - Research

**Researched:** 2026-01-21
**Domain:** Swift Protocol-Oriented Design for Actor-Based Dependency Injection
**Confidence:** HIGH

## Summary

This phase defines abstraction contracts (protocols) for SyncEngine's dependencies to enable unit testing without real network or database access. The key challenge is that SyncEngine is a Swift actor, and its dependencies include ModelContext which is non-Sendable.

The standard approach for actor-compatible protocols in Swift 6 is:
1. Mark protocols as `Sendable` for safe actor boundary crossing
2. Define all methods as `async` to handle actor isolation
3. Use the factory pattern for non-Sendable types like ModelContext
4. Leverage Swift Testing framework (already in use) with mock implementations

**Primary recommendation:** Define three protocols (NetworkClientProtocol, DataStoreProtocol, DataStoreFactory) with Sendable conformance and async methods. Use closure-based factory pattern to defer ModelContext creation to the actor's isolation context.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | Built-in (Xcode 16+) | Unit testing | Already used in codebase, modern macro-based syntax |
| Swift Concurrency | Built-in | Actor isolation | Native language feature for thread safety |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftData | iOS 17+ | Persistence | Already used; ModelContext is non-Sendable |
| Foundation | Built-in | Network types (URLSession) | HTTP communication abstraction |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual mocks | Cuckoo/SwiftyMocky | Third-party dependency; less control; complexity with actors |
| Protocol extraction | Dependency injection container | Over-engineering for this scope; adds framework dependency |
| Factory pattern | @ModelActor macro | Macro handles boilerplate but less flexible for testing |

**No new dependencies required.** All tooling is already in the codebase.

## Architecture Patterns

### Recommended Project Structure
```
apps/ios/trendy/
├── Protocols/                   # NEW: Protocol definitions
│   ├── NetworkClientProtocol.swift
│   ├── DataStoreProtocol.swift
│   └── DataStoreFactory.swift
├── Services/
│   ├── APIClient.swift          # Conforms to NetworkClientProtocol
│   └── Sync/
│       ├── SyncEngine.swift     # Uses protocols via DI
│       └── LocalStore.swift     # Conforms to DataStoreProtocol
└── Tests/
    └── trendyTests/
        └── Mocks/               # NEW: Mock implementations
            ├── MockNetworkClient.swift
            └── MockDataStore.swift
```

### Pattern 1: Sendable Protocol for Actor Dependencies

**What:** Mark protocols as `Sendable` to allow safe passage across actor boundaries.

**When to use:** Any protocol that an actor will hold as a dependency.

**Example:**
```swift
// Source: Swift Evolution SE-0302, Apple Concurrency docs
protocol NetworkClientProtocol: Sendable {
    // All methods must be async for actor isolation
    func getEventTypes() async throws -> [APIEventType]
    func getEvents(limit: Int, offset: Int) async throws -> [APIEvent]
    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent
    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> APIEvent
    func deleteEvent(id: String) async throws
    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse
    func getLatestCursor() async throws -> Int64
    // ... other methods SyncEngine calls on APIClient
}

// Conformance (APIClient is a class, so needs final)
extension APIClient: NetworkClientProtocol {
    // Methods already async, conformance is automatic
}
```

### Pattern 2: Factory Pattern for Non-Sendable ModelContext

**What:** Use a factory protocol that creates ModelContext within the actor's isolation context, avoiding the need to pass non-Sendable ModelContext across boundaries.

**When to use:** When dependency needs ModelContext but must be injected into an actor.

**Example:**
```swift
// Source: BrightDigit ModelActor tutorial, Apple SwiftData concurrency docs
protocol DataStoreFactory: Sendable {
    /// Creates a DataStore bound to a new ModelContext.
    /// Called within actor's isolation context to avoid crossing boundaries.
    func makeDataStore() -> any DataStoreProtocol
}

// Production implementation
final class DefaultDataStoreFactory: DataStoreFactory {
    private let modelContainer: ModelContainer  // ModelContainer IS Sendable

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func makeDataStore() -> any DataStoreProtocol {
        let context = ModelContext(modelContainer)
        return LocalStore(modelContext: context)
    }
}
```

### Pattern 3: DataStoreProtocol Wrapping LocalStore

**What:** Abstract LocalStore operations behind a protocol for testability.

**When to use:** When SyncEngine needs to perform persistence operations.

**Example:**
```swift
// Source: Project-specific based on LocalStore.swift analysis
protocol DataStoreProtocol {
    // Note: NOT Sendable - created within actor context via factory

    // Upsert operations
    @discardableResult
    func upsertEvent(id: String, configure: (Event) -> Void) throws -> Event
    @discardableResult
    func upsertEventType(id: String, configure: (EventType) -> Void) throws -> EventType
    @discardableResult
    func upsertGeofence(id: String, configure: (Geofence) -> Void) throws -> Geofence
    @discardableResult
    func upsertPropertyDefinition(id: String, eventTypeId: String, configure: (PropertyDefinition) -> Void) throws -> PropertyDefinition

    // Delete operations
    func deleteEvent(id: String) throws
    func deleteEventType(id: String) throws
    func deleteGeofence(id: String) throws
    func deletePropertyDefinition(id: String) throws

    // Lookup operations
    func findEvent(id: String) throws -> Event?
    func findEventType(id: String) throws -> EventType?
    func findGeofence(id: String) throws -> Geofence?
    func findPropertyDefinition(id: String) throws -> PropertyDefinition?

    // Pending operations
    func fetchPendingMutations() throws -> [PendingMutation]

    // Sync status
    func markEventSynced(id: String) throws
    func markEventTypeSynced(id: String) throws
    func markGeofenceSynced(id: String) throws
    func markPropertyDefinitionSynced(id: String) throws

    // Persistence
    func save() throws
}
```

### Anti-Patterns to Avoid

- **@unchecked Sendable on ModelContext:** Suppresses warnings but creates data races. ModelContext is not thread-safe.
- **Passing ModelContext to actor init:** Crosses isolation boundary. Use factory pattern instead.
- **Non-async protocol methods for actor dependencies:** Swift 6 strict concurrency will flag this. All methods must be async.
- **Returning SwiftData models from actors:** Models are not Sendable. Return PersistentIdentifier or value-type DTOs instead.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mock generation | Custom mock framework | Manual protocol mocks | Actor mock frameworks immature; manual mocks are clearer |
| Sendable conformance | @unchecked Sendable hacks | Proper protocol design with async | Runtime crashes vs compile-time safety |
| ModelContext threading | Custom locking/queues | Factory pattern + actor isolation | SwiftData requires specific threading model |
| Test data persistence | In-memory SQLite | Ephemeral ModelContainer | SwiftData provides isStoredInMemoryOnly configuration |

**Key insight:** The Swift compiler's strict concurrency checking is the best tool for catching threading issues. Don't work around it with @unchecked Sendable - fix the design.

## Common Pitfalls

### Pitfall 1: ModelContext Crossing Actor Boundaries
**What goes wrong:** Passing ModelContext from main thread into actor init causes runtime crash or data corruption.
**Why it happens:** ModelContext is not Sendable and must be used on the thread/actor where created.
**How to avoid:** Use factory pattern - pass ModelContainer (Sendable) and create ModelContext inside actor.
**Warning signs:** "Non-sendable type 'ModelContext'" compiler warnings.

### Pitfall 2: Forgetting async on Protocol Methods
**What goes wrong:** Protocol with sync methods can't be properly used across actor isolation boundaries.
**Why it happens:** Actor-isolated methods are implicitly async from outside the actor.
**How to avoid:** Make all protocol methods async from the start.
**Warning signs:** "Actor-isolated instance method cannot satisfy nonisolated protocol requirement" error.

### Pitfall 3: Mock State Not Thread-Safe
**What goes wrong:** Mock implementations have shared mutable state causing race conditions in tests.
**Why it happens:** Mocks created as classes without proper synchronization.
**How to avoid:** Make mocks actors OR use actor for the data storage.
**Warning signs:** Flaky tests, "access race" errors with TSAN enabled.

### Pitfall 4: Returning Model Objects from Protocol Methods
**What goes wrong:** Protocol method signatures return Event/EventType directly, which are @Model classes (not Sendable).
**Why it happens:** Following existing LocalStore API signatures directly.
**How to avoid:** DataStoreProtocol methods can return models because DataStore is used WITHIN actor context (not crossing boundaries). NetworkClientProtocol returns Codable DTOs (already Sendable).
**Warning signs:** This is actually NOT a pitfall for DataStoreProtocol since it's created inside the actor.

## Code Examples

Verified patterns for protocol definitions:

### NetworkClientProtocol Definition
```swift
// File: Protocols/NetworkClientProtocol.swift
import Foundation

/// Protocol for network operations required by SyncEngine.
/// Conforms to Sendable for safe use across actor boundaries.
/// All methods are async as required for actor isolation.
protocol NetworkClientProtocol: Sendable {
    // Event Type operations
    func getEventTypes() async throws -> [APIEventType]
    func createEventType(_ request: CreateEventTypeRequest) async throws -> APIEventType
    func createEventTypeWithIdempotency(_ request: CreateEventTypeRequest, idempotencyKey: String) async throws -> APIEventType
    func updateEventType(id: String, _ request: UpdateEventTypeRequest) async throws -> APIEventType
    func deleteEventType(id: String) async throws

    // Event operations
    func getEvents(limit: Int, offset: Int) async throws -> [APIEvent]
    func getAllEvents(batchSize: Int) async throws -> [APIEvent]
    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent
    func createEventWithIdempotency(_ request: CreateEventRequest, idempotencyKey: String) async throws -> APIEvent
    func createEventsBatch(_ events: [CreateEventRequest]) async throws -> BatchCreateEventsResponse
    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> APIEvent
    func deleteEvent(id: String) async throws

    // Geofence operations
    func getGeofences(activeOnly: Bool) async throws -> [APIGeofence]
    func createGeofence(_ request: CreateGeofenceRequest) async throws -> APIGeofence
    func createGeofenceWithIdempotency(_ request: CreateGeofenceRequest, idempotencyKey: String) async throws -> APIGeofence
    func updateGeofence(id: String, _ request: UpdateGeofenceRequest) async throws -> APIGeofence
    func deleteGeofence(id: String) async throws

    // Property definition operations
    func getPropertyDefinitions(eventTypeId: String) async throws -> [APIPropertyDefinition]
    func createPropertyDefinition(eventTypeId: String, _ request: CreatePropertyDefinitionRequest) async throws -> APIPropertyDefinition
    func createPropertyDefinitionWithIdempotency(_ request: CreatePropertyDefinitionRequest, idempotencyKey: String) async throws -> APIPropertyDefinition
    func updatePropertyDefinition(id: String, _ request: UpdatePropertyDefinitionRequest) async throws -> APIPropertyDefinition
    func deletePropertyDefinition(id: String) async throws

    // Change feed operations
    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse
    func getLatestCursor() async throws -> Int64
}
```

### DataStoreFactory Protocol
```swift
// File: Protocols/DataStoreFactory.swift
import Foundation
import SwiftData

/// Factory protocol for creating DataStore instances within actor context.
/// Sendable because it's passed into the actor, but DataStoreProtocol itself
/// does not need to be Sendable since it's created and used within the actor.
protocol DataStoreFactory: Sendable {
    /// Creates a new DataStore with a fresh ModelContext.
    /// Called within actor isolation context.
    func makeDataStore() -> any DataStoreProtocol
}

/// Production implementation using ModelContainer
final class DefaultDataStoreFactory: DataStoreFactory {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func makeDataStore() -> any DataStoreProtocol {
        let context = ModelContext(modelContainer)
        return LocalStore(modelContext: context)
    }
}
```

### Mock Implementation Pattern
```swift
// File: trendyTests/Mocks/MockNetworkClient.swift
import Foundation
@testable import trendy

/// Mock network client for testing SyncEngine in isolation.
/// Uses actor for thread-safe state management.
actor MockNetworkClient: NetworkClientProtocol {
    // Track calls for verification
    var getEventTypesCalled = false
    var createEventCalls: [CreateEventRequest] = []
    var deleteEventCalls: [String] = []

    // Stubbed responses
    var stubbedEventTypes: [APIEventType] = []
    var stubbedEvents: [APIEvent] = []
    var stubbedChanges: ChangeFeedResponse = ChangeFeedResponse(changes: [], nextCursor: 0, hasMore: false)
    var stubbedLatestCursor: Int64 = 0

    // Error injection
    var errorToThrow: Error?

    // MARK: - NetworkClientProtocol

    func getEventTypes() async throws -> [APIEventType] {
        getEventTypesCalled = true
        if let error = errorToThrow { throw error }
        return stubbedEventTypes
    }

    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent {
        createEventCalls.append(request)
        if let error = errorToThrow { throw error }
        // Return stubbed or synthesized response
        return APIEvent(
            id: request.id,
            userId: "test-user",
            eventTypeId: request.eventTypeId,
            timestamp: request.timestamp,
            // ... other fields
        )
    }

    // ... implement other methods similarly
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Protocol-witness tables | Existential any types | Swift 5.6 | More explicit about dynamic dispatch |
| @escaping closures for async | async/await | Swift 5.5 | Cleaner actor integration |
| DispatchQueue for thread safety | Actors | Swift 5.5 | Compiler-enforced isolation |
| @unchecked Sendable hacks | Proper protocol design | Swift 6 strict mode | Compile-time safety vs runtime crashes |
| @ModelActor macro | Factory + protocol | 2024 | More flexible for testing |

**Deprecated/outdated:**
- Dispatch-based synchronization for SwiftData: Use actors instead
- OperationQueue for background work: Use structured concurrency (TaskGroup)
- Singleton pattern for shared state: Inject dependencies instead

## Open Questions

1. **Should MockNetworkClient be an actor or class?**
   - What we know: Making it an actor ensures thread safety for call tracking
   - What's unclear: Whether tests need to check state synchronously
   - Recommendation: Use actor - async access is fine for test assertions

2. **How to handle APIClient's URLSession dependency?**
   - What we know: APIClient initializes its own URLSession
   - What's unclear: Whether URLSession should also be injected
   - Recommendation: Start with NetworkClientProtocol abstraction; URLSession injection can be added later if needed for more granular testing

## Sources

### Primary (HIGH confidence)
- Apple Swift Concurrency documentation - Sendable protocol, actor isolation
- Apple SwiftData documentation - ModelContext threading requirements
- Swift Evolution SE-0302 - Sendable and @Sendable closures
- Existing codebase: `apps/ios/trendy/Services/Sync/SyncEngine.swift` - actual usage patterns
- Existing codebase: `apps/ios/trendy/Services/Sync/LocalStore.swift` - method signatures to abstract
- Existing codebase: `apps/ios/trendy/Services/APIClient.swift` - network methods to abstract

### Secondary (MEDIUM confidence)
- [BrightDigit ModelActor Tutorial](https://brightdigit.com/tutorials/swiftdata-modelactor/) - Factory pattern for SwiftData
- [SwiftLee Sendable Protocol Guide](https://www.avanderlee.com/swift/sendable-protocol-closures/) - Sendable conformance patterns
- [Swift with Majid DI with Protocols](https://swiftwithmajid.com/2019/03/06/dependency-injection-in-swift-with-protocols/) - Protocol-based DI
- [Thumbtack Engineering Actor Testing](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631) - Mock actor patterns

### Tertiary (LOW confidence)
- WebSearch results for "Swift actor protocol dependency injection" - community patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using existing Swift/SwiftData tooling
- Architecture: HIGH - Patterns verified against Apple documentation
- Pitfalls: HIGH - Based on actual compiler errors and SwiftData threading model

**Research date:** 2026-01-21
**Valid until:** 60 days (stable Swift 6 patterns)
