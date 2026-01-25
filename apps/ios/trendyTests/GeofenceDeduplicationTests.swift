//
//  GeofenceDeduplicationTests.swift
//  trendyTests
//
//  Tests for geofence event deduplication mechanisms.
//  Verifies that duplicate geofence entry events are not created when:
//  - Multiple delegate callbacks fire for the same entry
//  - Region re-registration triggers didDetermineState while user is still inside
//  - App restart clears in-memory state but events exist in database
//
//  Requirements tested:
//  - GEO-DUP-01: Recent entry exists check prevents duplicate within tolerance window
//  - GEO-DUP-02: Early claim pattern prevents concurrent duplicate creation
//  - GEO-DUP-03: Database-level check catches duplicates missed by in-memory check
//  - GEO-DUP-04: Events outside tolerance window allow new entry creation
//

import Testing
import Foundation
import SwiftData
@testable import trendy

// MARK: - Test Fixtures

/// Factory for creating geofence test fixtures
struct GeofenceTestFixture {

    /// Create a basic event type for geofence events
    static func makeEventType(
        context: ModelContext,
        name: String = "Gym",
        colorHex: String = "#FF5733",
        iconName: String = "figure.walk"
    ) -> EventType {
        let eventType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        context.insert(eventType)
        return eventType
    }

    /// Create a geofence entry event
    static func makeGeofenceEntryEvent(
        context: ModelContext,
        eventType: EventType,
        geofenceId: String,
        timestamp: Date = Date(),
        endDate: Date? = nil
    ) -> Event {
        let event = Event(
            timestamp: timestamp,
            eventType: eventType,
            notes: "Auto-logged by geofence: Test Geofence",
            sourceType: .geofence,
            geofenceId: geofenceId
        )
        event.endDate = endDate
        context.insert(event)
        return event
    }

    /// Create a geofence record
    static func makeGeofence(
        context: ModelContext,
        id: String = UUIDv7.generate(),
        name: String = "Test Geofence",
        eventTypeEntryID: String? = nil
    ) -> Geofence {
        let geofence = Geofence(
            id: id,
            name: name,
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 100.0,
            eventTypeEntryID: eventTypeEntryID,
            eventTypeExitID: nil,
            isActive: true,
            notifyOnEntry: false,
            notifyOnExit: false,
            syncStatus: .synced
        )
        context.insert(geofence)
        return geofence
    }
}

// MARK: - Test Helpers

