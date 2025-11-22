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
}

@Model
final class Event {
    var id: UUID
    var timestamp: Date
    var notes: String?
    var eventType: EventType?
    // Store raw string to avoid SwiftData context detachment issues with enums
    var sourceTypeRaw: String = EventSourceType.manual.rawValue
    var externalId: String?
    var originalTitle: String?
    var isAllDay: Bool = false
    var endDate: Date?
    var calendarEventId: String?
    var geofenceId: UUID?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var locationName: String?
    var propertiesData: Data? // Encoded [String: PropertyValue]

    // Computed property for convenient enum access
    @Transient var sourceType: EventSourceType {
        get { EventSourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    // Computed property for convenient access to properties
    var properties: [String: PropertyValue] {
        get {
            guard let data = propertiesData else { return [:] }
            return (try? JSONDecoder().decode([String: PropertyValue].self, from: data)) ?? [:]
        }
        set {
            propertiesData = try? JSONEncoder().encode(newValue)
        }
    }

    init(timestamp: Date = Date(), eventType: EventType? = nil, notes: String? = nil, sourceType: EventSourceType = .manual, externalId: String? = nil, originalTitle: String? = nil, isAllDay: Bool = false, endDate: Date? = nil, calendarEventId: String? = nil, geofenceId: UUID? = nil, locationLatitude: Double? = nil, locationLongitude: Double? = nil, locationName: String? = nil, properties: [String: PropertyValue] = [:]) {
        self.id = UUID()
        self.timestamp = timestamp
        self.eventType = eventType
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
        self.propertiesData = try? JSONEncoder().encode(properties)
    }
}
