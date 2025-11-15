//
//  PropertyTypeTests.swift
//  trendyTests
//
//  Production-grade tests for PropertyType enum
//
//  SUT: PropertyType (custom property field types for event tracking)
//
//  Assumptions:
//  - PropertyType is a String-backed enum
//  - 8 cases: text, number, boolean, date, select, duration, url, email
//  - Conforms to Codable for backend API serialization
//  - Conforms to CaseIterable for UI iteration
//  - Each type has a user-friendly displayName
//
//  Covered Behaviors:
//  ✅ Raw value mapping (text, number, boolean, date, etc.)
//  ✅ Display names for UI presentation
//  ✅ Codable roundtrip encoding/decoding
//  ✅ CaseIterable provides all 8 cases
//  ✅ String initialization from raw value
//
//  Intentionally Omitted:
//  - Property validation logic (tested in PropertyValue tests)
//  - UI rendering (out of scope for model tests)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Suite

@Suite("PropertyType Basic Properties")
struct PropertyTypeBasicTests {

    @Test("PropertyType raw values match expected strings")
    func test_propertyType_rawValues_matchExpectedStrings() {
        #expect(PropertyType.text.rawValue == "text", "text raw value should be 'text'")
        #expect(PropertyType.number.rawValue == "number", "number raw value should be 'number'")
        #expect(PropertyType.boolean.rawValue == "boolean", "boolean raw value should be 'boolean'")
        #expect(PropertyType.date.rawValue == "date", "date raw value should be 'date'")
        #expect(PropertyType.select.rawValue == "select", "select raw value should be 'select'")
        #expect(PropertyType.duration.rawValue == "duration", "duration raw value should be 'duration'")
        #expect(PropertyType.url.rawValue == "url", "url raw value should be 'url'")
        #expect(PropertyType.email.rawValue == "email", "email raw value should be 'email'")
    }

    @Test("PropertyType can be initialized from raw value")
    func test_propertyType_initFromRawValue_succeeds() {
        #expect(PropertyType(rawValue: "text") == .text, "Should initialize .text from 'text'")
        #expect(PropertyType(rawValue: "number") == .number, "Should initialize .number from 'number'")
        #expect(PropertyType(rawValue: "boolean") == .boolean, "Should initialize .boolean from 'boolean'")
        #expect(PropertyType(rawValue: "date") == .date, "Should initialize .date from 'date'")
        #expect(PropertyType(rawValue: "select") == .select, "Should initialize .select from 'select'")
        #expect(PropertyType(rawValue: "duration") == .duration, "Should initialize .duration from 'duration'")
        #expect(PropertyType(rawValue: "url") == .url, "Should initialize .url from 'url'")
        #expect(PropertyType(rawValue: "email") == .email, "Should initialize .email from 'email'")
    }

    @Test("PropertyType init from invalid raw value returns nil")
    func test_propertyType_initFromInvalidRawValue_returnsNil() {
        let invalid = PropertyType(rawValue: "unknown")

        #expect(invalid == nil, "Invalid raw value should return nil")
    }
}

@Suite("PropertyType Display Names")
struct PropertyTypeDisplayNameTests {

    @Test("PropertyType display names are user-friendly")
    func test_propertyType_displayNames_areUserFriendly() {
        #expect(PropertyType.text.displayName == "Text", "text displayName should be 'Text'")
        #expect(PropertyType.number.displayName == "Number", "number displayName should be 'Number'")
        #expect(PropertyType.boolean.displayName == "Boolean", "boolean displayName should be 'Boolean'")
        #expect(PropertyType.date.displayName == "Date", "date displayName should be 'Date'")
        #expect(PropertyType.select.displayName == "Select", "select displayName should be 'Select'")
        #expect(PropertyType.duration.displayName == "Duration", "duration displayName should be 'Duration'")
        #expect(PropertyType.url.displayName == "URL", "url displayName should be 'URL'")
        #expect(PropertyType.email.displayName == "Email", "email displayName should be 'Email'")
    }

