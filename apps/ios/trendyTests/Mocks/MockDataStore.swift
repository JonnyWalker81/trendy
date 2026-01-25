//
//  MockDataStore.swift
//  trendyTests
//
//  Mock implementation of DataStoreProtocol for unit testing.
//  Uses an in-memory ModelContainer to satisfy SwiftData's @Model requirements.
//

import Foundation
import SwiftData
@testable import trendy

/// Mock implementation of DataStoreProtocol for unit testing.
/// Uses an in-memory ModelContainer to satisfy SwiftData's @Model requirements.
final class MockDataStore: DataStoreProtocol {
    // MARK: - In-Memory Storage

    /// In-memory container for @Model objects
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    /// Convenience accessors for test verification
    private(set) var storedEvents: [String: Event] = [:]
    private(set) var storedEventTypes: [String: EventType] = [:]
    private(set) var storedGeofences: [String: Geofence] = [:]
    private(set) var storedPropertyDefinitions: [String: PropertyDefinition] = [:]
    private(set) var storedPendingMutations: [PendingMutation] = []

    // MARK: - Call Recording (Spy Pattern)

    struct UpsertEventCall { let id: String; let timestamp: Date }
    struct DeleteEventCall { let id: String; let timestamp: Date }
    struct FindEventCall { let id: String; let timestamp: Date }
    struct UpsertEventTypeCall { let id: String; let timestamp: Date }
    struct DeleteEventTypeCall { let id: String; let timestamp: Date }
    struct FindEventTypeCall { let id: String; let timestamp: Date }
    struct UpsertGeofenceCall { let id: String; let timestamp: Date }
    struct DeleteGeofenceCall { let id: String; let timestamp: Date }
    struct FindGeofenceCall { let id: String; let timestamp: Date }
    struct UpsertPropertyDefinitionCall { let id: String; let timestamp: Date }
    struct DeletePropertyDefinitionCall { let id: String; let timestamp: Date }
    struct FindPropertyDefinitionCall { let id: String; let timestamp: Date }
    struct InsertMutationCall { let entityType: String; let entityId: String; let timestamp: Date }
    struct HasPendingMutationCall { let entityId: String; let entityType: String; let operation: String; let timestamp: Date }
    struct MarkSyncedCall { let id: String; let timestamp: Date }

    private(set) var upsertEventCalls: [UpsertEventCall] = []
    private(set) var deleteEventCalls: [DeleteEventCall] = []
    private(set) var findEventCalls: [FindEventCall] = []
    private(set) var upsertEventTypeCalls: [UpsertEventTypeCall] = []
    private(set) var deleteEventTypeCalls: [DeleteEventTypeCall] = []
    private(set) var findEventTypeCalls: [FindEventTypeCall] = []
    private(set) var upsertGeofenceCalls: [UpsertGeofenceCall] = []
    private(set) var deleteGeofenceCalls: [DeleteGeofenceCall] = []
    private(set) var findGeofenceCalls: [FindGeofenceCall] = []
    private(set) var upsertPropertyDefinitionCalls: [UpsertPropertyDefinitionCall] = []
    private(set) var deletePropertyDefinitionCalls: [DeletePropertyDefinitionCall] = []
    private(set) var findPropertyDefinitionCalls: [FindPropertyDefinitionCall] = []
    private(set) var insertMutationCalls: [InsertMutationCall] = []
    private(set) var hasPendingMutationCalls: [HasPendingMutationCall] = []
    private(set) var markEventSyncedCalls: [MarkSyncedCall] = []
    private(set) var markEventTypeSyncedCalls: [MarkSyncedCall] = []
    private(set) var markGeofenceSyncedCalls: [MarkSyncedCall] = []
    private(set) var markPropertyDefinitionSyncedCalls: [MarkSyncedCall] = []
    private(set) var saveCalls: Int = 0
    private(set) var fetchAllEventsCalls: Int = 0
    private(set) var fetchAllEventTypesCalls: Int = 0
    private(set) var fetchAllGeofencesCalls: Int = 0
    private(set) var fetchAllPropertyDefinitionsCalls: Int = 0
    private(set) var deleteAllEventsCalls: Int = 0
    private(set) var deleteAllEventTypesCalls: Int = 0
    private(set) var deleteAllGeofencesCalls: Int = 0
    private(set) var deleteAllPropertyDefinitionsCalls: Int = 0
    private(set) var fetchPendingMutationsCalls: Int = 0

