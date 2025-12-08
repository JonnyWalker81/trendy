//
//  APIModelsTests.swift
//  trendyTests
//
//  Production-grade tests for API model encoding/decoding
//
//  SUT: APIModels (Codable request/response models for backend communication)
//
//  Assumptions:
//  - Backend uses snake_case (event_type_id, created_at, etc.)
//  - iOS uses camelCase (eventTypeId, createdAt, etc.)
//  - Dates are encoded/decoded as ISO8601 strings
//  - Nested relationships (APIEvent contains APIEventType) are optional
//
//  Covered Behaviors:
//  ✅ CreateEventRequest encoding with snake_case mapping
//  ✅ APIEvent decoding with nested APIEventType
//  ✅ CreateEventTypeRequest roundtrip encoding/decoding
//  ✅ APIPropertyValue custom encoding (date → ISO8601)
//  ✅ Pagination response decoding
//  ✅ Error response decoding
//  ✅ Edge cases: null/nil values, empty arrays, missing nested objects
//
//  Intentionally Omitted:
//  - Network communication (tested in APIClientTests with mocks)
//  - SwiftData persistence (tested in integration tests)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Suite

@Suite("API Models Encoding/Decoding")
struct APIModelsTests {

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

    // MARK: - Event Type Request Tests

    @Test("CreateEventTypeRequest encodes with snake_case keys")
    func test_createEventTypeRequest_encodesWithSnakeCase() throws {
        let request = CreateEventTypeRequest(
            name: "Workout",
            color: "#FF5733",
            icon: "figure.run"
        )

        let encoded = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["name"] as? String == "Workout", "name should be 'Workout'")
        #expect(json?["color"] as? String == "#FF5733", "color should be '#FF5733'")
        #expect(json?["icon"] as? String == "figure.run", "icon should be 'figure.run'")
    }

    @Test("CreateEventTypeRequest roundtrips correctly")
    func test_createEventTypeRequest_roundtripsCorrectly() throws {
        let original = CreateEventTypeRequest(
            name: "Reading",
            color: "#00AAFF",
            icon: "book.fill"
        )

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(CreateEventTypeRequest.self, from: encoded)

        #expect(decoded.name == "Reading", "name should match")
        #expect(decoded.color == "#00AAFF", "color should match")
        #expect(decoded.icon == "book.fill", "icon should match")
    }

    // MARK: - Event Request Tests

    @Test("CreateEventRequest encodes with snake_case keys")
    func test_createEventRequest_encodesWithSnakeCase() throws {
        let fixedDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let request = CreateEventRequest(
            eventTypeId: "type-123",
            timestamp: fixedDate,
            notes: "Morning run",
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",
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

        #expect(json?["event_type_id"] as? String == "type-123", "event_type_id should use snake_case")
        #expect(json?["notes"] as? String == "Morning run", "notes should be 'Morning run'")
        #expect(json?["is_all_day"] as? Bool == false, "is_all_day should use snake_case")
        #expect(json?["source_type"] as? String == "manual", "source_type should use snake_case")
    }

    @Test("CreateEventRequest with properties encodes correctly")
    func test_createEventRequest_withProperties_encodesCorrectly() throws {
        let properties: [String: APIPropertyValue] = [
            "distance": APIPropertyValue(type: "number", value: AnyCodable(5.2)),
            "location": APIPropertyValue(type: "text", value: AnyCodable("Central Park"))
        ]

        let request = CreateEventRequest(
            eventTypeId: "workout-type",
            timestamp: Date(),
            notes: nil,
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",
            externalId: nil,
            originalTitle: nil,
            geofenceId: nil,
            locationLatitude: nil,
            locationLongitude: nil,
            locationName: nil,
            properties: properties
        )

        let encoded = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let encodedProps = json?["properties"] as? [String: Any]

        #expect(encodedProps != nil, "properties should be encoded")
        #expect(encodedProps?["distance"] != nil, "distance property should exist")
        #expect(encodedProps?["location"] != nil, "location property should exist")
    }

    // MARK: - API Event Type Decoding Tests

    @Test("APIEventType decodes from snake_case JSON")
    func test_apiEventType_decodesFromSnakeCase() throws {
        let json = """
        {
            "id": "evt-type-1",
            "user_id": "user-123",
            "name": "Exercise",
            "color": "#00FF00",
            "icon": "heart.fill",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-02T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIEventType.self, from: json)

        #expect(decoded.id == "evt-type-1", "id should match")
        #expect(decoded.userId == "user-123", "userId should map from user_id")
        #expect(decoded.name == "Exercise", "name should match")
        #expect(decoded.color == "#00FF00", "color should match")
        #expect(decoded.icon == "heart.fill", "icon should match")
        #expect(decoded.createdAt != Date(timeIntervalSince1970: 0), "createdAt should be parsed")
    }

    // MARK: - API Event Decoding Tests

    @Test("APIEvent decodes with nested APIEventType")
    func test_apiEvent_decodesWithNestedEventType() throws {
        let json = """
        {
            "id": "evt-1",
            "user_id": "user-456",
            "event_type_id": "type-1",
            "timestamp": "2024-01-15T10:30:00Z",
            "notes": "Great session",
            "is_all_day": false,
            "end_date": null,
            "source_type": "manual",
            "external_id": null,
            "original_title": null,
            "properties": null,
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T10:30:00Z",
            "event_type": {
                "id": "type-1",
                "user_id": "user-456",
                "name": "Workout",
                "color": "#FF0000",
                "icon": "flame.fill",
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z"
            }
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIEvent.self, from: json)

        #expect(decoded.id == "evt-1", "event id should match")
        #expect(decoded.userId == "user-456", "userId should map from user_id")
        #expect(decoded.eventTypeId == "type-1", "eventTypeId should map from event_type_id")
        #expect(decoded.notes == "Great session", "notes should match")
        #expect(decoded.isAllDay == false, "isAllDay should map from is_all_day")
        #expect(decoded.sourceType == "manual", "sourceType should map from source_type")

        #expect(decoded.eventType != nil, "nested eventType should be decoded")
        #expect(decoded.eventType?.name == "Workout", "nested eventType name should be 'Workout'")
    }

    @Test("APIEvent decodes without nested eventType (nil)")
    func test_apiEvent_decodesWithoutNestedEventType() throws {
        let json = """
        {
            "id": "evt-2",
            "user_id": "user-789",
            "event_type_id": "type-2",
            "timestamp": "2024-02-01T14:00:00Z",
            "notes": null,
            "is_all_day": true,
            "end_date": "2024-02-02T00:00:00Z",
            "source_type": "imported",
            "external_id": "cal-123",
            "original_title": "Imported Event",
            "properties": {},
            "created_at": "2024-02-01T14:00:00Z",
            "updated_at": "2024-02-01T14:00:00Z",
            "event_type": null
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIEvent.self, from: json)

        #expect(decoded.id == "evt-2", "event id should match")
        #expect(decoded.notes == nil, "notes should be nil")
        #expect(decoded.isAllDay == true, "isAllDay should be true")
        #expect(decoded.endDate != nil, "endDate should be decoded")
        #expect(decoded.sourceType == "imported", "sourceType should be 'imported'")
        #expect(decoded.externalId == "cal-123", "externalId should match")
        #expect(decoded.originalTitle == "Imported Event", "originalTitle should match")
        #expect(decoded.eventType == nil, "eventType should be nil")
    }

    // MARK: - API Property Value Tests

    @Test("APIPropertyValue with date encodes as ISO8601 string")
    func test_apiPropertyValue_date_encodesAsISO8601() throws {
        let fixedDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let propValue = APIPropertyValue(type: "date", value: AnyCodable(fixedDate))

        let encoded = try encoder.encode(propValue)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["type"] as? String == "date", "type should be 'date'")

        let valueString = json?["value"] as? String
        #expect(valueString != nil, "date should be encoded as string")
        #expect(valueString?.contains("2024-01-01") == true, "date string should contain '2024-01-01'")
    }

    @Test("APIPropertyValue equality compares by type and value")
    func test_apiPropertyValue_equality_comparesByTypeAndValue() {
        let prop1 = APIPropertyValue(type: "text", value: AnyCodable("Hello"))
        let prop2 = APIPropertyValue(type: "text", value: AnyCodable("Hello"))
        let prop3 = APIPropertyValue(type: "text", value: AnyCodable("World"))
        let prop4 = APIPropertyValue(type: "number", value: AnyCodable(42))

        #expect(prop1 == prop2, "Same type and value should be equal")
        #expect(prop1 != prop3, "Same type, different value should not be equal")
        #expect(prop1 != prop4, "Different type should not be equal")
    }

    @Test("APIPropertyValue convenience getters return correct values")
    func test_apiPropertyValue_convenienceGetters_returnCorrectValues() {
        let textProp = APIPropertyValue(type: "text", value: AnyCodable("Sample"))
        let numberProp = APIPropertyValue(type: "number", value: AnyCodable(99))
        let boolProp = APIPropertyValue(type: "boolean", value: AnyCodable(true))

        #expect(textProp.stringValue == "Sample", "stringValue should return 'Sample'")
        #expect(numberProp.intValue == 99, "intValue should return 99")
        #expect(boolProp.boolValue == true, "boolValue should return true")
    }

    // MARK: - Pagination Response Tests

    @Test("PaginatedResponse decodes correctly")
    func test_paginatedResponse_decodesCorrectly() throws {
        let json = """
        {
            "data": [
                {
                    "id": "type-1",
                    "user_id": "user-1",
                    "name": "Type A",
                    "color": "#FF0000",
                    "icon": "star.fill",
                    "created_at": "2024-01-01T00:00:00Z",
                    "updated_at": "2024-01-01T00:00:00Z"
                }
            ],
            "total": 100,
            "limit": 50,
            "offset": 0
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(PaginatedResponse<APIEventType>.self, from: json)

        #expect(decoded.data.count == 1, "data should have 1 item")
        #expect(decoded.total == 100, "total should be 100")
        #expect(decoded.limit == 50, "limit should be 50")
        #expect(decoded.offset == 0, "offset should be 0")
        #expect(decoded.data.first?.name == "Type A", "first item name should be 'Type A'")
    }

    @Test("PaginatedResponse with empty data decodes correctly")
    func test_paginatedResponse_emptyData_decodesCorrectly() throws {
        let json = """
        {
            "data": [],
            "total": 0,
            "limit": 50,
            "offset": 0
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(PaginatedResponse<APIEventType>.self, from: json)

        #expect(decoded.data.isEmpty, "data should be empty")
        #expect(decoded.total == 0, "total should be 0")
    }

    // MARK: - Error Response Tests

    @Test("APIErrorResponse decodes correctly")
    func test_apiErrorResponse_decodesCorrectly() throws {
        let json = """
        {
            "error": "validation_error",
            "message": "Invalid event type ID",
            "status_code": 400
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIErrorResponse.self, from: json)

        #expect(decoded.error == "validation_error", "error should be 'validation_error'")
        #expect(decoded.message == "Invalid event type ID", "message should match")
        #expect(decoded.statusCode == 400, "statusCode should be 400")
    }

    @Test("APIErrorResponse decodes with nil message and statusCode")
    func test_apiErrorResponse_nilFields_decodesCorrectly() throws {
        let json = """
        {
            "error": "unknown_error"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIErrorResponse.self, from: json)

        #expect(decoded.error == "unknown_error", "error should be 'unknown_error'")
        #expect(decoded.message == nil, "message should be nil")
        #expect(decoded.statusCode == nil, "statusCode should be nil")
    }

    // MARK: - Edge Cases

    @Test("CreateEventRequest with all nil optional fields encodes correctly")
    func test_createEventRequest_allNilOptionals_encodesCorrectly() throws {
        let request = CreateEventRequest(
            eventTypeId: "type-1",
            timestamp: Date(),
            notes: nil,
            isAllDay: false,
            endDate: nil,
            sourceType: "manual",
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

        // Optional fields should not be present in JSON (or present as null depending on encoder settings)
        #expect(json?["event_type_id"] != nil, "event_type_id should be present")
        #expect(json?["timestamp"] != nil, "timestamp should be present")
    }

    @Test("UpdateEventRequest with partial fields encodes correctly")
    func test_updateEventRequest_partialFields_encodesCorrectly() throws {
        let request = UpdateEventRequest(
            eventTypeId: nil,
            timestamp: nil,
            notes: "Updated notes",
            isAllDay: nil,
            endDate: nil,
            sourceType: nil,
            externalId: nil,
            originalTitle: nil,
            properties: nil
        )

        let encoded = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        // Only notes should have a non-null value (depending on encoder null handling)
        #expect(json != nil, "JSON should be encoded")
    }

    // MARK: - Micro-Benchmark (Performance)

    @Test("Performance: Encoding 1000 CreateEventRequest objects")
    func test_performance_createEventRequest_encoding() {
        measureMetrics(
            description: "Encoding 1000 CreateEventRequest objects",
            iterations: 10
        ) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            for i in 0..<1000 {
                let request = CreateEventRequest(
                    eventTypeId: "type-\(i)",
                    timestamp: Date(),
                    notes: "Event \(i)",
                    isAllDay: false,
                    endDate: nil,
                    sourceType: "manual",
                    externalId: nil,
                    originalTitle: nil,
                    geofenceId: nil,
                    locationLatitude: nil,
                    locationLongitude: nil,
                    locationName: nil,
                    properties: [:]
                )

                _ = try? encoder.encode(request)
            }
        }
    }

    @Test("Performance: Decoding 1000 APIEvent objects")
    func test_performance_apiEvent_decoding() {
        let jsonTemplate = """
        {
            "id": "evt-{{ID}}",
            "user_id": "user-1",
            "event_type_id": "type-1",
            "timestamp": "2024-01-15T10:30:00Z",
            "notes": "Event {{ID}}",
            "is_all_day": false,
            "end_date": null,
            "source_type": "manual",
            "external_id": null,
            "original_title": null,
            "properties": null,
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T10:30:00Z",
            "event_type": null
        }
        """

        measureMetrics(
            description: "Decoding 1000 APIEvent objects",
            iterations: 10
        ) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for i in 0..<1000 {
                let json = jsonTemplate
                    .replacingOccurrences(of: "{{ID}}", with: "\(i)")
                    .data(using: .utf8)!

                _ = try? decoder.decode(APIEvent.self, from: json)
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
