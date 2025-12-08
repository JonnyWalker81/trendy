//
//  EventSourceTypeTests.swift
//  trendyTests
//
//  Production-grade tests for EventSourceType enum
//
//  SUT: EventSourceType (manual vs imported event classification)
//
//  Assumptions:
//  - EventSourceType is a String-backed enum
//  - Two cases: .manual (user-created) and .imported (from calendar/external)
//  - Conforms to Codable for backend API serialization
//  - Conforms to CaseIterable for iteration
//
//  Covered Behaviors:
//  ✅ Raw value mapping ("manual", "imported")
//  ✅ Codable roundtrip encoding/decoding
//  ✅ CaseIterable provides all cases
//  ✅ String initialization (from raw value)
//  ✅ JSON encoding/decoding matches backend format
//
//  Intentionally Omitted:
//  - Business logic (tested in Event/EventStore tests)
//  - UI presentation (out of scope for model tests)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Suite

@Suite("EventSourceType Basic Properties")
struct EventSourceTypeBasicTests {

    @Test("EventSourceType manual has correct raw value")
    func test_eventSourceType_manual_hasCorrectRawValue() {
        #expect(EventSourceType.manual.rawValue == "manual", "Manual raw value should be 'manual'")
    }

    @Test("EventSourceType imported has correct raw value")
    func test_eventSourceType_imported_hasCorrectRawValue() {
        #expect(EventSourceType.imported.rawValue == "imported", "Imported raw value should be 'imported'")
    }

    @Test("EventSourceType can be initialized from raw value")
    func test_eventSourceType_initFromRawValue_succeeds() {
        let manual = EventSourceType(rawValue: "manual")
        let imported = EventSourceType(rawValue: "imported")

        #expect(manual == .manual, "Should initialize .manual from 'manual'")
        #expect(imported == .imported, "Should initialize .imported from 'imported'")
    }

    @Test("EventSourceType init from invalid raw value returns nil")
    func test_eventSourceType_initFromInvalidRawValue_returnsNil() {
        let invalid = EventSourceType(rawValue: "unknown")

        #expect(invalid == nil, "Invalid raw value should return nil")
    }
}

@Suite("EventSourceType CaseIterable")
struct EventSourceTypeCaseIterableTests {

    @Test("EventSourceType allCases contains all cases")
    func test_eventSourceType_allCases_containsAllCases() {
        let allCases = EventSourceType.allCases

        #expect(allCases.count == 2, "Should have exactly 2 cases")
        #expect(allCases.contains(.manual), "allCases should contain .manual")
        #expect(allCases.contains(.imported), "allCases should contain .imported")
    }

    @Test("EventSourceType allCases order is stable")
    func test_eventSourceType_allCases_orderIsStable() {
        let allCases = EventSourceType.allCases

        #expect(allCases[0] == .manual, "First case should be .manual")
        #expect(allCases[1] == .imported, "Second case should be .imported")
    }

    @Test("EventSourceType can iterate over all cases")
    func test_eventSourceType_iteration_works() {
        var count = 0
        var foundManual = false
        var foundImported = false

        for type in EventSourceType.allCases {
            count += 1
            if type == .manual { foundManual = true }
            if type == .imported { foundImported = true }
        }

        #expect(count == 2, "Should iterate over 2 cases")
        #expect(foundManual, "Should find .manual during iteration")
        #expect(foundImported, "Should find .imported during iteration")
    }
}

@Suite("EventSourceType Codable")
struct EventSourceTypeCodableTests {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    @Test("EventSourceType manual encodes to JSON string")
    func test_eventSourceType_manual_encodesToJSONString() throws {
        let sourceType = EventSourceType.manual

        let encoded = try encoder.encode(sourceType)
        let json = String(data: encoded, encoding: .utf8)

        #expect(json == "\"manual\"", "Should encode as JSON string \"manual\": got \(json ?? "nil")")
    }

    @Test("EventSourceType imported encodes to JSON string")
    func test_eventSourceType_imported_encodesToJSONString() throws {
        let sourceType = EventSourceType.imported

        let encoded = try encoder.encode(sourceType)
        let json = String(data: encoded, encoding: .utf8)

        #expect(json == "\"imported\"", "Should encode as JSON string \"imported\": got \(json ?? "nil")")
    }

    @Test("EventSourceType manual decodes from JSON string")
    func test_eventSourceType_manual_decodesFromJSONString() throws {
        let json = "\"manual\"".data(using: .utf8)!

        let decoded = try decoder.decode(EventSourceType.self, from: json)

        #expect(decoded == .manual, "Should decode to .manual")
    }

