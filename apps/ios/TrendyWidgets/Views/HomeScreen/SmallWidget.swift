//
//  SmallWidget.swift
//  TrendyWidgets
//
//  systemSmall widget for quick logging a single EventType.
//

import SwiftUI
import WidgetKit
import AppIntents

struct SmallWidgetView: View {
    let entry: QuickLogEntry

    var body: some View {
        if let eventType = entry.eventType {
            Button(intent: QuickLogIntent(eventTypeId: eventType.id)) {
                VStack(spacing: 8) {
                    // Event type bubble
                    ZStack {
                        Circle()
                            .fill(eventType.color.gradient)
                            .frame(width: 56, height: 56)

                        Image(systemName: eventType.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    // Event type name
                    Text(eventType.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    // Today's count
                    if (entry.configuration.showTodayCount ?? true) && entry.todayCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(entry.todayCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(eventType.color)
                            Text("today")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if (entry.configuration.showStreak ?? true) && entry.streak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(entry.streak)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        } else {
            // No EventType configured
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("Tap to\nconfigure")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SmallQuickLogWidget: Widget {
    let kind: String = "SmallQuickLog"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SingleEventTypeConfigurationIntent.self,
            provider: QuickLogProvider()
        ) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Tap to quickly log an event")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    SmallQuickLogWidget()
} timeline: {
    QuickLogEntry(
        date: Date(),
        eventType: EventTypeData(id: "preview", name: "Running", colorHex: "#FF5722", iconName: "figure.run"),
        todayCount: 3,
        streak: 7,
        lastEventTime: Date().addingTimeInterval(-3600),
        configuration: SingleEventTypeConfigurationIntent()
    )
}
