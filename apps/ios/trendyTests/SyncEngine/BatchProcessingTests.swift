//
//  BatchProcessingTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine batch processing.
//  Verifies 50-event batch size and partial failure handling.
//
//  Requirements tested:
//  - SYNC-04: Test batch processing (50-event batches, partial failure handling)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Helpers

/// Helper to create fresh test dependencies for each test
private func makeTestDependencies() -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    cleanupSyncEngineUserDefaults()
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}

/// Helper to configure mock for flush operations (skip bootstrap, pass health check)
private func configureForFlush(mockNetwork: MockNetworkClient, mockStore: MockDataStore) {
    // Health check passes (required before any sync operations)
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Set cursor to non-zero to skip bootstrap
    UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")

    // Configure empty change feed to skip pullChanges processing
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}

/// Helper to seed multiple CREATE mutations
private func seedMultipleMutations(mockStore: MockDataStore, count: Int, prefix: String = "evt") {
    for i in 0..<count {
        let eventId = "\(prefix)-\(i)"
        let request = APIModelFixture.makeCreateEventRequest(id: eventId, eventTypeId: "type-1")
        let payload = try! JSONEncoder().encode(request)
        _ = mockStore.seedPendingMutation(entityType: .event, entityId: eventId, operation: .create, payload: payload)
    }
}

/// Helper to create a successful batch response for N events
private func makeSuccessfulBatchResponse(eventIds: [String]) -> BatchCreateEventsResponse {
    let created = eventIds.map { APIModelFixture.makeAPIEvent(id: $0) }
    return BatchCreateEventsResponse(
        created: created,
        errors: nil,
        total: eventIds.count,
        success: eventIds.count,
        failed: 0
    )
}

/// Helper to create a batch response with partial failures
private func makePartialFailureBatchResponse(
    successIds: [String],
    failures: [(index: Int, message: String)]
) -> BatchCreateEventsResponse {
    let created = successIds.map { APIModelFixture.makeAPIEvent(id: $0) }
    let errors = failures.map { BatchError(index: $0.index, message: $0.message) }
    return BatchCreateEventsResponse(
        created: created,
        errors: errors,
        total: successIds.count + failures.count,
        success: successIds.count,
        failed: failures.count
    )
}

// MARK: - Batch Processing

@Suite("Batch Processing")
struct BatchProcessingTests {

    @Test("Batch processing handles partial failures correctly (SYNC-04)")
    func testSYNC04_BatchProcessingHandlesPartialFailures() async throws {
        // Covers SYNC-04: Verify batch processing with 50-event batches and partial failure handling

        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed 3 mutations
        seedMultipleMutations(mockStore: mockStore, count: 3, prefix: "evt")

        // Configure batch response with partial failure:
        // - evt-0 and evt-2 succeed
        // - evt-1 fails
        mockNetwork.createEventsBatchResponses = [
            .success(BatchCreateEventsResponse(
                created: [
                    APIModelFixture.makeAPIEvent(id: "evt-0"),
                    APIModelFixture.makeAPIEvent(id: "evt-2")
                ],
                errors: [BatchError(index: 1, message: "Validation failed")],
                total: 3,
                success: 2,
                failed: 1
            ))
        ]

        await engine.performSync()

        // Verify batch call was made
        #expect(mockNetwork.createEventsBatchCalls.count == 1,
                "Should make one batch call for 3 events")

        // Check pending mutations - evt-1 should still be pending (failed)
        let pendingMutations = mockStore.storedPendingMutations
        let pendingIds = pendingMutations.map { $0.entityId }

        // evt-0 and evt-2 succeeded, so should be removed
        #expect(!pendingIds.contains("evt-0"), "evt-0 should be removed (success)")
        #expect(!pendingIds.contains("evt-2"), "evt-2 should be removed (success)")

        // evt-1 failed, so should still be pending with incremented attempts
        #expect(pendingIds.contains("evt-1"), "evt-1 should still be pending (failed)")

