//
//  TestWidget.swift
//  TrendyWidgets
//
//  Minimal test widget to verify widget extension is working.
//

import SwiftUI
import WidgetKit

// Simple timeline entry with just a date
struct TestEntry: TimelineEntry {
    let date: Date
}

// Simple provider that returns static data
struct TestProvider: TimelineProvider {
    func placeholder(in context: Context) -> TestEntry {
        TestEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TestEntry) -> Void) {
        completion(TestEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TestEntry>) -> Void) {
        let entry = TestEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

// Simple widget view
struct TestWidgetView: View {
    let entry: TestEntry

    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Trendy")
                .font(.headline)
            Text("Widget Works!")
                .font(.caption)
        }
    }
}

// The widget definition using StaticConfiguration (simplest form)
struct TestWidget: Widget {
    let kind: String = "TestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TestProvider()) { entry in
            TestWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Test Widget")
        .description("A simple test widget")
        .supportedFamilies([.systemSmall])
    }
}
