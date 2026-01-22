//
//  LocalStore.swift
//  trendy
//
//  Utilities for local SwiftData operations with UUIDv7 ID scheme.
//  Since IDs are now client-generated UUIDv7, there's no server/local ID distinction.
//

import Foundation
import SwiftData

/// Errors that can occur in LocalStore operations
enum LocalStoreError: LocalizedError {
    case eventNotFound(id: String)
    case eventTypeNotFound(id: String)
    case geofenceNotFound(id: String)
    case propertyDefinitionNotFound(id: String)

    var errorDescription: String? {
        switch self {
        case .eventNotFound(let id):
            return "Event not found with ID: \(id)"
        case .eventTypeNotFound(let id):
            return "EventType not found with ID: \(id)"
        case .geofenceNotFound(let id):
            return "Geofence not found with ID: \(id)"
        case .propertyDefinitionNotFound(let id):
            return "PropertyDefinition not found with ID: \(id)"
        }
    }
}

/// Utilities for local SwiftData operations with sync support.
/// Provides idempotent upsert operations that prevent duplicates.
/// Uses UUIDv7 as the canonical ID - same ID is used locally and on server.
struct LocalStore: DataStoreProtocol {
    let modelContext: ModelContext

    // MARK: - Upsert Operations

    /// Upsert an Event by ID - creates if not exists, updates if exists.
    /// This is idempotent - calling multiple times with the same ID has no effect.
    ///
    /// - Parameters:
    ///   - id: The UUIDv7 ID (same on client and server)
    ///   - configure: Closure to configure the entity's properties
    /// - Returns: The created or updated Event
    @discardableResult
    func upsertEvent(id: String, configure: (Event) -> Void) throws -> Event {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = Event(id: id)
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    /// Upsert an EventType by ID
    @discardableResult
    func upsertEventType(id: String, configure: (EventType) -> Void) throws -> EventType {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = EventType(id: id, name: "Placeholder")
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    /// Upsert a Geofence by ID
    @discardableResult
    func upsertGeofence(id: String, configure: (Geofence) -> Void) throws -> Geofence {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = Geofence(id: id, name: "Placeholder", latitude: 0, longitude: 0, radius: 100.0, eventTypeEntryID: nil, eventTypeExitID: nil)
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    /// Upsert a PropertyDefinition by ID
    @discardableResult
    func upsertPropertyDefinition(id: String, eventTypeId: String, configure: (PropertyDefinition) -> Void) throws -> PropertyDefinition {
        let descriptor = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = PropertyDefinition(
                id: id,
                eventTypeId: eventTypeId,
                key: "placeholder",
                label: "Placeholder",
                propertyType: .text
            )
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    // MARK: - Delete Operations

    /// Delete an Event by ID
    func deleteEvent(id: String) throws {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    /// Delete an EventType by ID
    func deleteEventType(id: String) throws {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    /// Delete a Geofence by ID
    func deleteGeofence(id: String) throws {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    /// Delete a PropertyDefinition by ID
    func deletePropertyDefinition(id: String) throws {
        let descriptor = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    // MARK: - Lookup Operations

    /// Find an Event by ID
    func findEvent(id: String) throws -> Event? {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Find an EventType by ID
    func findEventType(id: String) throws -> EventType? {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Find a Geofence by ID
    func findGeofence(id: String) throws -> Geofence? {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Find a PropertyDefinition by ID
    func findPropertyDefinition(id: String) throws -> PropertyDefinition? {
        let descriptor = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Fetch All Operations

    /// Fetch all Events
    func fetchAllEvents() throws -> [Event] {
        let descriptor = FetchDescriptor<Event>()
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all EventTypes
    func fetchAllEventTypes() throws -> [EventType] {
        let descriptor = FetchDescriptor<EventType>()
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all Geofences
    func fetchAllGeofences() throws -> [Geofence] {
        let descriptor = FetchDescriptor<Geofence>()
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all PropertyDefinitions
    func fetchAllPropertyDefinitions() throws -> [PropertyDefinition] {
        let descriptor = FetchDescriptor<PropertyDefinition>()
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Bulk Delete Operations

    /// Delete all Events
    func deleteAllEvents() throws {
        let events = try fetchAllEvents()
        for event in events {
            modelContext.delete(event)
        }
    }

    /// Delete all EventTypes
    func deleteAllEventTypes() throws {
        let eventTypes = try fetchAllEventTypes()
        for eventType in eventTypes {
            modelContext.delete(eventType)
        }
    }

    /// Delete all Geofences
    func deleteAllGeofences() throws {
        let geofences = try fetchAllGeofences()
        for geofence in geofences {
            modelContext.delete(geofence)
        }
    }

    /// Delete all PropertyDefinitions
    func deleteAllPropertyDefinitions() throws {
        let propertyDefinitions = try fetchAllPropertyDefinitions()
        for propDef in propertyDefinitions {
            modelContext.delete(propDef)
        }
    }

    // MARK: - Pending Operations

    /// Fetch all pending Events (not yet synced)
    func fetchPendingEvents() throws -> [Event] {
        let pendingStatus = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.syncStatusRaw == pendingStatus }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all pending EventTypes
    func fetchPendingEventTypes() throws -> [EventType] {
        let pendingStatus = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.syncStatusRaw == pendingStatus }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all pending Geofences
    func fetchPendingGeofences() throws -> [Geofence] {
        let pendingStatus = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.syncStatusRaw == pendingStatus }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all pending mutations
    func fetchPendingMutations() throws -> [PendingMutation] {
        let descriptor = FetchDescriptor<PendingMutation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Check if a pending mutation exists for given entity with same operation
    func hasPendingMutation(entityId: String, entityType: MutationEntityType, operation: MutationOperation) throws -> Bool {
        let entityTypeRaw = entityType.rawValue
        let operationRaw = operation.rawValue
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate {
                $0.entityId == entityId &&
                $0.entityTypeRaw == entityTypeRaw &&
                $0.operationRaw == operationRaw
            }
        )
        return try modelContext.fetchCount(descriptor) > 0
    }

    /// Insert a new PendingMutation
    func insertPendingMutation(_ mutation: PendingMutation) throws {
        modelContext.insert(mutation)
    }

    /// Delete a PendingMutation
    func deletePendingMutation(_ mutation: PendingMutation) throws {
        modelContext.delete(mutation)
    }

    // MARK: - Sync Status Updates

    /// Mark an entity as synced. With UUIDv7, no reconciliation is needed -
    /// the ID is the same on client and server.
    func markEventSynced(id: String) throws {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.id == id }
        )

        guard let event = try modelContext.fetch(descriptor).first else {
            Log.sync.error("markEventSynced: Event not found!", context: .with { ctx in
                ctx.add("id", id)
            })
            throw LocalStoreError.eventNotFound(id: id)
        }

        event.syncStatus = .synced
    }

    func markEventTypeSynced(id: String) throws {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == id }
        )

        guard let eventType = try modelContext.fetch(descriptor).first else {
            Log.sync.error("markEventTypeSynced: EventType not found!", context: .with { ctx in
                ctx.add("id", id)
            })
            throw LocalStoreError.eventTypeNotFound(id: id)
        }

        eventType.syncStatus = .synced
    }

    func markGeofenceSynced(id: String) throws {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == id }
        )

        guard let geofence = try modelContext.fetch(descriptor).first else {
            Log.sync.error("markGeofenceSynced: Geofence not found!", context: .with { ctx in
                ctx.add("id", id)
            })
            throw LocalStoreError.geofenceNotFound(id: id)
        }

        geofence.syncStatus = .synced
    }

    func markPropertyDefinitionSynced(id: String) throws {
        let descriptor = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.id == id }
        )

        guard let propDef = try modelContext.fetch(descriptor).first else {
            Log.sync.error("markPropertyDefinitionSynced: PropertyDefinition not found!", context: .with { ctx in
                ctx.add("id", id)
            })
            throw LocalStoreError.propertyDefinitionNotFound(id: id)
        }

        propDef.syncStatus = .synced
    }

    // MARK: - Save

    /// Save any pending changes to the context
    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
