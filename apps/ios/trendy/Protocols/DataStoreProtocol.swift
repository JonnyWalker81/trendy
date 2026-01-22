//
//  DataStoreProtocol.swift
//  trendy
//
//  Protocol for persistence operations required by SyncEngine.
//  NOT Sendable - instances are created and used entirely within actor context.
//

import Foundation

/// Protocol for persistence operations required by SyncEngine.
/// Note: This protocol is NOT Sendable because:
/// 1. DataStore instances are created inside the actor via DataStoreFactory
/// 2. They are used only within the actor's isolation context
/// 3. The underlying ModelContext is not thread-safe
protocol DataStoreProtocol {
    // MARK: - Upsert Operations

    /// Upsert an Event by ID - creates if not exists, updates if exists.
    @discardableResult
    func upsertEvent(id: String, configure: (Event) -> Void) throws -> Event

    /// Upsert an EventType by ID
    @discardableResult
    func upsertEventType(id: String, configure: (EventType) -> Void) throws -> EventType

    /// Upsert a Geofence by ID
    @discardableResult
    func upsertGeofence(id: String, configure: (Geofence) -> Void) throws -> Geofence

    /// Upsert a PropertyDefinition by ID
    @discardableResult
    func upsertPropertyDefinition(id: String, eventTypeId: String, configure: (PropertyDefinition) -> Void) throws -> PropertyDefinition

    // MARK: - Delete Operations

    /// Delete an Event by ID
    func deleteEvent(id: String) throws

    /// Delete an EventType by ID
    func deleteEventType(id: String) throws

    /// Delete a Geofence by ID
    func deleteGeofence(id: String) throws

    /// Delete a PropertyDefinition by ID
    func deletePropertyDefinition(id: String) throws

    // MARK: - Lookup Operations

    /// Find an Event by ID
    func findEvent(id: String) throws -> Event?

    /// Find an EventType by ID
    func findEventType(id: String) throws -> EventType?

    /// Find a Geofence by ID
    func findGeofence(id: String) throws -> Geofence?

    /// Find a PropertyDefinition by ID
    func findPropertyDefinition(id: String) throws -> PropertyDefinition?

    // MARK: - Pending Operations

    /// Fetch all pending mutations ordered by creation time
    func fetchPendingMutations() throws -> [PendingMutation]

    // MARK: - Sync Status Updates

    /// Mark an Event as synced
    func markEventSynced(id: String) throws

    /// Mark an EventType as synced
    func markEventTypeSynced(id: String) throws

    /// Mark a Geofence as synced
    func markGeofenceSynced(id: String) throws

    /// Mark a PropertyDefinition as synced
    func markPropertyDefinitionSynced(id: String) throws

    // MARK: - Persistence

    /// Save any pending changes to the context
    func save() throws
}
