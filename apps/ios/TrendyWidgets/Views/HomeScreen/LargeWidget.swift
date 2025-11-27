//
//  LargeWidget.swift
//  TrendyWidgets
//
//  systemLarge dashboard widget with quick log, recent events, and stats.
//

import SwiftUI
import WidgetKit
import AppIntents

struct LargeWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Today's Activity")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if entry.configuration.showTodaySummary ?? true {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption)
                        Text("\(entry.todayTotalCount) events")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Quick Log Row
            if !entry.quickLogTypes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Log")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        ForEach(entry.quickLogTypes) { eventType in
                            DashboardQuickLogButton(eventType: eventType)
                        }
                        Spacer()
                    }
                }
            }

            Divider()

            // Recent Events
            if entry.configuration.showRecentEvents ?? true {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    if entry.recentEvents.isEmpty {
                        HStack {
                            Spacer()
                            Text("No events yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(entry.recentEvents.prefix(4)) { event in
                            RecentEventRow(event: event)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

struct DashboardQuickLogButton: View {
    let eventType: EventTypeWithCount

    var body: some View {
        Button(intent: QuickLogIntent(eventTypeId: eventType.id)) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(eventType.color.gradient)
                        .frame(width: 36, height: 36)

                    Image(systemName: eventType.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(eventType.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if eventType.todayCount > 0 {
                    Text("\(eventType.todayCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(eventType.color)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct RecentEventRow: View {
    let event: RecentEventData

    var body: some View {
        HStack(spacing: 10) {
            // Event type indicator
            Circle()
                .fill(event.color)
                .frame(width: 8, height: 8)

            // Event type name
            Text(event.eventTypeName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            // Source indicator for HealthKit events
            if event.sourceType == "healthkit" {
                Image(systemName: "heart.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
            }

            Spacer()

            // Time
            Text(event.formattedTime)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LargeDashboardWidget: Widget {
    let kind: String = "LargeDashboard"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DashboardConfigurationIntent.self,
            provider: DashboardProvider()
        ) { entry in
            LargeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dashboard")
        .description("Quick log, recent events, and daily summary")
        .supportedFamilies([.systemLarge])
    }
}

#Preview(as: .systemLarge) {
    LargeDashboardWidget()
} timeline: {
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
