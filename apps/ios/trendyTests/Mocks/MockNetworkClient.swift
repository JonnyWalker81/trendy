//
//  MockNetworkClient.swift
//  trendyTests
//
//  Mock implementation of NetworkClientProtocol for unit testing.
//  Uses spy pattern to record method calls and supports response configuration.
//

import Foundation
@testable import trendy

/// Mock network client for testing SyncEngine.
/// Thread-safe implementation with spy pattern for call tracking.
final class MockNetworkClient: NetworkClientProtocol, @unchecked Sendable {

    // MARK: - Thread Safety

    private let lock = NSLock()

    // MARK: - Call Records (Spy Pattern)

    struct GetEventTypesCall {
        let timestamp: Date
    }

    struct CreateEventTypeCall {
        let request: CreateEventTypeRequest
        let timestamp: Date
    }

    struct CreateEventTypeWithIdempotencyCall {
        let request: CreateEventTypeRequest
        let idempotencyKey: String
        let timestamp: Date
    }

    struct UpdateEventTypeCall {
        let id: String
        let request: UpdateEventTypeRequest
        let timestamp: Date
    }

    struct DeleteEventTypeCall {
        let id: String
        let timestamp: Date
    }

    struct GetEventsCall {
        let limit: Int
        let offset: Int
        let timestamp: Date
    }

    struct GetAllEventsCall {
        let batchSize: Int
        let timestamp: Date
    }

    struct CreateEventCall {
        let request: CreateEventRequest
        let timestamp: Date
    }

    struct CreateEventWithIdempotencyCall {
        let request: CreateEventRequest
        let idempotencyKey: String
        let timestamp: Date
    }

    struct CreateEventsBatchCall {
        let events: [CreateEventRequest]
        let timestamp: Date
    }

    struct UpdateEventCall {
        let id: String
        let request: UpdateEventRequest
        let timestamp: Date
    }

    struct DeleteEventCall {
        let id: String
        let timestamp: Date
    }

    struct GetGeofencesCall {
        let activeOnly: Bool
        let timestamp: Date
    }

    struct CreateGeofenceCall {
        let request: CreateGeofenceRequest
        let timestamp: Date
    }

    struct CreateGeofenceWithIdempotencyCall {
        let request: CreateGeofenceRequest
        let idempotencyKey: String
        let timestamp: Date
    }

    struct UpdateGeofenceCall {
        let id: String
        let request: UpdateGeofenceRequest
        let timestamp: Date
    }

    struct DeleteGeofenceCall {
        let id: String
        let timestamp: Date
    }

    struct GetPropertyDefinitionsCall {
        let eventTypeId: String
        let timestamp: Date
    }

    struct CreatePropertyDefinitionCall {
        let eventTypeId: String
        let request: CreatePropertyDefinitionRequest
        let timestamp: Date
    }

    struct CreatePropertyDefinitionWithIdempotencyCall {
        let request: CreatePropertyDefinitionRequest
        let idempotencyKey: String
        let timestamp: Date
    }

    struct UpdatePropertyDefinitionCall {
        let id: String
        let request: UpdatePropertyDefinitionRequest
        let timestamp: Date
    }

    struct DeletePropertyDefinitionCall {
        let id: String
        let timestamp: Date
    }

    struct GetChangesCall {
        let cursor: Int64
        let limit: Int
        let timestamp: Date
    }

    struct GetLatestCursorCall {
        let timestamp: Date
    }

    // Call storage arrays
    private(set) var getEventTypesCalls: [GetEventTypesCall] = []
    private(set) var createEventTypeCalls: [CreateEventTypeCall] = []
    private(set) var createEventTypeWithIdempotencyCalls: [CreateEventTypeWithIdempotencyCall] = []
    private(set) var updateEventTypeCalls: [UpdateEventTypeCall] = []
    private(set) var deleteEventTypeCalls: [DeleteEventTypeCall] = []

    private(set) var getEventsCalls: [GetEventsCall] = []
    private(set) var getAllEventsCalls: [GetAllEventsCall] = []
    private(set) var createEventCalls: [CreateEventCall] = []
    private(set) var createEventWithIdempotencyCalls: [CreateEventWithIdempotencyCall] = []
    private(set) var createEventsBatchCalls: [CreateEventsBatchCall] = []
    private(set) var updateEventCalls: [UpdateEventCall] = []
    private(set) var deleteEventCalls: [DeleteEventCall] = []