        if let failedMutation = pendingMutations.first(where: { $0.entityId == "evt-1" }) {
            #expect(failedMutation.attempts >= 1, "Failed mutation should have attempts recorded")
        }
    }

    @Test("Batch size is 50 events")
    func testBatchSizeIs50Events() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed 60 mutations (should result in 2 batches: 50 + 10)
        seedMultipleMutations(mockStore: mockStore, count: 60, prefix: "evt")

        // Configure success responses for both batches
        let batch1Ids = (0..<50).map { "evt-\($0)" }
        let batch2Ids = (50..<60).map { "evt-\($0)" }

        mockNetwork.createEventsBatchResponses = [
            .success(makeSuccessfulBatchResponse(eventIds: batch1Ids)),
            .success(makeSuccessfulBatchResponse(eventIds: batch2Ids))
        ]

        await engine.performSync()

        // Verify 2 batch calls were made
        #expect(mockNetwork.createEventsBatchCalls.count == 2,
                "Should make 2 batch calls for 60 events (50 + 10)")

        // Verify first batch has 50 events
        #expect(mockNetwork.createEventsBatchCalls[0].events.count == 50,
                "First batch should have 50 events")

        // Verify second batch has 10 events
        #expect(mockNetwork.createEventsBatchCalls[1].events.count == 10,
                "Second batch should have 10 events")
    }

    @Test("Whole batch failure keeps all mutations pending")
    func testWholeBatchFailureKeepsAllPending() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed 3 mutations
        seedMultipleMutations(mockStore: mockStore, count: 3, prefix: "evt")

        // Configure batch to fail entirely
        mockNetwork.createEventsBatchResponses = [
            .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)))
        ]

        await engine.performSync()

        // All 3 mutations should still be pending
        let pendingMutations = mockStore.storedPendingMutations
        let pendingIds = Set(pendingMutations.map { $0.entityId })

        #expect(pendingIds.contains("evt-0"), "evt-0 should still be pending after batch failure")
        #expect(pendingIds.contains("evt-1"), "evt-1 should still be pending after batch failure")
        #expect(pendingIds.contains("evt-2"), "evt-2 should still be pending after batch failure")
    }

    @Test("Successful batch removes all mutations from queue")
    func testSuccessfulBatchRemovesAllFromQueue() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed 3 mutations
        seedMultipleMutations(mockStore: mockStore, count: 3, prefix: "evt")

        // Configure all success
        mockNetwork.createEventsBatchResponses = [
            .success(makeSuccessfulBatchResponse(eventIds: ["evt-0", "evt-1", "evt-2"]))
        ]

        await engine.performSync()

        // Verify no event create mutations remain pending
        let pendingEventMutations = mockStore.storedPendingMutations.filter {
            $0.entityType == .event && $0.operation == .create
        }

        #expect(pendingEventMutations.isEmpty,
                "All event create mutations should be removed after successful batch")
    }

    @Test("Batch failure increments attempt count on mutations")
    func testBatchFailureIncrementsAttemptCount() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed 1 mutation
        seedMultipleMutations(mockStore: mockStore, count: 1, prefix: "evt")

        // Get initial attempt count (should be 0)
        let initialAttempts = mockStore.storedPendingMutations.first?.attempts ?? -1
        #expect(initialAttempts == 0, "Initial attempts should be 0")

        // Configure batch failure
        mockNetwork.createEventsBatchResponses = [
            .failure(APIError.httpError(500))
        ]

        await engine.performSync()

        // Verify attempt count was incremented
        if let mutation = mockStore.storedPendingMutations.first {
            #expect(mutation.attempts >= 1,
                    "Mutation attempts should be incremented after failure - got \(mutation.attempts)")
        }
    }
}

// MARK: - Batch Processing Edge Cases

