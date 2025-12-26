//
//  PendingMutation.swift
//  trendy
//
//  Model for tracking pending mutations that need to be synced to the server.
//  Each mutation has a unique clientRequestId used as the Idempotency-Key header
//  to ensure exactly-once semantics.
//

import Foundation
import SwiftData

/// Entity types that can be mutated
enum MutationEntityType: String, Codable {
    case event = "event"
    case eventType = "event_type"
    case geofence = "geofence"
    case propertyDefinition = "property_definition"
}

/// Types of mutations
enum MutationOperation: String, Codable {
    case create = "create"
    case update = "update"
    case delete = "delete"
}

/// Represents a pending mutation that needs to be synced to the server.
/// The clientRequestId is used as the Idempotency-Key header to ensure
/// exactly-once semantics - if the same mutation is retried, the server
/// will return the cached response.
@Model
final class PendingMutation {
    /// Unique identifier for this mutation record
    var id: UUID

    /// UUID used as the Idempotency-Key header for exactly-once semantics.
    /// This is generated once when the mutation is created and never changes.
    var clientRequestId: String

    /// Type of entity being mutated (event, event_type, geofence, property_definition)
    var entityTypeRaw: String

    /// Type of operation (create, update, delete)
    var operationRaw: String

    /// UUIDv7 ID of the entity being mutated.
    /// This is the canonical ID used both locally and on the server.
    var entityId: String

    /// JSON-encoded request payload
    var payload: Data

    /// When this mutation was created
    var createdAt: Date

    /// Number of sync attempts made
    var attempts: Int

    /// Error message from the last failed attempt
    var lastError: String?

    /// When the last sync attempt was made
    var lastAttemptAt: Date?

    // MARK: - Computed Properties

    var entityType: MutationEntityType {
        get { MutationEntityType(rawValue: entityTypeRaw) ?? .event }
        set { entityTypeRaw = newValue.rawValue }
    }

    var operation: MutationOperation {
        get { MutationOperation(rawValue: operationRaw) ?? .create }
        set { operationRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init(
        entityType: MutationEntityType,
        operation: MutationOperation,
        entityId: String,
        payload: Data
    ) {
        self.id = UUID()
        self.clientRequestId = UUID().uuidString
        self.entityTypeRaw = entityType.rawValue
        self.operationRaw = operation.rawValue
        self.entityId = entityId
        self.payload = payload
        self.createdAt = Date()
        self.attempts = 0
        self.lastError = nil
        self.lastAttemptAt = nil
    }

    // MARK: - Convenience Methods

    /// Record a failed sync attempt
    func recordFailure(error: String) {
        self.attempts += 1
        self.lastError = error
        self.lastAttemptAt = Date()
    }

    /// Check if this mutation should be retried (max 5 attempts)
    var shouldRetry: Bool {
        return attempts < 5
    }

    /// Check if this mutation has exceeded retry limit
    var hasExceededRetryLimit: Bool {
        return attempts >= 5
    }
}