    @Test("PropertyType display names are capitalized")
    func test_propertyType_displayNames_areCapitalized() {
        for type in PropertyType.allCases {
            let displayName = type.displayName
            let firstChar = displayName.first!

            #expect(firstChar.isUppercase, "Display name '\(displayName)' should start with uppercase")
        }
    }

    @Test("PropertyType display names are not empty")
    func test_propertyType_displayNames_notEmpty() {
        for type in PropertyType.allCases {
            #expect(!type.displayName.isEmpty, "Display name for \(type.rawValue) should not be empty")
        }
    }
}

@Suite("PropertyType CaseIterable")
struct PropertyTypeCaseIterableTests {

    @Test("PropertyType allCases contains all 8 cases")
    func test_propertyType_allCases_containsAll8Cases() {
        let allCases = PropertyType.allCases

        #expect(allCases.count == 8, "Should have exactly 8 cases, got \(allCases.count)")
    }

    @Test("PropertyType allCases contains all expected types")
    func test_propertyType_allCases_containsExpectedTypes() {
        let allCases = PropertyType.allCases

        #expect(allCases.contains(.text), "allCases should contain .text")
        #expect(allCases.contains(.number), "allCases should contain .number")
        #expect(allCases.contains(.boolean), "allCases should contain .boolean")
        #expect(allCases.contains(.date), "allCases should contain .date")
        #expect(allCases.contains(.select), "allCases should contain .select")
        #expect(allCases.contains(.duration), "allCases should contain .duration")
        #expect(allCases.contains(.url), "allCases should contain .url")
        #expect(allCases.contains(.email), "allCases should contain .email")
    }

    @Test("PropertyType can iterate over all cases")
    func test_propertyType_iteration_works() {
        var count = 0
        var seenTypes = Set<PropertyType>()

        for type in PropertyType.allCases {
            count += 1
            seenTypes.insert(type)
        }

        #expect(count == 8, "Should iterate over 8 cases")
        #expect(seenTypes.count == 8, "Should see 8 unique types")
    }
}

@Suite("PropertyType Codable")
struct PropertyTypeCodableTests {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    @Test("PropertyType encodes to JSON string", arguments: PropertyType.allCases)
    func test_propertyType_encodesToJSONString(type: PropertyType) throws {
        let encoded = try encoder.encode(type)
        let json = String(data: encoded, encoding: .utf8)

        let expectedJSON = "\"\(type.rawValue)\""
        #expect(json == expectedJSON, "Should encode as JSON string \(expectedJSON): got \(json ?? "nil")")
    }

    @Test("PropertyType decodes from JSON string", arguments: PropertyType.allCases)
    func test_propertyType_decodesFromJSONString(type: PropertyType) throws {
        let json = "\"\(type.rawValue)\"".data(using: .utf8)!

        let decoded = try decoder.decode(PropertyType.self, from: json)

        #expect(decoded == type, "Should decode to \(type.rawValue)")
    }

    @Test("PropertyType roundtrip preserves value", arguments: PropertyType.allCases)
    func test_propertyType_roundtrip_preservesValue(type: PropertyType) throws {
        let encoded = try encoder.encode(type)
        let decoded = try decoder.decode(PropertyType.self, from: encoded)

        #expect(decoded == type, "Roundtrip should preserve \(type.rawValue)")
    }

    @Test("PropertyType decoding invalid value throws error")
    func test_propertyType_decodingInvalidValue_throwsError() {
        let json = "\"invalid_type\"".data(using: .utf8)!

        #expect(throws: Error.self) {
            _ = try decoder.decode(PropertyType.self, from: json)
        }
    }
}

@Suite("PropertyType in PropertyDefinition")
struct PropertyTypeInPropertyDefinitionTests {

    @Test("PropertyDefinition with text type initializes correctly")
    func test_propertyDefinition_textType_initializesCorrectly() {
        let propDef = PropertyDefinition(
            eventTypeId: UUID(),
            key: "notes",
            label: "Notes",
            propertyType: .text
        )

        #expect(propDef.propertyType == .text, "propertyType should be .text")
        #expect(propDef.propertyType.rawValue == "text", "propertyType raw value should be 'text'")
        #expect(propDef.propertyType.displayName == "Text", "propertyType displayName should be 'Text'")
    }

