//
//  TestSupport.swift
//  trendyTests
//
//  Shared test utilities, factories, and fixtures
//  Provides deterministic test data builders for all test suites
//

import Foundation
import SwiftUI
@testable import trendy

// MARK: - SyncEngine Test Isolation

/// Clean up SyncEngine UserDefaults keys to prevent test pollution across parallel test runs.
/// Call this at the start of every test helper that creates SyncEngine dependencies.
func cleanupSyncEngineUserDefaults() {
    let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
    let pendingDeleteIdsKey = "sync_engine_pending_delete_ids_\(AppEnvironment.current.rawValue)"
    UserDefaults.standard.removeObject(forKey: cursorKey)
    UserDefaults.standard.removeObject(forKey: pendingDeleteIdsKey)
}

// MARK: - Deterministic Fixtures

/// Factory for creating deterministic Event fixtures
struct EventFixture {

    /// Create a basic event with fixed timestamp
    static func makeEvent(
        timestamp: Date = Date(timeIntervalSince1970: 1704067200), // 2024-01-01 00:00:00 UTC
        notes: String? = "Test event",
        sourceType: EventSourceType = .manual,
        isAllDay: Bool = false
    ) -> Event {
        let eventType = EventTypeFixture.makeEventType(name: "Test Type")
        return Event(
            timestamp: timestamp,
            eventType: eventType,
            notes: notes,
            sourceType: sourceType,
            isAllDay: isAllDay
        )
    }

    /// Create event with properties
    static func makeEventWithProperties(
        properties: [String: PropertyValue] = ["key": PropertyValue(type: .text, value: "value")]
    ) -> Event {
        let eventType = EventTypeFixture.makeEventType()
        return Event(
            timestamp: Date(timeIntervalSince1970: 1704067200),
            eventType: eventType,
            notes: nil,
            properties: properties
        )
    }
}

/// Factory for creating deterministic EventType fixtures
struct EventTypeFixture {

    /// Create a basic event type with fixed values
    static func makeEventType(
        name: String = "Workout",
        colorHex: String = "#FF5733",
        iconName: String = "figure.run"
    ) -> EventType {
        EventType(name: name, colorHex: colorHex, iconName: iconName)
    }

    /// Create a set of common event types
    static func makeCommonEventTypes() -> [EventType] {
        [
            makeEventType(name: "Exercise", colorHex: "#FF0000", iconName: "heart.fill"),
            makeEventType(name: "Reading", colorHex: "#00FF00", iconName: "book.fill"),
            makeEventType(name: "Meditation", colorHex: "#0000FF", iconName: "sparkles")
        ]
    }
}

/// Factory for creating deterministic API model fixtures
struct APIModelFixture {

    /// Create a basic APIEventType
    static func makeAPIEventType(
        id: String = "type-1",
        userId: String = "user-1",
        name: String = "Workout",
        color: String = "#FF5733",
        icon: String = "figure.run"
    ) -> APIEventType {
        APIEventType(
            id: id,
            userId: userId,
            name: name,
            color: color,
            icon: icon,
            createdAt: Date(timeIntervalSince1970: 1704067200),
            updatedAt: Date(timeIntervalSince1970: 1704067200)
        )
    }

    /// Create a basic APIEvent
    static func makeAPIEvent(
        id: String = "evt-1",
        userId: String = "user-1",
        eventTypeId: String = "type-1",
        timestamp: Date = Date(timeIntervalSince1970: 1704067200),
        notes: String? = "Test event",
        geofenceId: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        locationName: String? = nil,
        healthKitSampleId: String? = nil,
        healthKitCategory: String? = nil,
        eventType: APIEventType? = nil
    ) -> APIEvent {
        APIEvent(
            id: id,
            userId: userId,
            eventTypeId: eventTypeId,
            timestamp: timestamp,
            notes: notes,
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",
            externalId: nil,
            originalTitle: nil,
            geofenceId: geofenceId,
            locationLatitude: locationLatitude,
            locationLongitude: locationLongitude,
            locationName: locationName,
            healthKitSampleId: healthKitSampleId,
            healthKitCategory: healthKitCategory,
            properties: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            eventType: eventType
        )
    }