@Suite("Batch Processing Edge Cases")
struct BatchProcessingEdgeCasesTests {

    @Test("Duplicate errors in batch are treated as success")
    func testDuplicateErrorsTreatedAsSuccess() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed 2 mutations
        seedMultipleMutations(mockStore: mockStore, count: 2, prefix: "evt")

        // Pre-seed local events so delete can work
        let eventType = mockStore.seedEventType { et in
            et.id = "type-1"
            et.name = "Test"
        }
        _ = mockStore.seedEvent(eventType: eventType) { e in e.id = "evt-1" }

        // Configure batch with duplicate error (should be treated as success)
        mockNetwork.createEventsBatchResponses = [
            .success(BatchCreateEventsResponse(
                created: [APIModelFixture.makeAPIEvent(id: "evt-0")],
                errors: [BatchError(index: 1, message: "Duplicate key constraint violation")],
                total: 2,
                success: 1,
                failed: 1
            ))
        ]

        await engine.performSync()

        // Both mutations should be removed (evt-0 succeeded, evt-1 was duplicate)
        let pendingMutations = mockStore.storedPendingMutations.filter {
            $0.entityType == .event && $0.operation == .create
        }

        #expect(pendingMutations.isEmpty,
                "Duplicate errors should remove mutation from queue")
    }

    @Test("Rate limit error during batch triggers circuit breaker check")
    func testRateLimitDuringBatch() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush with multiple health check responses
        mockNetwork.getEventTypesResponses = [
            .success([APIModelFixture.makeAPIEventType()]),
            .success([APIModelFixture.makeAPIEventType()]),
            .success([APIModelFixture.makeAPIEventType()])
        ]
        UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Seed 3 mutations (enough for 3 batch attempts)
        seedMultipleMutations(mockStore: mockStore, count: 3, prefix: "evt")

        // Configure 3 rate limit errors
        mockNetwork.createEventsBatchResponses = [
            .failure(APIError.httpError(429)),
            .failure(APIError.httpError(429)),
            .failure(APIError.httpError(429))
        ]

        await engine.performSync()

        // After 3 rate limit errors, circuit breaker should be tripped
        let isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == true,
                "Circuit breaker should trip after 3 rate limit errors")
    }

    @Test("Empty batch (no pending mutations) skips batch call")
    func testEmptyBatchSkipsBatchCall() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush but don't seed any mutations
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        await engine.performSync()

        // No batch calls should be made
        #expect(mockNetwork.createEventsBatchCalls.isEmpty,
                "No batch calls should be made when no pending mutations")
    }

    @Test("Non-event mutations processed individually after batch")
    func testNonEventMutationsProcessedIndividually() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for flush
        configureForFlush(mockNetwork: mockNetwork, mockStore: mockStore)

        // Seed event CREATE mutation (batched)
        seedMultipleMutations(mockStore: mockStore, count: 1, prefix: "evt")

        // Seed event type CREATE mutation (processed individually)
        let typeRequest = APIModelFixture.makeCreateEventTypeRequest(id: "type-new", name: "New Type")
        let typePayload = try! JSONEncoder().encode(typeRequest)
        _ = mockStore.seedPendingMutation(entityType: .eventType, entityId: "type-new", operation: .create, payload: typePayload)

        // Configure success for both
        mockNetwork.createEventsBatchResponses = [
            .success(makeSuccessfulBatchResponse(eventIds: ["evt-0"]))
        ]
        mockNetwork.createEventTypeResponses = [
            .success(APIModelFixture.makeAPIEventType(id: "type-new", name: "New Type"))
        ]

        await engine.performSync()

        // Verify batch was used for event
        #expect(mockNetwork.createEventsBatchCalls.count == 1,
                "Event create should use batch API")

        // Verify individual create was used for event type
        #expect(mockNetwork.createEventTypeWithIdempotencyCalls.count == 1,
                "Event type create should use individual API")
    }
}
