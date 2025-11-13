import Foundation

struct PropertyValue: Codable, Equatable {
    let type: PropertyType
    let value: AnyCodable

    init(type: PropertyType, value: Any) {
        self.type = type
        self.value = AnyCodable(value)
    }

    // Convenience getters for different types
    var stringValue: String? {
        value.value as? String
    }

    var intValue: Int? {
        value.value as? Int
    }

    var doubleValue: Double? {
        value.value as? Double
    }

    var boolValue: Bool? {
        value.value as? Bool
    }

    var dateValue: Date? {
        if let string = stringValue {
            return ISO8601DateFormatter().date(from: string)
        }
        return value.value as? Date
    }

    // Encode date as ISO8601 string
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        // Special handling for dates - encode as ISO8601 string
        if type == .date, let date = value.value as? Date {
            let dateString = ISO8601DateFormatter().string(from: date)
            try container.encode(AnyCodable(dateString), forKey: .value)
        } else {
            try container.encode(value, forKey: .value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    // Custom Equatable implementation
    static func == (lhs: PropertyValue, rhs: PropertyValue) -> Bool {
        guard lhs.type == rhs.type else { return false }

        // Compare values based on type
        switch lhs.type {
        case .text, .url, .email, .select:
            return lhs.stringValue == rhs.stringValue
        case .number, .duration:
            // Compare as doubles for flexibility
            return lhs.doubleValue == rhs.doubleValue
        case .boolean:
            return lhs.boolValue == rhs.boolValue
        case .date:
            return lhs.dateValue == rhs.dateValue
        }
    }
}
