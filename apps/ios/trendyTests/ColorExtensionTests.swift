//
//  ColorExtensionTests.swift
//  trendyTests
//
//  Production-grade tests for Color hex string conversion
//
//  SUT: Color extension (hex string ↔ Color conversion)
//
//  Assumptions:
//  - Hex strings can be in format "#RRGGBB" or "RRGGBB" (with or without #)
//  - RGB values range from 0x00 to 0xFF (0-255)
//  - Color initializer returns nil for invalid hex strings
//  - Roundtrip conversion (hex → Color → hex) should preserve original RGB values
//
//  Covered Behaviors:
//  ✅ Color initialization from valid hex strings (#RRGGBB, RRGGBB)
//  ✅ Hex string extraction from Color (hexString property)
//  ✅ Roundtrip conversion preserves RGB values
//  ✅ Edge cases: #000000 (black), #FFFFFF (white), leading/trailing whitespace
//  ✅ Error cases: invalid formats, empty strings, non-hex characters, out of range
//  ✅ Property test: any valid hex → Color → hex should be idempotent
//
//  Intentionally Omitted:
//  - SwiftUI Color rendering (tested visually, not unit-testable)
//  - Alpha channel (not supported in current implementation)
//

import Testing
import SwiftUI
@testable import trendy

// MARK: - Test Suite

@Suite("Color Hex String Conversion")
struct ColorExtensionTests {

    // MARK: - Valid Hex String Initialization

    @Test("Color initializes from hex string with hash prefix")
    func test_color_initFromHex_withHashPrefix() {
        let color = Color(hex: "#FF5733")

        #expect(color != nil, "Color should initialize from valid hex string with #")
    }

    @Test("Color initializes from hex string without hash prefix")
    func test_color_initFromHex_withoutHashPrefix() {
        let color = Color(hex: "FF5733")

        #expect(color != nil, "Color should initialize from valid hex string without #")
    }

    @Test("Color initializes from lowercase hex string")
    func test_color_initFromHex_lowercase() {
        let color = Color(hex: "#ff5733")

        #expect(color != nil, "Color should initialize from lowercase hex string")
    }

    @Test("Color initializes from uppercase hex string")
    func test_color_initFromHex_uppercase() {
        let color = Color(hex: "#FF5733")

        #expect(color != nil, "Color should initialize from uppercase hex string")
    }

    @Test("Color initializes from mixed case hex string")
    func test_color_initFromHex_mixedCase() {
        let color = Color(hex: "#Ff5733")

        #expect(color != nil, "Color should initialize from mixed case hex string")
    }

    // MARK: - RGB Component Extraction (via hexString)

    @Test("Color hex string preserves red component")
    func test_color_hexString_preservesRedComponent() {
        let color = Color(hex: "#FF0000")!
        let hexString = color.hexString

        #expect(hexString.uppercased() == "#FF0000", "Red component should be preserved: got \(hexString)")
    }

    @Test("Color hex string preserves green component")
    func test_color_hexString_preservesGreenComponent() {
        let color = Color(hex: "#00FF00")!
        let hexString = color.hexString

        #expect(hexString.uppercased() == "#00FF00", "Green component should be preserved: got \(hexString)")
    }

    @Test("Color hex string preserves blue component")
    func test_color_hexString_preservesBlueComponent() {
        let color = Color(hex: "#0000FF")!
        let hexString = color.hexString

        #expect(hexString.uppercased() == "#0000FF", "Blue component should be preserved: got \(hexString)")
    }

    @Test("Color hex string for mixed RGB")
    func test_color_hexString_mixedRGB() {
        let color = Color(hex: "#FF5733")!
        let hexString = color.hexString

        #expect(hexString.uppercased() == "#FF5733", "Mixed RGB should be preserved: got \(hexString)")
    }

    // MARK: - Roundtrip Conversion Tests

    @Test("Color roundtrip conversion preserves RGB values")
    func test_color_roundtrip_preservesRGBValues() {
        let original = "#A1B2C3"
        let color = Color(hex: original)!
        let roundtripped = color.hexString

        #expect(roundtripped.uppercased() == original.uppercased(), "Roundtrip should preserve RGB: \(original) → \(roundtripped)")
    }

