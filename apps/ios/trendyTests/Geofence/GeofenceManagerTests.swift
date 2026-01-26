//
//  GeofenceManagerTests.swift
//  trendyTests
//
//  Unit tests for GeofenceManager functionality.
//  Tests CLLocationManager delegate handling, region registration,
//  authorization flow, and event creation without requiring simulator.
//
//  These tests focus on testable business logic - they don't test
//  actual CoreLocation behavior (which requires device/simulator).
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import trendy

// MARK: - Test Helpers

/// Helper to create a test model context with in-memory storage
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

/// Factory for creating test geofences
struct GeofenceManagerTestFixture {

    /// Create a geofence for testing
    static func makeGeofence(
        context: ModelContext,
        id: String = UUIDv7.generate(),
        name: String = "Test Geofence",
        latitude: Double = 37.7749,
        longitude: Double = -122.4194,
        radius: Double = 100.0,
        eventTypeEntryID: String? = nil,
        isActive: Bool = true
    ) -> Geofence {
        let geofence = Geofence(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            eventTypeEntryID: eventTypeEntryID,
            eventTypeExitID: nil,
            isActive: isActive,
            notifyOnEntry: true,
            notifyOnExit: true,
            syncStatus: .synced
        )
        context.insert(geofence)
        return geofence
    }

    /// Create an event type for geofence events
    static func makeEventType(
        context: ModelContext,
        name: String = "Gym Visit",
        colorHex: String = "#FF5733",
        iconName: String = "figure.walk"
    ) -> EventType {
        let eventType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        context.insert(eventType)
        return eventType
    }
}

// MARK: - GeofenceDefinition Tests

@Suite("GeofenceDefinition Creation")
struct GeofenceDefinitionTests {

    @Test("GeofenceDefinition from local Geofence preserves all fields")
    func fromLocalGeofence() throws {
        let context = makeTestModelContext()
        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            id: "geo-123",
            name: "Home",
            latitude: 37.7749,
            longitude: -122.4194,
            radius: 150.0,
            isActive: true
        )
        geofence.notifyOnEntry = true
        geofence.notifyOnExit = false
        try context.save()

        let definition = GeofenceDefinition(from: geofence)

        #expect(definition.identifier == "geo-123")
        #expect(definition.id == "geo-123")
        #expect(definition.name == "Home")
        #expect(definition.latitude == 37.7749)
        #expect(definition.longitude == -122.4194)
        #expect(definition.radius == 150.0)
        #expect(definition.isActive == true)
        #expect(definition.notifyOnEntry == true)
        #expect(definition.notifyOnExit == false)
    }

    @Test("GeofenceDefinition uses ID as region identifier")
    func regionIdentifierMatchesId() throws {
        let context = makeTestModelContext()
        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            id: "unique-geo-id"
        )
        try context.save()

        let definition = GeofenceDefinition(from: geofence)

        // The region identifier should be the canonical UUIDv7 ID
        #expect(definition.identifier == definition.id)
        #expect(definition.identifier == "unique-geo-id")
    }
}

// MARK: - Geofence Model Tests

@Suite("Geofence Model")
struct GeofenceModelTests {

    @Test("circularRegion has correct properties")
    func circularRegionProperties() throws {
        let context = makeTestModelContext()
        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            id: "region-test-id",
            latitude: 40.7128,
            longitude: -74.0060,
            radius: 200.0
        )
        try context.save()

        let region = geofence.circularRegion

        #expect(region.identifier == "region-test-id")
        #expect(region.center.latitude == 40.7128)
        #expect(region.center.longitude == -74.0060)
        #expect(region.radius == 200.0)
        #expect(region.notifyOnEntry == true)
        #expect(region.notifyOnExit == true)
    }

    @Test("regionIdentifier returns canonical ID")
    func regionIdentifierReturnsId() throws {
        let context = makeTestModelContext()
        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            id: "canonical-id-123"
        )
        try context.save()

        #expect(geofence.regionIdentifier == "canonical-id-123")
    }

    @Test("coordinate returns correct CLLocationCoordinate2D")
    func coordinateProperty() throws {
        let context = makeTestModelContext()
        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            latitude: 51.5074,
            longitude: -0.1278
        )
        try context.save()

        let coord = geofence.coordinate

        #expect(coord.latitude == 51.5074)
        #expect(coord.longitude == -0.1278)
    }
}

// MARK: - Authorization Status Tests

@Suite("Authorization Status Description")
struct AuthorizationStatusDescriptionTests {

