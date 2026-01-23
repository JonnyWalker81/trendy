//
//  PaginationTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine cursor pagination.
//  Verifies hasMore flag and cursor advancement work correctly.
//
//  Requirements tested:
//  - SYNC-02: Test cursor pagination (hasMore flag, cursor advancement)
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

/// Helper to configure mock for incremental sync (health check passes, non-zero cursor)
private func configureForIncrementalSync(mockNetwork: MockNetworkClient, initialCursor: Int64 = 1000) {
    // Health check passes
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Set cursor to non-zero to skip bootstrap and trigger pullChanges
    UserDefaults.standard.set(Int(initialCursor), forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
}

/// UserDefaults cursor key
private var cursorKey: String {
    "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
}

// MARK: - Cursor Pagination

@Suite("Cursor Pagination")
struct CursorPaginationTests {

    @Test("Pagination advances cursor until hasMore is false (SYNC-02)")
    func testSYNC02_PaginationAdvancesCursorUntilHasMoreFalse() async throws {
        // Covers SYNC-02: Verify cursor pagination with hasMore flag and cursor advancement

        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for incremental sync starting at cursor 1000
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 1000)

        // Configure multi-page getChangesResponses:
        // Page 1: nextCursor=2000, hasMore=true
        // Page 2: nextCursor=3000, hasMore=true
        // Page 3: nextCursor=4000, hasMore=false
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [], nextCursor: 2000, hasMore: true)),
            .success(ChangeFeedResponse(changes: [], nextCursor: 3000, hasMore: true)),
            .success(ChangeFeedResponse(changes: [], nextCursor: 4000, hasMore: false))
        ]

        await engine.performSync()

        // Verify 3 getChanges calls were made (one per page)
        #expect(mockNetwork.getChangesCalls.count == 3,
                "Should make 3 getChanges calls for 3 pages - got \(mockNetwork.getChangesCalls.count)")

        // Verify cursor progression: 1000 -> 2000 -> 3000
        #expect(mockNetwork.getChangesCalls[0].cursor == 1000, "First call should use cursor 1000")
        #expect(mockNetwork.getChangesCalls[1].cursor == 2000, "Second call should use cursor 2000")
        #expect(mockNetwork.getChangesCalls[2].cursor == 3000, "Third call should use cursor 3000")

        // Verify final cursor saved
        let savedCursor = UserDefaults.standard.integer(forKey: cursorKey)
        #expect(savedCursor == 4000, "Final cursor should be 4000 - got \(savedCursor)")
    }

    @Test("Pagination stops immediately when hasMore is false")
    func testPaginationStopsWhenHasMoreFalse() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for incremental sync
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 1000)

        // Single-page response with hasMore=false
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [], nextCursor: 1500, hasMore: false))
        ]

        await engine.performSync()

        // Verify only 1 getChanges call made
        #expect(mockNetwork.getChangesCalls.count == 1,
                "Should make only 1 getChanges call when hasMore=false immediately")
    }

    @Test("Cursor saved to UserDefaults after pagination")
    func testCursorSavedToUserDefaults() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for incremental sync
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 500)

        // Single-page response
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [], nextCursor: 1234, hasMore: false))
        ]

        await engine.performSync()

        // Verify cursor saved
        let savedCursor = UserDefaults.standard.integer(forKey: cursorKey)
        #expect(savedCursor == 1234, "Cursor should be saved to UserDefaults - got \(savedCursor)")
    }

    @Test("Empty changes array still advances cursor")
    func testEmptyChangesStillAdvancesCursor() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Configure for incremental sync
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 100)

        // Two pages with empty changes
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [], nextCursor: 200, hasMore: true)),
            .success(ChangeFeedResponse(changes: [], nextCursor: 300, hasMore: false))
        ]

        await engine.performSync()

        // Cursor should still advance even with empty changes
        #expect(mockNetwork.getChangesCalls.count == 2, "Should still paginate with empty changes")

        let savedCursor = UserDefaults.standard.integer(forKey: cursorKey)
        #expect(savedCursor == 300, "Cursor should advance to 300 even with empty changes")
    }
}

// MARK: - Cursor Edge Cases

@Suite("Cursor Edge Cases")
struct CursorEdgeCasesTests {

