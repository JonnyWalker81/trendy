//
//  DeduplicationTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine deduplication mechanisms.
//  Tests queue-level prevention and API-level idempotency keys.
//
//  Requirements tested:
//  - DUP-01: Test same event not created twice with same idempotency key
//  - DUP-02: Test retry after network error reuses same idempotency key
//  - DUP-03: Test different mutations use different idempotency keys
//  - DUP-04: Test server 409 Conflict response handled correctly
//  - DUP-05: Test mutation queue prevents duplicate pending entries
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Helpers

/// Helper to create fresh test dependencies for each test, with optional initial cursor
private func makeTestDependencies(initialCursor: Int64 = 0) -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    cleanupSyncEngineUserDefaults()
    // Set cursor BEFORE creating SyncEngine, because SyncEngine reads cursor in init()
    if initialCursor != 0 {
        UserDefaults.standard.set(Int(initialCursor), forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
    }
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}

/// Helper to configure mock for flush operations (skip bootstrap, pass health check)
/// NOTE: Cursor must be set via makeTestDependencies(initialCursor:) since SyncEngine reads it at init time.
private func configureForFlush(mockNetwork: MockNetworkClient, mockStore: MockDataStore) {
    // Health check passes (required before any sync operations)
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Configure empty change feed to skip pullChanges processing
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}

/// Helper to seed a CREATE pending mutation for an event
private func seedCreateMutation(mockStore: MockDataStore, eventId: String, eventTypeId: String = "type-1") -> PendingMutation {
    let request = APIModelFixture.makeCreateEventRequest(id: eventId, eventTypeId: eventTypeId)
    let payload = try! JSONEncoder().encode(request)
    return mockStore.seedPendingMutation(entityType: .event, entityId: eventId, operation: .create, payload: payload)
}

/// Helper to seed a CREATE pending mutation for an event type (uses individual idempotency path)
private func seedEventTypeCreateMutation(mockStore: MockDataStore, eventTypeId: String) -> PendingMutation {
    let request = APIModelFixture.makeCreateEventTypeRequest(id: eventTypeId)
    let payload = try! JSONEncoder().encode(request)
    return mockStore.seedPendingMutation(entityType: .eventType, entityId: eventTypeId, operation: .create, payload: payload)
}

/// Helper to seed an EventType entity in MockDataStore for deletion tests
private func seedEventTypeEntity(mockStore: MockDataStore, id: String) {
    _ = mockStore.seedEventType { type in
        type.id = id
        type.name = "Test Type"
    }
}

/// Helper to seed an Event in MockDataStore for deletion tests
private func seedEvent(mockStore: MockDataStore, id: String, eventTypeId: String = "type-1") {
    // Seed an event type first
    _ = mockStore.seedEventType { type in
        type.id = eventTypeId
        type.name = "Test Type"
    }
    // Then seed the event
    if let eventType = mockStore.storedEventTypes[eventTypeId] {
        _ = mockStore.seedEvent(eventType: eventType) { event in
            event.id = id
        }
    }
}

// MARK: - Queue Level Deduplication

@Suite("Queue Level Deduplication")
struct QueueDeduplicationTests {

    @Test("Mutation queue prevents duplicate pending entries (DUP-05)")
    func queuePreventsDuplicateEntries() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Queue first mutation
        let request = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
        let payload = try JSONEncoder().encode(request)

        try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-1", payload: payload)

        // Attempt to queue duplicate (same entityId + entityType + operation)
        try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-1", payload: payload)

