import Foundation
import SwiftData

enum PropertyType: String, Codable, CaseIterable {
    case text
    case number
    case boolean
    case date
    case select
    case duration
    case url
    case email

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .date: return "Date"
        case .select: return "Select"
        case .duration: return "Duration"
        case .url: return "URL"
        case .email: return "Email"
        }
    }
}

@Model
final class PropertyDefinition {
    /// UUIDv7 identifier - client-generated, globally unique, time-ordered
    /// This is THE canonical ID used both locally and on the server
    @Attribute(.unique) var id: String
    /// Sync status with the backend
    var syncStatusRaw: String = SyncStatus.pending.rawValue
    /// EventType ID (UUIDv7 string)
    var eventTypeId: String
    var key: String
    var label: String
    var propertyType: PropertyType
    var optionsData: Data? // Encoded [String]
    var defaultValueData: Data? // Encoded AnyCodable
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var eventType: EventType?

    // MARK: - Computed Properties

    /// Sync status computed property for convenient access
    @Transient var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var options: [String] {
        get {
            guard let data = optionsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            optionsData = try? JSONEncoder().encode(newValue)
        }
    }

    var defaultValue: AnyCodable? {
        get {
            guard let data = defaultValueData else { return nil }
            return try? JSONDecoder().decode(AnyCodable.self, from: data)
        }
        set {
            defaultValueData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        id: String = UUIDv7.generate(),
        eventTypeId: String,
        key: String,
        label: String,
        propertyType: PropertyType,
        options: [String] = [],
        defaultValue: AnyCodable? = nil,
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.syncStatusRaw = syncStatus.rawValue
        self.eventTypeId = eventTypeId
        self.key = key
        self.label = label
        self.propertyType = propertyType
        self.optionsData = try? JSONEncoder().encode(options)
        self.defaultValueData = try? JSONEncoder().encode(defaultValue)
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// AnyCodable for flexible JSON encoding/decoding
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