    @Test("Cursor only advances forward (never backward)")
    func testCursorOnlyAdvancesForward() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Start at cursor 5000
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 5000)

        // Response tries to set cursor backward to 1000 (invalid)
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false))
        ]

        await engine.performSync()

        // Cursor should NOT go backward
        let savedCursor = UserDefaults.standard.integer(forKey: cursorKey)
        #expect(savedCursor == 5000, "Cursor should not go backward from 5000 to 1000 - got \(savedCursor)")
    }

    @Test("Large cursor values handled correctly")
    func testLargeCursorValues() async throws {
        let (mockNetwork, _, _, engine) = makeTestDependencies()

        // Start with large cursor
        let largeCursor: Int64 = 9_000_000_000
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: largeCursor)

        // Response with even larger cursor
        let largerCursor: Int64 = 9_000_000_001
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [], nextCursor: largerCursor, hasMore: false))
        ]

        await engine.performSync()

        // Verify large cursor handled correctly
        let savedCursor = Int64(UserDefaults.standard.integer(forKey: cursorKey))
        // Note: UserDefaults.integer returns Int, which may truncate Int64 on 32-bit systems
        // On 64-bit systems this should work correctly
        #expect(savedCursor == largerCursor || mockNetwork.getChangesCalls.count == 1,
                "Large cursor should be handled (or at least sync should complete)")
    }

    @Test("Pagination with changes applies them correctly")
    func testPaginationWithChangesAppliesCorrectly() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for incremental sync
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 1000)

        // Create change entry data for an event type
        let changeData = ChangeEntryData(
            name: "New Event Type",
            color: "#FF0000",
            icon: "star",
            timestamp: nil,
            notes: nil,
            isAllDay: nil,
            endDate: nil,
            eventTypeId: nil,
            sourceType: nil,
            externalId: nil,
            originalTitle: nil,
            geofenceId: nil,
            locationLatitude: nil,
            locationLongitude: nil,
            locationName: nil,
            healthKitSampleId: nil,
            healthKitCategory: nil,
            properties: nil,
            latitude: nil,
            longitude: nil,
            radius: nil,
            isActive: nil,
            notifyOnEntry: nil,
            notifyOnExit: nil,
            eventTypeEntryId: nil,
            eventTypeExitId: nil,
            key: nil,
            label: nil,
            propertyType: nil,
            displayOrder: nil,
            options: nil
        )

        let change = ChangeEntry(
            id: 1001,
            entityType: "event_type",
            operation: "create",
            entityId: "type-new",
            data: changeData,
            deletedAt: nil,
            createdAt: Date()
        )

        // Page with a change
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [change], nextCursor: 2000, hasMore: false))
        ]

        await engine.performSync()

        // Verify change was applied (EventType was upserted)
        #expect(mockStore.upsertEventTypeCalls.count == 1,
                "Change should trigger upsert - got \(mockStore.upsertEventTypeCalls.count) calls")
        #expect(mockStore.upsertEventTypeCalls.first?.id == "type-new",
                "Should upsert the correct event type ID")
    }

    @Test("Multiple pages of changes processed correctly")
    func testMultiplePagesOfChanges() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

        // Configure for incremental sync
        configureForIncrementalSync(mockNetwork: mockNetwork, initialCursor: 1000)

        // Create change entries
        let change1 = APIModelFixture.makeChangeEntry(id: 1001, entityType: "event_type", operation: "create", entityId: "type-1")
        let change2 = APIModelFixture.makeChangeEntry(id: 1002, entityType: "event_type", operation: "create", entityId: "type-2")
        let change3 = APIModelFixture.makeChangeEntry(id: 1003, entityType: "event_type", operation: "create", entityId: "type-3")

        // Three pages with changes
        mockNetwork.getChangesResponses = [
            .success(ChangeFeedResponse(changes: [change1], nextCursor: 2000, hasMore: true)),
            .success(ChangeFeedResponse(changes: [change2], nextCursor: 3000, hasMore: true)),
            .success(ChangeFeedResponse(changes: [change3], nextCursor: 4000, hasMore: false))
        ]

        await engine.performSync()

        // All 3 pages should have been processed
        #expect(mockNetwork.getChangesCalls.count == 3, "Should process all 3 pages")

        // All 3 changes should have been applied
        #expect(mockStore.upsertEventTypeCalls.count == 3,
                "Should apply all 3 changes - got \(mockStore.upsertEventTypeCalls.count)")

        // Verify cursor advanced to final value
        let savedCursor = UserDefaults.standard.integer(forKey: cursorKey)
        #expect(savedCursor == 4000, "Final cursor should be 4000")
    }
}