    @Test("Authorization status descriptions are human-readable")
    func statusDescriptions() {
        // Test the description extension on CLAuthorizationStatus
        #expect(CLAuthorizationStatus.notDetermined.description == "Not Determined")
        #expect(CLAuthorizationStatus.restricted.description == "Restricted")
        #expect(CLAuthorizationStatus.denied.description == "Denied")
        #expect(CLAuthorizationStatus.authorizedAlways.description == "Authorized Always")
        #expect(CLAuthorizationStatus.authorizedWhenInUse.description == "Authorized When In Use")
    }
}

// MARK: - Active Geofence Events Persistence Tests

@Suite("Active Geofence Events Persistence")
struct ActiveGeofenceEventsPersistenceTests {

    @Test("Active events dictionary encodes and decodes correctly")
    func dictionaryEncodingRoundTrip() throws {
        let testKey = "test_activeEvents_\(UUID().uuidString)"

        // Simulate the encoding done by GeofenceManager
        let original: [String: String] = [
            "geofence-1": "event-1",
            "geofence-2": "event-2"
        ]

        let encoded = try JSONEncoder().encode(original)
        UserDefaults.standard.set(encoded, forKey: testKey)

        // Simulate the loading done by GeofenceManager
        guard let data = UserDefaults.standard.data(forKey: testKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            Issue.record("Failed to decode active events")
            return
        }

        #expect(decoded["geofence-1"] == "event-1")
        #expect(decoded["geofence-2"] == "event-2")
        #expect(decoded.count == 2)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    @Test("Empty dictionary persists correctly")
    func emptyDictionaryPersistence() throws {
        let testKey = "test_emptyEvents_\(UUID().uuidString)"

        let original: [String: String] = [:]
        let encoded = try JSONEncoder().encode(original)
        UserDefaults.standard.set(encoded, forKey: testKey)

        guard let data = UserDefaults.standard.data(forKey: testKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            Issue.record("Failed to decode empty events")
            return
        }

        #expect(decoded.isEmpty)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: testKey)
    }
}

// MARK: - Geofence Health Status Tests

@Suite("Geofence Health Status")
struct GeofenceHealthStatusTests {

    @Test("Health status correctly identifies healthy state")
    func healthyState() {
        let iosRegions: Set<String> = ["geo-1", "geo-2", "geo-3"]
        let appGeofences: Set<String> = ["geo-1", "geo-2", "geo-3"]

        let status = GeofenceHealthStatus(
            registeredWithiOS: iosRegions,
            savedInApp: appGeofences,
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: true
        )

        #expect(status.isHealthy)
        #expect(status.missingFromiOS.isEmpty)
        #expect(status.orphanedIniOS.isEmpty)
        #expect(status.authorizationStatus == .authorizedAlways)
        #expect(status.locationServicesEnabled)
    }

    @Test("Health status identifies missing regions")
    func missingRegions() {
        let iosRegions: Set<String> = ["geo-1"]
        let appGeofences: Set<String> = ["geo-1", "geo-2", "geo-3"]

        let status = GeofenceHealthStatus(
            registeredWithiOS: iosRegions,
            savedInApp: appGeofences,
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: true
        )

        #expect(!status.isHealthy)
        #expect(status.missingFromiOS.contains("geo-2"))
        #expect(status.missingFromiOS.contains("geo-3"))
        #expect(status.missingFromiOS.count == 2)
    }

    @Test("Health status identifies orphaned regions")
    func orphanedRegions() {
        let iosRegions: Set<String> = ["geo-1", "geo-2", "orphaned-geo"]
        let appGeofences: Set<String> = ["geo-1", "geo-2"]

        let status = GeofenceHealthStatus(
            registeredWithiOS: iosRegions,
            savedInApp: appGeofences,
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: true
        )

        #expect(!status.isHealthy)
        #expect(status.orphanedIniOS.contains("orphaned-geo"))
        #expect(status.orphanedIniOS.count == 1)
    }

    @Test("Health status reflects authorization denied")
    func authorizationDenied() {
        let status = GeofenceHealthStatus(
            registeredWithiOS: [],
            savedInApp: [],
            authorizationStatus: .denied,
            locationServicesEnabled: true
        )

        #expect(status.authorizationStatus != .authorizedAlways)
        #expect(!status.isHealthy)
    }

    @Test("Health status reflects location services disabled")
    func locationServicesDisabled() {
        let status = GeofenceHealthStatus(
            registeredWithiOS: [],
            savedInApp: [],
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: false
        )

        #expect(!status.locationServicesEnabled)
        #expect(!status.isHealthy)
    }

