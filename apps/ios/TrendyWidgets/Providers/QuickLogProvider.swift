//
//  QuickLogProvider.swift
//  TrendyWidgets
//
//  Timeline provider for single-EventType quick log widgets.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Entry for quick log widgets displaying a single EventType
struct QuickLogEntry: TimelineEntry {
    let date: Date
    let eventType: EventTypeData?
    let todayCount: Int
    let streak: Int
    let lastEventTime: Date?
    let configuration: SingleEventTypeConfigurationIntent
}

/// Lightweight data structure for EventType (avoids SwiftData context issues)
struct EventTypeData: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let iconName: String

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

// MARK: - Timeline Provider

struct QuickLogProvider: AppIntentTimelineProvider {
    typealias Entry = QuickLogEntry
    typealias Intent = SingleEventTypeConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        QuickLogEntry(
            date: Date(),
            eventType: EventTypeData(
                id: "placeholder",
                name: "Event",
                colorHex: "#007AFF",
                iconName: "circle.fill"
            ),
            todayCount: 3,
            streak: 7,
            lastEventTime: Date().addingTimeInterval(-3600),
            configuration: SingleEventTypeConfigurationIntent()
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        await getEntry(for: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let entry = await getEntry(for: configuration)

        // Calculate next refresh time
        // Refresh at midnight (to update daily counts) or in 15 minutes
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        let fifteenMinutes = Date().addingTimeInterval(15 * 60)
        let nextUpdate = min(tomorrow, fifteenMinutes)

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    @MainActor
    private func getEntry(for configuration: Intent) async -> Entry {
        // Check if an EventType is configured
        guard let configuredType = configuration.eventType else {
            return QuickLogEntry(
                date: Date(),
                eventType: nil,
                todayCount: 0,
                streak: 0,
                lastEventTime: nil,
                configuration: configuration
            )
        }

        let eventTypeId = configuredType.id
        let dataManager = WidgetDataManager.shared

        do {
            let todayCount = try await dataManager.getTodayCount(for: eventTypeId)
            let streak = (configuration.showStreak ?? true) ? try await dataManager.getStreak(for: eventTypeId) : 0
            let lastEventTime = try await dataManager.getLastEventTime(for: eventTypeId)

            return QuickLogEntry(
                date: Date(),
                eventType: EventTypeData(
                    id: configuredType.id,
                    name: configuredType.name,
                    colorHex: configuredType.colorHex,
                    iconName: configuredType.iconName
                ),
                todayCount: todayCount,
                streak: streak,
                lastEventTime: lastEventTime,
                configuration: configuration
            )
        } catch {
            return QuickLogEntry(
                date: Date(),
                eventType: EventTypeData(
                    id: configuredType.id,
                    name: configuredType.name,
                    colorHex: configuredType.colorHex,
                    iconName: configuredType.iconName
                ),
                todayCount: 0,
                streak: 0,
                lastEventTime: nil,
                configuration: configuration
            )
        }
    }
}
