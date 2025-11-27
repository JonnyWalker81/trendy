//
//  MediumWidget.swift
//  TrendyWidgets
//
//  systemMedium widget for quick logging multiple EventTypes in a dynamic grid.
//

import SwiftUI
import WidgetKit
import AppIntents

struct MediumWidgetView: View {
    let entry: MultiTypeEntry

    // Dynamic grid layout based on number of types
    private var columns: [GridItem] {
        let count = entry.eventTypes.count
        if count <= 3 {
            // Single row: 1-3 items
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: max(count, 1))
        } else {
            // Two rows: 4-6 items (3 per row)
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        }
    }

    var body: some View {
        if entry.eventTypes.isEmpty {
            // No EventTypes configured
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("Configure event types to display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("Quick Log")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Grid of event types
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(entry.eventTypes) { eventType in
                        QuickLogGridButton(eventType: eventType)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct QuickLogGridButton: View {
    let eventType: EventTypeWithCount

    var body: some View {
        Button(intent: QuickLogIntent(eventTypeId: eventType.id)) {
            VStack(spacing: 4) {
                // Bubble with icon
                ZStack {
                    Circle()
                        .fill(eventType.color.gradient)
                        .frame(width: 40, height: 40)

                    Image(systemName: eventType.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                // Name
                Text(eventType.name)
                    .font(.system(size: 10))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                // Count badge
                if eventType.todayCount > 0 {
                    Text("\(eventType.todayCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(eventType.color)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MediumQuickLogWidget: Widget {
    let kind: String = "MediumQuickLog"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MultiEventTypeConfigurationIntent.self,
            provider: MultiTypeProvider()
        ) { entry in
            MediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Log Grid")
        .description("Log multiple event types with one tap")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    MediumQuickLogWidget()
} timeline: {
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
