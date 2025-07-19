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
}

@Model
final class Event {
    var id: UUID
    var timestamp: Date
    var notes: String?
    var eventType: EventType?
    var sourceType: EventSourceType
    var externalId: String?
    var originalTitle: String?
    var isAllDay: Bool = false
    var endDate: Date?
    
    init(timestamp: Date = Date(), eventType: EventType? = nil, notes: String? = nil, sourceType: EventSourceType = .manual, externalId: String? = nil, originalTitle: String? = nil, isAllDay: Bool = false, endDate: Date? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.eventType = eventType
        self.notes = notes
        self.sourceType = sourceType
        self.externalId = externalId
        self.originalTitle = originalTitle
        self.isAllDay = isAllDay
        self.endDate = endDate
    }
}