    /// Create CreateEventRequest with defaults
    static func makeCreateEventRequest(
        id: String = UUIDv7.generate(),
        eventTypeId: String = "type-1",
        timestamp: Date = Date(timeIntervalSince1970: 1704067200),
        notes: String? = "Test event",
        properties: [String: APIPropertyValue] = [:]
    ) -> CreateEventRequest {
        CreateEventRequest(
            id: id,
            eventTypeId: eventTypeId,
            timestamp: timestamp,
            notes: notes,
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
            properties: properties
        )
    }

    // MARK: - Change Feed Fixtures

    /// Create a ChangeFeedResponse
    static func makeChangeFeedResponse(
        changes: [ChangeEntry] = [],
        nextCursor: Int64 = 0,
        hasMore: Bool = false
    ) -> ChangeFeedResponse {
        ChangeFeedResponse(
            changes: changes,
            nextCursor: nextCursor,
            hasMore: hasMore
        )
    }

    /// Create a ChangeEntry for create operation
    static func makeChangeEntry(
        id: Int64 = 1,
        entityType: String = "event",
        operation: String = "create",
        entityId: String = "entity-1",
        data: ChangeEntryData? = nil,
        deletedAt: Date? = nil
    ) -> ChangeEntry {
        ChangeEntry(
            id: id,
            entityType: entityType,
            operation: operation,
            entityId: entityId,
            data: data,
            deletedAt: deletedAt,
            createdAt: Date(timeIntervalSince1970: 1704067200)
        )
    }

    // MARK: - Geofence Fixtures

    /// Create an APIGeofence
    static func makeAPIGeofence(
        id: String = "geo-1",
        userId: String = "user-1",
        name: String = "Home",
        latitude: Double = 37.7749,
        longitude: Double = -122.4194,
        radius: Double = 100.0,
        eventTypeEntryId: String? = nil,
        eventTypeExitId: String? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = true,
        notifyOnExit: Bool = false
    ) -> APIGeofence {
        // APIGeofence uses custom decoder, but we can create JSON and decode
        // For simplicity, use a helper that creates the JSON and decodes
        let json: [String: Any] = [
            "id": id,
            "user_id": userId,
            "name": name,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "event_type_entry_id": eventTypeEntryId as Any,
            "event_type_exit_id": eventTypeExitId as Any,
            "is_active": isActive,
            "notify_on_entry": notifyOnEntry,
            "notify_on_exit": notifyOnExit,
            "ios_region_identifier": nil as Any?,
            "created_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1704067200)),
            "updated_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1704067200))
        ]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(APIGeofence.self, from: data)
    }

    /// Create a CreateGeofenceRequest
    static func makeCreateGeofenceRequest(
        id: String? = nil,
        name: String = "Test Geofence",
        latitude: Double = 37.7749,
        longitude: Double = -122.4194,
        radius: Double = 100.0,
        eventTypeEntryId: String? = nil,
        eventTypeExitId: String? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = true,
        notifyOnExit: Bool = false
    ) -> CreateGeofenceRequest {
        CreateGeofenceRequest(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            eventTypeEntryId: eventTypeEntryId,
            eventTypeExitId: eventTypeExitId,
            isActive: isActive,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )
    }

    // MARK: - Property Definition Fixtures

    /// Create an APIPropertyDefinition
    static func makeAPIPropertyDefinition(
        id: String = "propdef-1",
        eventTypeId: String = "type-1",
        userId: String = "user-1",
        key: String = "duration",
        label: String = "Duration",
        propertyType: String = "number",
        options: [String]? = nil,
        displayOrder: Int = 0
    ) -> APIPropertyDefinition {
        APIPropertyDefinition(
            id: id,
            eventTypeId: eventTypeId,
            userId: userId,
            key: key,
            label: label,
            propertyType: propertyType,
            options: options,
            defaultValue: nil,
            displayOrder: displayOrder,
            createdAt: Date(timeIntervalSince1970: 1704067200),
            updatedAt: Date(timeIntervalSince1970: 1704067200)
        )
    }

