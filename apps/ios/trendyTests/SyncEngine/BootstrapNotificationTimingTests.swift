//
//  BootstrapNotificationTimingTests.swift
//  trendyTests
//
//  Tests that the bootstrap completed notification is posted AFTER sync completes,
//  not during bootstrapFetch(). This prevents race conditions where HealthKitService
//  starts reconciliation while SyncEngine is still doing cursor updates and history recording.
//
//  Root cause: Previously, .syncEngineBootstrapCompleted was posted inside bootstrapFetch(),
//  but performSync() continued with more database operations afterward:
//  - networkClient.getLatestCursor()
//  - UserDefaults writes
//  - preSyncDataStore.fetchPendingMutations()
//  - recordSyncHistory()
//
//  When HealthKitService received the notification, it would start reconcileHealthKitData()
//  which uses mainContext, while SyncEngine was still using cachedDataStore - causing
//  "default.store couldn't be opened" SQLite file locking errors.
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Helpers

/// Observer that captures notification timing relative to sync state
@MainActor
final class NotificationTimingObserver: @unchecked Sendable {
    private var notificationReceived = false
    private var syncStateWhenReceived: SyncState?
    private var observerToken: NSObjectProtocol?

    init() {
        observerToken = NotificationCenter.default.addObserver(
            forName: .syncEngineBootstrapCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notificationReceived = true
            }
        }
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var wasNotificationReceived: Bool { notificationReceived }
    var stateWhenNotificationReceived: SyncState? { syncStateWhenReceived }

    func reset() {
        notificationReceived = false
        syncStateWhenReceived = nil
    }
}

/// Observer that tracks whether database operations happen AFTER notification
@MainActor
final class OperationOrderObserver: @unchecked Sendable {
    private(set) var notificationTime: Date?
    private(set) var postNotificationDbOperations: Int = 0
    private var observerToken: NSObjectProtocol?

    init() {
        observerToken = NotificationCenter.default.addObserver(
            forName: .syncEngineBootstrapCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notificationTime = Date()
            }
        }
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func recordDbOperation(at time: Date) {
        if let notifTime = notificationTime, time > notifTime {
            postNotificationDbOperations += 1
        }
    }

    func reset() {
        notificationTime = nil
        postNotificationDbOperations = 0
    }
}

// MARK: - Bootstrap Notification Timing Tests

@Suite("Bootstrap Notification Timing (Race Condition Prevention)")
struct BootstrapNotificationTimingTests {

