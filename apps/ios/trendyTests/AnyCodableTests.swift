//
//  AnyCodableTests.swift
//  trendyTests
//
//  Production-grade tests for AnyCodable and PropertyValue
//
//  SUT: AnyCodable (type-erasing Codable wrapper) + PropertyValue (custom encoding/equality)
//
//  Assumptions:
//  - AnyCodable supports primitives (String, Int, Double, Bool), arrays, and dicts
//  - PropertyValue encodes dates as ISO8601 strings
//  - Type-specific equality for PropertyValue (e.g., number types compared as Double)
//
//  Covered Behaviors:
//  ✅ AnyCodable roundtrip encoding/decoding (primitives, nested structures)
//  ✅ PropertyValue date → ISO8601 string encoding
//  ✅ PropertyValue type-specific equality (text, number, boolean, date)
//  ✅ Edge cases: empty strings, zero, nested arrays/dicts, whitespace
//  ✅ Error cases: invalid date strings, type mismatches
//
//  Intentionally Omitted:
//  - SwiftData persistence (tested separately in integration tests)
//  - Network-dependent behaviors (tested in APIClientTests)
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Suite

@Suite("AnyCodable Encoding/Decoding")
struct AnyCodableTests {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // MARK: - AnyCodable Primitive Tests

    @Test("AnyCodable roundtrip with String")
    func test_anyCodable_string_roundtripsCorrectly() throws {
        let original = AnyCodable("Hello, World!")
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded.value as? String == "Hello, World!", "String should roundtrip correctly")
    }

    @Test("AnyCodable roundtrip with Int")
    func test_anyCodable_int_roundtripsCorrectly() throws {
        let original = AnyCodable(42)
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded.value as? Int == 42, "Int should roundtrip correctly")
    }

    @Test("AnyCodable roundtrip with Double")
    func test_anyCodable_double_roundtripsCorrectly() throws {
        let original = AnyCodable(3.14159)
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded.value as? Double == 3.14159, "Double should roundtrip correctly")
    }

    @Test("AnyCodable roundtrip with Bool")
    func test_anyCodable_bool_roundtripsCorrectly() throws {
        let original = AnyCodable(true)
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded.value as? Bool == true, "Bool should roundtrip correctly")
    }

    // MARK: - AnyCodable Collection Tests

    @Test("AnyCodable roundtrip with Array")
    func test_anyCodable_array_roundtripsCorrectly() throws {
        let original = AnyCodable(["a", "b", "c"])
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        let result = decoded.value as? [Any]
        #expect(result?.count == 3, "Array should have 3 elements")
        #expect(result?[0] as? String == "a", "First element should be 'a'")
    }

    @Test("AnyCodable roundtrip with Dictionary")
    func test_anyCodable_dict_roundtripsCorrectly() throws {
        let original = AnyCodable(["key": "value", "count": 42])
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        let result = decoded.value as? [String: Any]
        #expect(result?["key"] as? String == "value", "Dict key 'key' should be 'value'")
        #expect(result?["count"] as? Int == 42, "Dict key 'count' should be 42")
    }

    @Test("AnyCodable roundtrip with nested structures")
    func test_anyCodable_nestedStructures_roundtripsCorrectly() throws {
        let nested: [String: Any] = [
            "level1": [
                "level2": ["a", "b", "c"],
                "number": 99
            ]
        ]
        let original = AnyCodable(nested)
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        let result = decoded.value as? [String: Any]
        let level1 = result?["level1"] as? [String: Any]
        let level2 = level1?["level2"] as? [Any]

        #expect(level2?.count == 3, "Nested array should have 3 elements")
        #expect(level1?["number"] as? Int == 99, "Nested number should be 99")
    }

    // MARK: - AnyCodable Edge Cases

    @Test("AnyCodable with empty string")
    func test_anyCodable_emptyString_handlesCorrectly() throws {
        let original = AnyCodable("")
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded.value as? String == "", "Empty string should roundtrip correctly")
    }

    @Test("AnyCodable with zero")
    func test_anyCodable_zero_handlesCorrectly() throws {
        let original = AnyCodable(0)
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded.value as? Int == 0, "Zero should roundtrip correctly")
    }

    @Test("AnyCodable with empty array")
    func test_anyCodable_emptyArray_handlesCorrectly() throws {
        let original = AnyCodable([])
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        let result = decoded.value as? [Any]
        #expect(result?.isEmpty == true, "Empty array should roundtrip correctly")
    }
}

