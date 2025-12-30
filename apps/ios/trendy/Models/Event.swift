//
//  Event.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import SwiftData

enum EventSourceType: String, Codable, CaseIterable {
    case manual = "manual"
    case imported = "imported"
    case geofence = "geofence"
    case healthKit = "healthkit"
}

@Model
final class Event {
    /// UUIDv7 identifier - client-generated, globally unique, time-ordered
    /// This is THE canonical ID used both locally and on the server
    @Attribute(.unique) var id: String
    /// Sync status with the backend
    var syncStatusRaw: String = SyncStatus.pending.rawValue
    var timestamp: Date
    var notes: String?
    var eventType: EventType?
    /// Stored eventTypeId for relationship recovery when eventType relationship is nil
    /// This is populated during sync and allows restoring broken relationships
    var eventTypeId: String?
    // Store raw string to avoid SwiftData context detachment issues with enums
    var sourceTypeRaw: String = EventSourceType.manual.rawValue
    var externalId: String?
    var originalTitle: String?
    var isAllDay: Bool = false
    var endDate: Date?
    var calendarEventId: String?
    /// Geofence ID (UUIDv7 string) - references Geofence.id
    var geofenceId: String?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationName: String?
    var healthKitSampleId: String?    // HealthKit sample UUID for deduplication
    var healthKitCategory: String?     // e.g., "workout", "sleep", "steps"
    var propertiesData: Data? // Encoded [String: PropertyValue]

    // MARK: - Computed Properties

    /// Sync status computed property for convenient access
    @Transient var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    // Computed property for convenient enum access
    @Transient var sourceType: EventSourceType {
        get { EventSourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    // Computed property for convenient access to properties
    var properties: [String: PropertyValue] {
        get {
            guard let data = propertiesData else {
                #if DEBUG
                print("📖 Event.properties GET: propertiesData is nil, returning empty dict")
                #endif
                return [:]
            }
            do {
                let decoded = try JSONDecoder().decode([String: PropertyValue].self, from: data)
                #if DEBUG
                print("📖 Event.properties GET: Decoded \(decoded.count) properties: \(decoded.keys.joined(separator: ", "))")
                #endif
                return decoded
            } catch {
                #if DEBUG
                print("❌ Event.properties GET: Failed to decode - \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("❌ Raw JSON was: \(jsonString)")
                }
                #endif
                return [:]
            }
        }
        set {
            #if DEBUG
            print("📝 Event.properties SET: Setting \(newValue.count) properties: \(newValue.keys.joined(separator: ", "))")
            for (key, value) in newValue {
                print("   - \(key): type=\(value.type.rawValue), value=\(value.value.value)")
            }
            #endif
            do {
                let encoded = try JSONEncoder().encode(newValue)
                #if DEBUG
                if let jsonString = String(data: encoded, encoding: .utf8) {
                    print("📝 Event.properties SET: Encoded JSON: \(jsonString)")
                }
                #endif
                propertiesData = encoded
            } catch {
                #if DEBUG
                print("❌ Event.properties SET: Failed to encode - \(error)")
                #endif
                propertiesData = nil
            }
        }
    }

    init(
        id: String = UUIDv7.generate(),
        timestamp: Date = Date(),
        eventType: EventType? = nil,
        notes: String? = nil,
        sourceType: EventSourceType = .manual,
        externalId: String? = nil,
        originalTitle: String? = nil,
        isAllDay: Bool = false,
        endDate: Date? = nil,
        calendarEventId: String? = nil,
        geofenceId: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        locationName: String? = nil,
        healthKitSampleId: String? = nil,
        healthKitCategory: String? = nil,
        properties: [String: PropertyValue] = [:],
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.syncStatusRaw = syncStatus.rawValue
        self.timestamp = timestamp
        self.eventType = eventType
        self.eventTypeId = eventType?.id  // Store for relationship recovery
        self.notes = notes
        self.sourceTypeRaw = sourceType.rawValue
        self.externalId = externalId
        self.originalTitle = originalTitle
        self.isAllDay = isAllDay
        self.endDate = endDate
        self.calendarEventId = calendarEventId
        self.geofenceId = geofenceId
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.locationName = locationName
        self.healthKitSampleId = healthKitSampleId
        self.healthKitCategory = healthKitCategory

        #if DEBUG
        print("🆕 Event.init() with \(properties.count) properties: \(properties.keys.joined(separator: ", "))")
        #endif

        do {
            let encoded = try JSONEncoder().encode(properties)
            self.propertiesData = encoded
            #if DEBUG
            if let jsonString = String(data: encoded, encoding: .utf8) {
                print("🆕 Event.init() encoded JSON: \(jsonString)")
            }
            #endif
        } catch {
            #if DEBUG
            print("❌ Event.init() failed to encode properties: \(error)")
            #endif
            self.propertiesData = nil
        }
    }
}
