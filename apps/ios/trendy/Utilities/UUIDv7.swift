//
//  UUIDv7.swift
//  trendy
//
//  RFC 9562 compliant UUIDv7 implementation for offline-first ID generation
//

import Foundation
import Security

/// Generates RFC 9562 compliant UUIDv7 values.
///
/// UUIDv7 provides time-ordered, globally unique identifiers that can be generated
/// on any device without server coordination. This is essential for offline-first
/// architectures where entities must be created before syncing with the backend.
///
/// Structure (128 bits total):
/// - Bytes 0-5 (48 bits): Unix timestamp in milliseconds (big-endian)
/// - Byte 6 (8 bits): Version nibble (0111) + 4 bits of random
/// - Byte 7 (8 bits): 8 bits of random
/// - Byte 8 (8 bits): Variant nibble (10) + 6 bits of random
/// - Bytes 9-15 (56 bits): Random data
///
/// Benefits:
/// - Time-ordered: Naturally sortable, useful for conflict resolution
/// - Globally unique: No collision risk across devices (122 bits of randomness + timestamp)
/// - Client-generatable: No server round-trip needed
/// - Embedded timestamp: First 48 bits = milliseconds since Unix epoch
struct UUIDv7 {

    /// Tracks the last timestamp used to ensure monotonicity within the same millisecond
    private static var lastTimestamp: UInt64 = 0
    private static var counter: UInt16 = 0
    private static let lock = NSLock()

    /// Generates a new UUIDv7 string.
    ///
    /// Thread-safe and guarantees monotonically increasing IDs even when called
    /// multiple times within the same millisecond.
    ///
    /// - Returns: A lowercase UUID string in the format "xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx"
    static func generate() -> String {
        lock.lock()
        defer { lock.unlock() }

        // Get current timestamp in milliseconds
        var timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

        // Handle clock skew and ensure monotonicity
        if timestamp <= lastTimestamp {
            // Same millisecond or clock went backward - use counter
            if counter < 0xFFF {
                counter += 1
                timestamp = lastTimestamp
            } else {
                // Counter overflow - wait for next millisecond
                timestamp = lastTimestamp + 1
                counter = 0
            }
        } else {
            // New millisecond - reset counter
            counter = 0
        }
        lastTimestamp = timestamp

        // Generate random bytes
        var randomBytes = [UInt8](repeating: 0, count: 10)
        let status = SecRandomCopyBytes(kSecRandomDefault, 10, &randomBytes)
        if status != errSecSuccess {
            // Fallback to less secure random if SecRandomCopyBytes fails
            for i in 0..<10 {
                randomBytes[i] = UInt8.random(in: 0...255)
            }
        }

        // Build the UUID bytes
        var bytes = [UInt8](repeating: 0, count: 16)

        // Bytes 0-5: 48-bit timestamp (big-endian)
        bytes[0] = UInt8((timestamp >> 40) & 0xFF)
        bytes[1] = UInt8((timestamp >> 32) & 0xFF)
        bytes[2] = UInt8((timestamp >> 24) & 0xFF)
        bytes[3] = UInt8((timestamp >> 16) & 0xFF)
        bytes[4] = UInt8((timestamp >> 8) & 0xFF)
        bytes[5] = UInt8(timestamp & 0xFF)

        // Byte 6: version 7 (0111xxxx) - upper 4 bits are version, lower 4 are random
        bytes[6] = (randomBytes[0] & 0x0F) | 0x70

        // Byte 7: random
        bytes[7] = randomBytes[1]

        // Byte 8: variant (10xxxxxx) - upper 2 bits are variant, lower 6 are random
        bytes[8] = (randomBytes[2] & 0x3F) | 0x80

        // Bytes 9-15: random
        for i in 0..<7 {
            bytes[9 + i] = randomBytes[3 + i]
        }

        // Format as UUID string (lowercase)
        return formatUUID(bytes)
    }

    /// Extracts the timestamp from a UUIDv7 string.
    ///
    /// - Parameter uuidv7: A UUID string (with or without hyphens)
    /// - Returns: The embedded timestamp as a Date, or nil if the UUID is invalid
    static func extractTimestamp(_ uuidv7: String) -> Date? {
        // Remove hyphens and validate length
        let hex = uuidv7.replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32 else { return nil }

        // Validate it's a UUIDv7 (check version nibble)
        let versionIndex = hex.index(hex.startIndex, offsetBy: 12)
        guard hex[versionIndex] == "7" else { return nil }

        // First 12 hex chars = 48 bits of timestamp
        let timestampHex = String(hex.prefix(12))
        guard let timestamp = UInt64(timestampHex, radix: 16) else { return nil }

        return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

    /// Validates that a string is a properly formatted UUIDv7.
    ///
    /// - Parameter uuidv7: A UUID string to validate
    /// - Returns: true if the string is a valid UUIDv7, false otherwise
    static func isValid(_ uuidv7: String) -> Bool {
        let hex = uuidv7.replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32 else { return false }

        // Check all characters are valid hex
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        guard hex.unicodeScalars.allSatisfy({ hexChars.contains($0) }) else { return false }

        // Check version nibble is 7
        let versionIndex = hex.index(hex.startIndex, offsetBy: 12)
        guard hex[versionIndex] == "7" else { return false }

        // Check variant nibble is 8, 9, a, or b
        let variantIndex = hex.index(hex.startIndex, offsetBy: 16)
        let variantChar = hex[variantIndex]
        guard variantChar == "8" || variantChar == "9" || variantChar == "a" || variantChar == "b" else {
            return false
        }

        return true
    }

    /// Formats bytes as a UUID string.
    private static func formatUUID(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()

        // Insert hyphens at positions 8, 12, 16, 20
        var result = ""
        for (index, char) in hex.enumerated() {
            if index == 8 || index == 12 || index == 16 || index == 20 {
                result += "-"
            }
            result.append(char)
        }
        return result
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Returns true if this string is a valid UUIDv7.
    var isValidUUIDv7: Bool {
        UUIDv7.isValid(self)
    }

    /// Extracts the timestamp from this UUIDv7 string.
    var uuidv7Timestamp: Date? {
        UUIDv7.extractTimestamp(self)
    }
}