    /// Create a CreatePropertyDefinitionRequest
    static func makeCreatePropertyDefinitionRequest(
        id: String = "propdef-1",
        eventTypeId: String = "type-1",
        key: String = "duration",
        label: String = "Duration",
        propertyType: String = "number",
        options: [String]? = nil,
        displayOrder: Int = 0
    ) -> CreatePropertyDefinitionRequest {
        CreatePropertyDefinitionRequest(
            id: id,
            eventTypeId: eventTypeId,
            key: key,
            label: label,
            propertyType: propertyType,
            options: options,
            defaultValue: nil,
            displayOrder: displayOrder
        )
    }

    // MARK: - Batch Response Fixtures

    /// Create a BatchCreateEventsResponse
    static func makeBatchCreateEventsResponse(
        created: [APIEvent] = [],
        errors: [BatchError]? = nil,
        total: Int? = nil,
        success: Int? = nil,
        failed: Int? = nil
    ) -> BatchCreateEventsResponse {
        BatchCreateEventsResponse(
            created: created,
            errors: errors,
            total: total ?? created.count,
            success: success ?? created.count,
            failed: failed ?? (errors?.count ?? 0)
        )
    }

    /// Create a BatchError
    static func makeBatchError(
        index: Int = 0,
        message: String = "Validation failed"
    ) -> BatchError {
        BatchError(index: index, message: message)
    }

    // MARK: - Event Type Request Fixtures

    /// Create a CreateEventTypeRequest
    static func makeCreateEventTypeRequest(
        id: String = "type-1",
        name: String = "Workout",
        color: String = "#FF5733",
        icon: String = "figure.run"
    ) -> CreateEventTypeRequest {
        CreateEventTypeRequest(
            id: id,
            name: name,
            color: color,
            icon: icon
        )
    }

    /// Create an UpdateEventTypeRequest
    static func makeUpdateEventTypeRequest(
        name: String? = nil,
        color: String? = nil,
        icon: String? = nil
    ) -> UpdateEventTypeRequest {
        UpdateEventTypeRequest(
            name: name,
            color: color,
            icon: icon
        )
    }
}

/// Factory for creating deterministic PropertyValue fixtures
struct PropertyValueFixture {

    static func makeTextProperty(value: String = "Sample") -> PropertyValue {
        PropertyValue(type: .text, value: value)
    }

    static func makeNumberProperty(value: Int = 42) -> PropertyValue {
        PropertyValue(type: .number, value: value)
    }

    static func makeBooleanProperty(value: Bool = true) -> PropertyValue {
        PropertyValue(type: .boolean, value: value)
    }

    static func makeDateProperty(value: Date = Date(timeIntervalSince1970: 1704067200)) -> PropertyValue {
        PropertyValue(type: .date, value: value)
    }

    static func makeSelectProperty(value: String = "Option A") -> PropertyValue {
        PropertyValue(type: .select, value: value)
    }
}

// MARK: - Deterministic UUIDs

/// Provider for deterministic UUIDs (useful for tests that need stable IDs)
struct DeterministicUUID {

    /// Generate UUID from seed integer
    static func uuid(from seed: Int) -> UUID {
        let bytes = withUnsafeBytes(of: seed) { Array($0) }
        let paddedBytes = bytes + Array(repeating: UInt8(0), count: 16 - bytes.count)
        return UUID(uuid: (
            paddedBytes[0], paddedBytes[1], paddedBytes[2], paddedBytes[3],
            paddedBytes[4], paddedBytes[5], paddedBytes[6], paddedBytes[7],
            paddedBytes[8], paddedBytes[9], paddedBytes[10], paddedBytes[11],
            paddedBytes[12], paddedBytes[13], paddedBytes[14], paddedBytes[15]
        ))
    }

    /// Common fixed UUIDs for tests
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let one = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let two = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
}

// MARK: - Deterministic Dates