        // Verify only one pending mutation exists
        let pending = try mockStore.fetchPendingMutations()
        #expect(pending.count == 1, "Duplicate mutation should be skipped - got \(pending.count)")
    }

    @Test("Queue allows different operations for same entity")
    func queueAllowsDifferentOperationsForSameEntity() async throws {
        let (_, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Queue CREATE
        let createRequest = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
        let createPayload = try JSONEncoder().encode(createRequest)
        try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-1", payload: createPayload)

        // Queue DELETE for same entity (different operation)
        try await engine.queueMutation(entityType: .event, operation: .delete, entityId: "evt-1", payload: Data())

        // Both should be queued
        let pending = try mockStore.fetchPendingMutations()
        #expect(pending.count == 2, "Different operations should both be queued")
    }

    @Test("Queue allows same operation for different entities")
    func queueAllowsSameOperationForDifferentEntities() async throws {
        let (_, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Queue CREATE for evt-1
        let request1 = APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1")
        let payload1 = try JSONEncoder().encode(request1)
        try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-1", payload: payload1)

        // Queue CREATE for evt-2
        let request2 = APIModelFixture.makeCreateEventRequest(id: "evt-2", eventTypeId: "type-1")
        let payload2 = try JSONEncoder().encode(request2)
        try await engine.queueMutation(entityType: .event, operation: .create, entityId: "evt-2", payload: payload2)

        // Both should be queued
        let pending = try mockStore.fetchPendingMutations()
        #expect(pending.count == 2, "Different entities should both be queued")
    }
}

// MARK: - Idempotency Key Uniqueness

@Suite("Idempotency Key Uniqueness")
struct IdempotencyKeyUniquenessTests {

    @Test("Different mutations have different idempotency keys (DUP-03)")
    func differentMutationsHaveDifferentKeys() async throws {
        let (_, mockStore, _, _) = makeTestDependencies(initialCursor: 1000)

        // Seed two different mutations
        let mutation1 = seedCreateMutation(mockStore: mockStore, eventId: "evt-1")
        let mutation2 = seedCreateMutation(mockStore: mockStore, eventId: "evt-2")

        // Verify keys are unique
        #expect(mutation1.clientRequestId != mutation2.clientRequestId,
                "Each mutation must have unique idempotency key")
    }

    @Test("Idempotency key is UUID format")
    func idempotencyKeyIsUUIDFormat() async throws {
        let (_, mockStore, _, _) = makeTestDependencies(initialCursor: 1000)

        let mutation = seedCreateMutation(mockStore: mockStore, eventId: "evt-1")

        // Verify key is valid UUID
        let uuid = UUID(uuidString: mutation.clientRequestId)
        #expect(uuid != nil, "clientRequestId should be valid UUID - got: \(mutation.clientRequestId)")
    }

    @Test("Same entity not created twice with same idempotency key (DUP-01)")
    func sameEventNotCreatedTwiceWithSameKey() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for successful sync
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Configure success response for eventType idempotency path
        mockNetwork.createEventTypeWithIdempotencyResponses = [
            .success(APIModelFixture.makeAPIEventType(id: "type-new"))
        ]

        // Seed eventType CREATE mutation (goes through individual idempotency path)
        let mutation = seedEventTypeCreateMutation(mockStore: mockStore, eventTypeId: "type-new")
        let originalKey = mutation.clientRequestId

        await engine.performSync()

        // Verify idempotency key was used correctly
        #expect(mockNetwork.createEventTypeWithIdempotencyCalls.count == 1,
                "Should have exactly one API call")
        #expect(mockNetwork.createEventTypeWithIdempotencyCalls.first?.idempotencyKey == originalKey,
                "API call should use mutation's clientRequestId as idempotency key")
    }
}

// MARK: - Retry Behavior

@Suite("Retry Behavior")
struct RetryBehaviorTests {

    @Test("Retry after network error reuses same idempotency key (DUP-02)")
    func retryReusesSameIdempotencyKey() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for flush with extra health check responses for retry
        mockNetwork.getEventTypesResponses = [
            .success([APIModelFixture.makeAPIEventType()]),
            .success([APIModelFixture.makeAPIEventType()])
        ]
        UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Configure: first call fails with network error, second succeeds
        mockNetwork.createEventTypeWithIdempotencyResponses = [
            .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil))),
            .success(APIModelFixture.makeAPIEventType(id: "type-new"))
        ]

        // Seed eventType CREATE mutation and capture its idempotency key
        let mutation = seedEventTypeCreateMutation(mockStore: mockStore, eventTypeId: "type-new")
        let originalKey = mutation.clientRequestId

        // First sync - will fail
        await engine.performSync()

        // Second sync - should succeed with same key
        await engine.performSync()

        // Verify both calls used the same idempotency key
        let calls = mockNetwork.createEventTypeWithIdempotencyCalls
        #expect(calls.count == 2, "Should have two API calls (initial + retry) - got \(calls.count)")

        if calls.count >= 2 {
            #expect(calls[0].idempotencyKey == originalKey, "First call should use original key")
            #expect(calls[1].idempotencyKey == originalKey, "Retry should reuse same key")
            #expect(calls[0].idempotencyKey == calls[1].idempotencyKey, "Both calls must use identical key")
        }
    }
}

