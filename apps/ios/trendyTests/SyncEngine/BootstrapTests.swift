//
//  BootstrapTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine bootstrap fetch.
//  Verifies full data download and relationship restoration.
//
//  Requirements tested:
//  - SYNC-03: Test bootstrap fetch (full data download, relationship restoration)
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

/// UserDefaults cursor key
private var cursorKey: String {
    "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
}

/// Helper to configure mock for bootstrap (cursor=0, all endpoints configured)
private func configureForBootstrap(
    mockNetwork: MockNetworkClient,
    eventTypes: [APIEventType] = [APIModelFixture.makeAPIEventType()],
    events: [APIEvent] = [],
    geofences: [APIGeofence] = [],
    latestCursor: Int64 = 5000
) {
    // Health check passes
    mockNetwork.getEventTypesResponses = [
        .success(eventTypes),  // Health check
        .success(eventTypes)   // Bootstrap fetch
    ]

    // Set cursor to 0 to trigger bootstrap
    UserDefaults.standard.set(0, forKey: cursorKey)

    // Configure bootstrap endpoints
    mockNetwork.geofencesToReturn = geofences
    mockNetwork.getAllEventsResponses = [.success(events)]
    mockNetwork.getLatestCursorResponses = [.success(latestCursor)]
    mockNetwork.getPropertyDefinitionsResponses = Array(repeating: .success([]), count: eventTypes.count)
}

// MARK: - Bootstrap Fetch

@Suite("Bootstrap Fetch")
struct BootstrapFetchTests {

    @Test("Bootstrap restores Event to EventType relationships (SYNC-03)")
    func testSYNC03_BootstrapRestoresEventToEventTypeRelationships() async throws {
        // Covers SYNC-03: Verify bootstrap fetch downloads full data and restores relationships

        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Create test event type
        let eventType = APIModelFixture.makeAPIEventType(id: "type-work", name: "Work")

        // Create test event referencing the event type
        let event = APIEvent(
            id: "evt-1",
            userId: "user-1",
            eventTypeId: "type-work",
            timestamp: Date(),
            notes: "Test event",
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
            properties: nil,
            createdAt: Date(),
            updatedAt: Date(),
            eventType: nil
        )

        // Configure for bootstrap
        configureForBootstrap(
            mockNetwork: mockNetwork,
            eventTypes: [eventType],
            events: [event],
            latestCursor: 1000
        )

        await engine.performSync()

        // Verify event was stored
        let storedEvent = mockStore.storedEvents["evt-1"]
        #expect(storedEvent != nil, "Event should be stored after bootstrap")

        // Verify EventType was stored
        let storedEventType = mockStore.storedEventTypes["type-work"]
        #expect(storedEventType != nil, "EventType should be stored after bootstrap")
        #expect(storedEventType?.name == "Work", "EventType name should be 'Work'")

        // Verify Event->EventType relationship is established
        #expect(storedEvent?.eventType != nil, "Event should have eventType relationship")
        #expect(storedEvent?.eventType?.id == "type-work",
                "Event should be linked to correct EventType")
        #expect(storedEvent?.eventType?.name == "Work",
                "Event's eventType should have correct name")
    }

    @Test("Bootstrap triggered when cursor is zero")
    func testBootstrapTriggeredWhenCursorIsZero() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for bootstrap with cursor=0
        configureForBootstrap(mockNetwork: mockNetwork, latestCursor: 5000)

        await engine.performSync()

        // Verify getAllEvents was called (bootstrap behavior)
        #expect(mockNetwork.getAllEventsCalls.count == 1,
                "getAllEvents should be called during bootstrap")

        // Verify getChanges was NOT called (bootstrap skips incremental sync)
        #expect(mockNetwork.getChangesCalls.count == 0,
                "getChanges should NOT be called during bootstrap")
    }

    @Test("Bootstrap NOT triggered when cursor is non-zero")
    func testBootstrapNotTriggeredWhenCursorNonZero() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Configure for incremental sync
        mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        await engine.performSync()

        // Verify getAllEvents was NOT called (incremental sync, not bootstrap)
        #expect(mockNetwork.getAllEventsCalls.count == 0,
                "getAllEvents should NOT be called for incremental sync")

        // Verify getChanges WAS called (incremental sync behavior)
        #expect(mockNetwork.getChangesCalls.count == 1,
                "getChanges should be called for incremental sync")
    }

    @Test("Bootstrap updates cursor from getLatestCursor after completion")
    func testBootstrapUpdatesLatestCursorAfterCompletion() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for bootstrap with specific latest cursor
        configureForBootstrap(mockNetwork: mockNetwork, latestCursor: 9999)

        await engine.performSync()

        // Verify cursor was updated to latest value
        let savedCursor = UserDefaults.standard.integer(forKey: cursorKey)
        #expect(savedCursor == 9999, "Cursor should be updated to latest after bootstrap - got \(savedCursor)")
    }

    @Test("Bootstrap downloads all EventTypes")
    func testBootstrapDownloadsAllEventTypes() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Create multiple event types
        let eventTypes = [
            APIModelFixture.makeAPIEventType(id: "type-1", name: "Work"),
            APIModelFixture.makeAPIEventType(id: "type-2", name: "Exercise"),
            APIModelFixture.makeAPIEventType(id: "type-3", name: "Reading")
        ]

        // Configure for bootstrap with multiple event types
        configureForBootstrap(mockNetwork: mockNetwork, eventTypes: eventTypes, latestCursor: 1000)

        await engine.performSync()

        // Verify all event types were stored
        #expect(mockStore.storedEventTypes.count == 3,
                "All 3 event types should be stored - got \(mockStore.storedEventTypes.count)")
        #expect(mockStore.storedEventTypes["type-1"]?.name == "Work", "type-1 should be 'Work'")
        #expect(mockStore.storedEventTypes["type-2"]?.name == "Exercise", "type-2 should be 'Exercise'")
        #expect(mockStore.storedEventTypes["type-3"]?.name == "Reading", "type-3 should be 'Reading'")
    }
}

