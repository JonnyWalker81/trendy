//
//  IDMappings.swift
//  trendy
//
//  Manages bidirectional ID mappings between local UUIDs and backend string IDs
//

import Foundation

/// Manages persistent ID mappings between local SwiftData UUIDs and backend string IDs.
/// Provides bidirectional lookup for EventTypes and Events only.
/// NOTE: Geofences store backendId directly on the model - no mapping needed.
struct IDMappings {
    // MARK: - Storage Keys

    private static let eventTypeKey = "eventTypeBackendIds"
    private static let eventKey = "eventBackendIds"

    // MARK: - EventType Mappings

    private var eventTypeLocalToBackend: [UUID: String] = [:]
    private var eventTypeBackendToLocal: [String: UUID] = [:]

    // MARK: - Event Mappings

    private var eventLocalToBackend: [UUID: String] = [:]
    private var eventBackendToLocal: [String: UUID] = [:]

    // MARK: - Initialization

    init() {
        loadFromUserDefaults()
    }

    // MARK: - EventType Mapping API

    /// Get backend ID for a local EventType UUID
    func eventTypeBackendId(for localId: UUID) -> String? {
        eventTypeLocalToBackend[localId]
    }

    /// Get local UUID for a backend EventType ID
    func localEventTypeId(for backendId: String) -> UUID? {
        eventTypeBackendToLocal[backendId]
    }

    /// Set mapping between local UUID and backend ID for EventType
    mutating func setEventTypeBackendId(_ backendId: String, for localId: UUID) {
        eventTypeLocalToBackend[localId] = backendId
        eventTypeBackendToLocal[backendId] = localId
    }

    /// Remove EventType mapping
    mutating func removeEventTypeMapping(for localId: UUID) {
        if let backendId = eventTypeLocalToBackend.removeValue(forKey: localId) {
            eventTypeBackendToLocal.removeValue(forKey: backendId)
        }
    }

    /// Get all EventType local IDs that have backend mappings
    var mappedEventTypeLocalIds: Set<UUID> {
        Set(eventTypeLocalToBackend.keys)
    }

    // MARK: - Event Mapping API

    /// Get backend ID for a local Event UUID
    func eventBackendId(for localId: UUID) -> String? {
        eventLocalToBackend[localId]
    }

    /// Get local UUID for a backend Event ID
    func localEventId(for backendId: String) -> UUID? {
        eventBackendToLocal[backendId]
    }

    /// Set mapping between local UUID and backend ID for Event
    mutating func setEventBackendId(_ backendId: String, for localId: UUID) {
        eventLocalToBackend[localId] = backendId
        eventBackendToLocal[backendId] = localId
    }

    /// Remove Event mapping
    mutating func removeEventMapping(for localId: UUID) {
        if let backendId = eventLocalToBackend.removeValue(forKey: localId) {
            eventBackendToLocal.removeValue(forKey: backendId)
        }
    }

    /// Get all Event local IDs that have backend mappings
    var mappedEventLocalIds: Set<UUID> {
        Set(eventLocalToBackend.keys)
    }

    // MARK: - Persistence

    /// Load all mappings from UserDefaults
    mutating func loadFromUserDefaults() {
        eventTypeLocalToBackend = loadMapping(key: Self.eventTypeKey)
        eventTypeBackendToLocal = buildReverseMapping(eventTypeLocalToBackend)

        eventLocalToBackend = loadMapping(key: Self.eventKey)
        eventBackendToLocal = buildReverseMapping(eventLocalToBackend)
    }

    /// Save all mappings to UserDefaults
    func saveToUserDefaults() {
        saveMapping(eventTypeLocalToBackend, key: Self.eventTypeKey)
        saveMapping(eventLocalToBackend, key: Self.eventKey)
    }

    // MARK: - Private Helpers

    private func loadMapping(key: String) -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        var result: [UUID: String] = [:]
        for (uuidString, backendId) in dict {
            if let uuid = UUID(uuidString: uuidString) {
                result[uuid] = backendId
            }
        }
        return result
    }

    private func saveMapping(_ mapping: [UUID: String], key: String) {
        let stringDict = Dictionary(uniqueKeysWithValues: mapping.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func buildReverseMapping(_ mapping: [UUID: String]) -> [String: UUID] {
        // Use uniquingKeysWith to handle duplicate backend IDs (keep the first one)
        Dictionary(mapping.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Debugging

    /// Print current mapping counts for debugging
    func debugPrintCounts() {
        Log.sync.debug("IDMappings counts", context: .with { ctx in
            ctx.add("eventTypes", eventTypeLocalToBackend.count)
            ctx.add("events", eventLocalToBackend.count)
        })
    }
}