    @Test("Color roundtrip for black")
    func test_color_roundtrip_black() {
        let original = "#000000"
        let color = Color(hex: original)!
        let roundtripped = color.hexString

        #expect(roundtripped.uppercased() == "#000000", "Black should roundtrip correctly: got \(roundtripped)")
    }

    @Test("Color roundtrip for white")
    func test_color_roundtrip_white() {
        let original = "#FFFFFF"
        let color = Color(hex: original)!
        let roundtripped = color.hexString

        #expect(roundtripped.uppercased() == "#FFFFFF", "White should roundtrip correctly: got \(roundtripped)")
    }

    @Test("Color roundtrip for gray")
    func test_color_roundtrip_gray() {
        let original = "#808080"
        let color = Color(hex: original)!
        let roundtripped = color.hexString

        #expect(roundtripped.uppercased() == "#808080", "Gray should roundtrip correctly: got \(roundtripped)")
    }

    // MARK: - Edge Cases

    @Test("Color initializes from hex with leading whitespace")
    func test_color_initFromHex_leadingWhitespace() {
        let color = Color(hex: "  #FF5733")

        #expect(color != nil, "Color should trim leading whitespace")
    }

    @Test("Color initializes from hex with trailing whitespace")
    func test_color_initFromHex_trailingWhitespace() {
        let color = Color(hex: "#FF5733  ")

        #expect(color != nil, "Color should trim trailing whitespace")
    }

    @Test("Color initializes from hex with both leading and trailing whitespace")
    func test_color_initFromHex_bothWhitespace() {
        let color = Color(hex: "  #FF5733  ")

        #expect(color != nil, "Color should trim both leading and trailing whitespace")
    }

    @Test("Color initializes from hex with multiple hash symbols")
    func test_color_initFromHex_multipleHashSymbols() {
        // Current implementation only removes first # via replacingOccurrences
        // This might produce unexpected results, but test current behavior
        let color = Color(hex: "##FF5733")

        // Behavior: replacingOccurrences removes all #, so "FF5733" is parsed
        #expect(color != nil, "Multiple hashes are replaced, should still parse")
    }

    // MARK: - Boundary Values

    @Test("Color initializes from minimum RGB values (000000)")
    func test_color_initFromHex_minimumRGB() {
        let color = Color(hex: "#000000")

        #expect(color != nil, "Minimum RGB (000000) should be valid")
    }

    @Test("Color initializes from maximum RGB values (FFFFFF)")
    func test_color_initFromHex_maximumRGB() {
        let color = Color(hex: "#FFFFFF")

        #expect(color != nil, "Maximum RGB (FFFFFF) should be valid")
    }

    // MARK: - Error Cases (Invalid Input)

    @Test("Color returns nil for empty hex string")
    func test_color_initFromHex_emptyString_returnsNil() {
        let color = Color(hex: "")

        #expect(color == nil, "Empty string should return nil")
    }

    @Test("Color returns nil for whitespace-only string")
    func test_color_initFromHex_whitespaceOnly_returnsNil() {
        let color = Color(hex: "   ")

        #expect(color == nil, "Whitespace-only string should return nil")
    }

    @Test("Color returns nil for hash-only string")
    func test_color_initFromHex_hashOnly_returnsNil() {
        let color = Color(hex: "#")

        #expect(color == nil, "Hash-only string should return nil")
    }

    @Test("Color returns nil for short hex string (5 characters)")
    func test_color_initFromHex_shortString_returnsNil() {
        let color = Color(hex: "#FF573")

        #expect(color == nil, "Short hex string (5 chars) should return nil")
    }

    @Test("Color returns nil for long hex string (7 characters)")
    func test_color_initFromHex_longString_returnsNil() {
        let color = Color(hex: "#FF57333")

        #expect(color == nil, "Long hex string (7 chars) should return nil")
    }

    @Test("Color returns nil for non-hex characters")
    func test_color_initFromHex_nonHexCharacters_returnsNil() {
        let color = Color(hex: "#GGGGGG")

        #expect(color == nil, "Non-hex characters (G) should return nil")
    }

    @Test("Color returns nil for invalid characters in hex")
    func test_color_initFromHex_invalidCharacters_returnsNil() {
        let color = Color(hex: "#ZZZ123")

        #expect(color == nil, "Invalid characters (Z) should return nil")
    }

    @Test("Color returns nil for alphanumeric gibberish")
    func test_color_initFromHex_gibberish_returnsNil() {
        let color = Color(hex: "not-a-color")

        #expect(color == nil, "Gibberish string should return nil")
    }

