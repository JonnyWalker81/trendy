//
//  CircularWidget.swift
//  TrendyWidgets
//
//  accessoryCircular widget for Lock Screen quick logging.
//

import SwiftUI
import WidgetKit
import AppIntents

struct CircularWidgetView: View {
    let entry: QuickLogEntry

    var body: some View {
        if let eventType = entry.eventType {
            Button(intent: QuickLogIntent(eventTypeId: eventType.id)) {
                ZStack {
                    // Progress ring (based on today's count)
                    if entry.configuration.showTodayCount ?? true {
                        // Background ring
                        Circle()
                            .stroke(lineWidth: 3)
                            .opacity(0.2)

                        // Progress ring (fills up to 5 events as "full")
                        Circle()
                            .trim(from: 0, to: min(CGFloat(entry.todayCount) / 5.0, 1.0))
                            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }

                    // Center content
                    VStack(spacing: 1) {
                        Image(systemName: eventType.iconName)
                            .font(.system(size: 16, weight: .medium))

                        if entry.todayCount > 0 {
                            Text("\(entry.todayCount)")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                }
                .widgetAccentable()
            }
            .buttonStyle(.plain)
        } else {
            // Not configured
            ZStack {
                Circle()
                    .stroke(lineWidth: 2)
                    .opacity(0.3)

                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
            }
            .widgetAccentable()
        }
    }
}

struct CircularQuickLogWidget: Widget {
    let kind: String = "CircularQuickLog"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SingleEventTypeConfigurationIntent.self,
            provider: QuickLogProvider()
        ) { entry in
            CircularWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Tap to log an event from Lock Screen")
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview(as: .accessoryCircular) {
    CircularQuickLogWidget()
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
