//
//  APIModels.swift
//  trendy
//
//  API models matching backend Go structs
//

import Foundation

// MARK: - Event Type Models

/// Backend EventType model
struct APIEventType: Codable, Identifiable {
    let id: String
    let userId: String
    let name: String
    let color: String
    let icon: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case color
        case icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Request model for creating event types
struct CreateEventTypeRequest: Codable {
    let id: String  // Client-generated UUIDv7
    let name: String
    let color: String
    let icon: String
}

/// Request model for updating event types.
/// Custom encoding ensures all fields are included in JSON output (including null values).
struct UpdateEventTypeRequest: Codable {
    let name: String?
    let color: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case name
        case color
        case icon
    }

    /// Custom encoding to ensure all fields are included in the JSON output.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(icon, forKey: .icon)
    }
}

/// Wrapper for queued event type updates (includes backend ID)
struct QueuedEventTypeUpdate: Codable {
    let backendId: String
    let request: UpdateEventTypeRequest
}

// MARK: - Event Models

/// Backend Event model
struct APIEvent: Codable, Identifiable {
    let id: String
    let userId: String
    let eventTypeId: String
    let timestamp: Date
    let notes: String?
    let isAllDay: Bool
    let endDate: Date?
    let sourceType: String
    let externalId: String?
    let originalTitle: String?
    let geofenceId: String?
    let locationLatitude: Double?
    let locationLongitude: Double?
    let locationName: String?
    let healthKitSampleId: String?
    let healthKitCategory: String?
    let properties: [String: APIPropertyValue]?
    let createdAt: Date
    let updatedAt: Date
    let eventType: APIEventType?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventTypeId = "event_type_id"
        case timestamp
        case notes
        case isAllDay = "is_all_day"
        case endDate = "end_date"
        case sourceType = "source_type"
        case externalId = "external_id"
        case originalTitle = "original_title"
        case geofenceId = "geofence_id"
        case locationLatitude = "location_latitude"
        case locationLongitude = "location_longitude"
        case locationName = "location_name"
        case healthKitSampleId = "healthkit_sample_id"
        case healthKitCategory = "healthkit_category"
        case properties
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case eventType = "event_type"
    }
}

/// Request model for creating events
struct CreateEventRequest: Codable {
    let id: String  // Client-generated UUIDv7
    let eventTypeId: String
    let timestamp: Date
    let notes: String?
    let isAllDay: Bool
    let endDate: Date?
    let sourceType: String
    let externalId: String?
    let originalTitle: String?
    let geofenceId: String?
    let locationLatitude: Double?
    let locationLongitude: Double?
    let locationName: String?
    let healthKitSampleId: String?
    let healthKitCategory: String?
    let properties: [String: APIPropertyValue]  // Required - backend rejects null

    enum CodingKeys: String, CodingKey {
        case id
        case eventTypeId = "event_type_id"
        case timestamp
        case notes
        case isAllDay = "is_all_day"
        case endDate = "end_date"
        case sourceType = "source_type"
        case externalId = "external_id"
        case originalTitle = "original_title"
        case geofenceId = "geofence_id"
        case locationLatitude = "location_latitude"
        case locationLongitude = "location_longitude"
        case locationName = "location_name"
        case healthKitSampleId = "healthkit_sample_id"
        case healthKitCategory = "healthkit_category"
        case properties
    }
}

/// Request model for batch creating events
struct BatchCreateEventsRequest: Codable {
    let events: [CreateEventRequest]
}

/// Response model for batch event creation
struct BatchCreateEventsResponse: Codable {
    let created: [APIEvent]
    let errors: [BatchError]?
    let total: Int
    let success: Int
    let failed: Int
}

/// Error for a specific item in a batch operation
struct BatchError: Codable {
    let index: Int
    let message: String
}

/// Request model for updating events.
/// Custom encoding ensures all fields are included in JSON output (including null values).
/// This is critical for PATCH-style updates where:
/// - Field present with value = update to that value
/// - Field present with null = clear the value
/// - Field absent = don't change
/// Swift's default JSONEncoder omits nil values, which would cause "clear field" operations to be ignored.
struct UpdateEventRequest: Codable {
    let eventTypeId: String?
    let timestamp: Date?
    let notes: String?
    let isAllDay: Bool?
    let endDate: Date?
    let sourceType: String?
    let externalId: String?
    let originalTitle: String?
    let geofenceId: String?
    let locationLatitude: Double?
    let locationLongitude: Double?
    let locationName: String?
    let healthKitSampleId: String?
    let healthKitCategory: String?
    let properties: [String: APIPropertyValue]?

