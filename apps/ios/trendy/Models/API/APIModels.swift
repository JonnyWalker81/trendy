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

    enum CodingKeys: String, CodingKey {
        case eventTypeId = "event_type_id"
        case timestamp
        case notes
        case isAllDay = "is_all_day"
        case endDate = "end_date"
        case sourceType = "source_type"
        case externalId = "external_id"
        case originalTitle = "original_title"
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

    enum CodingKeys: String, CodingKey {
        case eventTypeId = "event_type_id"
        case timestamp
        case notes
        case isAllDay = "is_all_day"
        case endDate = "end_date"
        case sourceType = "source_type"
        case externalId = "external_id"
        case originalTitle = "original_title"
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