/// Provider for deterministic dates
struct DeterministicDate {

    /// 2024-01-01 00:00:00 UTC
    static let jan1_2024 = Date(timeIntervalSince1970: 1704067200)

    /// 2024-06-15 12:00:00 UTC
    static let jun15_2024 = Date(timeIntervalSince1970: 1718452800)

    /// 2024-12-31 23:59:59 UTC
    static let dec31_2024 = Date(timeIntervalSince1970: 1735689599)

    /// Create date from components (UTC)
    static func make(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(identifier: "UTC")

        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - JSON Test Helpers

/// Helper for creating JSON data from dictionaries
struct JSONHelper {

    /// Convert dictionary to JSON Data
    static func jsonData(from dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict, options: [])
    }

    /// Convert JSON string to Data
    static func jsonData(from string: String) -> Data? {
        string.data(using: .utf8)
    }

    /// Decode JSON string to type
    static func decode<T: Decodable>(_ type: T.Type, from string: String, dateStrategy: JSONDecoder.DateDecodingStrategy = .iso8601) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateStrategy
        guard let data = string.data(using: .utf8) else {
            throw JSONError.invalidString
        }
        return try decoder.decode(type, from: data)
    }

    enum JSONError: Error {
        case invalidString
    }
}

// MARK: - Test Errors

/// Simple error type for testing API error handling
struct TestError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

// MARK: - ChangeEntryData Factory

extension APIModelFixture {

    /// Create ChangeEntryData for an event type (for change feed tests)
    static func makeChangeEntryDataForEventType(
        name: String = "Test Type",
        color: String = "#FF0000",
        icon: String = "star"
    ) -> ChangeEntryData? {
        let dict: [String: Any] = [
            "name": name,
            "color": color,
            "icon": icon
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(ChangeEntryData.self, from: jsonData)
    }

    /// Create ChangeEntryData for an event (for change feed tests)
    static func makeChangeEntryDataForEvent(
        eventTypeId: String = "type-1",
        timestamp: Date = Date(timeIntervalSince1970: 1704067200),
        notes: String? = nil
    ) -> ChangeEntryData? {
        var dict: [String: Any] = [
            "event_type_id": eventTypeId,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "is_all_day": false,
            "source_type": "manual"
        ]
        if let notes = notes {
            dict["notes"] = notes
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(ChangeEntryData.self, from: jsonData)
    }
}

/// Helper to create ChangeEntryData from dictionary (uses JSON round-trip)
func makeChangeEntryData(from dict: [String: AnyCodableValue]) -> ChangeEntryData? {
    // ChangeEntryData uses custom Codable, so we need to JSON round-trip
    guard let jsonData = try? JSONEncoder().encode(dict) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(ChangeEntryData.self, from: jsonData)
}

// MARK: - Assertion Helpers

/// Custom assertion helpers for common patterns
struct AssertHelpers {

    /// Assert that two dates are equal within a tolerance (useful for timestamp comparisons)
    static func assertDatesEqual(_ date1: Date, _ date2: Date, tolerance: TimeInterval = 1.0, message: String = "Dates should be equal within tolerance") -> Bool {
        abs(date1.timeIntervalSince(date2)) <= tolerance
    }

    /// Assert that two doubles are approximately equal
    static func assertDoublesEqual(_ value1: Double, _ value2: Double, tolerance: Double = 0.0001, message: String = "Doubles should be approximately equal") -> Bool {
        abs(value1 - value2) <= tolerance
    }
}

// MARK: - Mock Helpers

/// Mock configuration for testing (to be expanded as needed)
struct MockConfiguration {

    static func makeAPIConfiguration(baseURL: String = "http://localhost:8080/api/v1") -> APIConfiguration {
        APIConfiguration(baseURL: baseURL)
    }

    static func makeSupabaseConfiguration(
        url: String = "http://localhost:54321",
        anonKey: String = "test-anon-key"
    ) -> SupabaseConfiguration {
        SupabaseConfiguration(url: url, anonKey: anonKey)
    }
}