// MARK: - 409 Conflict Handling

@Suite("409 Conflict Handling")
struct ConflictHandlingTests {

    @Test("Server 409 Conflict response deletes local duplicate (DUP-04)")
    func conflict409DeletesLocalDuplicate() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Configure 409 Conflict response for eventType idempotency path
        mockNetwork.createEventTypeWithIdempotencyResponses = [
            .failure(APIError.serverError("Duplicate key violation", 409))
        ]

        // Seed eventType CREATE mutation AND local eventType entity (the duplicate)
        _ = seedEventTypeCreateMutation(mockStore: mockStore, eventTypeId: "type-duplicate")
        seedEventTypeEntity(mockStore: mockStore, id: "type-duplicate")

        // Verify eventType exists before sync
        let typesBefore = try mockStore.fetchAllEventTypes()
        #expect(typesBefore.count == 1, "EventType should exist before sync")

        await engine.performSync()

        // Verify mutation was removed from queue (treated as success)
        let pendingAfter = try mockStore.fetchPendingMutations()
        #expect(pendingAfter.isEmpty, "409 Conflict should remove mutation from queue")

        // Verify local duplicate was deleted
        let typesAfter = try mockStore.fetchAllEventTypes()
        #expect(typesAfter.isEmpty, "Local duplicate should be deleted on 409")
    }

    @Test("409 with unique constraint message also triggers deduplication")
    func uniqueConstraintMessageTriggersDedupe() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Configure error with unique constraint message (not 409 code)
        mockNetwork.createEventTypeWithIdempotencyResponses = [
            .failure(APIError.serverError("unique constraint violation on external_id", 400))
        ]

        // Seed eventType CREATE mutation and local eventType entity
        _ = seedEventTypeCreateMutation(mockStore: mockStore, eventTypeId: "type-unique")
        seedEventTypeEntity(mockStore: mockStore, id: "type-unique")

        await engine.performSync()

        // Should treat as duplicate because message contains "unique"
        let pendingAfter = try mockStore.fetchPendingMutations()
        #expect(pendingAfter.isEmpty, "Unique constraint error should remove mutation from queue")
    }

    @Test("Non-409 errors do not trigger deduplication")
    func non409ErrorsDoNotDeduplicate() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Configure 400 Bad Request (not duplicate) for eventType idempotency path
        mockNetwork.createEventTypeWithIdempotencyResponses = [
            .failure(APIError.httpError(400))
        ]

        // Seed eventType CREATE mutation (goes through individual idempotency path)
        _ = seedEventTypeCreateMutation(mockStore: mockStore, eventTypeId: "type-1")

        await engine.performSync()

        // Verify mutation still pending (not removed as duplicate)
        let pending = try mockStore.fetchPendingMutations()
        #expect(pending.count == 1, "400 error should not trigger deduplication - got \(pending.count) pending")
        #expect(pending.first?.attempts == 1, "Should record failure attempt")
    }

    @Test("500 errors do not trigger deduplication")
    func server500DoesNotDeduplicate() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Configure 500 Internal Server Error for eventType idempotency path
        mockNetwork.createEventTypeWithIdempotencyResponses = [
            .failure(APIError.serverError("Internal server error", 500))
        ]

        // Seed eventType CREATE mutation (goes through individual idempotency path)
        _ = seedEventTypeCreateMutation(mockStore: mockStore, eventTypeId: "type-1")

        await engine.performSync()

        // Verify mutation still pending
        let pending = try mockStore.fetchPendingMutations()
        #expect(pending.count == 1, "500 error should not trigger deduplication")
    }
}