    private(set) var getGeofencesCalls: [GetGeofencesCall] = []
    private(set) var createGeofenceCalls: [CreateGeofenceCall] = []
    private(set) var createGeofenceWithIdempotencyCalls: [CreateGeofenceWithIdempotencyCall] = []
    private(set) var updateGeofenceCalls: [UpdateGeofenceCall] = []
    private(set) var deleteGeofenceCalls: [DeleteGeofenceCall] = []

    private(set) var getPropertyDefinitionsCalls: [GetPropertyDefinitionsCall] = []
    private(set) var createPropertyDefinitionCalls: [CreatePropertyDefinitionCall] = []
    private(set) var createPropertyDefinitionWithIdempotencyCalls: [CreatePropertyDefinitionWithIdempotencyCall] = []
    private(set) var updatePropertyDefinitionCalls: [UpdatePropertyDefinitionCall] = []
    private(set) var deletePropertyDefinitionCalls: [DeletePropertyDefinitionCall] = []

    private(set) var getChangesCalls: [GetChangesCall] = []
    private(set) var getLatestCursorCalls: [GetLatestCursorCall] = []

    // MARK: - Response Configuration

    // Default return values
    var eventTypesToReturn: [APIEventType] = []
    var eventsToReturn: [APIEvent] = []
    var geofencesToReturn: [APIGeofence] = []
    var propertyDefinitionsToReturn: [APIPropertyDefinition] = []
    var changeFeedResponseToReturn: ChangeFeedResponse?
    var latestCursorToReturn: Int64 = 0
    var batchCreateResponseToReturn: BatchCreateEventsResponse?

    // Global error injection
    var errorToThrow: Error?

    // Response queues for sequential testing (critical for circuit breaker tests)
    var getEventTypesResponses: [Result<[APIEventType], Error>] = []
    var createEventTypeResponses: [Result<APIEventType, Error>] = []
    var updateEventTypeResponses: [Result<APIEventType, Error>] = []
    var getEventsResponses: [Result<[APIEvent], Error>] = []
    var getAllEventsResponses: [Result<[APIEvent], Error>] = []
    var createEventResponses: [Result<APIEvent, Error>] = []
    var createEventsBatchResponses: [Result<BatchCreateEventsResponse, Error>] = []
    var createEventWithIdempotencyResponses: [Result<APIEvent, Error>] = []
    var updateEventResponses: [Result<APIEvent, Error>] = []
    var getGeofencesResponses: [Result<[APIGeofence], Error>] = []
    var createGeofenceResponses: [Result<APIGeofence, Error>] = []
    var updateGeofenceResponses: [Result<APIGeofence, Error>] = []
    var getPropertyDefinitionsResponses: [Result<[APIPropertyDefinition], Error>] = []
    var createPropertyDefinitionResponses: [Result<APIPropertyDefinition, Error>] = []
    var updatePropertyDefinitionResponses: [Result<APIPropertyDefinition, Error>] = []
    var getChangesResponses: [Result<ChangeFeedResponse, Error>] = []
    var getLatestCursorResponses: [Result<Int64, Error>] = []

    // MARK: - Initialization

    init() {}

    // MARK: - Helper for APIGeofence construction

