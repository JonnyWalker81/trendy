//
//  LocalStore.swift
//  trendy
//
//  Utilities for local SwiftData operations, including idempotent upsert by server ID.
//

import Foundation
import SwiftData

/// Utilities for local SwiftData operations with sync support.
/// Provides idempotent upsert operations that prevent duplicates.
struct LocalStore {
    let modelContext: ModelContext

    // MARK: - Upsert Operations

    /// Upsert an Event by server ID - creates if not exists, updates if exists.
    /// This is idempotent - calling multiple times with the same serverId has no effect.
    ///
    /// - Parameters:
    ///   - serverId: The server-generated ID
    ///   - configure: Closure to configure the entity's properties
    /// - Returns: The created or updated Event
    @discardableResult
    func upsertEvent(serverId: String, configure: (Event) -> Void) throws -> Event {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = Event()
            new.serverId = serverId
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    /// Upsert an EventType by server ID
    @discardableResult
    func upsertEventType(serverId: String, configure: (EventType) -> Void) throws -> EventType {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = EventType(name: "Placeholder")
            new.serverId = serverId
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    /// Upsert a Geofence by server ID
    @discardableResult
    func upsertGeofence(serverId: String, configure: (Geofence) -> Void) throws -> Geofence {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = Geofence(name: "Placeholder", latitude: 0, longitude: 0, radius: 100.0, eventTypeEntryID: nil, eventTypeExitID: nil)
            new.serverId = serverId
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    /// Upsert a PropertyDefinition by server ID
    @discardableResult
    func upsertPropertyDefinition(serverId: String, eventTypeId: UUID, configure: (PropertyDefinition) -> Void) throws -> PropertyDefinition {
        let descriptor = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            configure(existing)
            existing.syncStatus = .synced
            return existing
        } else {
            let new = PropertyDefinition(
                eventTypeId: eventTypeId,
                key: "placeholder",
                label: "Placeholder",
                propertyType: .text
            )
            new.serverId = serverId
            new.syncStatus = .synced
            configure(new)
            modelContext.insert(new)
            return new
        }
    }

    // MARK: - Delete Operations

    /// Delete an Event by server ID
    func deleteEventByServerId(_ serverId: String) throws {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    /// Delete an EventType by server ID
    func deleteEventTypeByServerId(_ serverId: String) throws {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    /// Delete a Geofence by server ID
    func deleteGeofenceByServerId(_ serverId: String) throws {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    /// Delete a PropertyDefinition by server ID
    func deletePropertyDefinitionByServerId(_ serverId: String) throws {
        let descriptor = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.serverId == serverId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    // MARK: - Lookup Operations

    /// Find an Event by local UUID
    func findEvent(byLocalId id: UUID) throws -> Event? {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Find an Event by server ID
    func findEvent(byServerId serverId: String) throws -> Event? {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Find an EventType by server ID
    func findEventType(byServerId serverId: String) throws -> EventType? {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Find a Geofence by server ID
    func findGeofence(byServerId serverId: String) throws -> Geofence? {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try modelContext.fetch(descriptor).first
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

    // MARK: - Reconciliation

    /// Reconcile a pending entity with the server response.
    /// Updates the entity with the server ID and marks it as synced.
    func reconcilePendingEvent(localId: UUID, serverId: String) throws {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.id == localId }
        )

        if let event = try modelContext.fetch(descriptor).first {
            event.serverId = serverId
            event.syncStatus = .synced
        }
    }

    func reconcilePendingEventType(localId: UUID, serverId: String) throws {
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == localId }
        )

        if let eventType = try modelContext.fetch(descriptor).first {
            eventType.serverId = serverId
            eventType.syncStatus = .synced
        }
    }

    func reconcilePendingGeofence(localId: UUID, serverId: String) throws {
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == localId }
        )

        if let geofence = try modelContext.fetch(descriptor).first {
            geofence.serverId = serverId
            geofence.syncStatus = .synced
        }
    }

    // MARK: - Save

    /// Save any pending changes to the context
    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
