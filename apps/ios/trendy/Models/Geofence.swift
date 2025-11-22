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

    init(name: String, latitude: Double, longitude: Double, radius: Double = 100.0, eventTypeEntryID: UUID? = nil, eventTypeExitID: UUID? = nil, isActive: Bool = true, notifyOnEntry: Bool = false, notifyOnExit: Bool = false) {
        self.id = UUID()
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
    convenience init(name: String, latitude: Double, longitude: Double, radius: Double = 100.0, eventTypeEntry: EventType? = nil, eventTypeExit: EventType? = nil, isActive: Bool = true, notifyOnEntry: Bool = false, notifyOnExit: Bool = false) {
        self.init(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            eventTypeEntryID: eventTypeEntry?.id,
            eventTypeExitID: eventTypeExit?.id,
            isActive: isActive,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )
    }

    // Computed property for CoreLocation coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // Computed property to create CLCircularRegion for monitoring
    var circularRegion: CLCircularRegion {
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: id.uuidString)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }
}