    enum CodingKeys: String, CodingKey {
        case eventTypeId = "event_type_id"
        case timestamp
        case notes
        case isAllDay = "is_all_day"
        case endDate = "end_date"
        case sourceType = "source_type"
        case externalId = "external_id"
        case originalTitle = "original_title"
        case geofenceId = "geofence_id"
        case locationLatitude = "location_latitude"
        case locationLongitude = "location_longitude"
        case locationName = "location_name"
        case healthKitSampleId = "healthkit_sample_id"
        case healthKitCategory = "healthkit_category"
        case properties
    }

    /// Custom encoding to ensure all fields are included in the JSON output.
    /// This explicitly encodes nil values as JSON null, which is required for the backend
    /// to know that a field should be cleared (vs. left unchanged).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Always encode all fields - use encodeNil for nil values
        // This ensures the backend receives explicit null values for cleared fields
        try container.encode(eventTypeId, forKey: .eventTypeId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(notes, forKey: .notes)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(externalId, forKey: .externalId)
        try container.encode(originalTitle, forKey: .originalTitle)
        try container.encode(geofenceId, forKey: .geofenceId)
        try container.encode(locationLatitude, forKey: .locationLatitude)
        try container.encode(locationLongitude, forKey: .locationLongitude)
        try container.encode(locationName, forKey: .locationName)
        try container.encode(healthKitSampleId, forKey: .healthKitSampleId)
        try container.encode(healthKitCategory, forKey: .healthKitCategory)
        try container.encode(properties, forKey: .properties)
    }
}

// MARK: - Property Models

/// Property value from API
struct APIPropertyValue: Codable, Equatable {
    let type: String  // Maps to PropertyType enum
    let value: AnyCodable

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    // Custom encoding to match backend format
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        // Special handling for dates - encode as ISO8601 string
        if type == "date", let date = value.value as? Date {
            let dateString = ISO8601DateFormatter().string(from: date)
            try container.encode(AnyCodable(dateString), forKey: .value)
        } else {
            try container.encode(value, forKey: .value)
        }
    }

    // Convenience getters
    var stringValue: String? { value.value as? String }
    var intValue: Int? { value.value as? Int }
    var doubleValue: Double? { value.value as? Double }
    var boolValue: Bool? { value.value as? Bool }
    var dateValue: Date? {
        if let string = stringValue {
            return ISO8601DateFormatter().date(from: string)
        }
        return value.value as? Date
    }

    // Custom Equatable implementation
    static func == (lhs: APIPropertyValue, rhs: APIPropertyValue) -> Bool {
        guard lhs.type == rhs.type else { return false }

        // Compare values based on type
        switch lhs.type {
        case "text", "url", "email", "select":
            return lhs.stringValue == rhs.stringValue
        case "number", "duration":
            // Compare as doubles for flexibility
            return lhs.doubleValue == rhs.doubleValue
        case "boolean":
            return lhs.boolValue == rhs.boolValue
        case "date":
            return lhs.dateValue == rhs.dateValue
        default:
            // Fallback: try to compare as strings
            return String(describing: lhs.value.value) == String(describing: rhs.value.value)
        }
    }
}

/// Property definition from API
struct APIPropertyDefinition: Codable, Identifiable {
    let id: String
    let eventTypeId: String
    let userId: String
    let key: String
    let label: String
    let propertyType: String  // Maps to PropertyType enum
    let options: [String]?
    let defaultValue: AnyCodable?
    let displayOrder: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventTypeId = "event_type_id"
        case userId = "user_id"
        case key
        case label
        case propertyType = "property_type"
        case options
        case defaultValue = "default_value"
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Request model for creating property definitions
struct CreatePropertyDefinitionRequest: Codable {
    let id: String  // Client-generated UUIDv7
    let eventTypeId: String
    let key: String
    let label: String
    let propertyType: String  // PropertyType as string
    let options: [String]?
    let defaultValue: AnyCodable?
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case eventTypeId = "event_type_id"
        case key
        case label
        case propertyType = "property_type"
        case options
        case defaultValue = "default_value"
        case displayOrder = "display_order"
    }
}