// MARK: - Bootstrap Edge Cases

@Suite("Bootstrap Edge Cases")
struct BootstrapEdgeCasesTests {

    @Test("Bootstrap deletes local data before repopulating")
    func testBootstrapDeletesLocalDataBeforeRepopulating() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Pre-seed local data that should be deleted
        _ = mockStore.seedEventType { et in
            et.id = "old-type"
            et.name = "Old Type"
        }

        // Configure for bootstrap with new data
        let newEventType = APIModelFixture.makeAPIEventType(id: "new-type", name: "New Type")
        configureForBootstrap(mockNetwork: mockNetwork, eventTypes: [newEventType], latestCursor: 1000)

        await engine.performSync()

        // Verify deleteAllEventTypes was called
        #expect(mockStore.deleteAllEventTypesCalls > 0,
                "Bootstrap should call deleteAllEventTypes")

        // Verify only new data exists (old data was deleted)
        #expect(mockStore.storedEventTypes["old-type"] == nil,
                "Old event type should be deleted")
        #expect(mockStore.storedEventTypes["new-type"] != nil,
                "New event type should exist")
    }

    @Test("Bootstrap handles getLatestCursor failure with fallback")
    func testBootstrapHandlesLatestCursorFailure() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for bootstrap but getLatestCursor fails
        mockNetwork.getEventTypesResponses = [
            .success([APIModelFixture.makeAPIEventType()]),
            .success([APIModelFixture.makeAPIEventType()])
        ]
        UserDefaults.standard.set(0, forKey: cursorKey)
        mockNetwork.getAllEventsResponses = [.success([])]
        mockNetwork.getPropertyDefinitionsResponses = [.success([])]

        // getLatestCursor fails
        mockNetwork.getLatestCursorResponses = [
            .failure(APIError.networkError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)))
        ]

        await engine.performSync()

        // Verify cursor was set to fallback value (Int64.max / 2)
        let savedCursor = Int64(UserDefaults.standard.integer(forKey: cursorKey))
        #expect(savedCursor > 0, "Cursor should be set to a large fallback value after getLatestCursor failure")
    }

    @Test("Bootstrap fetches and stores geofences")
    func testBootstrapFetchesGeofences() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Create test geofence
        let geofence = APIModelFixture.makeAPIGeofence(id: "geo-1", name: "Home")

        // Configure for bootstrap with geofence
        configureForBootstrap(mockNetwork: mockNetwork, geofences: [geofence], latestCursor: 1000)

        await engine.performSync()

        // Verify geofence was stored
        #expect(mockStore.storedGeofences["geo-1"] != nil,
                "Geofence should be stored after bootstrap")
        #expect(mockStore.storedGeofences["geo-1"]?.name == "Home",
                "Geofence name should be 'Home'")
    }

    @Test("Bootstrap restores multiple Event-EventType relationships")
    func testBootstrapRestoresMultipleRelationships() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Create multiple event types
        let workType = APIModelFixture.makeAPIEventType(id: "type-work", name: "Work")
        let exerciseType = APIModelFixture.makeAPIEventType(id: "type-exercise", name: "Exercise")

        // Create events referencing different event types
        let event1 = APIEvent(
            id: "evt-1", userId: "user-1", eventTypeId: "type-work",
            timestamp: Date(), notes: nil, isAllDay: false, endDate: nil,
            sourceType: "manual", externalId: nil, originalTitle: nil,
            geofenceId: nil, locationLatitude: nil, locationLongitude: nil, locationName: nil,
            healthKitSampleId: nil, healthKitCategory: nil, properties: nil,
            createdAt: Date(), updatedAt: Date(), eventType: nil
        )
        let event2 = APIEvent(
            id: "evt-2", userId: "user-1", eventTypeId: "type-exercise",
            timestamp: Date(), notes: nil, isAllDay: false, endDate: nil,
            sourceType: "manual", externalId: nil, originalTitle: nil,
            geofenceId: nil, locationLatitude: nil, locationLongitude: nil, locationName: nil,
            healthKitSampleId: nil, healthKitCategory: nil, properties: nil,
            createdAt: Date(), updatedAt: Date(), eventType: nil
        )
        let event3 = APIEvent(
            id: "evt-3", userId: "user-1", eventTypeId: "type-work",
            timestamp: Date(), notes: nil, isAllDay: false, endDate: nil,
            sourceType: "manual", externalId: nil, originalTitle: nil,
            geofenceId: nil, locationLatitude: nil, locationLongitude: nil, locationName: nil,
            healthKitSampleId: nil, healthKitCategory: nil, properties: nil,
            createdAt: Date(), updatedAt: Date(), eventType: nil
        )

        // Configure for bootstrap
        configureForBootstrap(
            mockNetwork: mockNetwork,
            eventTypes: [workType, exerciseType],
            events: [event1, event2, event3],
            latestCursor: 1000
        )

        await engine.performSync()

        // Verify all events have correct relationships
        let storedEvent1 = mockStore.storedEvents["evt-1"]
        let storedEvent2 = mockStore.storedEvents["evt-2"]
        let storedEvent3 = mockStore.storedEvents["evt-3"]

        #expect(storedEvent1?.eventType?.id == "type-work", "Event 1 should link to Work type")
        #expect(storedEvent2?.eventType?.id == "type-exercise", "Event 2 should link to Exercise type")
        #expect(storedEvent3?.eventType?.id == "type-work", "Event 3 should link to Work type")
    }
}