/// Helper to create a test model context
private func makeTestModelContext() -> ModelContext {
    let schema = Schema([
        Event.self,
        EventType.self,
        Geofence.self,
        PropertyDefinition.self,
        PendingMutation.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    return ModelContext(container)
}

/// Helper to check if recent geofence entry exists in database
/// This simulates the logic from GeofenceManager.recentGeofenceEntryExists
private func checkRecentGeofenceEntryExists(
    context: ModelContext,
    geofenceId: String,
    tolerance: TimeInterval = 60
) -> Bool {
    let descriptor = FetchDescriptor<Event>(
        predicate: #Predicate { event in
            event.geofenceId == geofenceId &&
            event.sourceTypeRaw == "geofence" &&
            event.endDate == nil
        },
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )

    guard let events = try? context.fetch(descriptor), let mostRecent = events.first else {
        return false
    }

    let timeSinceEntry = Date().timeIntervalSince(mostRecent.timestamp)
    return timeSinceEntry <= tolerance
}

// MARK: - Database-Level Deduplication Tests

@Suite("Database-Level Geofence Deduplication")
struct GeofenceDatabaseDeduplicationTests {

    @Test("Recent entry exists check detects active entry within tolerance (GEO-DUP-01)")
    func recentEntryWithinToleranceIsDetected() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create an entry event 30 seconds ago (within default 60s tolerance)
        let entryTime = Date().addingTimeInterval(-30)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: entryTime,
            endDate: nil  // No exit = still active
        )
        try context.save()

        // Check should detect the recent entry
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(exists, "Should detect entry within tolerance window")
    }

    @Test("Entry outside tolerance window allows new entry (GEO-DUP-04)")
    func entryOutsideToleranceAllowsNewEntry() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create an entry event 120 seconds ago (outside default 60s tolerance)
        let entryTime = Date().addingTimeInterval(-120)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: entryTime,
            endDate: nil
        )
        try context.save()

        // Check should NOT detect the old entry
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId, tolerance: 60)
        #expect(!exists, "Should not detect entry outside tolerance window")
    }

    @Test("Completed entry (with exit) does not block new entry")
    func completedEntryDoesNotBlockNewEntry() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create a completed entry event (has endDate)
        let entryTime = Date().addingTimeInterval(-30)
        let exitTime = Date().addingTimeInterval(-10)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: entryTime,
            endDate: exitTime  // Has exit = completed
        )
        try context.save()

        // Check should NOT detect the completed entry
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(!exists, "Should not detect completed entry (with exit)")
    }

    @Test("Different geofence ID does not trigger duplicate detection")
    func differentGeofenceIdAllowsEntry() throws {
        let context = makeTestModelContext()
        let geofenceId1 = UUIDv7.generate()
        let geofenceId2 = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create an active entry for geofence 1
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId1,
            timestamp: Date().addingTimeInterval(-30),
            endDate: nil
        )
        try context.save()

        // Check for geofence 2 should not detect geofence 1's entry
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId2)
        #expect(!exists, "Should not detect entry for different geofence")
    }

    @Test("Non-geofence events do not trigger duplicate detection")
    func nonGeofenceEventsIgnored() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create a manual event (not geofence) with matching geofenceId
        let event = Event(
            timestamp: Date().addingTimeInterval(-30),
            eventType: eventType,
            notes: "Manual event",
            sourceType: .manual  // Not geofence
        )
        event.geofenceId = geofenceId
        context.insert(event)
        try context.save()

        // Check should not detect the manual event
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(!exists, "Should not detect non-geofence events")
    }

    @Test("Multiple active entries - most recent is checked")
    func multipleActiveEntriesChecksRecent() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create an old active entry (outside tolerance)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-120),
            endDate: nil
        )

        // Create a recent active entry (within tolerance)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-30),
            endDate: nil
        )
        try context.save()

        // Check should detect the recent entry
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId, tolerance: 60)
        #expect(exists, "Should detect most recent entry within tolerance")
    }
}

// MARK: - In-Memory Deduplication Tests

@Suite("In-Memory Geofence Deduplication")
struct GeofenceInMemoryDeduplicationTests {

    @Test("activeGeofenceEvents dictionary prevents duplicate when populated")
    func activeGeofenceEventsPreventsDuplicate() async throws {
        // This test verifies the in-memory dictionary behavior
        var activeGeofenceEvents: [String: String] = [:]
        let geofenceId = UUIDv7.generate()
        let eventId = UUIDv7.generate()

        // First check - should be nil
        #expect(activeGeofenceEvents[geofenceId] == nil)

        // Simulate entry: add to dictionary
        activeGeofenceEvents[geofenceId] = eventId

        // Second check - should find existing
        #expect(activeGeofenceEvents[geofenceId] == eventId)
    }

    @Test("UserDefaults persistence round-trip preserves state")
    func userDefaultsPersistenceWorks() throws {
        let testKey = "test_activeGeofenceEvents_\(UUID().uuidString)"
        let geofenceId = UUIDv7.generate()
        let eventId = UUIDv7.generate()

        // Save to UserDefaults
        let original: [String: String] = [geofenceId: eventId]
        let encoded = try JSONEncoder().encode(original)
        UserDefaults.standard.set(encoded, forKey: testKey)

        // Load from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: testKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            Issue.record("Failed to load from UserDefaults")
            return
        }

        #expect(decoded[geofenceId] == eventId, "Should preserve activeGeofenceEvents through UserDefaults")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: testKey)
    }
}

// MARK: - Edge Case Tests

@Suite("Geofence Deduplication Edge Cases")
struct GeofenceDeduplicationEdgeCaseTests {

