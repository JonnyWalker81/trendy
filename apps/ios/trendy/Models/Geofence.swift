//
//  Geofence.swift
//  trendy
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class Geofence {
    var id: UUID
    /// Server-generated ID - unique constraint ensures no duplicates
    @Attribute(.unique) var serverId: String?
    /// Sync status with the backend
    var syncStatusRaw: String = SyncStatus.pending.rawValue
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double // in meters

    // Store EventType IDs instead of direct relationships to avoid invalidation issues
    // when EventTypes are deleted/recreated during backend sync
    var eventTypeEntryID: UUID?
    var eventTypeExitID: UUID?

    var isActive: Bool
    var notifyOnEntry: Bool
    var notifyOnExit: Bool
    var createdAt: Date

    // MARK: - Computed Properties

    /// Sync status computed property for convenient access
    @Transient var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100.0,
        eventTypeEntryID: UUID? = nil,
        eventTypeExitID: UUID? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = false,
        notifyOnExit: Bool = false,
        serverId: String? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = UUID()
        self.serverId = serverId
        self.syncStatusRaw = syncStatus.rawValue
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.eventTypeEntryID = eventTypeEntryID
        self.eventTypeExitID = eventTypeExitID
        self.isActive = isActive
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.createdAt = Date()
    }

    // Convenience initializer that takes EventType objects
    convenience init(
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100.0,
        eventTypeEntry: EventType? = nil,
        eventTypeExit: EventType? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = false,
        notifyOnExit: Bool = false,
        serverId: String? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.init(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            eventTypeEntryID: eventTypeEntry?.id,
            eventTypeExitID: eventTypeExit?.id,
            isActive: isActive,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit,
            serverId: serverId,
            syncStatus: syncStatus
        )
    }

    // Computed property for CoreLocation coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Region identifier for CLLocationManager - uses serverId if synced, otherwise local UUID
    var regionIdentifier: String {
        serverId ?? id.uuidString
    }

    // Computed property to create CLCircularRegion for monitoring
    var circularRegion: CLCircularRegion {
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    // MARK: - Backward Compatibility

    /// Alias for serverId to maintain backward compatibility with existing code
    @Transient var backendId: String? {
        get { serverId }
        set { serverId = newValue }
    }
}