    @Test("Bootstrap notification is posted only during successful bootstrap sync")
    func notificationPostedOnlyDuringBootstrap() async throws {
        // Clean UserDefaults BEFORE creating engine since it reads cursor at init
        cleanupSyncEngineUserDefaults()

        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = MockDataStoreFactory(returning: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Configure for bootstrap success (cursor=0 after cleanup triggers bootstrap)
        // Two getEventTypes responses: one for health check, one for bootstrap fetch
        mockNetwork.getEventTypesResponses = [
            .success([]),  // Health check
            .success([])   // Bootstrap: fetchEventTypesForBootstrap
        ]
        mockNetwork.geofencesToReturn = []   // Bootstrap: empty geofences
        mockNetwork.getAllEventsResponses = [.success([])]  // Bootstrap: empty events
        mockNetwork.getLatestCursorResponses = [.success(1000)]  // Post-bootstrap cursor

        let observer = await NotificationTimingObserver()

        // Perform sync with bootstrap
        await engine.performSync()

        // Wait briefly for notification to be delivered on main thread
        try await Task.sleep(for: .milliseconds(100))

        // Notification should have been received (bootstrap was triggered)
        #expect(await observer.wasNotificationReceived, "Notification should be posted during bootstrap sync")

        // Clean up for next test
        await observer.reset()

        // Now do a non-bootstrap sync (cursor > 0, already 1000 from first sync)
        // Health check needs a response (queue was exhausted; falls through to eventTypesToReturn)
        mockNetwork.eventTypesToReturn = []
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        await engine.performSync()
        try await Task.sleep(for: .milliseconds(100))

        // Notification should NOT be received for non-bootstrap sync
        #expect(await !observer.wasNotificationReceived, "Notification should NOT be posted for non-bootstrap sync")
    }

    @Test("No database operations occur after bootstrap notification is posted")
    func noDbOpsAfterNotification() async throws {
        // This test verifies that moving the notification to the end of performSync()
        // means no more database operations happen after it's posted.

        // Clean UserDefaults BEFORE creating engine since it reads cursor at init
        cleanupSyncEngineUserDefaults()

        let mockNetwork = MockNetworkClient()
        let mockStore = TrackingMockDataStore()
        let factory = MockDataStoreFactory(returning: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Configure for bootstrap success (cursor=0 after cleanup triggers bootstrap)
        // Two getEventTypes responses: one for health check, one for bootstrap fetch
        mockNetwork.getEventTypesResponses = [
            .success([]),  // Health check
            .success([])   // Bootstrap: fetchEventTypesForBootstrap
        ]
        mockNetwork.geofencesToReturn = []
        mockNetwork.getAllEventsResponses = [.success([])]  // Bootstrap: empty events
        mockNetwork.getLatestCursorResponses = [.success(1000)]  // Post-bootstrap cursor

        var notificationTime: Date?
        let observer = NotificationCenter.default.addObserver(
            forName: .syncEngineBootstrapCompleted,
            object: nil,
            queue: .main
        ) { _ in
            notificationTime = Date()
        }

        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        // Track database operations
        mockStore.onAnyOperation = { operationTime in
            // If notification was already posted and this operation happened after,
            // it's a problem (race condition potential)
            if let notifTime = notificationTime, operationTime > notifTime {
                Issue.record("Database operation occurred after notification was posted")
            }
        }

        // Perform sync
        await engine.performSync()

        // Wait for notification delivery
        try await Task.sleep(for: .milliseconds(200))

        // Notification should have been received
        #expect(notificationTime != nil, "Bootstrap notification should have been posted")

        // No database operations should have occurred after notification
        // (The TrackingMockDataStore records all operations; we check timing above)
    }
}

// MARK: - Additional Mock for Timing Tests

/// Mock DataStore that tracks operation timing for race condition detection
final class TrackingMockDataStore: DataStoreProtocol {
    private let innerStore: MockDataStore
    var onAnyOperation: ((Date) -> Void)?

    init() {
        innerStore = MockDataStore()
    }

    private func recordOperation() {
        onAnyOperation?(Date())
    }

    // Forward all operations to inner store, recording timing

    @discardableResult
    func upsertEvent(id: String, configure: (Event) -> Void) throws -> Event {
        recordOperation()
        return try innerStore.upsertEvent(id: id, configure: configure)
    }

    @discardableResult
    func upsertEventType(id: String, configure: (EventType) -> Void) throws -> EventType {
        recordOperation()
        return try innerStore.upsertEventType(id: id, configure: configure)
    }

    @discardableResult
    func upsertGeofence(id: String, configure: (Geofence) -> Void) throws -> Geofence {
        recordOperation()
        return try innerStore.upsertGeofence(id: id, configure: configure)
    }

    @discardableResult
    func upsertPropertyDefinition(id: String, eventTypeId: String, configure: (PropertyDefinition) -> Void) throws -> PropertyDefinition {
        recordOperation()
        return try innerStore.upsertPropertyDefinition(id: id, eventTypeId: eventTypeId, configure: configure)
    }

    func deleteEvent(id: String) throws {
        recordOperation()
        try innerStore.deleteEvent(id: id)
    }

    func deleteEventType(id: String) throws {
        recordOperation()
        try innerStore.deleteEventType(id: id)
    }

    func deleteGeofence(id: String) throws {
        recordOperation()
        try innerStore.deleteGeofence(id: id)
    }

    func deletePropertyDefinition(id: String) throws {
        recordOperation()
        try innerStore.deletePropertyDefinition(id: id)
    }

    func findEvent(id: String) throws -> Event? {
        recordOperation()
        return try innerStore.findEvent(id: id)
    }

    func findEventType(id: String) throws -> EventType? {
        recordOperation()
        return try innerStore.findEventType(id: id)
    }

    func findGeofence(id: String) throws -> Geofence? {
        recordOperation()
        return try innerStore.findGeofence(id: id)
    }

    func findPropertyDefinition(id: String) throws -> PropertyDefinition? {
        recordOperation()
        return try innerStore.findPropertyDefinition(id: id)
    }

    func fetchAllEvents() throws -> [Event] {
        recordOperation()
        return try innerStore.fetchAllEvents()
    }

    func fetchAllEventTypes() throws -> [EventType] {
        recordOperation()
        return try innerStore.fetchAllEventTypes()
    }

    func fetchAllGeofences() throws -> [Geofence] {
        recordOperation()
        return try innerStore.fetchAllGeofences()
    }

    func fetchAllPropertyDefinitions() throws -> [PropertyDefinition] {
        recordOperation()
        return try innerStore.fetchAllPropertyDefinitions()
    }

    func deleteAllEvents() throws {
        recordOperation()
        try innerStore.deleteAllEvents()
    }

    func deleteAllEventTypes() throws {
        recordOperation()
        try innerStore.deleteAllEventTypes()
    }

    func deleteAllGeofences() throws {
        recordOperation()
        try innerStore.deleteAllGeofences()
    }

    func deleteAllPropertyDefinitions() throws {
        recordOperation()
        try innerStore.deleteAllPropertyDefinitions()
    }

    func fetchPendingMutations() throws -> [PendingMutation] {
        recordOperation()
        return try innerStore.fetchPendingMutations()
    }

    func hasPendingMutation(entityId: String, entityType: MutationEntityType, operation: MutationOperation) throws -> Bool {
        recordOperation()
        return try innerStore.hasPendingMutation(entityId: entityId, entityType: entityType, operation: operation)
    }

    func insertPendingMutation(_ mutation: PendingMutation) throws {
        recordOperation()
        try innerStore.insertPendingMutation(mutation)
    }

    func deletePendingMutation(_ mutation: PendingMutation) throws {
        recordOperation()
        try innerStore.deletePendingMutation(mutation)
    }

    func markEventSynced(id: String) throws {
        recordOperation()
        try innerStore.markEventSynced(id: id)
    }

    func markEventTypeSynced(id: String) throws {
        recordOperation()
        try innerStore.markEventTypeSynced(id: id)
    }

    func markGeofenceSynced(id: String) throws {
        recordOperation()
        try innerStore.markGeofenceSynced(id: id)
    }

    func markPropertyDefinitionSynced(id: String) throws {
        recordOperation()
        try innerStore.markPropertyDefinitionSynced(id: id)
    }

    func save() throws {
        recordOperation()
        try innerStore.save()
    }
}