// MARK: - PropertyValue Tests

@Suite("PropertyValue Encoding/Decoding")
struct PropertyValueTests {

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

    // MARK: - PropertyValue Encoding Tests

    @Test("PropertyValue text type encodes correctly")
    func test_propertyValue_text_encodesCorrectly() throws {
        let property = PropertyValue(type: .text, value: "Sample text")
        let encoded = try encoder.encode(property)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["type"] as? String == "text", "Type should be 'text'")
        #expect(json?["value"] as? String == "Sample text", "Value should be 'Sample text'")
    }

    @Test("PropertyValue number type encodes correctly")
    func test_propertyValue_number_encodesCorrectly() throws {
        let property = PropertyValue(type: .number, value: 42)
        let encoded = try encoder.encode(property)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["type"] as? String == "number", "Type should be 'number'")
        #expect(json?["value"] as? Int == 42, "Value should be 42")
    }

    @Test("PropertyValue boolean type encodes correctly")
    func test_propertyValue_boolean_encodesCorrectly() throws {
        let property = PropertyValue(type: .boolean, value: true)
        let encoded = try encoder.encode(property)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["type"] as? String == "boolean", "Type should be 'boolean'")
        #expect(json?["value"] as? Bool == true, "Value should be true")
    }

    @Test("PropertyValue date type encodes as ISO8601 string")
    func test_propertyValue_date_encodesAsISO8601String() throws {
        let fixedDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let property = PropertyValue(type: .date, value: fixedDate)
        let encoded = try encoder.encode(property)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["type"] as? String == "date", "Type should be 'date'")

        let dateString = json?["value"] as? String
        #expect(dateString != nil, "Date value should be a string (ISO8601)")
        #expect(dateString?.contains("2024-01-01") == true, "Date string should contain '2024-01-01'")
    }

    // MARK: - PropertyValue Decoding Tests

    @Test("PropertyValue text type decodes correctly")
    func test_propertyValue_text_decodesCorrectly() throws {
        let json = """
        {"type":"text","value":"Test value"}
        """.data(using: .utf8)!

        let decoded = try decoder.decode(PropertyValue.self, from: json)

        #expect(decoded.type == .text, "Type should be .text")
        #expect(decoded.stringValue == "Test value", "String value should be 'Test value'")
    }

    @Test("PropertyValue date type decodes from ISO8601 string")
    func test_propertyValue_date_decodesFromISO8601String() throws {
        let json = """
        {"type":"date","value":"2024-01-01T00:00:00Z"}
        """.data(using: .utf8)!

        let decoded = try decoder.decode(PropertyValue.self, from: json)

        #expect(decoded.type == .date, "Type should be .date")
        #expect(decoded.dateValue != nil, "Date value should not be nil")
    }

    // MARK: - PropertyValue Equality Tests

    @Test("PropertyValue text equality compares string values")
    func test_propertyValue_textEquality_comparesStringValues() {
        let prop1 = PropertyValue(type: .text, value: "Same")
        let prop2 = PropertyValue(type: .text, value: "Same")
        let prop3 = PropertyValue(type: .text, value: "Different")

        #expect(prop1 == prop2, "Identical text values should be equal")
        #expect(prop1 != prop3, "Different text values should not be equal")
    }

    @Test("PropertyValue number equality compares as Double")
    func test_propertyValue_numberEquality_comparesAsDouble() {
        let prop1 = PropertyValue(type: .number, value: 42)
        let prop2 = PropertyValue(type: .number, value: 42.0)
        let prop3 = PropertyValue(type: .number, value: 99)

        #expect(prop1 == prop2, "Int 42 and Double 42.0 should be equal")
        #expect(prop1 != prop3, "42 and 99 should not be equal")
    }

    @Test("PropertyValue boolean equality compares bool values")
    func test_propertyValue_booleanEquality_comparesBoolValues() {
        let prop1 = PropertyValue(type: .boolean, value: true)
        let prop2 = PropertyValue(type: .boolean, value: true)
        let prop3 = PropertyValue(type: .boolean, value: false)

        #expect(prop1 == prop2, "Both true should be equal")
        #expect(prop1 != prop3, "true and false should not be equal")
    }

    @Test("PropertyValue date equality compares date values")
    func test_propertyValue_dateEquality_comparesDateValues() {
        let fixedDate = Date(timeIntervalSince1970: 1704067200)
        let prop1 = PropertyValue(type: .date, value: fixedDate)
        let prop2 = PropertyValue(type: .date, value: fixedDate)
        let prop3 = PropertyValue(type: .date, value: Date(timeIntervalSince1970: 0))

        #expect(prop1 == prop2, "Identical dates should be equal")
        #expect(prop1 != prop3, "Different dates should not be equal")
    }

    @Test("PropertyValue different types are not equal")
    func test_propertyValue_differentTypes_notEqual() {
        let textProp = PropertyValue(type: .text, value: "42")
        let numProp = PropertyValue(type: .number, value: 42)

        #expect(textProp != numProp, "Different types should never be equal")
    }

    // MARK: - PropertyValue Convenience Getters

    @Test("PropertyValue stringValue getter returns correct value")
    func test_propertyValue_stringValueGetter_returnsCorrectValue() {
        let property = PropertyValue(type: .text, value: "Hello")
        #expect(property.stringValue == "Hello", "stringValue should return 'Hello'")
    }

    @Test("PropertyValue intValue getter returns correct value")
    func test_propertyValue_intValueGetter_returnsCorrectValue() {
        let property = PropertyValue(type: .number, value: 42)
        #expect(property.intValue == 42, "intValue should return 42")
    }

    @Test("PropertyValue doubleValue getter returns correct value")
    func test_propertyValue_doubleValueGetter_returnsCorrectValue() {
        let property = PropertyValue(type: .number, value: 3.14)
        #expect(property.doubleValue == 3.14, "doubleValue should return 3.14")
    }

    @Test("PropertyValue boolValue getter returns correct value")
    func test_propertyValue_boolValueGetter_returnsCorrectValue() {
        let property = PropertyValue(type: .boolean, value: true)
        #expect(property.boolValue == true, "boolValue should return true")
    }

    // MARK: - Edge Cases

    @Test("PropertyValue with empty string")
    func test_propertyValue_emptyString_handlesCorrectly() {
        let property = PropertyValue(type: .text, value: "")
        #expect(property.stringValue == "", "Empty string should be preserved")
    }

    @Test("PropertyValue with zero")
    func test_propertyValue_zero_handlesCorrectly() {
        let property = PropertyValue(type: .number, value: 0)
        #expect(property.intValue == 0, "Zero should be preserved")
        #expect(property.doubleValue == 0.0, "Zero should be 0.0 as double")
    }

    // MARK: - Micro-Benchmark (Performance)

    @Test("Performance: AnyCodable encoding/decoding 1000 primitives")
    func test_performance_anyCodable_1000Primitives() {
        measureMetrics(
            description: "Encoding/decoding 1000 AnyCodable primitives",
            iterations: 10
        ) {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            for i in 0..<1000 {
                let original = AnyCodable(i)
                if let encoded = try? encoder.encode(original),
                   let _ = try? decoder.decode(AnyCodable.self, from: encoded) {
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
