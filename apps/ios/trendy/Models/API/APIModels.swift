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
    let name: String
    let color: String
    let icon: String
}

/// Request model for updating event types
struct UpdateEventTypeRequest: Codable {
    let name: String?
    let color: String?
    let icon: String?
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
        case properties
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case eventType = "event_type"
    }
}

/// Request model for creating events
struct CreateEventRequest: Codable {
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
        case properties
    }
}

/// Request model for updating events
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
        case properties
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
    let eventTypeId: String
    let key: String
    let label: String
    let propertyType: String  // PropertyType as string
    let options: [String]?
    let defaultValue: AnyCodable?
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case eventTypeId = "event_type_id"
        case key
        case label
        case propertyType = "property_type"
        case options
        case defaultValue = "default_value"
        case displayOrder = "display_order"
    }
}

/// Request model for updating property definitions
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case eventTypeEntry = "event_type_entry"
        case eventTypeExit = "event_type_exit"
    }
}

/// Request model for creating geofences
struct CreateGeofenceRequest: Codable {
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
}

/// Request model for updating geofences
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
    }
}

/// Wrapper for queued geofence updates (includes backend ID)
struct QueuedGeofenceUpdate: Codable {
    let backendId: String
    let request: UpdateGeofenceRequest
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
