//
//  NetworkClientProtocol.swift
//  trendy
//
//  Protocol for network operations required by SyncEngine.
//  Enables dependency injection for unit testing.
//

import Foundation

/// Protocol for network operations required by SyncEngine.
/// Conforms to Sendable for safe use across actor boundaries.
/// All methods are async as required for actor isolation.
protocol NetworkClientProtocol: Sendable {
    // MARK: - Event Type Operations

    func getEventTypes() async throws -> [APIEventType]
    func createEventType(_ request: CreateEventTypeRequest) async throws -> APIEventType
    func createEventTypeWithIdempotency(_ request: CreateEventTypeRequest, idempotencyKey: String) async throws -> APIEventType
    func updateEventType(id: String, _ request: UpdateEventTypeRequest) async throws -> APIEventType
    func deleteEventType(id: String) async throws

    // MARK: - Event Operations

    func getEvents(limit: Int, offset: Int) async throws -> [APIEvent]
    func getAllEvents(batchSize: Int) async throws -> [APIEvent]
    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent
    func createEventWithIdempotency(_ request: CreateEventRequest, idempotencyKey: String) async throws -> APIEvent
    func createEventsBatch(_ events: [CreateEventRequest]) async throws -> BatchCreateEventsResponse
    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> APIEvent
    func deleteEvent(id: String) async throws

    // MARK: - Geofence Operations

    func getGeofences(activeOnly: Bool) async throws -> [APIGeofence]
    func createGeofence(_ request: CreateGeofenceRequest) async throws -> APIGeofence
    func createGeofenceWithIdempotency(_ request: CreateGeofenceRequest, idempotencyKey: String) async throws -> APIGeofence
    func updateGeofence(id: String, _ request: UpdateGeofenceRequest) async throws -> APIGeofence
    func deleteGeofence(id: String) async throws

    // MARK: - Property Definition Operations

    func getPropertyDefinitions(eventTypeId: String) async throws -> [APIPropertyDefinition]
    func createPropertyDefinition(eventTypeId: String, _ request: CreatePropertyDefinitionRequest) async throws -> APIPropertyDefinition
    func createPropertyDefinitionWithIdempotency(_ request: CreatePropertyDefinitionRequest, idempotencyKey: String) async throws -> APIPropertyDefinition
    func updatePropertyDefinition(id: String, _ request: UpdatePropertyDefinitionRequest) async throws -> APIPropertyDefinition
    func deletePropertyDefinition(id: String) async throws

    // MARK: - Change Feed Operations

    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse
    func getLatestCursor() async throws -> Int64
}
