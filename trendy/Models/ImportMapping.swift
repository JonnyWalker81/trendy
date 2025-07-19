//
//  ImportMapping.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import EventKit

struct CalendarEventMapping: Identifiable {
    let id = UUID()
    let calendarEvent: EKEvent
    var suggestedEventType: EventType?
    var suggestedEventTypeName: String
    var suggestedColor: String
    var suggestedIcon: String
    var shouldImport: Bool = true
    
    init(calendarEvent: EKEvent, suggestedEventType: EventType? = nil) {
        self.calendarEvent = calendarEvent
        self.suggestedEventType = suggestedEventType
        self.suggestedEventTypeName = calendarEvent.title ?? "Unknown Event"
        self.suggestedColor = "#007AFF"
        self.suggestedIcon = "circle.fill"
    }
}

struct EventTypeMapping: Identifiable {
    let id = UUID()
    let name: String
    let calendarEvents: [EKEvent]
    var existingEventType: EventType?
    var suggestedColor: String
    var suggestedIcon: String
    var shouldCreateNew: Bool
    var isSelected: Bool = true
    
    init(name: String, events: [EKEvent], existingType: EventType? = nil) {
        self.name = name
        self.calendarEvents = events
        self.existingEventType = existingType
        self.shouldCreateNew = (existingType == nil)
        self.suggestedColor = existingType?.colorHex ?? "#007AFF"
        self.suggestedIcon = existingType?.iconName ?? "circle.fill"
    }
}

struct ImportSummary {
    let totalEvents: Int
    let importedEvents: Int
    let skippedEvents: Int
    let newEventTypes: Int
    let errors: [String]
    let startDate: Date
    let endDate: Date
}