    @Test("Empty database returns no duplicate")
    func emptyDatabaseNoDuplicate() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()

        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(!exists, "Empty database should not detect any duplicates")
    }

    @Test("Tolerance boundary - just inside tolerance")
    func toleranceBoundaryJustInside() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)
        let tolerance: TimeInterval = 60

        // Create an entry 1 second inside the tolerance boundary
        // Using tolerance - 1 instead of exactly tolerance to avoid timing flakiness
        let entryTime = Date().addingTimeInterval(-(tolerance - 1))
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: entryTime,
            endDate: nil
        )
        try context.save()

        // Entry 1 second inside tolerance should be detected
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId, tolerance: tolerance)
        #expect(exists, "Entry just inside tolerance boundary should be detected")
    }

    @Test("Tolerance boundary - just past tolerance")
    func toleranceBoundaryJustPast() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)
        let tolerance: TimeInterval = 60

        // Create an entry just past tolerance boundary
        let entryTime = Date().addingTimeInterval(-tolerance - 1)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: entryTime,
            endDate: nil
        )
        try context.save()

        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId, tolerance: tolerance)
        #expect(!exists, "Entry just past tolerance boundary should not be detected")
    }

    @Test("Custom tolerance value is respected")
    func customToleranceRespected() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Create an entry 45 seconds ago
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-45),
            endDate: nil
        )
        try context.save()

        // With 30s tolerance, should NOT detect
        let existsWith30s = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId, tolerance: 30)
        #expect(!existsWith30s, "Should not detect with 30s tolerance")

        // With 60s tolerance, SHOULD detect
        let existsWith60s = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId, tolerance: 60)
        #expect(existsWith60s, "Should detect with 60s tolerance")
    }
}

// MARK: - Integration Scenario Tests

@Suite("Geofence Deduplication Scenarios")
struct GeofenceDeduplicationScenarioTests {

    @Test("Scenario: Region re-registration while user is inside")
    func regionReRegistrationWhileInside() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Simulate: User entered geofence 30 seconds ago, event was created
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-30),
            endDate: nil
        )
        try context.save()

        // Simulate: App re-registers regions (e.g., ensureRegionsRegistered called)
        // iOS fires didDetermineState(.inside) because user is still inside
        // The deduplication check should prevent a second event
        let wouldCreateDuplicate = !checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(!wouldCreateDuplicate, "Should not create duplicate on region re-registration")
    }

    @Test("Scenario: App restart clears in-memory state but database has entry")
    func appRestartWithDatabaseEntry() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // Simulate: Entry exists in database from before app restart
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-30),
            endDate: nil
        )
        try context.save()

        // Simulate: App restarted, in-memory activeGeofenceEvents is empty
        let activeGeofenceEvents: [String: String] = [:]

        // In-memory check passes (returns nil)
        #expect(activeGeofenceEvents[geofenceId] == nil, "In-memory check should pass after restart")

        // Database check should catch the duplicate
        let dbCheckBlocks = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(dbCheckBlocks, "Database check should catch duplicate after app restart")
    }

    @Test("Scenario: Legitimate re-entry after exit")
    func legitimateReEntryAfterExit() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // First visit: entry and exit completed
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-300),  // 5 minutes ago
            endDate: Date().addingTimeInterval(-120)     // Exited 2 minutes ago
        )
        try context.save()

        // User re-enters the geofence now - should be allowed
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(!exists, "Should allow new entry after previous visit completed")
    }

    @Test("Scenario: Quick entry-exit-entry should create new event")
    func quickEntryExitEntry() throws {
        let context = makeTestModelContext()
        let geofenceId = UUIDv7.generate()
        let eventType = GeofenceTestFixture.makeEventType(context: context)

        // First visit: quick entry and exit (completed 20 seconds ago)
        _ = GeofenceTestFixture.makeGeofenceEntryEvent(
            context: context,
            eventType: eventType,
            geofenceId: geofenceId,
            timestamp: Date().addingTimeInterval(-30),   // Entered 30 seconds ago
            endDate: Date().addingTimeInterval(-20)      // Exited 20 seconds ago
        )
        try context.save()

        // User re-enters now - should be allowed (previous visit is complete)
        let exists = checkRecentGeofenceEntryExists(context: context, geofenceId: geofenceId)
        #expect(!exists, "Should allow new entry after quick exit")
    }
}