/// Request model for updating property definitions.
/// Custom encoding ensures all fields are included in JSON output (including null values).
struct UpdatePropertyDefinitionRequest: Codable {
    let key: String?
    let label: String?
    let propertyType: String?  // PropertyType as string
    let options: [String]?
    let defaultValue: AnyCodable?
    let displayOrder: Int?

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case propertyType = "property_type"
        case options
        case defaultValue = "default_value"
        case displayOrder = "display_order"
    }

    /// Custom encoding to ensure all fields are included in the JSON output.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(label, forKey: .label)
        try container.encode(propertyType, forKey: .propertyType)
        try container.encode(options, forKey: .options)
        try container.encode(defaultValue, forKey: .defaultValue)
        try container.encode(displayOrder, forKey: .displayOrder)
    }
}

// MARK: - Authentication Models

/// Authentication response from backend
struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: APIUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

/// User model from backend
struct APIUser: Codable {
    let id: String
    let email: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Login request
struct LoginRequest: Codable {
    let email: String
    let password: String
}

/// Signup request
struct SignupRequest: Codable {
    let email: String
    let password: String
}

// MARK: - Analytics Models

/// Analytics summary response
struct AnalyticsSummary: Codable {
    let totalEvents: Int
    let eventsByType: [String: Int]
    let mostActiveEventType: String?
    let averageEventsPerDay: Double

    enum CodingKeys: String, CodingKey {
        case totalEvents = "total_events"
        case eventsByType = "events_by_type"
        case mostActiveEventType = "most_active_event_type"
        case averageEventsPerDay = "average_events_per_day"
    }
}

/// Trend data response
struct TrendData: Codable {
    let period: String
    let data: [TrendDataPoint]
}

/// Single trend data point
struct TrendDataPoint: Codable {
    let date: Date
    let count: Int
    let eventTypeId: String?

    enum CodingKeys: String, CodingKey {
        case date
        case count
        case eventTypeId = "event_type_id"
    }
}

// MARK: - Pagination Models

/// Paginated response wrapper
struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Error Response

/// Error response from API
struct APIErrorResponse: Codable {
    let error: String
    let message: String?
    let statusCode: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case statusCode = "status_code"
    }
}

// MARK: - Geofence Models

/// Backend Geofence model
struct APIGeofence: Codable, Identifiable {
    let id: String
    let userId: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let eventTypeEntryId: String?
    let eventTypeExitId: String?
    let isActive: Bool
    let notifyOnEntry: Bool
    let notifyOnExit: Bool
    let iosRegionIdentifier: String?
    let createdAt: Date
    let updatedAt: Date
    let eventTypeEntry: APIEventType?
    let eventTypeExit: APIEventType?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case latitude
        case longitude
        case radius
        case eventTypeEntryId = "event_type_entry_id"
        case eventTypeExitId = "event_type_exit_id"
        case isActive = "is_active"
        case notifyOnEntry = "notify_on_entry"
        case notifyOnExit = "notify_on_exit"
        case iosRegionIdentifier = "ios_region_identifier"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case eventTypeEntry = "event_type_entry"
        case eventTypeExit = "event_type_exit"
    }

    // Custom decoder to handle optional booleans from backend (which uses *bool)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radius = try container.decode(Double.self, forKey: .radius)
        eventTypeEntryId = try container.decodeIfPresent(String.self, forKey: .eventTypeEntryId)
        eventTypeExitId = try container.decodeIfPresent(String.self, forKey: .eventTypeExitId)
        // Handle optional booleans with defaults (backend uses *bool which can be null)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        notifyOnEntry = try container.decodeIfPresent(Bool.self, forKey: .notifyOnEntry) ?? false
        notifyOnExit = try container.decodeIfPresent(Bool.self, forKey: .notifyOnExit) ?? false
        iosRegionIdentifier = try container.decodeIfPresent(String.self, forKey: .iosRegionIdentifier)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        eventTypeEntry = try container.decodeIfPresent(APIEventType.self, forKey: .eventTypeEntry)
        eventTypeExit = try container.decodeIfPresent(APIEventType.self, forKey: .eventTypeExit)
    }
}

