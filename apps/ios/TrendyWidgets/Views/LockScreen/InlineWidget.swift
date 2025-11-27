//
//  InlineWidget.swift
//  TrendyWidgets
//
//  accessoryInline widget for Lock Screen (above time).
//

import SwiftUI
import WidgetKit

struct InlineWidgetView: View {
    let entry: QuickLogEntry

    var body: some View {
        if let eventType = entry.eventType {
            // Note: accessoryInline does not support interactive buttons
            ViewThatFits {
                // Full version
                Label {
                    if entry.todayCount > 0 {
                        Text("\(eventType.name): \(entry.todayCount) today")
                            .privacySensitive()
                    } else if entry.streak > 0 {
                        Text("\(eventType.name): \(entry.streak) day streak")
                            .privacySensitive()
                    } else {
                        Text(eventType.name)
                            .privacySensitive()
                    }
                } icon: {
                    Image(systemName: eventType.iconName)
                }

                // Shorter version
                Label {
                    if entry.todayCount > 0 {
                        Text("\(entry.todayCount) today")
                            .privacySensitive()
                    } else {
                        Text(eventType.name)
                            .privacySensitive()
                    }
                } icon: {
                    Image(systemName: eventType.iconName)
                }

                // Minimal version
                Label("\(entry.todayCount)", systemImage: eventType.iconName)
                    .privacySensitive()
            }
        } else {
            Label("Tap to configure", systemImage: "plus.circle")
        }
    }
}

struct InlineStatWidget: Widget {
    let kind: String = "InlineStat"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SingleEventTypeConfigurationIntent.self,
            provider: QuickLogProvider()
        ) { entry in
            InlineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Stat")
        .description("Show event count above the time")
        .supportedFamilies([.accessoryInline])
    }
}

#Preview(as: .accessoryInline) {
    InlineStatWidget()
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
