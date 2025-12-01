//
//  InsightDataProvider.swift
//  trendy
//
//  Aggregates data from EventStore and InsightsViewModel into InsightContext
//  for consumption by the Foundation Model
//

import Foundation
import SwiftData

/// Provides aggregated insight context from app data stores
@MainActor
final class InsightDataProvider {
    // MARK: - Dependencies

    private let eventStore: EventStore
    private let insightsViewModel: InsightsViewModel

    // MARK: - Initialization

    init(eventStore: EventStore, insightsViewModel: InsightsViewModel) {
        self.eventStore = eventStore
        self.insightsViewModel = insightsViewModel
    }

    // MARK: - Public Methods

    /// Build complete insight context from current app state
    func buildContext() async -> InsightContext {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let dayOfWeek = calendar.weekdaySymbols[calendar.component(.weekday, from: now) - 1]

        // Get recent events
        let last24Hours = eventsInRange(from: now.addingTimeInterval(-86400), to: now)
        let lastWeek = eventsInRange(from: now.addingTimeInterval(-7 * 86400), to: now)

        // Build event type statistics
        let stats = buildEventTypeStatistics()

        // Build week-over-week changes from InsightsViewModel
        let weeklyChanges = buildWeeklyChanges()

        // Build correlation summaries
        let correlations = buildCorrelationSummaries()

        // Build streak summaries
        let streaks = buildStreakSummaries()

        // Build time patterns
        let timePatterns = buildTimePatterns()

        // Calculate tracking days
        let trackingDays = calculateTrackingDays()

        return InsightContext(
            currentDate: now,
            timeOfDay: .from(hour: hour),
            dayOfWeek: dayOfWeek,
            eventsLast24Hours: last24Hours,
            eventsLastWeek: lastWeek,
            eventTypeStats: stats,
            weekOverWeekChanges: weeklyChanges,
            correlations: correlations,
            streaks: streaks,
            timePatterns: timePatterns,
            totalEventTypes: eventStore.eventTypes.count,
            totalEvents: eventStore.events.count,
            trackingDays: trackingDays
        )
    }

    /// Build context for a specific correlation explanation
    func buildContextForCorrelation(_ insight: APIInsight) async -> (InsightContext, CorrelationSummary)? {
        let context = await buildContext()

        guard let eventTypeA = insight.eventTypeA,
              let eventTypeB = insight.eventTypeB else {
            return nil
        }

        let correlation = CorrelationSummary(
            eventTypeAName: eventTypeA.name,
            eventTypeBName: eventTypeB.name,
            coefficient: insight.metricValue,
            direction: insight.direction.rawValue,
            confidence: insight.confidence.rawValue,
            sampleSize: insight.sampleSize
        )

        return (context, correlation)
    }

    // MARK: - Private Helpers