/// Request model for creating geofences
/// NOTE: id is optional - backend generates the ID if not provided
struct CreateGeofenceRequest: Codable {
    let id: String?  // Optional - backend generates ID if not provided
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let eventTypeEntryId: String?
    let eventTypeExitId: String?
    let isActive: Bool
    let notifyOnEntry: Bool
    let notifyOnExit: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case radius
        case eventTypeEntryId = "event_type_entry_id"
        case eventTypeExitId = "event_type_exit_id"
        case isActive = "is_active"
        case notifyOnEntry = "notify_on_entry"
        case notifyOnExit = "notify_on_exit"
    }

    /// Convenience initializer without id (backend generates)
    init(name: String, latitude: Double, longitude: Double, radius: Double, eventTypeEntryId: String?, eventTypeExitId: String?, isActive: Bool, notifyOnEntry: Bool, notifyOnExit: Bool) {
        self.id = nil
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.eventTypeEntryId = eventTypeEntryId
        self.eventTypeExitId = eventTypeExitId
        self.isActive = isActive
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
    }

    /// Full initializer with optional id
    init(id: String?, name: String, latitude: Double, longitude: Double, radius: Double, eventTypeEntryId: String?, eventTypeExitId: String?, isActive: Bool, notifyOnEntry: Bool, notifyOnExit: Bool) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.eventTypeEntryId = eventTypeEntryId
        self.eventTypeExitId = eventTypeExitId
        self.isActive = isActive
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
    }
}

/// Request model for updating geofences.
/// Custom encoding ensures all fields are included in JSON output (including null values).
struct UpdateGeofenceRequest: Codable {
    let name: String?
    let latitude: Double?
    let longitude: Double?
    let radius: Double?
    let eventTypeEntryId: String?
    let eventTypeExitId: String?
    let isActive: Bool?
    let notifyOnEntry: Bool?
    let notifyOnExit: Bool?
    let iosRegionIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case name
        case latitude
        case longitude
        case radius
        case eventTypeEntryId = "event_type_entry_id"
        case eventTypeExitId = "event_type_exit_id"
        case isActive = "is_active"
        case notifyOnEntry = "notify_on_entry"
        case notifyOnExit = "notify_on_exit"
        case iosRegionIdentifier = "ios_region_identifier"
    }

    /// Custom encoding to ensure all fields are included in the JSON output.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(radius, forKey: .radius)
        try container.encode(eventTypeEntryId, forKey: .eventTypeEntryId)
        try container.encode(eventTypeExitId, forKey: .eventTypeExitId)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(notifyOnEntry, forKey: .notifyOnEntry)
        try container.encode(notifyOnExit, forKey: .notifyOnExit)
        try container.encode(iosRegionIdentifier, forKey: .iosRegionIdentifier)
    }
}

/// Wrapper for queued geofence updates (includes backend ID)
struct QueuedGeofenceUpdate: Codable {
    let backendId: String
    let request: UpdateGeofenceRequest
}

// MARK: - Geofence Reconciliation

/// Represents a geofence definition for reconciliation with CLLocationManager.
/// Used to bridge between backend APIGeofence and iOS CLCircularRegion.
struct GeofenceDefinition: Hashable, Sendable {
    /// Region identifier for CLLocationManager - uses the UUIDv7 ID
    let identifier: String
    /// The canonical geofence ID (UUIDv7)
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let isActive: Bool
    let notifyOnEntry: Bool
    let notifyOnExit: Bool

    /// Creates from APIGeofence (backend data)
    init(from apiGeofence: APIGeofence) {
        // Use ios_region_identifier if set, otherwise fall back to ID
        self.identifier = apiGeofence.iosRegionIdentifier ?? apiGeofence.id
        self.id = apiGeofence.id
        self.name = apiGeofence.name
        self.latitude = apiGeofence.latitude
        self.longitude = apiGeofence.longitude
        self.radius = apiGeofence.radius
        self.isActive = apiGeofence.isActive
        self.notifyOnEntry = apiGeofence.notifyOnEntry
        self.notifyOnExit = apiGeofence.notifyOnExit
    }