    // MARK: - Error Injection

    var throwOnSave: Error?
    var throwOnUpsert: Error?
    var throwOnDelete: Error?
    var throwOnFind: Error?
    var throwOnFetchAll: Error?
    var throwOnInsertMutation: Error?
    var throwOnMarkSynced: Error?

    // MARK: - Initialization

    init() {
        // Create in-memory test container - models exist only in RAM
        let schema = Schema([
            Event.self,
            EventType.self,
            Geofence.self,
            PropertyDefinition.self,
            PendingMutation.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
            modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("Failed to create test ModelContainer: \(error)")
        }
    }

    // MARK: - Helper Methods

    /// Helper to ensure we have a valid EventType for Event creation
    private func getOrCreateDefaultEventType() throws -> EventType {
        if let existingType = storedEventTypes.values.first {
            return existingType
        }
        // Create a default type in the context
        let defaultType = EventType(name: "MockDefault", colorHex: "#888888", iconName: "circle")
        modelContext.insert(defaultType)
        storedEventTypes[defaultType.id] = defaultType
        return defaultType
    }

    // MARK: - Upsert Operations

    @discardableResult
    func upsertEvent(id: String, configure: (Event) -> Void) throws -> Event {
        upsertEventCalls.append(UpsertEventCall(id: id, timestamp: Date()))

        if let error = throwOnUpsert { throw error }

        let event: Event
        if let existing = storedEvents[id] {
            event = existing
        } else {
            // Create Event with ModelContext - use a default EventType
            let defaultType = try getOrCreateDefaultEventType()
            event = Event(timestamp: Date(), eventType: defaultType)
            event.id = id
            modelContext.insert(event)
        }

        configure(event)
        storedEvents[id] = event
        return event
    }

    @discardableResult
    func upsertEventType(id: String, configure: (EventType) -> Void) throws -> EventType {
        upsertEventTypeCalls.append(UpsertEventTypeCall(id: id, timestamp: Date()))

        if let error = throwOnUpsert { throw error }

        let eventType: EventType
        if let existing = storedEventTypes[id] {
            eventType = existing
        } else {
            eventType = EventType(name: "Placeholder", colorHex: "#000000", iconName: "circle")
            eventType.id = id
            modelContext.insert(eventType)
        }

        configure(eventType)
        storedEventTypes[id] = eventType
        return eventType
    }

    @discardableResult
    func upsertGeofence(id: String, configure: (Geofence) -> Void) throws -> Geofence {
        upsertGeofenceCalls.append(UpsertGeofenceCall(id: id, timestamp: Date()))

        if let error = throwOnUpsert { throw error }

        let geofence: Geofence
        if let existing = storedGeofences[id] {
            geofence = existing
        } else {
            geofence = Geofence(id: UUIDv7.generate(), name: "Placeholder", latitude: 0, longitude: 0, radius: 100, eventTypeEntryID: nil, eventTypeExitID: nil, isActive: true, notifyOnEntry: false, notifyOnExit: false, syncStatus: .pending)
            geofence.id = id
            modelContext.insert(geofence)
        }

        configure(geofence)
        storedGeofences[id] = geofence
        return geofence
    }

    @discardableResult
    func upsertPropertyDefinition(id: String, eventTypeId: String, configure: (PropertyDefinition) -> Void) throws -> PropertyDefinition {
        upsertPropertyDefinitionCalls.append(UpsertPropertyDefinitionCall(id: id, timestamp: Date()))

        if let error = throwOnUpsert { throw error }

        let propertyDefinition: PropertyDefinition
        if let existing = storedPropertyDefinitions[id] {
            propertyDefinition = existing
        } else {
            // Look up or create the EventType
            let eventType: EventType
            if let existingType = storedEventTypes[eventTypeId] {
                eventType = existingType
            } else {
                eventType = EventType(name: "Placeholder", colorHex: "#000000", iconName: "circle")
                eventType.id = eventTypeId
                modelContext.insert(eventType)
                storedEventTypes[eventTypeId] = eventType
            }

            propertyDefinition = PropertyDefinition(
                eventTypeId: eventTypeId,
                key: "placeholder",
                label: "Placeholder",
                propertyType: .text
            )
            propertyDefinition.id = id
            propertyDefinition.eventType = eventType
            modelContext.insert(propertyDefinition)
        }

        configure(propertyDefinition)
        storedPropertyDefinitions[id] = propertyDefinition
        return propertyDefinition
    }

    // MARK: - Delete Operations

    func deleteEvent(id: String) throws {
        deleteEventCalls.append(DeleteEventCall(id: id, timestamp: Date()))

        if let error = throwOnDelete { throw error }

        if let event = storedEvents.removeValue(forKey: id) {
            modelContext.delete(event)
        }
    }

    func deleteEventType(id: String) throws {
        deleteEventTypeCalls.append(DeleteEventTypeCall(id: id, timestamp: Date()))

        if let error = throwOnDelete { throw error }

        if let eventType = storedEventTypes.removeValue(forKey: id) {
            modelContext.delete(eventType)
        }
    }

    func deleteGeofence(id: String) throws {
        deleteGeofenceCalls.append(DeleteGeofenceCall(id: id, timestamp: Date()))

        if let error = throwOnDelete { throw error }

        if let geofence = storedGeofences.removeValue(forKey: id) {
            modelContext.delete(geofence)
        }
    }

    func deletePropertyDefinition(id: String) throws {
        deletePropertyDefinitionCalls.append(DeletePropertyDefinitionCall(id: id, timestamp: Date()))

        if let error = throwOnDelete { throw error }

        if let propertyDefinition = storedPropertyDefinitions.removeValue(forKey: id) {
            modelContext.delete(propertyDefinition)
        }
    }

    // MARK: - Lookup Operations

    func findEvent(id: String) throws -> Event? {
        findEventCalls.append(FindEventCall(id: id, timestamp: Date()))

        if let error = throwOnFind { throw error }

        return storedEvents[id]
    }

    func findEventType(id: String) throws -> EventType? {
        findEventTypeCalls.append(FindEventTypeCall(id: id, timestamp: Date()))

        if let error = throwOnFind { throw error }

        return storedEventTypes[id]
    }

    func findGeofence(id: String) throws -> Geofence? {
        findGeofenceCalls.append(FindGeofenceCall(id: id, timestamp: Date()))

        if let error = throwOnFind { throw error }

        return storedGeofences[id]
    }

    func findPropertyDefinition(id: String) throws -> PropertyDefinition? {
        findPropertyDefinitionCalls.append(FindPropertyDefinitionCall(id: id, timestamp: Date()))

        if let error = throwOnFind { throw error }

        return storedPropertyDefinitions[id]
    }

    // MARK: - Fetch All Operations

    func fetchAllEvents() throws -> [Event] {
        fetchAllEventsCalls += 1

        if let error = throwOnFetchAll { throw error }

        return Array(storedEvents.values)
    }

    func fetchAllEventTypes() throws -> [EventType] {
        fetchAllEventTypesCalls += 1

        if let error = throwOnFetchAll { throw error }

        return Array(storedEventTypes.values)
    }

    func fetchAllGeofences() throws -> [Geofence] {
        fetchAllGeofencesCalls += 1

        if let error = throwOnFetchAll { throw error }

        return Array(storedGeofences.values)
    }

    func fetchAllPropertyDefinitions() throws -> [PropertyDefinition] {
        fetchAllPropertyDefinitionsCalls += 1

        if let error = throwOnFetchAll { throw error }

        return Array(storedPropertyDefinitions.values)
    }

    // MARK: - Delete All Operations

    func deleteAllEvents() throws {
        deleteAllEventsCalls += 1

        if let error = throwOnDelete { throw error }

        for event in storedEvents.values {
            modelContext.delete(event)
        }
        storedEvents.removeAll()
    }

    func deleteAllEventTypes() throws {
        deleteAllEventTypesCalls += 1

        if let error = throwOnDelete { throw error }

        for eventType in storedEventTypes.values {
            modelContext.delete(eventType)
        }
        storedEventTypes.removeAll()
    }

    func deleteAllGeofences() throws {
        deleteAllGeofencesCalls += 1

        if let error = throwOnDelete { throw error }

        for geofence in storedGeofences.values {
            modelContext.delete(geofence)
        }
        storedGeofences.removeAll()
    }

    func deleteAllPropertyDefinitions() throws {
        deleteAllPropertyDefinitionsCalls += 1

        if let error = throwOnDelete { throw error }

        for propertyDefinition in storedPropertyDefinitions.values {
            modelContext.delete(propertyDefinition)
        }
        storedPropertyDefinitions.removeAll()
    }

    // MARK: - Pending Mutation Operations

    func insertPendingMutation(_ mutation: PendingMutation) throws {
        insertMutationCalls.append(InsertMutationCall(
            entityType: mutation.entityType.rawValue,
            entityId: mutation.entityId,
            timestamp: Date()
        ))

        if let error = throwOnInsertMutation { throw error }

        modelContext.insert(mutation)
        storedPendingMutations.append(mutation)
    }

    func fetchPendingMutations() throws -> [PendingMutation] {
        fetchPendingMutationsCalls += 1

        if let error = throwOnFetchAll { throw error }

        return storedPendingMutations
    }

    func hasPendingMutation(entityId: String, entityType: MutationEntityType, operation: MutationOperation) throws -> Bool {
        hasPendingMutationCalls.append(HasPendingMutationCall(
            entityId: entityId,
            entityType: entityType.rawValue,
            operation: operation.rawValue,
            timestamp: Date()
        ))

        if let error = throwOnFind { throw error }

        return storedPendingMutations.contains { mutation in
            mutation.entityId == entityId &&
            mutation.entityType == entityType &&
            mutation.operation == operation
        }
    }

    func deletePendingMutation(_ mutation: PendingMutation) throws {
        if let error = throwOnDelete { throw error }

        storedPendingMutations.removeAll { $0.id == mutation.id }
        modelContext.delete(mutation)
    }

    // MARK: - Sync Status Updates

    func markEventSynced(id: String) throws {
        markEventSyncedCalls.append(MarkSyncedCall(id: id, timestamp: Date()))

        if let error = throwOnMarkSynced { throw error }

        if let event = storedEvents[id] {
            event.syncStatus = .synced
        }
    }

    func markEventTypeSynced(id: String) throws {
        markEventTypeSyncedCalls.append(MarkSyncedCall(id: id, timestamp: Date()))

        if let error = throwOnMarkSynced { throw error }

        if let eventType = storedEventTypes[id] {
            eventType.syncStatus = .synced
        }
    }

    func markGeofenceSynced(id: String) throws {
        markGeofenceSyncedCalls.append(MarkSyncedCall(id: id, timestamp: Date()))

        if let error = throwOnMarkSynced { throw error }

        if let geofence = storedGeofences[id] {
            geofence.syncStatus = .synced
        }
    }

    func markPropertyDefinitionSynced(id: String) throws {
        markPropertyDefinitionSyncedCalls.append(MarkSyncedCall(id: id, timestamp: Date()))

        if let error = throwOnMarkSynced { throw error }

        if let propertyDefinition = storedPropertyDefinitions[id] {
            propertyDefinition.syncStatus = .synced
        }
    }

    // MARK: - Persistence

    func save() throws {
        saveCalls += 1

        if let error = throwOnSave { throw error }

        // In-memory ModelContext - just ensure state is consistent
        try modelContext.save()
    }

    // MARK: - Test Helper Methods

    /// Reset all state and call records
    func reset() {
        // Clear stored entities
        for event in storedEvents.values { modelContext.delete(event) }
        for eventType in storedEventTypes.values { modelContext.delete(eventType) }
        for geofence in storedGeofences.values { modelContext.delete(geofence) }
        for propDef in storedPropertyDefinitions.values { modelContext.delete(propDef) }
        for mutation in storedPendingMutations { modelContext.delete(mutation) }

        storedEvents.removeAll()
        storedEventTypes.removeAll()
        storedGeofences.removeAll()
        storedPropertyDefinitions.removeAll()
        storedPendingMutations.removeAll()

        // Clear call records
        upsertEventCalls.removeAll()
        deleteEventCalls.removeAll()
        findEventCalls.removeAll()
        upsertEventTypeCalls.removeAll()
        deleteEventTypeCalls.removeAll()
        findEventTypeCalls.removeAll()
        upsertGeofenceCalls.removeAll()
        deleteGeofenceCalls.removeAll()
        findGeofenceCalls.removeAll()
        upsertPropertyDefinitionCalls.removeAll()
        deletePropertyDefinitionCalls.removeAll()
        findPropertyDefinitionCalls.removeAll()
        insertMutationCalls.removeAll()
        hasPendingMutationCalls.removeAll()
        markEventSyncedCalls.removeAll()
        markEventTypeSyncedCalls.removeAll()
        markGeofenceSyncedCalls.removeAll()
        markPropertyDefinitionSyncedCalls.removeAll()
        saveCalls = 0
        fetchAllEventsCalls = 0
        fetchAllEventTypesCalls = 0
        fetchAllGeofencesCalls = 0
        fetchAllPropertyDefinitionsCalls = 0
        deleteAllEventsCalls = 0
        deleteAllEventTypesCalls = 0
        deleteAllGeofencesCalls = 0
        deleteAllPropertyDefinitionsCalls = 0
        fetchPendingMutationsCalls = 0

        // Clear error injections
        throwOnSave = nil
        throwOnUpsert = nil
        throwOnDelete = nil
        throwOnFind = nil
        throwOnFetchAll = nil
        throwOnInsertMutation = nil
        throwOnMarkSynced = nil
    }

    // MARK: - State Seeding Methods

    /// Direct state seeding for test setup - inserts into ModelContext
    func seedEventType(_ configure: (EventType) -> Void) -> EventType {
        let eventType = EventType(name: "Seeded", colorHex: "#000000", iconName: "circle")
        modelContext.insert(eventType)
        configure(eventType)
        storedEventTypes[eventType.id] = eventType
        return eventType
    }

    func seedEvent(eventType: EventType, _ configure: (Event) -> Void) -> Event {
        let event = Event(timestamp: Date(), eventType: eventType)
        modelContext.insert(event)
        configure(event)
        storedEvents[event.id] = event
        return event
    }

    func seedGeofence(_ configure: (Geofence) -> Void) -> Geofence {
        let geofence = Geofence(id: UUIDv7.generate(), name: "Seeded", latitude: 0, longitude: 0, radius: 100, eventTypeEntryID: nil, eventTypeExitID: nil, isActive: true, notifyOnEntry: false, notifyOnExit: false, syncStatus: .pending)
        modelContext.insert(geofence)
        configure(geofence)
        storedGeofences[geofence.id] = geofence
        return geofence
    }

    func seedPropertyDefinition(eventType: EventType, _ configure: (PropertyDefinition) -> Void) -> PropertyDefinition {
        let propDef = PropertyDefinition(eventTypeId: eventType.id, key: "seeded", label: "Seeded", propertyType: .text)
        propDef.eventType = eventType
        modelContext.insert(propDef)
        configure(propDef)
        storedPropertyDefinitions[propDef.id] = propDef
        return propDef
    }

    func seedPendingMutation(entityType: MutationEntityType, entityId: String, operation: MutationOperation, payload: Data? = nil) -> PendingMutation {
        let mutation = PendingMutation(entityType: entityType, operation: operation, entityId: entityId, payload: payload ?? Data())
        modelContext.insert(mutation)
        storedPendingMutations.append(mutation)
        return mutation
    }
}
