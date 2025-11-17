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
    var eventTypeEntry: EventType? // Event type to create on entry
    var eventTypeExit: EventType? // Event type to create on exit (currently unused, for future)
    var isActive: Bool
    var notifyOnEntry: Bool
    var notifyOnExit: Bool
    var createdAt: Date

    init(name: String, latitude: Double, longitude: Double, radius: Double = 100.0, eventTypeEntry: EventType? = nil, eventTypeExit: EventType? = nil, isActive: Bool = true, notifyOnEntry: Bool = false, notifyOnExit: Bool = false) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.eventTypeEntry = eventTypeEntry
        self.eventTypeExit = eventTypeExit
        self.isActive = isActive
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.createdAt = Date()
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