    /// Creates from local Geofence
    init(from geofence: Geofence) {
        self.identifier = geofence.id
        self.id = geofence.id
        self.name = geofence.name
        self.latitude = geofence.latitude
        self.longitude = geofence.longitude
        self.radius = geofence.radius
        self.isActive = geofence.isActive
        self.notifyOnEntry = geofence.notifyOnEntry
        self.notifyOnExit = geofence.notifyOnExit
    }
}

// MARK: - Insights Models

/// Insight type enumeration
enum APIInsightType: String, Codable {
    case correlation
    case pattern
    case streak
    case summary
}

/// Insight category enumeration
enum APIInsightCategory: String, Codable {
    case crossEvent = "cross_event"
    case property
    case timeOfDay = "time_of_day"
    case dayOfWeek = "day_of_week"
    case weekly
    case streak
}

/// Confidence level for insights
enum APIConfidence: String, Codable {
    case high
    case medium
    case low
}

/// Direction for correlations and trends
enum APIDirection: String, Codable {
    case positive
    case negative
    case neutral
}

/// Single insight from the backend
struct APIInsight: Codable, Identifiable {
    let id: String
    let userId: String
    let insightType: APIInsightType
    let category: APIInsightCategory
    let title: String
    let description: String
    let eventTypeAId: String?
    let eventTypeBId: String?
    let propertyKey: String?
    let metricValue: Double
    let pValue: Double?
    let sampleSize: Int
    let confidence: APIConfidence
    let direction: APIDirection
    let metadata: [String: AnyCodable]?
    let computedAt: Date
    let validUntil: Date
    let createdAt: Date
    let eventTypeA: APIEventType?
    let eventTypeB: APIEventType?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightType = "insight_type"
        case category
        case title
        case description
        case eventTypeAId = "event_type_a_id"
        case eventTypeBId = "event_type_b_id"
        case propertyKey = "property_key"
        case metricValue = "metric_value"
        case pValue = "p_value"
        case sampleSize = "sample_size"
        case confidence
        case direction
        case metadata
        case computedAt = "computed_at"
        case validUntil = "valid_until"
        case createdAt = "created_at"
        case eventTypeA = "event_type_a"
        case eventTypeB = "event_type_b"
    }
}

/// Weekly summary for a single event type
struct APIWeeklySummary: Codable, Identifiable {
    var id: String { eventTypeId }
    let eventTypeId: String
    let eventTypeName: String
    let eventTypeColor: String
    let eventTypeIcon: String
    let thisWeekCount: Int
    let lastWeekCount: Int
    let changePercent: Double
    let direction: String  // "up", "down", "same"

    enum CodingKeys: String, CodingKey {
        case eventTypeId = "event_type_id"
        case eventTypeName = "event_type_name"
        case eventTypeColor = "event_type_color"
        case eventTypeIcon = "event_type_icon"
        case thisWeekCount = "this_week_count"
        case lastWeekCount = "last_week_count"
        case changePercent = "change_percent"
        case direction
    }
}

/// Streak data from backend
struct APIStreak: Codable, Identifiable {
    let id: String
    let userId: String
    let eventTypeId: String
    let streakType: String  // "current" or "longest"
    let startDate: Date
    let endDate: Date?
    let length: Int
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let eventType: APIEventType?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventTypeId = "event_type_id"
        case streakType = "streak_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case length
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case eventType = "event_type"
    }
}

/// Full insights response from backend
struct APIInsightsResponse: Codable {
    let correlations: [APIInsight]
    let patterns: [APIInsight]
    let streaks: [APIInsight]
    let weeklySummary: [APIWeeklySummary]
    let computedAt: Date
    let dataSufficient: Bool
    let minDaysNeeded: Int?
    let totalDays: Int

    enum CodingKeys: String, CodingKey {
        case correlations
        case patterns
        case streaks
        case weeklySummary = "weekly_summary"
        case computedAt = "computed_at"
        case dataSufficient = "data_sufficient"
        case minDaysNeeded = "min_days_needed"
        case totalDays = "total_days"
    }
}