    // MARK: - Property-Based Test (Idempotency)

    @Test("Property: any valid hex roundtrips to itself", arguments: [
        "#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF",
        "#123456", "#ABCDEF", "#987654", "#FEDCBA", "#112233",
        "#445566", "#778899", "#AABBCC", "#DDEEFF", "#102030"
    ])
    func test_property_hexRoundtrip_idempotent(hex: String) {
        let color = Color(hex: hex)
        #expect(color != nil, "Valid hex '\(hex)' should initialize")

        let roundtripped = color?.hexString.uppercased()
        #expect(roundtripped == hex.uppercased(), "Hex '\(hex)' should roundtrip to itself: got \(roundtripped ?? "nil")")
    }

    // MARK: - Real-World Color Examples (from trendy app)

    @Test("Color initializes from default iOS blue (#007AFF)")
    func test_color_initFromHex_iOSBlue() {
        let color = Color(hex: "#007AFF")

        #expect(color != nil, "iOS blue should initialize")
    }

    @Test("EventType default color roundtrips correctly")
    func test_eventType_defaultColor_roundtrips() {
        let defaultColor = "#007AFF"
        let color = Color(hex: defaultColor)!
        let roundtripped = color.hexString

        #expect(roundtripped.uppercased() == defaultColor.uppercased(), "EventType default color should roundtrip")
    }

    // MARK: - Hex String Format Validation

    @Test("hexString always includes hash prefix")
    func test_hexString_alwaysIncludesHashPrefix() {
        let color = Color(hex: "FF5733")! // No hash in input
        let hexString = color.hexString

        #expect(hexString.hasPrefix("#"), "hexString should always start with #: got \(hexString)")
    }

    @Test("hexString always has 7 characters (#RRGGBB)")
    func test_hexString_alwaysHas7Characters() {
        let color = Color(hex: "#ABC123")!
        let hexString = color.hexString

        #expect(hexString.count == 7, "hexString should have 7 characters (#RRGGBB): got \(hexString.count)")
    }

    @Test("hexString uses lowercase hex by default")
    func test_hexString_usesLowercaseByDefault() {
        let color = Color(hex: "#ABCDEF")!
        let hexString = color.hexString

        // Current implementation uses String(format: "#%06x", ...) which produces lowercase
        #expect(hexString == "#abcdef", "hexString should be lowercase by default: got \(hexString)")
    }

    // MARK: - Micro-Benchmark (Performance)

    @Test("Performance: Hex → Color conversion (1000 iterations)")
    func test_performance_hexToColor_1000Iterations() {
        let hexColors = [
            "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF",
            "#00FFFF", "#123456", "#ABCDEF", "#987654", "#FEDCBA"
        ]

        measureMetrics(
            description: "Hex → Color conversion (1000 iterations)",
            iterations: 10
        ) {
            for _ in 0..<100 {
                for hex in hexColors {
                    _ = Color(hex: hex)
                }
            }
        }
    }

    @Test("Performance: Color → Hex conversion (1000 iterations)")
    func test_performance_colorToHex_1000Iterations() {
        let colors = [
            Color(hex: "#FF0000")!, Color(hex: "#00FF00")!, Color(hex: "#0000FF")!,
            Color(hex: "#FFFF00")!, Color(hex: "#FF00FF")!, Color(hex: "#00FFFF")!,
            Color(hex: "#123456")!, Color(hex: "#ABCDEF")!, Color(hex: "#987654")!,
            Color(hex: "#FEDCBA")!
        ]

        measureMetrics(
            description: "Color → Hex conversion (1000 iterations)",
            iterations: 10
        ) {
            for _ in 0..<100 {
                for color in colors {
                    _ = color.hexString
                }
            }
        }
    }

    @Test("Performance: Roundtrip Hex → Color → Hex (1000 iterations)")
    func test_performance_roundtrip_1000Iterations() {
        let hexColors = [
            "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF",
            "#00FFFF", "#123456", "#ABCDEF", "#987654", "#FEDCBA"
        ]

        measureMetrics(
            description: "Roundtrip Hex → Color → Hex (1000 iterations)",
            iterations: 10
        ) {
            for _ in 0..<100 {
                for hex in hexColors {
                    if let color = Color(hex: hex) {
                        _ = color.hexString
                    }
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