    private func eventsInRange(from startDate: Date, to endDate: Date) -> [EventSummary] {
        let calendar = Calendar.current

        return eventStore.events
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .compactMap { event -> EventSummary? in
                guard let eventType = event.eventType else { return nil }

                let hour = calendar.component(.hour, from: event.timestamp)
                let weekday = calendar.component(.weekday, from: event.timestamp)
                let dayName = calendar.weekdaySymbols[weekday - 1]

                let timeOfDay: String
                switch hour {
                case 5..<12: timeOfDay = "morning"
                case 12..<17: timeOfDay = "afternoon"
                case 17..<21: timeOfDay = "evening"
                default: timeOfDay = "night"
                }

                return EventSummary(
                    eventTypeName: eventType.name,
                    timestamp: event.timestamp,
                    hasNotes: event.notes != nil && !event.notes!.isEmpty,
                    dayOfWeek: dayName,
                    timeOfDay: timeOfDay
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func buildEventTypeStatistics() -> [EventTypeStatistics] {
        let now = Date()
        let calendar = Calendar.current

        return eventStore.eventTypes.map { eventType in
            let typeEvents = eventStore.events.filter { $0.eventType?.id == eventType.id }
            let last7Days = typeEvents.filter { $0.timestamp >= now.addingTimeInterval(-7 * 86400) }
            let last30Days = typeEvents.filter { $0.timestamp >= now.addingTimeInterval(-30 * 86400) }

            // Calculate trend by comparing last 2 weeks
            let previousWeek = typeEvents.filter {
                $0.timestamp >= now.addingTimeInterval(-14 * 86400) &&
                $0.timestamp < now.addingTimeInterval(-7 * 86400)
            }

            let trend: String
            if last7Days.count > previousWeek.count + 2 {
                trend = "increasing"
            } else if last7Days.count < previousWeek.count - 2 {
                trend = "decreasing"
            } else {
                trend = "stable"
            }

            // Calculate average per week
            let weeks = max(1, typeEvents.isEmpty ? 1 : calendar.dateComponents([.weekOfYear], from: typeEvents.map { $0.timestamp }.min()!, to: now).weekOfYear ?? 1)
            let averagePerWeek = Double(typeEvents.count) / Double(weeks)

            return EventTypeStatistics(
                name: eventType.name,
                totalCount: typeEvents.count,
                last7DaysCount: last7Days.count,
                last30DaysCount: last30Days.count,
                averagePerWeek: averagePerWeek,
                trend: trend
            )
        }
    }

    private func buildWeeklyChanges() -> [WeeklyChange] {
        return insightsViewModel.weeklySummary.map { summary in
            WeeklyChange(
                eventTypeName: summary.eventTypeName,
                thisWeekCount: summary.thisWeekCount,
                lastWeekCount: summary.lastWeekCount,
                changePercent: summary.changePercent,
                direction: summary.direction
            )
        }
    }

    private func buildCorrelationSummaries() -> [CorrelationSummary] {
        return insightsViewModel.correlations.compactMap { insight -> CorrelationSummary? in
            guard let eventTypeA = insight.eventTypeA,
                  let eventTypeB = insight.eventTypeB else {
                return nil
            }

            return CorrelationSummary(
                eventTypeAName: eventTypeA.name,
                eventTypeBName: eventTypeB.name,
                coefficient: insight.metricValue,
                direction: insight.direction.rawValue,
                confidence: insight.confidence.rawValue,
                sampleSize: insight.sampleSize
            )
        }
    }

    private func buildStreakSummaries() -> [StreakSummary] {
        // Group streaks by event type
        var streaksByType: [String: (current: Int, longest: Int, isActive: Bool, name: String)] = [:]

        for insight in insightsViewModel.streaks {
            guard let eventType = insight.eventTypeA else { continue }

            let existing = streaksByType[eventType.id] ?? (current: 0, longest: 0, isActive: false, name: eventType.name)

            // Determine if this is current or longest streak based on insight data
            let isActive = insight.metadata?["is_active"]?.value as? Bool ?? false
            let length = Int(insight.metricValue)

            if isActive {
                streaksByType[eventType.id] = (
                    current: length,
                    longest: max(existing.longest, length),
                    isActive: true,
                    name: eventType.name
                )
            } else {
                streaksByType[eventType.id] = (
                    current: existing.current,
                    longest: max(existing.longest, length),
                    isActive: existing.isActive,
                    name: eventType.name
                )
            }
        }

        return streaksByType.values.map { data in
            StreakSummary(
                eventTypeName: data.name,
                currentStreak: data.current,
                longestStreak: data.longest,
                isActive: data.isActive
            )
        }
    }

    private func buildTimePatterns() -> [TimePattern] {
        return insightsViewModel.patterns.compactMap { insight -> TimePattern? in
            guard let eventType = insight.eventTypeA else { return nil }

            return TimePattern(
                eventTypeName: eventType.name,
                patternType: insight.category.rawValue,
                description: insight.description,
                confidence: insight.confidence.rawValue
            )
        }
    }

    private func calculateTrackingDays() -> Int {
        guard let oldest = eventStore.events.map({ $0.timestamp }).min() else {
            return 0
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: oldest, to: Date()).day ?? 0
        return max(1, days)
    }
}
