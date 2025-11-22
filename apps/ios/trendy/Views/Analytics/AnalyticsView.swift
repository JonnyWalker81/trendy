//
//  AnalyticsView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(EventStore.self) private var eventStore
    @State private var analyticsViewModel = AnalyticsViewModel()
    @State private var selectedEventTypeID: UUID?
    @State private var timeRange: TimeRange = .month
    @State private var statistics: Statistics?
    
    @AppStorage("analyticsSelectedEventTypeId") private var savedEventTypeId: String = ""
    @AppStorage("analyticsTimeRange") private var savedTimeRangeRaw: String = TimeRange.month.rawValue
    
    private var selectedEventType: EventType? {
        guard let id = selectedEventTypeID else { return nil }
        return eventStore.eventTypes.first { $0.id == id }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if eventStore.eventTypes.isEmpty {
                        emptyStateView
                    } else {
                        eventTypePicker
                        
                        if selectedEventType != nil {
                            timeRangePicker
                            
                            if analyticsViewModel.isCalculating {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 50)
                            } else {
                                statisticsCard
                                
                                frequencyChart
                            }
                        } else {
                            Text("Select an event type to view analytics")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 50)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .task {
                await eventStore.fetchData()
                
                // Restore saved state
                if !savedEventTypeId.isEmpty,
                   let savedType = eventStore.eventTypes.first(where: { $0.id.uuidString == savedEventTypeId }) {
                    selectedEventTypeID = savedType.id
                } else if let firstType = eventStore.eventTypes.first {
                    selectedEventTypeID = firstType.id
                }
                
                // Restore time range
                if let savedRange = TimeRange(rawValue: savedTimeRangeRaw) {
                    timeRange = savedRange
                }
            }
            .task(id: selectedEventTypeID) {
                await loadAnalytics()
            }
            .task(id: timeRange) {
                await loadAnalytics()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Data Available")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Start tracking events to see analytics")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
    
    private var eventTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(eventStore.eventTypes) { eventType in
                    Button {
                        selectedEventTypeID = eventType.id
                        savedEventTypeId = eventType.id.uuidString
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: eventType.iconName)
                            Text(eventType.name)
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedEventTypeID == eventType.id ? eventType.color : Color.chipBackground)
                        .foregroundColor(selectedEventTypeID == eventType.id ? .white : .primary)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    private var timeRangePicker: some View {
        Picker("Time Range", selection: Binding(
            get: { timeRange },
            set: { newValue in
                timeRange = newValue
                savedTimeRangeRaw = newValue.rawValue
            }
        )) {
            Text("Week").tag(TimeRange.week)
            Text("Month").tag(TimeRange.month)
            Text("Year").tag(TimeRange.year)
        }
        .pickerStyle(.segmented)
    }
    
    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
            
            if let statistics = statistics {
                HStack(spacing: 20) {
                    StatisticItem(
                        title: "Total",
                        value: "\(statistics.totalCount)",
                        icon: "number"
                    )
                    
                    StatisticItem(
                        title: averageTitle(for: timeRange),
                        value: String(format: "%.1f", averageValue(for: statistics, timeRange: timeRange)),
                        icon: averageIcon(for: timeRange)
                    )
                    
                    StatisticItem(
                        title: "Trend",
                        value: trendText(statistics.trend),
                        icon: trendIcon(statistics.trend)
                    )
                }
                
                if let lastOccurrence = statistics.lastOccurrence {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text("Last occurrence: \(lastOccurrence, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private var frequencyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequency Over Time")
                .font(.headline)
            
            let data = timeRange == .week ? analyticsViewModel.dailyData :
                      timeRange == .month ? analyticsViewModel.weeklyData :
                      analyticsViewModel.monthlyData
            
            if data.isEmpty {
                Text("No data available for this time range")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
            } else {
                Chart(data) { dataPoint in
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Count", dataPoint.count)
                    )
                    .foregroundStyle(selectedEventType?.color ?? .blue)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Count", dataPoint.count)
                    )
                    .foregroundStyle((selectedEventType?.color ?? .blue).opacity(0.2))
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Count", dataPoint.count)
                    )
                    .foregroundStyle(selectedEventType?.color ?? .blue)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel(format: dateFormat(for: timeRange))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private func loadAnalytics() async {
        guard let eventType = selectedEventType else { return }
        
        _ = await analyticsViewModel.calculateFrequency(
            for: eventType,
            events: eventStore.events,
            timeRange: timeRange
        )
        
        statistics = await analyticsViewModel.generateStatistics(
            for: eventType,
            events: eventStore.events,
            timeRange: timeRange
        )
    }
    
    private func trendText(_ trend: Statistics.Trend) -> String {
        switch trend {
        case .increasing: return "Up"
        case .decreasing: return "Down"
        case .stable: return "Stable"
        }
    }
    
    private func trendIcon(_ trend: Statistics.Trend) -> String {
        switch trend {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    
    private func dateFormat(for range: TimeRange) -> Date.FormatStyle {
        switch range {
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .year: return .dateTime.month(.abbreviated)
        }
    }
    
    private func averageTitle(for timeRange: TimeRange) -> String {
        switch timeRange {
        case .week: return "Avg/Day"
        case .month: return "Avg/Week"
        case .year: return "Avg/Month"
        }
    }
    
    private func averageValue(for statistics: Statistics, timeRange: TimeRange) -> Double {
        switch timeRange {
        case .week: return statistics.averagePerDay
        case .month: return statistics.averagePerWeek
        case .year: return statistics.averagePerMonth
        }
    }
    
    private func averageIcon(for timeRange: TimeRange) -> String {
        switch timeRange {
        case .week: return "calendar.day.timeline.left"
        case .month: return "calendar"
        case .year: return "calendar.badge.clock"
        }
    }
}

struct StatisticItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}