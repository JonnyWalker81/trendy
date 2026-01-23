//
//  HealthCheckTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine health check.
//  Verifies captive portal detection prevents false syncs.
//
//  Requirements tested:
//  - SYNC-05: Test health check detects captive portal (prevents false syncs)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Helpers

/// Helper to create fresh test dependencies for each test
private func makeTestDependencies() -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}

/// Helper to seed an event mutation
private func seedEventMutation(mockStore: MockDataStore, eventId: String) {
    let request = APIModelFixture.makeCreateEventRequest(id: eventId, eventTypeId: "type-1")
    let payload = try! JSONEncoder().encode(request)
    _ = mockStore.seedPendingMutation(entityType: .event, entityId: eventId, operation: .create, payload: payload)
}

/// UserDefaults cursor key
private var cursorKey: String {
    "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
}

// MARK: - Health Check

@Suite("Health Check")
struct HealthCheckTests {

    @Test("Health check detects captive portal and prevents sync (SYNC-05)")
    func testSYNC05_HealthCheckDetectsCaptivePortalAndPreventsSync() async throws {
        // Covers SYNC-05: Verify health check detects captive portal (prevents false syncs)
        // Captive portals return HTML instead of JSON, causing decoding errors

        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero (skip bootstrap)
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed a pending mutation (so sync would try to flush if health check passed)
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure health check to fail with decoding error (simulates captive portal HTML response)
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.decodingError("Expected array, got HTML login page"))
        ]

        // Record network call count before sync
        let healthCheckCallsBefore = mockNetwork.getEventTypesCalls.count
        let batchCallsBefore = mockNetwork.createEventsBatchCalls.count

        await engine.performSync()

        // Verify only 1 health check call was made
        #expect(mockNetwork.getEventTypesCalls.count == healthCheckCallsBefore + 1,
                "Only one health check should be attempted")

        // Verify no flush operations occurred
        #expect(mockNetwork.createEventsBatchCalls.count == batchCallsBefore,
                "No batch calls should be made when health check fails - got \(mockNetwork.createEventsBatchCalls.count)")

        // Verify no individual create calls
        #expect(mockNetwork.createEventWithIdempotencyCalls.isEmpty,
                "No create calls should be made when health check fails")

        // Verify pending mutation still exists
        let pending = mockStore.storedPendingMutations
        #expect(pending.count == 1, "Pending mutation should still exist after blocked sync")
        #expect(pending.first?.entityId == "evt-1", "Pending mutation should be unchanged")
    }

    @Test("Health check passes with valid response")
    func testHealthCheckPassesWithValidResponse() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for successful sync
        mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
        UserDefaults.standard.set(1000, forKey: cursorKey)
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Seed a mutation to flush
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure success response for flush
        mockNetwork.createEventWithIdempotencyResponses = [
            .success(APIModelFixture.makeAPIEvent(id: "evt-1"))
        ]

        await engine.performSync()

        // Verify sync proceeded normally
        #expect(mockNetwork.getEventTypesCalls.count == 1, "Health check should be called")
        #expect(mockNetwork.createEventWithIdempotencyCalls.count == 1,
                "Flush should occur after successful health check")

        // Verify mutation was processed
        let pending = mockStore.storedPendingMutations.filter {
            $0.entityType == .event && $0.operation == .create && $0.entityId == "evt-1"
        }
        #expect(pending.isEmpty, "Mutation should be flushed after successful sync")
    }

    @Test("Health check failure with network error blocks sync")
    func testHealthCheckFailureWithNetworkError() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed a mutation
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure health check to fail with network error
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)))
        ]

        await engine.performSync()

        // Verify sync was blocked
        #expect(mockNetwork.createEventsBatchCalls.isEmpty,
                "No batch calls should be made when health check fails with network error")

        // Verify mutation still pending
        #expect(mockStore.storedPendingMutations.count == 1,
                "Mutation should still be pending after blocked sync")
    }

    @Test("Health check called before every sync")
    func testHealthCheckCalledBeforeEverySync() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for multiple successful syncs
        mockNetwork.getEventTypesResponses = [
            .success([APIModelFixture.makeAPIEventType()]),
            .success([APIModelFixture.makeAPIEventType()])
        ]
        UserDefaults.standard.set(1000, forKey: cursorKey)
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // First sync
        await engine.performSync()

        // Second sync
        await engine.performSync()

        // Verify health check was called twice (once per sync)
        #expect(mockNetwork.getEventTypesCalls.count == 2,
                "Health check should be called before each sync")
    }

    @Test("Sync blocked during captive portal - no pullChanges called")
    func testSyncBlockedDuringCaptivePortalNoPullChanges() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed a mutation
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure health check to return decoding error (captive portal HTML)
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.decodingError("Unexpected character '<' at position 0"))
        ]

        await engine.performSync()

        // Verify no mutations flushed
        #expect(mockNetwork.createEventsBatchCalls.isEmpty, "No batch calls during captive portal")
        #expect(mockNetwork.createEventWithIdempotencyCalls.isEmpty, "No create calls during captive portal")

        // Verify no pullChanges called
        #expect(mockNetwork.getChangesCalls.isEmpty, "No getChanges calls during captive portal")

        // Verify mutation still pending
        #expect(mockStore.storedPendingMutations.count == 1, "Mutation still pending during captive portal")
    }
}