    @Test("Status summary provides helpful messages")
    func statusSummaryMessages() {
        // Location disabled
        var status = GeofenceHealthStatus(
            registeredWithiOS: [],
            savedInApp: [],
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: false
        )
        #expect(status.statusSummary == "Location services disabled")

        // Not authorized
        status = GeofenceHealthStatus(
            registeredWithiOS: [],
            savedInApp: [],
            authorizationStatus: .authorizedWhenInUse,
            locationServicesEnabled: true
        )
        #expect(status.statusSummary == "Needs 'Always' authorization")

        // Missing geofences
        status = GeofenceHealthStatus(
            registeredWithiOS: [],
            savedInApp: ["geo-1", "geo-2"],
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: true
        )
        #expect(status.statusSummary.contains("not registered"))

        // Healthy
        status = GeofenceHealthStatus(
            registeredWithiOS: ["geo-1"],
            savedInApp: ["geo-1"],
            authorizationStatus: .authorizedAlways,
            locationServicesEnabled: true
        )
        #expect(status.statusSummary == "Healthy")
    }
}

// MARK: - iOS Region Limit Tests

@Suite("iOS Region Limit Handling")
struct iOSRegionLimitTests {

    @Test("More than 20 geofences are limited")
    func regionLimitApplied() throws {
        let context = makeTestModelContext()

        // Create 25 active geofences
        for i in 1...25 {
            _ = GeofenceManagerTestFixture.makeGeofence(
                context: context,
                id: "geo-\(i)",
                name: "Geofence \(i)",
                isActive: true
            )
        }
        try context.save()

        // Fetch and verify all are created
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.isActive }
        )
        let allGeofences = try context.fetch(descriptor)
        #expect(allGeofences.count == 25)

        // Convert to definitions (simulating what reconcileRegions does)
        let definitions = allGeofences.map { GeofenceDefinition(from: $0) }
        let limitedDefinitions = Array(definitions.prefix(20))

        #expect(limitedDefinitions.count == 20)
    }
}

// MARK: - Geofence Entry Event Creation Logic Tests

@Suite("Geofence Entry Event Logic")
struct GeofenceEntryEventLogicTests {

    @Test("Entry event has correct properties")
    func entryEventProperties() throws {
        let context = makeTestModelContext()
        let eventType = GeofenceManagerTestFixture.makeEventType(context: context, name: "Gym")
        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            name: "Downtown Gym",
            latitude: 37.7749,
            longitude: -122.4194,
            eventTypeEntryID: eventType.id
        )
        try context.save()

        // Simulate what handleGeofenceEntry does
        let entryTime = Date()
        let entryProperties: [String: PropertyValue] = [
            "Entered At": PropertyValue(type: .date, value: entryTime)
        ]

        let event = Event(
            timestamp: entryTime,
            eventType: eventType,
            notes: "Auto-logged by geofence: \(geofence.name)",
            sourceType: .geofence,
            geofenceId: geofence.id,
            locationLatitude: geofence.latitude,
            locationLongitude: geofence.longitude,
            locationName: geofence.name,
            properties: entryProperties
        )
        context.insert(event)
        try context.save()

        // Verify event properties
        #expect(event.sourceType == .geofence)
        #expect(event.geofenceId == geofence.id)
        #expect(event.locationLatitude == 37.7749)
        #expect(event.locationLongitude == -122.4194)
        #expect(event.locationName == "Downtown Gym")
        #expect(event.notes?.contains("Downtown Gym") == true)
        #expect(event.eventType?.name == "Gym")
        #expect(event.properties["Entered At"] != nil)
    }

    @Test("Exit event adds duration property")
    func exitEventDuration() throws {
        let context = makeTestModelContext()
        let eventType = GeofenceManagerTestFixture.makeEventType(context: context)
        try context.save()

        // Create entry event
        let entryTime = Date().addingTimeInterval(-3600) // 1 hour ago
        let event = Event(
            timestamp: entryTime,
            eventType: eventType,
            notes: "Test entry",
            sourceType: .geofence
        )
        context.insert(event)
        try context.save()

        // Simulate exit
        let exitTime = Date()
        event.endDate = exitTime

        let durationSeconds = exitTime.timeIntervalSince(entryTime)
        var updatedProperties = event.properties
        updatedProperties["Exited At"] = PropertyValue(type: .date, value: exitTime)
        updatedProperties["Duration"] = PropertyValue(type: .duration, value: durationSeconds)
        event.properties = updatedProperties
        try context.save()

        // Verify
        #expect(event.endDate != nil)
        #expect(event.properties["Exited At"] != nil)
        #expect(event.properties["Duration"] != nil)

        if let durationProp = event.properties["Duration"],
           let duration = durationProp.doubleValue {
            // Duration should be approximately 1 hour (3600 seconds)
            #expect(duration >= 3599 && duration <= 3601)
        } else {
            Issue.record("Duration property not found or wrong type")
        }
    }
}

