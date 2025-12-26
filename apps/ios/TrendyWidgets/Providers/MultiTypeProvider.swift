//
//  MultiTypeProvider.swift
//  TrendyWidgets
//
//  Timeline provider for multi-EventType grid widgets.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Entry for widgets displaying multiple EventTypes in a grid
struct MultiTypeEntry: TimelineEntry {
    let date: Date
    let eventTypes: [EventTypeWithCount]
    let configuration: MultiEventTypeConfigurationIntent
}

/// EventType data with today's count
struct EventTypeWithCount: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let iconName: String
    let todayCount: Int

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

// MARK: - Timeline Provider

struct MultiTypeProvider: AppIntentTimelineProvider {
    typealias Entry = MultiTypeEntry
    typealias Intent = MultiEventTypeConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        MultiTypeEntry(
            date: Date(),
            eventTypes: [
                EventTypeWithCount(id: "1", name: "Running", colorHex: "#FF5722", iconName: "figure.run", todayCount: 2),
                EventTypeWithCount(id: "2", name: "Water", colorHex: "#2196F3", iconName: "drop.fill", todayCount: 5),
                EventTypeWithCount(id: "3", name: "Sleep", colorHex: "#9C27B0", iconName: "bed.double.fill", todayCount: 1),
                EventTypeWithCount(id: "4", name: "Reading", colorHex: "#4CAF50", iconName: "book.fill", todayCount: 0)
            ],
            configuration: MultiEventTypeConfigurationIntent()
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        await getEntry(for: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let entry = await getEntry(for: configuration)

        // Refresh at midnight or in 15 minutes
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        let fifteenMinutes = Date().addingTimeInterval(15 * 60)
        let nextUpdate = min(tomorrow, fifteenMinutes)

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    @MainActor
    private func getEntry(for configuration: Intent) async -> Entry {
        let configuredTypes = configuration.eventTypes ?? []

        guard !configuredTypes.isEmpty else {
            return MultiTypeEntry(
                date: Date(),
                eventTypes: [],
                configuration: configuration
            )
        }

        let dataManager = WidgetDataManager.shared
        var eventTypesWithCounts: [EventTypeWithCount] = []

        for configType in configuredTypes.prefix(6) { // Max 6 types
            let eventTypeId = configType.id
            let count = (try? await dataManager.getTodayCount(for: eventTypeId)) ?? 0

            eventTypesWithCounts.append(EventTypeWithCount(
                id: configType.id,
                name: configType.name,
                colorHex: configType.colorHex,
                iconName: configType.iconName,
                todayCount: (configuration.showTodayCount ?? true) ? count : 0
            ))
        }

        return MultiTypeEntry(
            date: Date(),
            eventTypes: eventTypesWithCounts,
            configuration: configuration
        )
    }
}
