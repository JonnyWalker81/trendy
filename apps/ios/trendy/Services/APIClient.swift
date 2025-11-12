//
//  APIClient.swift
//  trendy
//
//  HTTP client for backend API communication
//

import Foundation

/// HTTP client for backend API requests
class APIClient {
    private let baseURL: String
    private let session: URLSession
    private let supabaseService: SupabaseService

    // JSON encoder/decoder with ISO8601 date strategy
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Initialize APIClient with configuration
    /// - Parameters:
    ///   - configuration: API configuration containing base URL
    ///   - supabaseService: Supabase service for authentication
    init(configuration: APIConfiguration, supabaseService: SupabaseService) {
        self.baseURL = configuration.baseURL
        self.session = URLSession.shared
        self.supabaseService = supabaseService
    }

    // MARK: - Helper Methods

    /// Build URL for endpoint
    private func url(for endpoint: String) -> URL {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            fatalError("Invalid URL: \(baseURL)\(endpoint)")
        }
        return url
    }

    /// Get auth headers with Bearer token
    private func authHeaders() async throws -> [String: String] {
        let token = try await supabaseService.getAccessToken()
        return [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token)"
        ]
    }

    /// Perform HTTP request with automatic auth header injection
    private func request<T: Decodable>(
        _ method: String,
        endpoint: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var urlRequest = URLRequest(url: url(for: endpoint))
        urlRequest.httpMethod = method

        // Add headers
        if requiresAuth {
            let headers = try await authHeaders()
            headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        } else {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Add body if provided
        if let body = body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        // Perform request
        let (data, response) = try await session.data(for: urlRequest)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle error responses
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error, httpResponse.statusCode)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        // Decode response
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            print("Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw APIError.decodingError(error)
        }
    }

    /// Perform HTTP request without response body (for DELETE)
    private func requestWithoutResponse(
        _ method: String,
        endpoint: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        var urlRequest = URLRequest(url: url(for: endpoint))
        urlRequest.httpMethod = method

        // Add headers
        if requiresAuth {
            let headers = try await authHeaders()
            headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        } else {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Add body if provided
        if let body = body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        // Perform request
        let (_, response) = try await session.data(for: urlRequest)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Event Type Endpoints

    /// Get all event types
    func getEventTypes() async throws -> [APIEventType] {
        return try await request("GET", endpoint: "/event-types")
    }

    /// Get single event type
    func getEventType(id: String) async throws -> APIEventType {
        return try await request("GET", endpoint: "/event-types/\(id)")
    }

    /// Create event type
    func createEventType(_ request: CreateEventTypeRequest) async throws -> APIEventType {
        return try await self.request("POST", endpoint: "/event-types", body: request)
    }

    /// Update event type
    func updateEventType(id: String, _ request: UpdateEventTypeRequest) async throws -> APIEventType {
        return try await self.request("PUT", endpoint: "/event-types/\(id)", body: request)
    }

    /// Delete event type
    func deleteEventType(id: String) async throws {
        try await requestWithoutResponse("DELETE", endpoint: "/event-types/\(id)")
    }

    // MARK: - Event Endpoints

    /// Get all events with optional pagination
    func getEvents(limit: Int = 1000, offset: Int = 0) async throws -> [APIEvent] {
        return try await request("GET", endpoint: "/events?limit=\(limit)&offset=\(offset)")
    }

    /// Get single event
    func getEvent(id: String) async throws -> APIEvent {
        return try await request("GET", endpoint: "/events/\(id)")
    }

    /// Create event
    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent {
        return try await self.request("POST", endpoint: "/events", body: request)
    }

    /// Update event
    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> APIEvent {
        return try await self.request("PUT", endpoint: "/events/\(id)", body: request)
    }

    /// Delete event
    func deleteEvent(id: String) async throws {
        try await requestWithoutResponse("DELETE", endpoint: "/events/\(id)")
    }

    /// Get events by external ID (for duplicate detection during migration)
    func getEventByExternalId(_ externalId: String) async throws -> APIEvent? {
        let events: [APIEvent] = try await request("GET", endpoint: "/events?external_id=\(externalId)")
        return events.first
    }

    // MARK: - Analytics Endpoints

    /// Get analytics summary
    func getAnalyticsSummary() async throws -> AnalyticsSummary {
        return try await request("GET", endpoint: "/analytics/summary")
    }

    /// Get trend data
    func getTrends(period: String = "month", startDate: Date? = nil, endDate: Date? = nil) async throws -> TrendData {
        var endpoint = "/analytics/trends?period=\(period)"

        if let startDate = startDate {
            let formatter = ISO8601DateFormatter()
            endpoint += "&start_date=\(formatter.string(from: startDate))"
        }

        if let endDate = endDate {
            let formatter = ISO8601DateFormatter()
            endpoint += "&end_date=\(formatter.string(from: endDate))"
        }

        return try await request("GET", endpoint: endpoint)
    }

    /// Get event type specific analytics
    func getEventTypeAnalytics(id: String) async throws -> AnalyticsSummary {
        return try await request("GET", endpoint: "/analytics/event-type/\(id)")
    }

    // MARK: - Health Check

    /// Check if API is reachable
    func healthCheck() async throws -> Bool {
        let url = URL(string: baseURL.replacingOccurrences(of: "/api/v1", with: "/health"))!
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200...299).contains(httpResponse.statusCode)
    }
}

// MARK: - Error Types

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String, Int)
    case decodingError(Error)
    case networkError(Error)
    case noConnection

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message, let code):
            return "Server error (\(code)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noConnection:
            return "No internet connection"
        }
    }
}