    @Test("EventSourceType imported decodes from JSON string")
    func test_eventSourceType_imported_decodesFromJSONString() throws {
        let json = "\"imported\"".data(using: .utf8)!

        let decoded = try decoder.decode(EventSourceType.self, from: json)

        #expect(decoded == .imported, "Should decode to .imported")
    }

    @Test("EventSourceType roundtrip encoding/decoding preserves value")
    func test_eventSourceType_roundtrip_preservesValue() throws {
        let original = EventSourceType.manual

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(EventSourceType.self, from: encoded)

        #expect(decoded == original, "Roundtrip should preserve original value")
    }

    @Test("EventSourceType roundtrip for all cases", arguments: EventSourceType.allCases)
    func test_eventSourceType_roundtrip_allCases(sourceType: EventSourceType) throws {
        let encoded = try encoder.encode(sourceType)
        let decoded = try decoder.decode(EventSourceType.self, from: encoded)

        #expect(decoded == sourceType, "Roundtrip should preserve \(sourceType.rawValue)")
    }

    @Test("EventSourceType decoding invalid value throws error")
    func test_eventSourceType_decodingInvalidValue_throwsError() {
        let json = "\"unknown\"".data(using: .utf8)!

        #expect(throws: Error.self) {
            _ = try decoder.decode(EventSourceType.self, from: json)
        }
    }
}

@Suite("EventSourceType in Event Model")
struct EventSourceTypeInEventTests {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    @Test("Event with manual sourceType encodes correctly")
    func test_event_manualSourceType_encodesCorrectly() throws {
        let event = Event(
            timestamp: Date(),
            eventType: nil,
            notes: "Test",
            sourceType: .manual
        )

        // Can't directly test Event encoding (it's a SwiftData @Model),
        // but we verify the sourceType property is accessible and correct
        #expect(event.sourceType == .manual, "Event sourceType should be .manual")
        #expect(event.sourceType.rawValue == "manual", "Event sourceType raw value should be 'manual'")
    }

    @Test("Event with imported sourceType has correct properties")
    func test_event_importedSourceType_hasCorrectProperties() {
        let event = Event(
            timestamp: Date(),
            eventType: nil,
            notes: "Imported event",
            sourceType: .imported,
            externalId: "cal-123",
            originalTitle: "Calendar Event"
        )

        #expect(event.sourceType == .imported, "Event sourceType should be .imported")
        #expect(event.externalId == "cal-123", "Imported event should have external ID")
        #expect(event.originalTitle == "Calendar Event", "Imported event should have original title")
    }

    @Test("Event default sourceType is manual")
    func test_event_defaultSourceType_isManual() {
        let event = Event(timestamp: Date())

        #expect(event.sourceType == .manual, "Default sourceType should be .manual")
    }
}

@Suite("EventSourceType Equality")
struct EventSourceTypeEqualityTests {

    @Test("EventSourceType manual equals itself")
    func test_eventSourceType_manual_equalsItself() {
        #expect(EventSourceType.manual == EventSourceType.manual, ".manual should equal itself")
    }

    @Test("EventSourceType imported equals itself")
    func test_eventSourceType_imported_equalsItself() {
        #expect(EventSourceType.imported == EventSourceType.imported, ".imported should equal itself")
    }

    @Test("EventSourceType manual not equals imported")
    func test_eventSourceType_manual_notEqualsImported() {
        #expect(EventSourceType.manual != EventSourceType.imported, ".manual should not equal .imported")
    }

    @Test("EventSourceType equality via raw value comparison")
    func test_eventSourceType_equalityViaRawValue() {
        let manual1 = EventSourceType.manual
        let manual2 = EventSourceType(rawValue: "manual")!

        #expect(manual1 == manual2, "Should be equal when created from same raw value")
    }
}

@Suite("EventSourceType Backend API Compatibility")
struct EventSourceTypeAPICompatibilityTests {

