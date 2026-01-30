//
//  ConfigurationIntent.swift
//  TrendyWidgets
//
//  Configuration intents for widget customization.
//

import AppIntents
import SwiftUI

// MARK: - Event Type Entity

/// Entity representing an EventType for widget configuration
struct EventTypeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Event Type"
    static var defaultQuery = EventTypeQuery()

    var id: String
    var name: String
    var colorHex: String
    var iconName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: iconName)
        )
    }
}

// MARK: - Event Type Query

/// Query for fetching EventTypes from the JSON bridge (no SwiftData access)
struct EventTypeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [EventTypeEntity] {
        let dataManager = WidgetDataManager.shared
        let allTypes = try await dataManager.getAllEventTypes()

        return allTypes
            .filter { identifiers.contains($0.id) }
            .map { eventType in
                EventTypeEntity(
                    id: eventType.id,
                    name: eventType.name,
                    colorHex: eventType.colorHex,
                    iconName: eventType.iconName
                )
            }
    }

    func suggestedEntities() async throws -> [EventTypeEntity] {
        let dataManager = WidgetDataManager.shared
        let allTypes = try await dataManager.getAllEventTypes()

        return allTypes.map { eventType in
            EventTypeEntity(
                id: eventType.id,
                name: eventType.name,
                colorHex: eventType.colorHex,
                iconName: eventType.iconName
            )
        }
    }

    func defaultResult() async -> EventTypeEntity? {
        try? await suggestedEntities().first
    }
}

// MARK: - Single Event Type Configuration

/// Configuration intent for widgets that display a single EventType
struct SingleEventTypeConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Event Type"
    static var description = IntentDescription("Choose which event type to display")

    @Parameter(title: "Event Type")
    var eventType: EventTypeEntity?

    @Parameter(title: "Show Streak", default: true)
    var showStreak: Bool?

    @Parameter(title: "Show Today's Count", default: true)
    var showTodayCount: Bool?
}

// MARK: - Multiple Event Types Configuration

/// Configuration intent for widgets that display multiple EventTypes (grid widgets)
struct MultiEventTypeConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Event Types"
    static var description = IntentDescription("Choose which event types to display (1-6)")

    @Parameter(title: "Event Types")
    var eventTypes: [EventTypeEntity]?

    @Parameter(title: "Show Today's Count", default: true)
    var showTodayCount: Bool?

    init() {
        self.eventTypes = []
        self.showTodayCount = true
    }

    init(eventTypes: [EventTypeEntity], showTodayCount: Bool = true) {
        self.eventTypes = eventTypes
        self.showTodayCount = showTodayCount
    }
}

// MARK: - Dashboard Configuration

/// Configuration intent for the large dashboard widget
struct DashboardConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Dashboard Settings"
    static var description = IntentDescription("Configure the dashboard widget")

    @Parameter(title: "Quick Log Types")
    var quickLogTypes: [EventTypeEntity]?

    @Parameter(title: "Show Recent Events", default: true)
    var showRecentEvents: Bool?

    @Parameter(title: "Show Today's Summary", default: true)
    var showTodaySummary: Bool?

    init() {
        self.quickLogTypes = []
        self.showRecentEvents = true
        self.showTodaySummary = true
    }
}
