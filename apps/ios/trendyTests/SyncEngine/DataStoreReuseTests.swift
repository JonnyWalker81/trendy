//
//  DataStoreReuseTests.swift
//  trendyTests
//
//  Tests that SyncEngine reuses a single DataStore instance (cached ModelContext)
//  instead of creating a new ModelContext on every operation.
//
//  This prevents "default.store couldn't be opened" errors caused by too many
//  concurrent SQLite connections when geofence events trigger sync operations
//  simultaneously with ongoing sync activity.
//
//  Root cause: DefaultDataStoreFactory.makeDataStore() was called 14+ times per sync,
//  each creating a new ModelContext(modelContainer) and opening a new SQLite connection.
//  When geofence events arrived during sync, the additional ModelContext from the
//  MainActor (used by GeofenceManager/EventStore) competed for file access.
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Helpers

/// Counting factory that tracks how many times makeDataStore() is called.
/// Used to verify the SyncEngine caches and reuses a single DataStore instance.
final class CountingDataStoreFactory: DataStoreFactory, @unchecked Sendable {
    private let mockStore: MockDataStore
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.withLock { _callCount }
    }

    init(mockStore: MockDataStore) {
        self.mockStore = mockStore
    }

    func makeDataStore() -> any DataStoreProtocol {
        lock.withLock {
            _callCount += 1
        }
        return mockStore
    }
}

