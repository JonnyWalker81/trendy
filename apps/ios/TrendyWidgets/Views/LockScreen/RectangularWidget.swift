//
//  RectangularWidget.swift
//  TrendyWidgets
//
//  accessoryRectangular widget for Lock Screen with streak and stats.
//

import SwiftUI
import WidgetKit
import AppIntents

struct RectangularWidgetView: View {
    let entry: QuickLogEntry

    var body: some View {
        if let eventType = entry.eventType {
            Button(intent: QuickLogIntent(eventTypeId: eventType.id)) {
                HStack(spacing: 10) {
                    // Icon
                    Image(systemName: eventType.iconName)
                        .font(.title2)
                        .widgetAccentable()

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        // Event type name
                        Text(eventType.name)
                            .font(.headline)
                            .lineLimit(1)

                        // Streak (if enabled and > 0)
                        if (entry.configuration.showStreak ?? true) && entry.streak > 0 {
                            Label("\(entry.streak) day streak", systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Today's count or last event time
                        if entry.configuration.showTodayCount ?? true {
                            if entry.todayCount > 0 {
                                Text("\(entry.todayCount) today")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if let lastTime = entry.lastEventTime {
                                Text("Last: \(lastTime, style: .relative)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            // Not configured
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.title2)
                    .widgetAccentable()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure Widget")
                        .font(.headline)
                    Text("Tap to select event type")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }
}

struct RectangularStreakWidget: Widget {
    let kind: String = "RectangularStreak"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SingleEventTypeConfigurationIntent.self,
            provider: QuickLogProvider()
        ) { entry in
            RectangularWidgetView(entry: entry)
                .containerBackground(for: .widget) { }
        }
        .configurationDisplayName("Streak & Stats")
        .description("Show streak, count, and tap to log")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    RectangularStreakWidget()
} timeline: {
    QuickLogEntry(
        date: Date(),
        eventType: EventTypeData(id: "preview", name: "Running", colorHex: "#FF5722", iconName: "figure.run"),
        todayCount: 2,
        streak: 7,
        lastEventTime: Date().addingTimeInterval(-7200),
        configuration: {
            let config = SingleEventTypeConfigurationIntent()
            return config
        }()
    )
}