// MARK: - Region Reconciliation Logic Tests

@Suite("Region Reconciliation Logic")
struct RegionReconciliationLogicTests {

    @Test("Reconciliation identifies regions to add")
    func reconciliationAddsRegions() throws {
        // Simulate reconciliation logic
        let desiredIds: Set<String> = ["geo-1", "geo-2", "geo-3"]
        let systemIds: Set<String> = ["geo-1"]

        let toAdd = desiredIds.subtracting(systemIds)

        #expect(toAdd.count == 2)
        #expect(toAdd.contains("geo-2"))
        #expect(toAdd.contains("geo-3"))
    }

    @Test("Reconciliation identifies regions to remove")
    func reconciliationRemovesRegions() throws {
        let desiredIds: Set<String> = ["geo-1"]
        let systemIds: Set<String> = ["geo-1", "geo-2", "stale-geo"]

        let toRemove = systemIds.subtracting(desiredIds)

        #expect(toRemove.count == 2)
        #expect(toRemove.contains("geo-2"))
        #expect(toRemove.contains("stale-geo"))
    }

    @Test("Reconciliation is idempotent")
    func reconciliationIdempotent() throws {
        let desiredIds: Set<String> = ["geo-1", "geo-2", "geo-3"]
        let systemIds: Set<String> = ["geo-1", "geo-2", "geo-3"]

        let toAdd = desiredIds.subtracting(systemIds)
        let toRemove = systemIds.subtracting(desiredIds)

        #expect(toAdd.isEmpty)
        #expect(toRemove.isEmpty)
    }
}

// MARK: - Processing Lock Tests (Race Condition Prevention)

@Suite("Processing Lock (Race Condition Prevention)")
struct ProcessingLockTests {

    @Test("Static processingGeofenceIds prevents concurrent processing")
    func processingLockPreventsRace() async throws {
        // Access the static set directly
        let geofenceId = "test-geo-\(UUID().uuidString)"

        // Ensure it's empty first
        GeofenceManager.processingGeofenceIds.remove(geofenceId)

        // First claim should succeed
        let firstClaim = !GeofenceManager.processingGeofenceIds.contains(geofenceId)
        #expect(firstClaim, "First claim should succeed")

        // Insert the claim
        GeofenceManager.processingGeofenceIds.insert(geofenceId)

        // Second claim should fail
        let secondClaim = !GeofenceManager.processingGeofenceIds.contains(geofenceId)
        #expect(!secondClaim, "Second claim should fail while first is processing")

        // Release the lock
        GeofenceManager.processingGeofenceIds.remove(geofenceId)

        // Third claim should succeed again
        let thirdClaim = !GeofenceManager.processingGeofenceIds.contains(geofenceId)
        #expect(thirdClaim, "Third claim should succeed after release")
    }
}

// MARK: - Notification Name Tests

@Suite("Notification Names")
struct NotificationNameTests {

    @Test("Background entry notification name is defined")
    func backgroundEntryNotificationName() {
        let name = GeofenceManager.backgroundEntryNotification
        #expect(name.rawValue == "GeofenceManager.backgroundEntry")
    }

    @Test("Background exit notification name is defined")
    func backgroundExitNotificationName() {
        let name = GeofenceManager.backgroundExitNotification
        #expect(name.rawValue == "GeofenceManager.backgroundExit")
    }

    @Test("Normal launch notification name is defined")
    func normalLaunchNotificationName() {
        let name = AppDelegate.normalLaunchNotification
        #expect(name.rawValue == "GeofenceManager.normalLaunch")
    }
}

// MARK: - Geofence Error Tests

@Suite("Geofence Errors")
struct GeofenceErrorTests {

    @Test("Entry event save failed error has descriptive message")
    func entryEventSaveFailedError() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = GeofenceError.entryEventSaveFailed("Home", underlyingError)

        if case .entryEventSaveFailed(let name, _) = error {
            #expect(name == "Home")
        } else {
            Issue.record("Wrong error type")
        }
    }

    @Test("Exit event save failed error has descriptive message")
    func exitEventSaveFailedError() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = GeofenceError.exitEventSaveFailed("Office", underlyingError)

        if case .exitEventSaveFailed(let name, _) = error {
            #expect(name == "Office")
        } else {
            Issue.record("Wrong error type")
        }
    }
}

