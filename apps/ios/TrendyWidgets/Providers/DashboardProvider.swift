//
//  DashboardProvider.swift
//  TrendyWidgets
//
//  Timeline provider for the large dashboard widget.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Entry for the large dashboard widget
struct DashboardEntry: TimelineEntry {
    let date: Date
    let quickLogTypes: [EventTypeWithCount]
    let recentEvents: [RecentEventData]
    let todayTotalCount: Int
    let configuration: DashboardConfigurationIntent
}

/// Lightweight data for displaying recent events
struct RecentEventData: Identifiable {
    let id: String
    let eventTypeName: String
    let eventTypeColorHex: String
    let eventTypeIconName: String
    let timestamp: Date
    let sourceType: String

    var color: Color {
        Color(hex: eventTypeColorHex) ?? .blue
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Timeline Provider

struct DashboardProvider: AppIntentTimelineProvider {
    typealias Entry = DashboardEntry
    typealias Intent = DashboardConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        DashboardEntry(
            date: Date(),
            quickLogTypes: [
                EventTypeWithCount(id: "1", name: "Running", colorHex: "#FF5722", iconName: "figure.run", todayCount: 2),
                EventTypeWithCount(id: "2", name: "Water", colorHex: "#2196F3", iconName: "drop.fill", todayCount: 5),
                EventTypeWithCount(id: "3", name: "Meditation", colorHex: "#9C27B0", iconName: "brain.head.profile", todayCount: 1)
            ],
            recentEvents: [
                RecentEventData(id: "1", eventTypeName: "Running", eventTypeColorHex: "#FF5722", eventTypeIconName: "figure.run", timestamp: Date().addingTimeInterval(-3600), sourceType: "manual"),
                RecentEventData(id: "2", eventTypeName: "Water", eventTypeColorHex: "#2196F3", eventTypeIconName: "drop.fill", timestamp: Date().addingTimeInterval(-7200), sourceType: "manual"),
                RecentEventData(id: "3", eventTypeName: "Sleep", eventTypeColorHex: "#673AB7", eventTypeIconName: "bed.double.fill", timestamp: Date().addingTimeInterval(-28800), sourceType: "healthkit")
            ],
            todayTotalCount: 8,
            configuration: DashboardConfigurationIntent()
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
        let dataManager = WidgetDataManager.shared

        // Fetch quick log types with counts
        var quickLogTypes: [EventTypeWithCount] = []
        for configType in (configuration.quickLogTypes ?? []).prefix(4) {
            guard let uuid = UUID(uuidString: configType.id) else { continue }
            let count = (try? await dataManager.getTodayCount(for: uuid)) ?? 0
            quickLogTypes.append(EventTypeWithCount(
                id: configType.id,
                name: configType.name,
                colorHex: configType.colorHex,
                iconName: configType.iconName,
                todayCount: count
            ))
        }

        // Fetch recent events
        var recentEvents: [RecentEventData] = []
        if configuration.showRecentEvents ?? true {
            let events = (try? await dataManager.getRecentEvents(limit: 5)) ?? []
            recentEvents = events.compactMap { event in
                guard let eventType = event.eventType else { return nil }
                return RecentEventData(
                    id: event.id.uuidString,
                    eventTypeName: eventType.name,
                    eventTypeColorHex: eventType.colorHex,
                    eventTypeIconName: eventType.iconName,
                    timestamp: event.timestamp,
                    sourceType: event.sourceTypeRaw
                )
            }
        }

        // Calculate today's total
        let todayTotal: Int
        if configuration.showTodaySummary ?? true {
            let todayEvents = (try? await dataManager.getTodayEventsAll()) ?? []
            todayTotal = todayEvents.count
        } else {
            todayTotal = 0
        }

        return DashboardEntry(
            date: Date(),
            quickLogTypes: quickLogTypes,
            recentEvents: recentEvents,
            todayTotalCount: todayTotal,
            configuration: configuration
        )
    }
}
