//
//  SingleFlightTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine single-flight pattern.
//  Verifies concurrent sync calls are coalesced into single execution.
//
//  Requirements tested:
//  - SYNC-01: Test single-flight pattern (concurrent sync calls coalesced)
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

/// Helper to configure mock for successful sync (health check passes, cursor set, empty change feed)
private func configureForSuccessfulSync(mockNetwork: MockNetworkClient, responseCount: Int = 1) {
    // Health check passes (required before any sync operations)
    // Provide multiple responses for concurrent calls
    mockNetwork.getEventTypesResponses = Array(repeating: .success([APIModelFixture.makeAPIEventType()]), count: responseCount)

    // Set cursor to non-zero to skip bootstrap
    UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")

    // Configure empty change feed to skip pullChanges processing
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}

/// Helper to seed an event mutation for flush testing
private func seedEventMutation(mockStore: MockDataStore, eventId: String) {
    let request = APIModelFixture.makeCreateEventRequest(id: eventId, eventTypeId: "type-1")
    let payload = try! JSONEncoder().encode(request)
    _ = mockStore.seedPendingMutation(entityType: .event, entityId: eventId, operation: .create, payload: payload)
}

// MARK: - Single Flight Pattern

@Suite("Single Flight Pattern")
struct SingleFlightPatternTests {

    @Test("Concurrent sync calls are coalesced into single execution (SYNC-01)")
    func testSYNC01_ConcurrentSyncCallsCoalesce() async throws {
        // Covers SYNC-01: Verify that multiple concurrent performSync() calls
        // result in only one actual sync operation (single-flight pattern)

        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for successful sync with enough responses for potential parallel calls
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 10)

        // Launch 5 concurrent performSync() calls
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await engine.performSync()
                }
            }
        }

        // Verify: Only 1 health check call should have been made
        // (subsequent calls should be blocked by isSyncing flag)
        // The first call acquires the lock, others see isSyncing=true and return early
        #expect(mockNetwork.getEventTypesCalls.count == 1,
                "Only one sync should execute - got \(mockNetwork.getEventTypesCalls.count) health check calls")
    }

    @Test("All concurrent callers complete without hanging")
    func testConcurrentSyncCallsAllComplete() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for successful sync
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 10)

        // Track completion of all tasks
        var completedCount = 0
        let lock = NSLock()

        // Launch 5 concurrent performSync() calls and verify all complete
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await engine.performSync()
                    lock.lock()
                    completedCount += 1
                    lock.unlock()
                }
            }
        }

        // All 5 tasks should have completed (not hung)
        #expect(completedCount == 5, "All concurrent callers should complete - got \(completedCount)")
    }

    @Test("Second sync after first completes executes normally")
    func testSequentialSyncsExecuteNormally() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for successful sync with enough responses for 2 syncs
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 5)

        // First sync
        await engine.performSync()

        // Second sync (after first completes)
        await engine.performSync()

        // Verify: Both syncs should have executed (2 health check calls)
        // Sequential calls are NOT coalesced because the first one completed
        #expect(mockNetwork.getEventTypesCalls.count == 2,
                "Both sequential syncs should execute - got \(mockNetwork.getEventTypesCalls.count) health check calls")
    }

    @Test("Sync blocked while in progress returns immediately")
    func testSyncBlockedReturnsImmediately() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for successful sync
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 10)

        // Add a small delay to the first sync by seeding mutations
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Configure success response for the mutation
        mockNetwork.createEventWithIdempotencyResponses = [
            .success(APIModelFixture.makeAPIEvent(id: "evt-1"))
        ]

        // Record start time
        let startTime = Date()

        // Launch concurrent syncs
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await engine.performSync()
                }
            }
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Should complete quickly (blocked calls return immediately)
        // Even with network delays, the test should complete in under 5 seconds
        #expect(duration < 5.0,
                "Concurrent syncs should complete quickly - took \(duration)s")

        // Only one sync should have actually executed
        #expect(mockNetwork.getEventTypesCalls.count == 1,
                "Only one sync should execute with concurrent calls")
    }
}

// MARK: - Single Flight Edge Cases

@Suite("Single Flight Edge Cases")
struct SingleFlightEdgeCasesTests {

    @Test("Sync with health check failure still releases lock for next sync")
    func testHealthCheckFailureReleasesLock() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // First sync: health check fails
        mockNetwork.getEventTypesResponses = [
            .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)))
        ]
        UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")

        await engine.performSync()

        // Second sync: health check succeeds
        mockNetwork.getEventTypesResponses = [
            .success([APIModelFixture.makeAPIEventType()])
        ]
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        await engine.performSync()

        // Both syncs should have attempted health check
        #expect(mockNetwork.getEventTypesCalls.count == 2,
                "Both syncs should attempt health check after failure releases lock")
    }

    @Test("Rapid sequential syncs execute independently")
    func testRapidSequentialSyncs() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for multiple successful syncs
        mockNetwork.getEventTypesResponses = Array(repeating: .success([APIModelFixture.makeAPIEventType()]), count: 5)
        UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Execute 3 sequential syncs rapidly
        for _ in 0..<3 {
            await engine.performSync()
        }

        // All 3 should execute (they're sequential, not concurrent)
        #expect(mockNetwork.getEventTypesCalls.count == 3,
                "All sequential syncs should execute - got \(mockNetwork.getEventTypesCalls.count)")
    }
}