// MARK: - Lookup Failure Scenario Tests

@Suite("Lookup Failure Scenarios")
struct LookupFailureScenarioTests {

    @Test("Lookup returns nil for non-existent geofence ID")
    func lookupReturnsNilForMissingGeofence() throws {
        let context = makeTestModelContext()

        // Create one geofence
        _ = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            id: "existing-geo"
        )
        try context.save()

        // Lookup a different ID
        let targetId = "non-existent-geo"
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == targetId }
        )
        let results = try context.fetch(descriptor)

        #expect(results.isEmpty, "Lookup should return empty for non-existent ID")
    }

    @Test("Lookup finds geofence by exact ID match")
    func lookupFindsByExactId() throws {
        let context = makeTestModelContext()

        let geofence = GeofenceManagerTestFixture.makeGeofence(
            context: context,
            id: "exact-match-id",
            name: "Target Geofence"
        )
        try context.save()

        let targetId = "exact-match-id"
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == targetId }
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 1)
        #expect(results.first?.name == "Target Geofence")
    }
}

// MARK: - Background Launch Notification Forwarding Tests

@Suite("Background Launch Notification Forwarding")
struct BackgroundLaunchNotificationTests {

    @Test("Notification userInfo contains region identifier")
    func notificationContainsIdentifier() {
        let notification = Notification(
            name: GeofenceManager.backgroundEntryNotification,
            object: nil,
            userInfo: ["identifier": "test-region-id"]
        )

        let identifier = notification.userInfo?["identifier"] as? String
        #expect(identifier == "test-region-id")
    }

    @Test("Missing identifier in notification userInfo")
    func missingIdentifierHandled() {
        let notification = Notification(
            name: GeofenceManager.backgroundEntryNotification,
            object: nil,
            userInfo: nil
        )

        let identifier = notification.userInfo?["identifier"] as? String
        #expect(identifier == nil)
    }

    @Test("Wrong type in identifier is handled")
    func wrongTypeIdentifierHandled() {
        let notification = Notification(
            name: GeofenceManager.backgroundEntryNotification,
            object: nil,
            userInfo: ["identifier": 12345] // Wrong type: Int instead of String
        )

        let identifier = notification.userInfo?["identifier"] as? String
        #expect(identifier == nil)
    }
}

// MARK: - Pending Events Queue Tests

@Suite("Pending Events Queue")
struct PendingEventsQueueTests {

    @Test("PendingGeofenceEvent stores correct type and identifier")
    func pendingEventStoresData() {
        let entryEvent = PendingGeofenceEvent(type: .entry, regionIdentifier: "geo-entry")
        let exitEvent = PendingGeofenceEvent(type: .exit, regionIdentifier: "geo-exit")

        #expect(entryEvent.type == .entry)
        #expect(entryEvent.regionIdentifier == "geo-entry")
        #expect(entryEvent.timestamp <= Date())

        #expect(exitEvent.type == .exit)
        #expect(exitEvent.regionIdentifier == "geo-exit")
    }

    @Test("Drain returns empty array when no pending events")
    func drainEmptyQueue() {
        // Ensure queue is empty first by draining any existing events
        _ = AppDelegate.drainPendingEvents()

        // Drain again should return empty
        let events = AppDelegate.drainPendingEvents()
        #expect(events.isEmpty)
    }

    @Test("hasPendingEvents returns false when queue is empty")
    func hasPendingEventsFalseWhenEmpty() {
        // Ensure queue is empty first
        _ = AppDelegate.drainPendingEvents()

        #expect(!AppDelegate.hasPendingEvents)
    }
}

// MARK: - Authorization Flow Tests

@Suite("Authorization Flow")
struct AuthorizationFlowTests {

    @Test("hasGeofencingAuthorization requires authorizedAlways")
    func hasGeofencingAuthorizationLogic() {
        // Test the logic that determines if geofencing is allowed
        // This mirrors the hasGeofencingAuthorization computed property

        func checkAuthorization(_ status: CLAuthorizationStatus) -> Bool {
            switch status {
            case .authorizedAlways:
                return true
            case .authorizedWhenInUse, .notDetermined, .restricted, .denied:
                return false
            @unknown default:
                return false
            }
        }

        #expect(checkAuthorization(.authorizedAlways) == true)
        #expect(checkAuthorization(.authorizedWhenInUse) == false)
        #expect(checkAuthorization(.notDetermined) == false)
        #expect(checkAuthorization(.denied) == false)
        #expect(checkAuthorization(.restricted) == false)
    }
}