    @Test("PropertyDefinition with select type has options")
    func test_propertyDefinition_selectType_hasOptions() {
        let propDef = PropertyDefinition(
            eventTypeId: UUID(),
            key: "priority",
            label: "Priority",
            propertyType: .select,
            options: ["Low", "Medium", "High"]
        )

        #expect(propDef.propertyType == .select, "propertyType should be .select")
        #expect(propDef.options == ["Low", "Medium", "High"], "options should be set")
    }

    @Test("PropertyDefinition supports all PropertyType cases")
    func test_propertyDefinition_supportsAllPropertyTypes() {
        for type in PropertyType.allCases {
            let propDef = PropertyDefinition(
                eventTypeId: UUID(),
                key: "test_\(type.rawValue)",
                label: "Test \(type.displayName)",
                propertyType: type
            )

            #expect(propDef.propertyType == type, "Should support \(type.rawValue)")
        }
    }
}

@Suite("PropertyType Backend API Compatibility")
struct PropertyTypeAPICompatibilityTests {

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

    @Test("CreatePropertyDefinitionRequest encodes propertyType correctly", arguments: [
        ("text", PropertyType.text),
        ("number", PropertyType.number),
        ("boolean", PropertyType.boolean),
        ("date", PropertyType.date)
    ])
    func test_createPropertyDefinitionRequest_encodesPropertyType(rawValue: String, type: PropertyType) throws {
        let request = CreatePropertyDefinitionRequest(
            eventTypeId: "type-1",
            key: "test",
            label: "Test",
            propertyType: rawValue,  // String in API model
            options: nil,
            defaultValue: nil,
            displayOrder: 0
        )

        let encoded = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["property_type"] as? String == rawValue, "property_type should be '\(rawValue)' in JSON")
    }

    @Test("APIPropertyDefinition decodes propertyType correctly")
    func test_apiPropertyDefinition_decodesPropertyType() throws {
        let json = """
        {
            "id": "prop-1",
            "event_type_id": "type-1",
            "user_id": "user-1",
            "key": "distance",
            "label": "Distance",
            "property_type": "number",
            "options": null,
            "default_value": null,
            "display_order": 0,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(APIPropertyDefinition.self, from: json)

        #expect(decoded.propertyType == "number", "propertyType should be 'number'")
    }

    @Test("APIPropertyValue type field matches PropertyType raw values", arguments: PropertyType.allCases)
    func test_apiPropertyValue_typeField_matchesPropertyType(type: PropertyType) {
        let apiPropValue = APIPropertyValue(type: type.rawValue, value: AnyCodable("test"))

        #expect(apiPropValue.type == type.rawValue, "APIPropertyValue type should match PropertyType raw value")
    }
}

@Suite("PropertyType Equality")
struct PropertyTypeEqualityTests {

    @Test("PropertyType cases equal themselves", arguments: PropertyType.allCases)
    func test_propertyType_casesEqualThemselves(type: PropertyType) {
        #expect(type == type, "\(type.rawValue) should equal itself")
    }

    @Test("PropertyType different cases not equal")
    func test_propertyType_differentCases_notEqual() {
        #expect(PropertyType.text != PropertyType.number, ".text should not equal .number")
        #expect(PropertyType.boolean != PropertyType.date, ".boolean should not equal .date")
        #expect(PropertyType.select != PropertyType.duration, ".select should not equal .duration")
        #expect(PropertyType.url != PropertyType.email, ".url should not equal .email")
    }

    @Test("PropertyType equality via raw value comparison")
    func test_propertyType_equalityViaRawValue() {
        let text1 = PropertyType.text
        let text2 = PropertyType(rawValue: "text")!

        #expect(text1 == text2, "Should be equal when created from same raw value")
    }
}

@Suite("PropertyType Edge Cases")
struct PropertyTypeEdgeCaseTests {

    @Test("PropertyType raw values are lowercase")
    func test_propertyType_rawValues_areLowercase() {
        for type in PropertyType.allCases {
            let rawValue = type.rawValue
            #expect(rawValue == rawValue.lowercased(), "Raw value '\(rawValue)' should be lowercase")
        }
    }

    @Test("PropertyType string comparison is case-sensitive")
    func test_propertyType_stringComparison_caseSensitive() {
        let uppercase = PropertyType(rawValue: "TEXT")
        let mixedCase = PropertyType(rawValue: "Number")

        #expect(uppercase == nil, "Uppercase 'TEXT' should not initialize")
        #expect(mixedCase == nil, "Mixed case 'Number' should not initialize")
    }

    @Test("PropertyType display names do not match raw values")
    func test_propertyType_displayNames_doNotMatchRawValues() {
        for type in PropertyType.allCases {
            // Display names are capitalized, raw values are lowercase
            if type != .url {  // Special case: URL is uppercase
                #expect(type.displayName != type.rawValue, "Display name should differ from raw value for \(type.rawValue)")
            }
        }
    }

    @Test("PropertyType URL displayName is uppercase")
    func test_propertyType_url_displayNameIsUppercase() {
        #expect(PropertyType.url.displayName == "URL", "URL displayName should be uppercase 'URL'")
    }
}

@Suite("PropertyType Use Cases")
struct PropertyTypeUseCaseTests {

    @Test("PropertyType text is suitable for free-form input")
    func test_propertyType_text_suitableForFreeFormInput() {
        let type = PropertyType.text

        #expect(type.displayName == "Text", "Text type should have user-friendly name")
        #expect(type.rawValue == "text", "Text type should have backend-compatible raw value")
    }

    @Test("PropertyType number is suitable for numeric values")
    func test_propertyType_number_suitableForNumericValues() {
        let type = PropertyType.number

        #expect(type.displayName == "Number", "Number type should have user-friendly name")
        #expect(type.rawValue == "number", "Number type should have backend-compatible raw value")
    }

    @Test("PropertyType select is suitable for dropdown options")
    func test_propertyType_select_suitableForDropdown() {
        let type = PropertyType.select

        #expect(type.displayName == "Select", "Select type should have user-friendly name")
        #expect(type.rawValue == "select", "Select type should have backend-compatible raw value")
    }

    @Test("PropertyType url is suitable for links")
    func test_propertyType_url_suitableForLinks() {
        let type = PropertyType.url

        #expect(type.displayName == "URL", "URL type should have user-friendly name")
        #expect(type.rawValue == "url", "URL type should have backend-compatible raw value")
    }

    @Test("PropertyType email is suitable for email addresses")
    func test_propertyType_email_suitableForEmailAddresses() {
        let type = PropertyType.email

        #expect(type.displayName == "Email", "Email type should have user-friendly name")
        #expect(type.rawValue == "email", "Email type should have backend-compatible raw value")
    }
}

// MARK: - Performance Tests

@Suite("PropertyType Performance")
struct PropertyTypePerformanceTests {

    @Test("Performance: Encoding/decoding 10000 PropertyType values")
    func test_performance_encodingDecoding_10000Values() {
        measureMetrics(
            description: "Encoding/decoding 10000 PropertyType values",
            iterations: 10
        ) {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let types = PropertyType.allCases

            for i in 0..<10000 {
                let type = types[i % types.count]

                if let encoded = try? encoder.encode(type),
                   let _ = try? decoder.decode(PropertyType.self, from: encoded) {
                    // Successfully roundtripped
                }
            }
        }
    }

    @Test("Performance: Accessing displayName 100000 times")
    func test_performance_displayName_100000Times() {
        measureMetrics(
            description: "Accessing displayName 100000 times",
            iterations: 10
        ) {
            let types = PropertyType.allCases

            for i in 0..<100000 {
                let type = types[i % types.count]
                _ = type.displayName
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