    /// Helper to construct APIGeofence using JSON decoding (required since APIGeofence has custom init(from:))
    private func makeAPIGeofence(
        id: String,
        userId: String = "user-1",
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        eventTypeEntryId: String? = nil,
        eventTypeExitId: String? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = false,
        notifyOnExit: Bool = false,
        iosRegionIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> APIGeofence {
        let json: [String: Any] = [
            "id": id,
            "user_id": userId,
            "name": name,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "event_type_entry_id": eventTypeEntryId as Any,
            "event_type_exit_id": eventTypeExitId as Any,
            "is_active": isActive,
            "notify_on_entry": notifyOnEntry,
            "notify_on_exit": notifyOnExit,
            "ios_region_identifier": iosRegionIdentifier as Any,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "updated_at": ISO8601DateFormatter().string(from: updatedAt)
        ]

        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(APIGeofence.self, from: data)
    }

    // MARK: - Event Type Operations

    func getEventTypes() async throws -> [APIEventType] {
        lock.lock()
        getEventTypesCalls.append(GetEventTypesCall(timestamp: Date()))

        // Check response queue first (for sequential testing)
        if !getEventTypesResponses.isEmpty {
            let result = getEventTypesResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let types): return types
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        // Check global error
        if let error = errorToThrow {
            throw error
        }

        // Return configured response
        return eventTypesToReturn
    }

    func createEventType(_ request: CreateEventTypeRequest) async throws -> APIEventType {
        lock.lock()
        createEventTypeCalls.append(CreateEventTypeCall(request: request, timestamp: Date()))

        if !createEventTypeResponses.isEmpty {
            let result = createEventTypeResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let type): return type
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        // Return a default event type based on request
        return APIEventType(
            id: request.id,
            userId: "user-1",
            name: request.name,
            color: request.color,
            icon: request.icon,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func createEventTypeWithIdempotency(_ request: CreateEventTypeRequest, idempotencyKey: String) async throws -> APIEventType {
        lock.lock()
        createEventTypeWithIdempotencyCalls.append(CreateEventTypeWithIdempotencyCall(request: request, idempotencyKey: idempotencyKey, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIEventType(
            id: request.id,
            userId: "user-1",
            name: request.name,
            color: request.color,
            icon: request.icon,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func updateEventType(id: String, _ request: UpdateEventTypeRequest) async throws -> APIEventType {
        lock.lock()
        updateEventTypeCalls.append(UpdateEventTypeCall(id: id, request: request, timestamp: Date()))

        if !updateEventTypeResponses.isEmpty {
            let result = updateEventTypeResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let type): return type
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIEventType(
            id: id,
            userId: "user-1",
            name: request.name ?? "Updated",
            color: request.color ?? "#000000",
            icon: request.icon ?? "star",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func deleteEventType(id: String) async throws {
        lock.lock()
        deleteEventTypeCalls.append(DeleteEventTypeCall(id: id, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }
    }

    // MARK: - Event Operations

    func getEvents(limit: Int, offset: Int) async throws -> [APIEvent] {
        lock.lock()
        getEventsCalls.append(GetEventsCall(limit: limit, offset: offset, timestamp: Date()))

        if !getEventsResponses.isEmpty {
            let result = getEventsResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let events): return events
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return eventsToReturn
    }

    func getAllEvents(batchSize: Int) async throws -> [APIEvent] {
        lock.lock()
        getAllEventsCalls.append(GetAllEventsCall(batchSize: batchSize, timestamp: Date()))

        if !getAllEventsResponses.isEmpty {
            let result = getAllEventsResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let events): return events
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return eventsToReturn
    }

    func createEvent(_ request: CreateEventRequest) async throws -> APIEvent {
        lock.lock()
        createEventCalls.append(CreateEventCall(request: request, timestamp: Date()))

        if !createEventResponses.isEmpty {
            let result = createEventResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let event): return event
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIEvent(
            id: request.id,
            userId: "user-1",
            eventTypeId: request.eventTypeId,
            timestamp: request.timestamp,
            notes: request.notes,
            isAllDay: request.isAllDay,
            endDate: request.endDate,
            sourceType: request.sourceType,
            externalId: request.externalId,
            originalTitle: request.originalTitle,
            geofenceId: request.geofenceId,
            locationLatitude: request.locationLatitude,
            locationLongitude: request.locationLongitude,
            locationName: request.locationName,
            healthKitSampleId: request.healthKitSampleId,
            healthKitCategory: request.healthKitCategory,
            properties: request.properties,
            createdAt: Date(),
            updatedAt: Date(),
            eventType: nil
        )
    }

    func createEventWithIdempotency(_ request: CreateEventRequest, idempotencyKey: String) async throws -> APIEvent {
        lock.lock()
        createEventWithIdempotencyCalls.append(CreateEventWithIdempotencyCall(request: request, idempotencyKey: idempotencyKey, timestamp: Date()))

        // Check response queue first (for sequential testing)
        if !createEventWithIdempotencyResponses.isEmpty {
            let result = createEventWithIdempotencyResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let event): return event
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        // Check global error
        if let error = errorToThrow {
            throw error
        }

        return APIEvent(
            id: request.id,
            userId: "user-1",
            eventTypeId: request.eventTypeId,
            timestamp: request.timestamp,
            notes: request.notes,
            isAllDay: request.isAllDay,
            endDate: request.endDate,
            sourceType: request.sourceType,
            externalId: request.externalId,
            originalTitle: request.originalTitle,
            geofenceId: request.geofenceId,
            locationLatitude: request.locationLatitude,
            locationLongitude: request.locationLongitude,
            locationName: request.locationName,
            healthKitSampleId: request.healthKitSampleId,
            healthKitCategory: request.healthKitCategory,
            properties: request.properties,
            createdAt: Date(),
            updatedAt: Date(),
            eventType: nil
        )
    }

    func createEventsBatch(_ events: [CreateEventRequest]) async throws -> BatchCreateEventsResponse {
        lock.lock()
        createEventsBatchCalls.append(CreateEventsBatchCall(events: events, timestamp: Date()))

        if !createEventsBatchResponses.isEmpty {
            let result = createEventsBatchResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let response): return response
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        if let configured = batchCreateResponseToReturn {
            return configured
        }

        // Default: all succeed
        let created = events.map { request in
            APIEvent(
                id: request.id,
                userId: "user-1",
                eventTypeId: request.eventTypeId,
                timestamp: request.timestamp,
                notes: request.notes,
                isAllDay: request.isAllDay,
                endDate: request.endDate,
                sourceType: request.sourceType,
                externalId: request.externalId,
                originalTitle: request.originalTitle,
                geofenceId: request.geofenceId,
                locationLatitude: request.locationLatitude,
                locationLongitude: request.locationLongitude,
                locationName: request.locationName,
                healthKitSampleId: request.healthKitSampleId,
                healthKitCategory: request.healthKitCategory,
                properties: request.properties,
                createdAt: Date(),
                updatedAt: Date(),
                eventType: nil
            )
        }

        return BatchCreateEventsResponse(
            created: created,
            errors: nil,
            total: events.count,
            success: events.count,
            failed: 0
        )
    }

    func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> APIEvent {
        lock.lock()
        updateEventCalls.append(UpdateEventCall(id: id, request: request, timestamp: Date()))

        if !updateEventResponses.isEmpty {
            let result = updateEventResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let event): return event
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIEvent(
            id: id,
            userId: "user-1",
            eventTypeId: request.eventTypeId ?? "type-1",
            timestamp: request.timestamp ?? Date(),
            notes: request.notes,
            isAllDay: request.isAllDay ?? false,
            endDate: request.endDate,
            sourceType: request.sourceType ?? "manual",
            externalId: request.externalId,
            originalTitle: request.originalTitle,
            geofenceId: request.geofenceId,
            locationLatitude: request.locationLatitude,
            locationLongitude: request.locationLongitude,
            locationName: request.locationName,
            healthKitSampleId: request.healthKitSampleId,
            healthKitCategory: request.healthKitCategory,
            properties: request.properties,
            createdAt: Date(),
            updatedAt: Date(),
            eventType: nil
        )
    }

    func deleteEvent(id: String) async throws {
        lock.lock()
        deleteEventCalls.append(DeleteEventCall(id: id, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }
    }

    // MARK: - Geofence Operations

    func getGeofences(activeOnly: Bool) async throws -> [APIGeofence] {
        lock.lock()
        getGeofencesCalls.append(GetGeofencesCall(activeOnly: activeOnly, timestamp: Date()))

        if !getGeofencesResponses.isEmpty {
            let result = getGeofencesResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let geofences): return geofences
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return geofencesToReturn
    }

    func createGeofence(_ request: CreateGeofenceRequest) async throws -> APIGeofence {
        lock.lock()
        createGeofenceCalls.append(CreateGeofenceCall(request: request, timestamp: Date()))

        if !createGeofenceResponses.isEmpty {
            let result = createGeofenceResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let geofence): return geofence
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return makeAPIGeofence(
            id: request.id ?? UUIDv7.generate(),
            name: request.name,
            latitude: request.latitude,
            longitude: request.longitude,
            radius: request.radius,
            eventTypeEntryId: request.eventTypeEntryId,
            eventTypeExitId: request.eventTypeExitId,
            isActive: request.isActive,
            notifyOnEntry: request.notifyOnEntry,
            notifyOnExit: request.notifyOnExit
        )
    }

    func createGeofenceWithIdempotency(_ request: CreateGeofenceRequest, idempotencyKey: String) async throws -> APIGeofence {
        lock.lock()
        createGeofenceWithIdempotencyCalls.append(CreateGeofenceWithIdempotencyCall(request: request, idempotencyKey: idempotencyKey, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return makeAPIGeofence(
            id: request.id ?? UUIDv7.generate(),
            name: request.name,
            latitude: request.latitude,
            longitude: request.longitude,
            radius: request.radius,
            eventTypeEntryId: request.eventTypeEntryId,
            eventTypeExitId: request.eventTypeExitId,
            isActive: request.isActive,
            notifyOnEntry: request.notifyOnEntry,
            notifyOnExit: request.notifyOnExit
        )
    }

    func updateGeofence(id: String, _ request: UpdateGeofenceRequest) async throws -> APIGeofence {
        lock.lock()
        updateGeofenceCalls.append(UpdateGeofenceCall(id: id, request: request, timestamp: Date()))

        if !updateGeofenceResponses.isEmpty {
            let result = updateGeofenceResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let geofence): return geofence
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return makeAPIGeofence(
            id: id,
            name: request.name ?? "Updated",
            latitude: request.latitude ?? 0.0,
            longitude: request.longitude ?? 0.0,
            radius: request.radius ?? 100.0,
            eventTypeEntryId: request.eventTypeEntryId,
            eventTypeExitId: request.eventTypeExitId,
            isActive: request.isActive ?? true,
            notifyOnEntry: request.notifyOnEntry ?? false,
            notifyOnExit: request.notifyOnExit ?? false,
            iosRegionIdentifier: request.iosRegionIdentifier
        )
    }

    func deleteGeofence(id: String) async throws {
        lock.lock()
        deleteGeofenceCalls.append(DeleteGeofenceCall(id: id, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }
    }

    // MARK: - Property Definition Operations

    func getPropertyDefinitions(eventTypeId: String) async throws -> [APIPropertyDefinition] {
        lock.lock()
        getPropertyDefinitionsCalls.append(GetPropertyDefinitionsCall(eventTypeId: eventTypeId, timestamp: Date()))

        if !getPropertyDefinitionsResponses.isEmpty {
            let result = getPropertyDefinitionsResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let definitions): return definitions
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return propertyDefinitionsToReturn
    }

    func createPropertyDefinition(eventTypeId: String, _ request: CreatePropertyDefinitionRequest) async throws -> APIPropertyDefinition {
        lock.lock()
        createPropertyDefinitionCalls.append(CreatePropertyDefinitionCall(eventTypeId: eventTypeId, request: request, timestamp: Date()))

        if !createPropertyDefinitionResponses.isEmpty {
            let result = createPropertyDefinitionResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let definition): return definition
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIPropertyDefinition(
            id: request.id,
            eventTypeId: request.eventTypeId,
            userId: "user-1",
            key: request.key,
            label: request.label,
            propertyType: request.propertyType,
            options: request.options,
            defaultValue: request.defaultValue,
            displayOrder: request.displayOrder,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func createPropertyDefinitionWithIdempotency(_ request: CreatePropertyDefinitionRequest, idempotencyKey: String) async throws -> APIPropertyDefinition {
        lock.lock()
        createPropertyDefinitionWithIdempotencyCalls.append(CreatePropertyDefinitionWithIdempotencyCall(request: request, idempotencyKey: idempotencyKey, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIPropertyDefinition(
            id: request.id,
            eventTypeId: request.eventTypeId,
            userId: "user-1",
            key: request.key,
            label: request.label,
            propertyType: request.propertyType,
            options: request.options,
            defaultValue: request.defaultValue,
            displayOrder: request.displayOrder,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func updatePropertyDefinition(id: String, _ request: UpdatePropertyDefinitionRequest) async throws -> APIPropertyDefinition {
        lock.lock()
        updatePropertyDefinitionCalls.append(UpdatePropertyDefinitionCall(id: id, request: request, timestamp: Date()))

        if !updatePropertyDefinitionResponses.isEmpty {
            let result = updatePropertyDefinitionResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let definition): return definition
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return APIPropertyDefinition(
            id: id,
            eventTypeId: "type-1",
            userId: "user-1",
            key: request.key ?? "key",
            label: request.label ?? "Label",
            propertyType: request.propertyType ?? "text",
            options: request.options,
            defaultValue: request.defaultValue,
            displayOrder: request.displayOrder ?? 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func deletePropertyDefinition(id: String) async throws {
        lock.lock()
        deletePropertyDefinitionCalls.append(DeletePropertyDefinitionCall(id: id, timestamp: Date()))
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }
    }

    // MARK: - Change Feed Operations

    func getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse {
        lock.lock()
        getChangesCalls.append(GetChangesCall(cursor: cursor, limit: limit, timestamp: Date()))

        if !getChangesResponses.isEmpty {
            let result = getChangesResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let response): return response
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        if let configured = changeFeedResponseToReturn {
            return configured
        }

        // Default: no changes
        return ChangeFeedResponse(changes: [], nextCursor: cursor, hasMore: false)
    }

    func getLatestCursor() async throws -> Int64 {
        lock.lock()
        getLatestCursorCalls.append(GetLatestCursorCall(timestamp: Date()))

        if !getLatestCursorResponses.isEmpty {
            let result = getLatestCursorResponses.removeFirst()
            lock.unlock()
            switch result {
            case .success(let cursor): return cursor
            case .failure(let error): throw error
            }
        }
        lock.unlock()

        if let error = errorToThrow {
            throw error
        }

        return latestCursorToReturn
    }

    // MARK: - Helper Methods

    /// Reset all call records and response configurations
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        // Clear call records
        getEventTypesCalls.removeAll()
        createEventTypeCalls.removeAll()
        createEventTypeWithIdempotencyCalls.removeAll()
        updateEventTypeCalls.removeAll()
        deleteEventTypeCalls.removeAll()

        getEventsCalls.removeAll()
        getAllEventsCalls.removeAll()
        createEventCalls.removeAll()
        createEventWithIdempotencyCalls.removeAll()
        createEventsBatchCalls.removeAll()
        updateEventCalls.removeAll()
        deleteEventCalls.removeAll()

        getGeofencesCalls.removeAll()
        createGeofenceCalls.removeAll()
        createGeofenceWithIdempotencyCalls.removeAll()
        updateGeofenceCalls.removeAll()
        deleteGeofenceCalls.removeAll()

        getPropertyDefinitionsCalls.removeAll()
        createPropertyDefinitionCalls.removeAll()
        createPropertyDefinitionWithIdempotencyCalls.removeAll()
        updatePropertyDefinitionCalls.removeAll()
        deletePropertyDefinitionCalls.removeAll()

        getChangesCalls.removeAll()
        getLatestCursorCalls.removeAll()

        // Clear response configurations
        eventTypesToReturn.removeAll()
        eventsToReturn.removeAll()
        geofencesToReturn.removeAll()
        propertyDefinitionsToReturn.removeAll()
        changeFeedResponseToReturn = nil
        latestCursorToReturn = 0
        batchCreateResponseToReturn = nil

        // Clear response queues
        getEventTypesResponses.removeAll()
        createEventTypeResponses.removeAll()
        updateEventTypeResponses.removeAll()
        getEventsResponses.removeAll()
        getAllEventsResponses.removeAll()
        createEventResponses.removeAll()
        createEventsBatchResponses.removeAll()
        createEventWithIdempotencyResponses.removeAll()
        updateEventResponses.removeAll()
        getGeofencesResponses.removeAll()
        createGeofenceResponses.removeAll()
        updateGeofenceResponses.removeAll()
        getPropertyDefinitionsResponses.removeAll()
        createPropertyDefinitionResponses.removeAll()
        updatePropertyDefinitionResponses.removeAll()
        getChangesResponses.removeAll()
        getLatestCursorResponses.removeAll()

        // Clear global error
        errorToThrow = nil
    }

    /// Get total count of all method calls
    var totalCallCount: Int {
        lock.lock()
        defer { lock.unlock() }

        // Break up expression to help Swift type-checker
        let eventTypeCounts = getEventTypesCalls.count + createEventTypeCalls.count +
                              createEventTypeWithIdempotencyCalls.count + updateEventTypeCalls.count +
                              deleteEventTypeCalls.count

        let eventCounts = getEventsCalls.count + getAllEventsCalls.count +
                          createEventCalls.count + createEventWithIdempotencyCalls.count +
                          createEventsBatchCalls.count + updateEventCalls.count + deleteEventCalls.count

        let geofenceCounts = getGeofencesCalls.count + createGeofenceCalls.count +
                             createGeofenceWithIdempotencyCalls.count + updateGeofenceCalls.count +
                             deleteGeofenceCalls.count

        let propDefCounts = getPropertyDefinitionsCalls.count + createPropertyDefinitionCalls.count +
                            createPropertyDefinitionWithIdempotencyCalls.count + updatePropertyDefinitionCalls.count +
                            deletePropertyDefinitionCalls.count

        let changeCounts = getChangesCalls.count + getLatestCursorCalls.count

        return eventTypeCounts + eventCounts + geofenceCounts + propDefCounts + changeCounts
    }
}