/// Helper to create test dependencies with counting factory
private func makeCountingDependencies(initialCursor: Int64 = 0) -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: CountingDataStoreFactory, engine: SyncEngine) {
    cleanupSyncEngineUserDefaults()
    // Set cursor BEFORE creating SyncEngine, because SyncEngine reads cursor in init()
    if initialCursor != 0 {
        UserDefaults.standard.set(Int(initialCursor), forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
    }
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = CountingDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}

/// Helper to configure mock for a successful sync pass
/// NOTE: Cursor must be set via makeCountingDependencies(initialCursor:) since SyncEngine reads it at init time.
private func configureForSuccessfulSync(mockNetwork: MockNetworkClient, responseCount: Int = 5) {
    // Health check passes
    mockNetwork.getEventTypesResponses = Array(repeating: .success([APIModelFixture.makeAPIEventType()]), count: responseCount)

    // Empty change feed
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}

// MARK: - DataStore Reuse Tests

@Suite("DataStore Reuse (Race Condition Prevention)")
struct DataStoreReuseTests {

    @Test("SyncEngine creates DataStore only once across multiple operations")
    func dataStoreCreatedOnce() async throws {
        let (mockNetwork, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)
        configureForSuccessfulSync(mockNetwork: mockNetwork)

        // Perform multiple operations that previously each created a new DataStore
        await engine.loadInitialState()
        await engine.performSync()
        _ = await engine.getPendingCount()

        // With caching, the factory should only be called ONCE (lazy initialization)
        // Previously this would have been 3+ calls, each creating a new ModelContext
        #expect(factory.callCount == 1, "Factory should only create one DataStore instance, got \(factory.callCount)")
    }

    @Test("Multiple sync cycles reuse the same cached DataStore")
    func multipleSyncCyclesReuseSameStore() async throws {
        let (mockNetwork, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 20)

        // Run multiple sync cycles
        await engine.loadInitialState()
        await engine.performSync()
        await engine.performSync()
        await engine.performSync()

        // All sync cycles should reuse the same DataStore
        #expect(factory.callCount == 1, "All sync cycles should reuse the same DataStore, got \(factory.callCount) factory calls")
    }

    @Test("queueMutation reuses cached DataStore instead of creating new one")
    func queueMutationReusesDataStore() async throws {
        let (_, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)

        // Queue multiple mutations
        for i in 0..<5 {
            try await engine.queueMutation(
                entityType: .event,
                operation: .create,
                entityId: "event-\(i)",
                payload: try JSONEncoder().encode(
                    APIModelFixture.makeCreateEventRequest(id: "event-\(i)")
                )
            )
        }

        // All queueMutation calls should reuse the same DataStore
        #expect(factory.callCount == 1, "queueMutation should reuse cached DataStore, got \(factory.callCount) factory calls")
    }

    @Test("Concurrent sync and mutation queue operations don't create multiple DataStores")
    func concurrentOperationsReuseDataStore() async throws {
        let (mockNetwork, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 20)

        // Simulate the race condition scenario:
        // 1. Geofence event triggers queueMutation + performSync
        // 2. Meanwhile, app lifecycle triggers performSync
        // Both should use the same cached DataStore

        await withTaskGroup(of: Void.self) { group in
            // Simulate geofence handler path
            group.addTask {
                try? await engine.queueMutation(
                    entityType: .event,
                    operation: .create,
                    entityId: "geofence-event-1",
                    payload: try! JSONEncoder().encode(
                        APIModelFixture.makeCreateEventRequest(id: "geofence-event-1")
                    )
                )
            }

            // Simulate concurrent sync trigger
            group.addTask {
                await engine.performSync()
            }

            // Simulate another concurrent operation
            group.addTask {
                _ = await engine.getPendingCount()
            }
        }

        // All concurrent operations should share one DataStore
        #expect(factory.callCount == 1, "Concurrent operations should reuse cached DataStore, got \(factory.callCount) factory calls")
    }

    @Test("clearPendingMutations reuses cached DataStore")
    func clearPendingMutationsReusesDataStore() async throws {
        let (_, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)

        // Queue a mutation then clear
        try await engine.queueMutation(
            entityType: .event,
            operation: .create,
            entityId: "event-1",
            payload: try JSONEncoder().encode(
                APIModelFixture.makeCreateEventRequest(id: "event-1")
            )
        )

        let cleared = await engine.clearPendingMutations()

        // Both operations should reuse same DataStore
        #expect(factory.callCount == 1, "clearPendingMutations should reuse cached DataStore, got \(factory.callCount) factory calls")
        #expect(cleared == 1, "Should have cleared 1 mutation")
    }

    @Test("skipToLatestCursor reuses cached DataStore")
    func skipToLatestCursorReusesDataStore() async throws {
        let (mockNetwork, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)

        // Configure for cursor fetch
        mockNetwork.latestCursorToReturn = 5000

        let cursor = try await engine.skipToLatestCursor()

        #expect(factory.callCount == 1, "skipToLatestCursor should reuse cached DataStore")
        #expect(cursor == 5000)
    }
}

// MARK: - Geofence Sync Race Condition Scenario Tests

@Suite("Geofence Sync Race Condition Scenario")
struct GeofenceSyncRaceConditionTests {

    @Test("Simulated geofence entry during active sync uses single DataStore")
    func geofenceEntryDuringSync() async throws {
        // This test simulates the exact scenario that causes "default.store couldn't be opened":
        // 1. A sync is already in progress (SyncEngine creating ModelContexts)
        // 2. A geofence entry event arrives
        // 3. GeofenceManager calls eventStore.syncEventToBackend()
        // 4. Which calls syncEngine.queueMutation() + syncEngine.performSync()
        //
        // With the fix, SyncEngine reuses a single cached DataStore,
        // so only ONE ModelContext is ever created, preventing SQLite file contention.

        let (mockNetwork, mockStore, factory, engine) = makeCountingDependencies(initialCursor: 1000)
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 20)

        // Phase 1: Start a sync (simulating regular app sync)
        let syncTask = Task {
            await engine.performSync()
        }

        // Phase 2: Simulate geofence event arriving mid-sync
        // The queueMutation call would previously create a NEW ModelContext
        try await engine.queueMutation(
            entityType: .event,
            operation: .create,
            entityId: "geofence-event",
            payload: try JSONEncoder().encode(
                APIModelFixture.makeCreateEventRequest(
                    id: "geofence-event",
                    eventTypeId: "gym-visit-type"
                )
            )
        )

        // Wait for initial sync to complete
        await syncTask.value

        // Phase 3: Geofence handler triggers another sync for the new event
        await engine.performSync()

        // Verify: only ONE DataStore was created despite multiple operations
        #expect(factory.callCount == 1, "All operations during geofence+sync race should use single DataStore, got \(factory.callCount)")

        // Verify the mutation was inserted (it may have been synced and removed by performSync,
        // so we check the insert call was recorded rather than checking pending state)
        let insertCalls = mockStore.insertMutationCalls
        let geofenceInsert = insertCalls.first { $0.entityId == "geofence-event" }
        #expect(geofenceInsert != nil, "Geofence event mutation should have been inserted")
    }

    @Test("Rapid geofence events don't cause DataStore proliferation")
    func rapidGeofenceEvents() async throws {
        // Simulates multiple rapid geofence events (e.g., user drives past multiple geofences)
        // Each event triggers queueMutation + performSync
        // Previously, each would create new ModelContext instances

        let (mockNetwork, _, factory, engine) = makeCountingDependencies(initialCursor: 1000)
        configureForSuccessfulSync(mockNetwork: mockNetwork, responseCount: 30)

        // Simulate 5 rapid geofence events
        for i in 0..<5 {
            try await engine.queueMutation(
                entityType: .event,
                operation: .create,
                entityId: "geofence-\(i)",
                payload: try JSONEncoder().encode(
                    APIModelFixture.makeCreateEventRequest(id: "geofence-\(i)")
                )
            )
        }

        // Trigger sync after all events are queued
        await engine.performSync()

        // Should still only have ONE DataStore
        #expect(factory.callCount == 1, "Rapid geofence events should all use single DataStore, got \(factory.callCount)")
    }
}
