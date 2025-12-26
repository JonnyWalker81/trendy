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
    /// UUIDv7 identifier - client-generated, globally unique, time-ordered
    /// This is THE canonical ID used both locally and on the server
    @Attribute(.unique) var id: String
    /// Sync status with the backend
    var syncStatusRaw: String = SyncStatus.pending.rawValue
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double // in meters

    // Store EventType IDs (UUIDv7 strings) instead of direct relationships
    // to avoid invalidation issues when EventTypes are deleted/recreated during backend sync
    var eventTypeEntryID: String?
    var eventTypeExitID: String?

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
        id: String = UUIDv7.generate(),
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100.0,
        eventTypeEntryID: String? = nil,
        eventTypeExitID: String? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = false,
        notifyOnExit: Bool = false,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
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
        id: String = UUIDv7.generate(),
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100.0,
        eventTypeEntry: EventType? = nil,
        eventTypeExit: EventType? = nil,
        isActive: Bool = true,
        notifyOnEntry: Bool = false,
        notifyOnExit: Bool = false,
        syncStatus: SyncStatus = .pending
    ) {
        self.init(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            eventTypeEntryID: eventTypeEntry?.id,
            eventTypeExitID: eventTypeExit?.id,
            isActive: isActive,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit,
            syncStatus: syncStatus
        )
    }

    // Computed property for CoreLocation coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Region identifier for CLLocationManager - uses the UUIDv7 id
    var regionIdentifier: String {
        id
    }

    // Computed property to create CLCircularRegion for monitoring
    var circularRegion: CLCircularRegion {
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }
}