// MARK: - Health Check Edge Cases

@Suite("Health Check Edge Cases")
struct HealthCheckEdgeCasesTests {

    @Test("Health check passes with empty event types array")
    func testHealthCheckPassesWithEmptyArray() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure health check to return empty array (valid response, just no types yet)
        mockNetwork.getEventTypesResponses = [.success([])]
        UserDefaults.standard.set(1000, forKey: cursorKey)
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        await engine.performSync()

        // Sync should proceed (empty array is valid JSON response)
        #expect(mockNetwork.getChangesCalls.count == 1,
                "pullChanges should be called even with empty event types")
    }

    @Test("Health check failure does not affect pending mutation count")
    func testHealthCheckFailurePreservesPendingCount() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed 3 mutations
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")
        seedEventMutation(mockStore: mockStore, eventId: "evt-2")
        seedEventMutation(mockStore: mockStore, eventId: "evt-3")

        // Verify 3 pending before sync
        #expect(mockStore.storedPendingMutations.count == 3, "Should have 3 pending mutations")

        // Configure health check to fail
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.httpError(503))
        ]

        await engine.performSync()

        // All 3 should still be pending
        #expect(mockStore.storedPendingMutations.count == 3,
                "All 3 mutations should still be pending after health check failure")
    }

    @Test("Health check timeout error blocks sync")
    func testHealthCheckTimeoutBlocksSync() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed a mutation
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure health check to timeout
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)))
        ]

        await engine.performSync()

        // Sync should be blocked
        #expect(mockNetwork.getChangesCalls.isEmpty, "No pullChanges during timeout")
        #expect(mockNetwork.createEventsBatchCalls.isEmpty, "No batch calls during timeout")
    }

    @Test("Health check server error (5xx) blocks sync")
    func testHealthCheckServerErrorBlocksSync() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed a mutation
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure health check to return 500 error
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.serverError("Internal Server Error", 500))
        ]

        await engine.performSync()

        // Sync should be blocked
        #expect(mockNetwork.getChangesCalls.isEmpty, "No pullChanges during server error")
        #expect(mockNetwork.createEventsBatchCalls.isEmpty, "No batch calls during server error")
        #expect(mockStore.storedPendingMutations.count == 1, "Mutation preserved during server error")
    }

    @Test("Health check 401 unauthorized blocks sync")
    func testHealthCheck401BlocksSync() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Set cursor to non-zero
        UserDefaults.standard.set(1000, forKey: cursorKey)

        // Seed a mutation
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure health check to return 401 (expired token)
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.httpError(401))
        ]

        await engine.performSync()

        // Sync should be blocked
        #expect(mockNetwork.getChangesCalls.isEmpty, "No pullChanges during auth failure")
        #expect(mockStore.storedPendingMutations.count == 1, "Mutation preserved during auth failure")
    }
}