/// Response wrapper for streaks endpoint
struct APIStreaksResponse: Codable {
    let streaks: [APIStreak]
}

/// Response wrapper for weekly summary endpoint
struct APIWeeklySummaryResponse: Codable {
    let weeklySummary: [APIWeeklySummary]

    enum CodingKeys: String, CodingKey {
        case weeklySummary = "weekly_summary"
    }
}

/// Response wrapper for correlations endpoint
struct APICorrelationsResponse: Codable {
    let correlations: [APIInsight]
    let computedAt: Date

    enum CodingKeys: String, CodingKey {
        case correlations
        case computedAt = "computed_at"
    }
}

// MARK: - Change Feed Models

/// Represents a single entry in the change feed
struct ChangeEntry: Codable {
    /// Monotonic cursor ID for pagination
    let id: Int64
    /// Type of entity: "event", "event_type", "geofence", "property_definition"
    let entityType: String
    /// Operation type: "create", "update", "delete"
    let operation: String
    /// Server ID of the affected entity
    let entityId: String
    /// Full entity data for create/update operations
    let data: ChangeEntryData?
    /// Timestamp for delete operations
    let deletedAt: Date?
    /// When the change was recorded
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case operation
        case entityId = "entity_id"
        case data
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }
}

/// Wrapper for flexible JSON data in change entries
struct ChangeEntryData: Codable {
    let rawData: [String: AnyCodableValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawData = try container.decode([String: AnyCodableValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawData)
    }

    // MARK: - Full Entity Decoders

    /// Extract an Event from the change data
    func asEvent(decoder: JSONDecoder) -> APIEvent? {
        guard let jsonData = try? JSONEncoder().encode(rawData) else { return nil }
        return try? decoder.decode(APIEvent.self, from: jsonData)
    }

    /// Extract an EventType from the change data
    func asEventType(decoder: JSONDecoder) -> APIEventType? {
        guard let jsonData = try? JSONEncoder().encode(rawData) else { return nil }
        return try? decoder.decode(APIEventType.self, from: jsonData)
    }

    /// Extract a Geofence from the change data
    func asGeofence(decoder: JSONDecoder) -> APIGeofence? {
        guard let jsonData = try? JSONEncoder().encode(rawData) else { return nil }
        return try? decoder.decode(APIGeofence.self, from: jsonData)
    }

    /// Extract a PropertyDefinition from the change data
    func asPropertyDefinition(decoder: JSONDecoder) -> APIPropertyDefinition? {
        guard let jsonData = try? JSONEncoder().encode(rawData) else { return nil }
        return try? decoder.decode(APIPropertyDefinition.self, from: jsonData)
    }

    // MARK: - Individual Field Accessors

    var timestamp: Date? {
        guard case .string(let str) = rawData["timestamp"] else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    var notes: String? {
        guard case .string(let str) = rawData["notes"] else { return nil }
        return str
    }

    var isAllDay: Bool? {
        guard case .bool(let val) = rawData["is_all_day"] else { return nil }
        return val
    }

    var endDate: Date? {
        guard case .string(let str) = rawData["end_date"] else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    var eventTypeId: String? {
        guard case .string(let str) = rawData["event_type_id"] else { return nil }
        return str
    }

    var sourceType: String? {
        guard case .string(let str) = rawData["source_type"] else { return nil }
        return str
    }

    var externalId: String? {
        guard case .string(let str) = rawData["external_id"] else { return nil }
        return str
    }

    var originalTitle: String? {
        guard case .string(let str) = rawData["original_title"] else { return nil }
        return str
    }

    var geofenceId: String? {
        guard case .string(let str) = rawData["geofence_id"] else { return nil }
        return str
    }

    var locationLatitude: Double? {
        switch rawData["location_latitude"] {
        case .double(let val): return val
        case .int(let val): return Double(val)
        default: return nil
        }
    }

    var locationLongitude: Double? {
        switch rawData["location_longitude"] {
        case .double(let val): return val
        case .int(let val): return Double(val)
        default: return nil
        }
    }

    var locationName: String? {
        guard case .string(let str) = rawData["location_name"] else { return nil }
        return str
    }

    var healthKitSampleId: String? {
        guard case .string(let str) = rawData["healthkit_sample_id"] else { return nil }
        return str
    }

    var healthKitCategory: String? {
        guard case .string(let str) = rawData["healthkit_category"] else { return nil }
        return str
    }

    var name: String? {
        guard case .string(let str) = rawData["name"] else { return nil }
        return str
    }

    var color: String? {
        guard case .string(let str) = rawData["color"] else { return nil }
        return str
    }

    var icon: String? {
        guard case .string(let str) = rawData["icon"] else { return nil }
        return str
    }

    var latitude: Double? {
        switch rawData["latitude"] {
        case .double(let val): return val
        case .int(let val): return Double(val)
        default: return nil
        }
    }

    var longitude: Double? {
        switch rawData["longitude"] {
        case .double(let val): return val
        case .int(let val): return Double(val)
        default: return nil
        }
    }

    var radius: Double? {
        switch rawData["radius"] {
        case .double(let val): return val
        case .int(let val): return Double(val)
        default: return nil
        }
    }

    var isActive: Bool? {
        guard case .bool(let val) = rawData["is_active"] else { return nil }
        return val
    }

    var notifyOnEntry: Bool? {
        guard case .bool(let val) = rawData["notify_on_entry"] else { return nil }
        return val
    }

    var notifyOnExit: Bool? {
        guard case .bool(let val) = rawData["notify_on_exit"] else { return nil }
        return val
    }

    var eventTypeEntryId: String? {
        guard case .string(let str) = rawData["event_type_entry_id"] else { return nil }
        return str
    }

    var eventTypeExitId: String? {
        guard case .string(let str) = rawData["event_type_exit_id"] else { return nil }
        return str
    }

    var key: String? {
        guard case .string(let str) = rawData["key"] else { return nil }
        return str
    }

    var label: String? {
        guard case .string(let str) = rawData["label"] else { return nil }
        return str
    }

    var propertyType: String? {
        guard case .string(let str) = rawData["property_type"] else { return nil }
        return str
    }

    var displayOrder: Int? {
        guard case .int(let val) = rawData["display_order"] else { return nil }
        return val
    }

    var options: [String]? {
        guard case .array(let arr) = rawData["options"] else { return nil }
        return arr.compactMap { value -> String? in
            guard case .string(let str) = value else { return nil }
            return str
        }
    }

    /// Extract properties dictionary from change data
    /// Properties are stored as {"key": {"type": "...", "value": ...}}
    var properties: [String: APIPropertyValue]? {
        guard case .dictionary(let dict) = rawData["properties"] else { return nil }
        var result: [String: APIPropertyValue] = [:]
        for (key, value) in dict {
            guard case .dictionary(let propDict) = value else { continue }
            guard case .string(let typeStr) = propDict["type"] else { continue }
            guard let valueData = propDict["value"] else { continue }

            // Convert AnyCodableValue to AnyCodable for APIPropertyValue
            let anyCodableValue: AnyCodable
            switch valueData {
            case .string(let s): anyCodableValue = AnyCodable(s)
            case .int(let i): anyCodableValue = AnyCodable(i)
            case .double(let d): anyCodableValue = AnyCodable(d)
            case .bool(let b): anyCodableValue = AnyCodable(b)
            case .null: anyCodableValue = AnyCodable(NSNull())
            case .array(let arr):
                // Convert array - simplified, assuming simple types
                let converted = arr.compactMap { item -> Any? in
                    switch item {
                    case .string(let s): return s
                    case .int(let i): return i
                    case .double(let d): return d
                    case .bool(let b): return b
                    default: return nil
                    }
                }
                anyCodableValue = AnyCodable(converted)
            case .dictionary:
                // Nested dictionaries - skip for now
                continue
            }

            result[key] = APIPropertyValue(type: typeStr, value: anyCodableValue)
        }
        return result.isEmpty ? nil : result
    }
}

/// Response from the change feed endpoint
struct ChangeFeedResponse: Codable {
    /// Array of changes since the provided cursor
    let changes: [ChangeEntry]
    /// Cursor for the next page (0 if no more changes)
    let nextCursor: Int64
    /// Whether there are more changes to fetch
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case changes
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

/// Flexible JSON value for change entry data
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dictionary = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dictionary)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
