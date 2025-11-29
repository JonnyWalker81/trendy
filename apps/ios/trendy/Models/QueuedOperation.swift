//
//  QueuedOperation.swift
//  trendy
//
//  Model for queued offline operations
//

import Foundation
import SwiftData

/// Represents an operation that was performed offline and needs to be synced
@Model
final class QueuedOperation {
    var id: UUID
    var operationType: String // "create_event", "update_event", "delete_event", "create_event_type", etc.
    var entityId: UUID // ID of the local entity
    var payload: Data // JSON-encoded operation data
    var createdAt: Date
    var attempts: Int // Number of sync attempts
    var lastError: String?

    init(
        id: UUID = UUID(),
        operationType: String,
        entityId: UUID,
        payload: Data,
        createdAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.operationType = operationType
        self.entityId = entityId
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
    }
}

/// Operation types
enum OperationType: String {
    case createEvent = "create_event"
    case updateEvent = "update_event"
    case deleteEvent = "delete_event"
    case createEventType = "create_event_type"
    case updateEventType = "update_event_type"
    case deleteEventType = "delete_event_type"
    case createGeofence = "create_geofence"
    case updateGeofence = "update_geofence"
    case deleteGeofence = "delete_geofence"
}
