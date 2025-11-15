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
            properties: nil,
            createdAt: timestamp,
            updatedAt: timestamp,
            eventType: eventType
        )
    }

    /// Create CreateEventRequest with defaults
    static func makeCreateEventRequest(
        eventTypeId: String = "type-1",
        timestamp: Date = Date(timeIntervalSince1970: 1704067200),
        notes: String? = "Test event"
    ) -> CreateEventRequest {
        CreateEventRequest(
            eventTypeId: eventTypeId,
            timestamp: timestamp,
            notes: notes,
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",
            externalId: nil,
            originalTitle: nil,
            properties: nil
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
