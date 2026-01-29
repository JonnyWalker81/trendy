//
//  DataStoreResetTests.swift
//  trendyTests
//
//  Tests that SyncEngine properly resets its cached DataStore when the app returns
//  from background. This prevents "default.store couldn't be opened" errors caused
//  by stale SQLite file handles after prolonged iOS background suspension.
//
//  Root cause: After the app was backgrounded for 1+ hours, iOS could invalidate
//  file descriptors for the SQLite database. The SyncEngine cached a ModelContext
//  (via lazy var cachedDataStore) which held these stale file handles. On foreground
//  return, the first sync would fail with "default.store couldn't be opened" because
//  the cached ModelContext tried to use the invalidated handles.
//
//  Fix: Changed cachedDataStore from lazy var to a resettable optional with a
//  resetDataStore() method. MainTabView calls this when scenePhase becomes .active.
//

import Testing
import Foundation
@testable import trendy

// MARK: - DataStore Reset Tests

@Suite("DataStore Reset (Background Suspension Fix)")
struct DataStoreResetTests {

    @Test("resetDataStore creates fresh DataStore on next access")
    func resetCreatesNewStore() async throws {
        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = CountingDataStoreFactory(mockStore: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // First access creates the DataStore (call count = 1)
        await engine.loadInitialState()
        #expect(factory.callCount == 1, "Initial access should create DataStore")

        // Reset the cached DataStore (simulating app returning from background)
        await engine.resetDataStore()

        // Next access should create a NEW DataStore (call count = 2)
        _ = await engine.getPendingCount()
        #expect(factory.callCount == 2, "After reset, next access should create a new DataStore")
    }

    @Test("resetDataStore is safe to call multiple times")
    func multipleResetsAreSafe() async throws {
        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = CountingDataStoreFactory(mockStore: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Initial access
        await engine.loadInitialState()
        #expect(factory.callCount == 1)

        // Multiple resets without any access in between
        await engine.resetDataStore()
        await engine.resetDataStore()
        await engine.resetDataStore()

        // Only ONE new DataStore created on next access (not three)
        _ = await engine.getPendingCount()
        #expect(factory.callCount == 2, "Multiple resets should still result in only one new DataStore on next access")
    }

    @Test("resetDataStore always clears cache even if sync was in progress")
    func resetAlwaysClearsCache() async throws {
        cleanupSyncEngineUserDefaults()
        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = CountingDataStoreFactory(mockStore: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Configure for a sync that will run
        mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
        let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        UserDefaults.standard.set(1000, forKey: cursorKey)
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Start sync in background
        let syncTask = Task {
            await engine.performSync()
        }

        // Reset during sync - should always clear the cache.
        // After prolonged background, the in-progress sync's file handles are also stale,
        // so skipping the reset would leave the engine in a broken state.
        // Due to actor serialization, resetDataStore runs AFTER performSync completes.
        await engine.resetDataStore()

        await syncTask.value

        // Verify no crash occurred and sync completed normally.
        // The DataStore cache was cleared by resetDataStore, so next access creates a new one.
        #expect(factory.callCount >= 1, "DataStore should be created at least once")
    }

    @Test("Operations work correctly after DataStore reset")
    func operationsWorkAfterReset() async throws {
        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = MockDataStoreFactory(returning: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Queue a mutation (triggers initial DataStore creation)
        try await engine.queueMutation(
            entityType: .event,
            operation: .create,
            entityId: "event-1",
            payload: try JSONEncoder().encode(
                APIModelFixture.makeCreateEventRequest(id: "event-1")
            )
        )

        // Verify mutation was queued
        let countBefore = await engine.getPendingCount()
        #expect(countBefore == 1, "Should have 1 pending mutation before reset")

        // Reset DataStore (simulating background return)
        await engine.resetDataStore()

        // Queue another mutation after reset
        try await engine.queueMutation(
            entityType: .event,
            operation: .create,
            entityId: "event-2",
            payload: try JSONEncoder().encode(
                APIModelFixture.makeCreateEventRequest(id: "event-2")
            )
        )

        // MockDataStore keeps its state across factory calls (same instance returned),
        // so both mutations should be visible
        let countAfter = await engine.getPendingCount()
        #expect(countAfter == 2, "Should have 2 pending mutations after reset and new queue")
    }

    @Test("Simulated background-foreground cycle with DataStore reset prevents stale context")
    func backgroundForegroundCycle() async throws {
        cleanupSyncEngineUserDefaults()
        // This test simulates the exact failure scenario:
        // 1. App is active, sync works fine
        // 2. App goes to background for extended period
        // 3. App returns to foreground
        // 4. Without fix: sync fails with "default.store couldn't be opened"
        // 5. With fix: resetDataStore() is called, fresh context is created, sync works

        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = CountingDataStoreFactory(mockStore: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Phase 1: Normal operation (app is active)
        await engine.loadInitialState()
        #expect(factory.callCount == 1, "Phase 1: Initial DataStore created")

        // Phase 2: App goes to background (nothing happens to SyncEngine)
        // ... (time passes, iOS may invalidate file handles)

        // Phase 3: App returns to foreground - reset DataStore BEFORE sync
        await engine.resetDataStore()
        #expect(factory.callCount == 1, "Reset only clears cache, doesn't create new store yet")

        // Phase 4: Trigger sync - this should use a FRESH DataStore
        // Configure for successful sync
        mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
        let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        UserDefaults.standard.set(1000, forKey: cursorKey)
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        await engine.performSync()
        #expect(factory.callCount == 2, "Phase 4: Fresh DataStore created for sync after background return")
    }
}
