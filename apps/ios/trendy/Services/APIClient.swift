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

    // Retry configuration for rate limiting
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0 // Start with 1 second

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

        Log.api.info("APIClient initialized", context: .with { ctx in
            ctx.add("base_url", configuration.baseURL)
        })
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

    /// Perform HTTP request with automatic auth header injection and retry logic
    private func request<T: Decodable>(
        _ method: String,
        endpoint: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true,
        retryCount: Int = 0
    ) async throws -> T {
        let startTime = Date()
        var urlRequest = URLRequest(url: url(for: endpoint))
        urlRequest.httpMethod = method

        Log.api.request(method, path: endpoint)

        // Add headers
        if requiresAuth {
            let headers = try await authHeaders()
            headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        } else {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Add body if provided
        var encodedBody: Data?
        if let body = body {
            encodedBody = try encoder.encode(body)
            urlRequest.httpBody = encodedBody

            // Log request body for event updates (works in all builds for debugging)
            if endpoint.contains("/events/") && method == "PUT" {
                if let bodyString = String(data: encodedBody!, encoding: .utf8) {
                    Log.api.info("PUT /events request body", context: .with { ctx in
                        ctx.add("body", bodyString)
                    })
                }
            }
        }

        // Perform request
        let (data, response) = try await session.data(for: urlRequest)
        let duration = Date().timeIntervalSince(startTime)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            Log.api.error("Invalid response", context: .with { ctx in
                ctx.add("method", method)
                ctx.add("endpoint", endpoint)
            })
            throw APIError.invalidResponse
        }

        Log.api.response(method, path: endpoint, statusCode: httpResponse.statusCode, duration: duration)

        // Handle rate limiting with exponential backoff
        if httpResponse.statusCode == 429 && retryCount < maxRetries {
            let delay = baseRetryDelay * pow(2.0, Double(retryCount))
            Log.api.warning("Rate limited, retrying", context: .with { ctx in
                ctx.add("endpoint", endpoint)
                ctx.add("retry_count", retryCount + 1)
                ctx.add("delay_seconds", delay)
            })
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await request(method, endpoint: endpoint, body: body, requiresAuth: requiresAuth, retryCount: retryCount + 1)
        }

        // Log response body for event updates (works in all builds for debugging)
        if endpoint.contains("/events") && method == "PUT" {
            if let responseString = String(data: data, encoding: .utf8) {
                // Truncate long responses
                let truncated = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                Log.api.info("PUT /events response", context: .with { ctx in
                    ctx.add("response", truncated)
                })
            }
        }

        // Handle error responses
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                Log.api.warning("Server error response", context: .with { ctx in
                    ctx.add("endpoint", endpoint)
                    ctx.add("status", httpResponse.statusCode)
                    ctx.add("error_message", errorResponse.error)
                })
                throw APIError.serverError(errorResponse.error, httpResponse.statusCode)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        // Decode response
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.api.error("Decoding error", error: error, context: .with { ctx in
                ctx.add("endpoint", endpoint)
                ctx.add("response_size", data.count)
            })
            #if DEBUG
            // Only log response data in debug builds to prevent PII leakage
            Log.api.debug("Response data for debugging", context: .with { ctx in
                ctx.add("data", String(data: data, encoding: .utf8) ?? "nil")
            })
            #endif
            throw APIError.decodingError(error)
        }
    }

    /// Perform HTTP request without response body (for DELETE) with retry logic
    private func requestWithoutResponse(
        _ method: String,
        endpoint: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true,
        retryCount: Int = 0
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

        // Handle rate limiting with exponential backoff
        if httpResponse.statusCode == 429 && retryCount < maxRetries {
            let delay = baseRetryDelay * pow(2.0, Double(retryCount))
            Log.api.warning("Rate limited, retrying", context: .with { ctx in
                ctx.add("endpoint", endpoint)
                ctx.add("retry_count", retryCount + 1)
                ctx.add("delay_seconds", delay)
            })
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await requestWithoutResponse(method, endpoint: endpoint, body: body, requiresAuth: requiresAuth, retryCount: retryCount + 1)
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

    /// Fetch all events using pagination
    /// This method iterates through all pages to ensure no events are missed
    /// - Parameter batchSize: Number of events to fetch per request (default: 500)
    /// - Returns: Array of all events for the user
    func getAllEvents(batchSize: Int = 500) async throws -> [APIEvent] {
        var allEvents: [APIEvent] = []
        var offset = 0

        while true {
            let batch: [APIEvent] = try await request(
                "GET",
                endpoint: "/events?limit=\(batchSize)&offset=\(offset)"
            )
            allEvents.append(contentsOf: batch)

            Log.api.debug("Fetched events batch", context: .with { ctx in
                ctx.add("batch_size", batch.count)
                ctx.add("offset", offset)
                ctx.add("total_so_far", allEvents.count)
            })

            // If we got fewer than requested, we've reached the end
            if batch.count < batchSize {
                break
            }
            offset += batchSize
        }

        Log.api.info("Fetched all events", context: .with { ctx in
            ctx.add("total_events", allEvents.count)
        })

        return allEvents
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

    /// Batch create events (up to 500 at a time)
    func createEventsBatch(_ events: [CreateEventRequest]) async throws -> BatchCreateEventsResponse {
        let request = BatchCreateEventsRequest(events: events)
        return try await self.request("POST", endpoint: "/events/batch", body: request)
    }

    /// Get events by external ID (for duplicate detection during migration)
    func getEventByExternalId(_ externalId: String) async throws -> APIEvent? {
        let events: [APIEvent] = try await request("GET", endpoint: "/events?external_id=\(externalId)")
        return events.first
    }

    // MARK: - Property Definition Endpoints

    /// Get property definitions for an event type
    func getPropertyDefinitions(eventTypeId: String) async throws -> [APIPropertyDefinition] {
        return try await request("GET", endpoint: "/event-types/\(eventTypeId)/properties")
    }

    /// Get single property definition
    func getPropertyDefinition(id: String) async throws -> APIPropertyDefinition {
        return try await request("GET", endpoint: "/property-definitions/\(id)")
    }

    /// Create property definition
    func createPropertyDefinition(eventTypeId: String, _ request: CreatePropertyDefinitionRequest) async throws -> APIPropertyDefinition {
        return try await self.request("POST", endpoint: "/event-types/\(eventTypeId)/properties", body: request)
    }

    /// Update property definition
    func updatePropertyDefinition(id: String, _ request: UpdatePropertyDefinitionRequest) async throws -> APIPropertyDefinition {
        return try await self.request("PUT", endpoint: "/property-definitions/\(id)", body: request)
    }

    /// Delete property definition
    func deletePropertyDefinition(id: String) async throws {
        try await requestWithoutResponse("DELETE", endpoint: "/property-definitions/\(id)")
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

    // MARK: - Geofence Endpoints

    /// Get all geofences
    /// - Parameter activeOnly: If true, only return active geofences
    func getGeofences(activeOnly: Bool = false) async throws -> [APIGeofence] {
        let endpoint = activeOnly ? "/geofences?active=true" : "/geofences"
        return try await request("GET", endpoint: endpoint)
    }

    /// Get single geofence
    func getGeofence(id: String) async throws -> APIGeofence {
        return try await request("GET", endpoint: "/geofences/\(id)")
    }

    /// Create geofence
    func createGeofence(_ request: CreateGeofenceRequest) async throws -> APIGeofence {
        return try await self.request("POST", endpoint: "/geofences", body: request)
    }

    /// Update geofence
    func updateGeofence(id: String, _ request: UpdateGeofenceRequest) async throws -> APIGeofence {
        return try await self.request("PUT", endpoint: "/geofences/\(id)", body: request)
    }

    /// Delete geofence
    func deleteGeofence(id: String) async throws {
        try await requestWithoutResponse("DELETE", endpoint: "/geofences/\(id)")
    }

    // MARK: - Change Feed

    /// Get changes since a cursor for incremental sync
    /// - Parameters:
    ///   - since: Cursor to start from (0 for initial sync)
    ///   - limit: Maximum number of changes to return
    /// - Returns: Change feed response with changes and next cursor
    func getChanges(since cursor: Int64, limit: Int = 100) async throws -> ChangeFeedResponse {
        return try await request("GET", endpoint: "/changes?since=\(cursor)&limit=\(limit)")
    }

    /// Get the latest cursor (max change_log ID) for the current user.
    /// Useful after bootstrap to skip all existing change_log entries.
    func getLatestCursor() async throws -> Int64 {
        struct CursorResponse: Decodable {
            let cursor: Int64
        }
        let response: CursorResponse = try await request("GET", endpoint: "/changes/latest-cursor")
        return response.cursor
    }

    // MARK: - Idempotent Create Operations

    /// Create event with idempotency key for exactly-once semantics
    func createEventWithIdempotency(_ request: CreateEventRequest, idempotencyKey: String) async throws -> APIEvent {
        return try await requestWithIdempotency("POST", endpoint: "/events", body: request, idempotencyKey: idempotencyKey)
    }

    /// Create event type with idempotency key for exactly-once semantics
    func createEventTypeWithIdempotency(_ request: CreateEventTypeRequest, idempotencyKey: String) async throws -> APIEventType {
        return try await requestWithIdempotency("POST", endpoint: "/event-types", body: request, idempotencyKey: idempotencyKey)
    }

    /// Create geofence with idempotency key for exactly-once semantics
    func createGeofenceWithIdempotency(_ request: CreateGeofenceRequest, idempotencyKey: String) async throws -> APIGeofence {
        return try await requestWithIdempotency("POST", endpoint: "/geofences", body: request, idempotencyKey: idempotencyKey)
    }

    /// Create property definition with idempotency key for exactly-once semantics
    func createPropertyDefinitionWithIdempotency(_ request: CreatePropertyDefinitionRequest, idempotencyKey: String) async throws -> APIPropertyDefinition {
        return try await requestWithIdempotency("POST", endpoint: "/event-types/\(request.eventTypeId)/properties", body: request, idempotencyKey: idempotencyKey)
    }

    /// Generic request with idempotency key header
    private func requestWithIdempotency<T: Decodable>(
        _ method: String,
        endpoint: String,
        body: Encodable,
        idempotencyKey: String,
        retryCount: Int = 0
    ) async throws -> T {
        let startTime = Date()
        var urlRequest = URLRequest(url: url(for: endpoint))
        urlRequest.httpMethod = method

        Log.api.request(method, path: endpoint)

        // Add headers including idempotency key
        let headers = try await authHeaders()
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")

        // Add body
        let encodedBody = try encoder.encode(body)
        urlRequest.httpBody = encodedBody

        // Perform request
        let (data, response) = try await session.data(for: urlRequest)
        let duration = Date().timeIntervalSince(startTime)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            Log.api.error("Invalid response", context: .with { ctx in
                ctx.add("method", method)
                ctx.add("endpoint", endpoint)
            })
            throw APIError.invalidResponse
        }

        Log.api.response(method, path: endpoint, statusCode: httpResponse.statusCode, duration: duration)

        // Handle rate limiting with exponential backoff
        if httpResponse.statusCode == 429 && retryCount < maxRetries {
            let delay = baseRetryDelay * pow(2.0, Double(retryCount))
            Log.api.warning("Rate limited, retrying", context: .with { ctx in
                ctx.add("endpoint", endpoint)
                ctx.add("retry_count", retryCount + 1)
                ctx.add("delay_seconds", delay)
            })
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await requestWithIdempotency(method, endpoint: endpoint, body: body, idempotencyKey: idempotencyKey, retryCount: retryCount + 1)
        }

        // Handle error responses
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                Log.api.warning("Server error response", context: .with { ctx in
                    ctx.add("endpoint", endpoint)
                    ctx.add("status", httpResponse.statusCode)
                    ctx.add("error_message", errorResponse.error)
                })
                throw APIError.serverError(errorResponse.error, httpResponse.statusCode)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        // Decode response
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.api.error("Decoding error", error: error, context: .with { ctx in
                ctx.add("endpoint", endpoint)
                ctx.add("response_size", data.count)
            })
            throw APIError.decodingError(error)
        }
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

    // MARK: - Insights Endpoints

    /// Get all insights (correlations, patterns, streaks, weekly summary)
    func getInsights() async throws -> APIInsightsResponse {
        return try await request("GET", endpoint: "/insights")
    }

    /// Get correlations only
    func getCorrelations() async throws -> APICorrelationsResponse {
        return try await request("GET", endpoint: "/insights/correlations")
    }

    /// Get streaks only
    func getStreaks() async throws -> APIStreaksResponse {
        return try await request("GET", endpoint: "/insights/streaks")
    }

    /// Get weekly summary only
    func getWeeklySummary() async throws -> APIWeeklySummaryResponse {
        return try await request("GET", endpoint: "/insights/weekly-summary")
    }

    /// Force refresh all insights
    func refreshInsights() async throws {
        try await requestWithoutResponse("POST", endpoint: "/insights/refresh")
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
    case duplicateEvent  // Unique constraint violation - event already exists

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
        case .duplicateEvent:
            return "Event already exists"
        }
    }

    /// Check if this error indicates a duplicate/conflict that should not be retried
    var isDuplicateError: Bool {
        switch self {
        case .duplicateEvent:
            return true
        case .serverError(let message, let code):
            // 409 Conflict or unique constraint violations
            return code == 409 || message.lowercased().contains("duplicate") || message.lowercased().contains("unique")
        case .httpError(let code):
            return code == 409
        default:
            return false
        }
    }
}