    let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    @Test("CreateEventRequest with manual sourceType encodes correctly")
    func test_createEventRequest_manualSourceType_encodesCorrectly() throws {
        let request = CreateEventRequest(
            eventTypeId: "type-1",
            timestamp: Date(),
            notes: "Test",
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",  // String in API model
            externalId: nil,
            originalTitle: nil,
            geofenceId: nil,
            locationLatitude: nil,
            locationLongitude: nil,
            locationName: nil,
            properties: [:]
        )

        let encoded = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["source_type"] as? String == "manual", "source_type should be 'manual' in JSON")
    }

    @Test("CreateEventRequest with imported sourceType encodes correctly")
    func test_createEventRequest_importedSourceType_encodesCorrectly() throws {
        let request = CreateEventRequest(
            eventTypeId: "type-1",
            timestamp: Date(),
            notes: "Test",
            isAllDay: false,
            endDate: nil,
            sourceType: "imported",  // String in API model
            externalId: "cal-456",
            originalTitle: "Imported",
            geofenceId: nil,
            locationLatitude: nil,
            locationLongitude: nil,
            locationName: nil,
            properties: [:]
        )

        let encoded = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["source_type"] as? String == "imported", "source_type should be 'imported' in JSON")
        #expect(json?["external_id"] as? String == "cal-456", "external_id should be present for imported")
    }

    @Test("APIEvent with manual sourceType decodes correctly")
    func test_apiEvent_manualSourceType_decodesCorrectly() throws {
        let json = """
        {
            "id": "evt-1",
            "user_id": "user-1",
            "event_type_id": "type-1",
            "timestamp": "2024-01-01T00:00:00Z",
            "notes": "Test",
            "is_all_day": false,
            "end_date": null,
            "source_type": "manual",
            "external_id": null,
            "original_title": null,
            "properties": null,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
            "event_type": null
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIEvent.self, from: json)

        #expect(decoded.sourceType == "manual", "sourceType should be 'manual'")
    }

    @Test("APIEvent with imported sourceType decodes correctly")
    func test_apiEvent_importedSourceType_decodesCorrectly() throws {
        let json = """
        {
            "id": "evt-2",
            "user_id": "user-1",
            "event_type_id": "type-1",
            "timestamp": "2024-01-01T00:00:00Z",
            "notes": "Imported",
            "is_all_day": false,
            "end_date": null,
            "source_type": "imported",
            "external_id": "cal-123",
            "original_title": "Calendar Event",
            "properties": null,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
            "event_type": null
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIEvent.self, from: json)

        #expect(decoded.sourceType == "imported", "sourceType should be 'imported'")
        #expect(decoded.externalId == "cal-123", "externalId should be decoded")
        #expect(decoded.originalTitle == "Calendar Event", "originalTitle should be decoded")
    }
}

@Suite("EventSourceType Edge Cases")
struct EventSourceTypeEdgeCaseTests {

    @Test("EventSourceType string comparison is case-sensitive")
    func test_eventSourceType_stringComparison_caseSensitive() {
        let manual = EventSourceType(rawValue: "Manual")  // Uppercase M
        let imported = EventSourceType(rawValue: "IMPORTED")  // All uppercase

        #expect(manual == nil, "Uppercase 'Manual' should not initialize")
        #expect(imported == nil, "Uppercase 'IMPORTED' should not initialize")
    }

    @Test("EventSourceType raw values are lowercase")
    func test_eventSourceType_rawValues_areLowercase() {
        for sourceType in EventSourceType.allCases {
            let rawValue = sourceType.rawValue
            #expect(rawValue == rawValue.lowercased(), "Raw value '\(rawValue)' should be lowercase")
        }
    }
}

// MARK: - Performance Tests

@Suite("EventSourceType Performance")
struct EventSourceTypePerformanceTests {

    @Test("Performance: Encoding/decoding 10000 EventSourceType values")
    func test_performance_encodingDecoding_10000Values() {
        measureMetrics(
            description: "Encoding/decoding 10000 EventSourceType values",
            iterations: 10
        ) {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for i in 0..<10000 {
                let sourceType: EventSourceType = (i % 2 == 0) ? .manual : .imported

                if let encoded = try? encoder.encode(sourceType),
                   let _ = try? decoder.decode(EventSourceType.self, from: encoded) {
                    // Successfully roundtripped
                }
            }
        }
    }
}

// MARK: - Test Helpers

/// Simple performance measurement helper for Swift Testing
private func measureMetrics(
    description: String,
    iterations: Int,
    block: () -> Void
) {
    var totalTime: TimeInterval = 0

    for _ in 0..<iterations {
        let start = Date()
        block()
        let end = Date()
        totalTime += end.timeIntervalSince(start)
    }

    let average = totalTime / Double(iterations)
    print("⏱️ \(description): \(average * 1000)ms average over \(iterations) iterations")
}
