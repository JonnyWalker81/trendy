//
//  InsightContext.swift
//  trendy
//
//  Context model that aggregates user data for AI insight generation
//

import Foundation

/// Aggregated context for AI insight generation
struct InsightContext: Sendable {
    // MARK: - Time Context

    let currentDate: Date
    let timeOfDay: TimeOfDay
    let dayOfWeek: String

    // MARK: - Recent Activity

    let eventsLast24Hours: [EventSummary]
    let eventsLastWeek: [EventSummary]

    // MARK: - Statistics

    let eventTypeStats: [EventTypeStatistics]
    let weekOverWeekChanges: [WeeklyChange]

    // MARK: - Patterns (from backend insights)

    let correlations: [CorrelationSummary]
    let streaks: [StreakSummary]
    let timePatterns: [TimePattern]

    // MARK: - Metadata

    let totalEventTypes: Int
    let totalEvents: Int
    let trackingDays: Int

    // MARK: - Time of Day

    enum TimeOfDay: String, Sendable {
        case morning
        case afternoon
        case evening
        case night

        var greeting: String {
            switch self {
            case .morning: return "Good morning"
            case .afternoon: return "Good afternoon"
            case .evening: return "Good evening"
            case .night: return "Good night"
            }
        }

        static func from(hour: Int) -> TimeOfDay {
            switch hour {
            case 5..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
    }

    // MARK: - Convenience Computed Properties

    /// Check if we have enough data for meaningful insights
    var hasEnoughData: Bool {
        trackingDays >= 7 && totalEvents >= 10
    }

    /// Get the most active event types
    var topEventTypes: [EventTypeStatistics] {
        eventTypeStats.sorted { $0.last7DaysCount > $1.last7DaysCount }.prefix(5).map { $0 }
    }

    /// Get active streaks
    var activeStreaks: [StreakSummary] {
        streaks.filter { $0.isActive && $0.currentStreak >= 2 }
    }

    /// Get significant week-over-week changes (>20%)
    var significantChanges: [WeeklyChange] {
        weekOverWeekChanges.filter { abs($0.changePercent) >= 20 }
    }

    /// Get high-confidence correlations
    var strongCorrelations: [CorrelationSummary] {
        correlations.filter { $0.confidence == "high" && abs($0.coefficient) >= 0.5 }
    }
}

// MARK: - Prompt Formatting

extension InsightContext {
    /// Format context as a prompt for the Foundation Model
    func formatForPrompt() -> String {
        var lines: [String] = []

        // Time context
        lines.append("Current time: \(timeOfDay.rawValue), \(dayOfWeek)")
        lines.append("Tracking for \(trackingDays) days with \(totalEvents) total events across \(totalEventTypes) event types.")
        lines.append("")

        // Recent activity
        if !eventsLast24Hours.isEmpty {
            let summary = eventsLast24Hours.reduce(into: [String: Int]()) { dict, event in
                dict[event.eventTypeName, default: 0] += 1
            }
            let formatted = summary.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            lines.append("Last 24 hours: \(formatted)")
        } else {
            lines.append("Last 24 hours: No events recorded")
        }
        lines.append("")

        // Event type stats
        if !eventTypeStats.isEmpty {
            lines.append("Event type activity (last 7 days):")
            for stat in topEventTypes.prefix(5) {
                lines.append("- \(stat.name): \(stat.last7DaysCount) events, trend: \(stat.trend)")
            }
            lines.append("")
        }

        // Week-over-week changes
        if !significantChanges.isEmpty {
            lines.append("Notable week-over-week changes:")
            for change in significantChanges.prefix(3) {
                let sign = change.changePercent >= 0 ? "+" : ""
                lines.append("- \(change.eventTypeName): \(sign)\(Int(change.changePercent))%")
            }
            lines.append("")
        }

        // Active streaks
        if !activeStreaks.isEmpty {
            lines.append("Active streaks:")
            for streak in activeStreaks.prefix(3) {
                lines.append("- \(streak.eventTypeName): \(streak.currentStreak) days")
            }
            lines.append("")
        }

        // Correlations
        if !strongCorrelations.isEmpty {
            lines.append("Discovered patterns:")
            for corr in strongCorrelations.prefix(3) {
                let direction = corr.direction == "positive" ? "positively" : "negatively"
                lines.append("- \(corr.eventTypeAName) and \(corr.eventTypeBName) are \(direction) correlated (r=\(String(format: "%.2f", corr.coefficient)))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Format context for a specific correlation explanation
    func formatForCorrelation(_ correlation: CorrelationSummary) -> String {
        var lines: [String] = []

        lines.append("Correlation to explain:")
        lines.append("- Event A: \(correlation.eventTypeAName)")
        lines.append("- Event B: \(correlation.eventTypeBName)")
        lines.append("- Correlation coefficient: \(String(format: "%.2f", correlation.coefficient))")
        lines.append("- Direction: \(correlation.direction)")
        lines.append("- Confidence: \(correlation.confidence)")
        lines.append("- Sample size: \(correlation.sampleSize) events")
        lines.append("")

        // Add context about each event type
        if let statsA = eventTypeStats.first(where: { $0.name == correlation.eventTypeAName }) {
            lines.append("\(correlation.eventTypeAName) stats: \(statsA.last7DaysCount) events last week, avg \(String(format: "%.1f", statsA.averagePerWeek))/week, trend: \(statsA.trend)")
        }

        if let statsB = eventTypeStats.first(where: { $0.name == correlation.eventTypeBName }) {
            lines.append("\(correlation.eventTypeBName) stats: \(statsB.last7DaysCount) events last week, avg \(String(format: "%.1f", statsB.averagePerWeek))/week, trend: \(statsB.trend)")
        }

        return lines.joined(separator: "\n")
    }
}
