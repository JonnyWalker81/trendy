//
//  AIInsightModels.swift
//  trendy
//
//  @Generable types for Apple Foundation Models structured output
//

import Foundation
import FoundationModels

// MARK: - Pattern Explanation (Primary Focus)

/// Natural language explanation of a statistical correlation
@Generable
struct PatternExplanation: Codable {
    @Guide(description: "Plain English explanation of the pattern in 1-2 sentences")
    var explanation: String

    @Guide(description: "Brief hypothesis for why this pattern might exist")
    var possibleReason: String

    @Guide(description: "One actionable recommendation based on this pattern")
    var recommendation: String

    @Guide(description: "Confidence level based on statistical strength: high, medium, or low")
    var confidence: String
}

// MARK: - Daily Briefing

/// Morning summary of user's recent activity
@Generable
struct DailyBriefing: Codable {
    @Guide(description: "One-sentence personalized greeting based on time of day and recent activity")
    var greeting: String

    @Guide(description: "Key highlights from recent activity", .count(1...3))
    var highlights: [String]

    @Guide(description: "One actionable suggestion for today based on patterns")
    var suggestion: String

    @Guide(description: "Brief motivational note based on recent progress or streaks")
    var motivation: String
}

// MARK: - Weekly Reflection

/// End-of-week analysis with trends and recommendations
@Generable
struct WeeklyReflection: Codable {
    @Guide(description: "Overall summary of the week in 2-3 sentences")
    var summary: String

    @Guide(description: "Top achievements or positive trends from this week", .count(1...3))
    var wins: [String]

    @Guide(description: "Areas that could use more attention", .count(0...2))
    var areasToImprove: [String]

    @Guide(description: "Suggested goal or focus for next week")
    var nextWeekGoal: String
}

// MARK: - Event Type Analysis

/// Deep dive analysis for a specific event type
@Generable
struct EventTypeAnalysis: Codable {
    @Guide(description: "Current trend: increasing, decreasing, or stable")
    var trend: String

    @Guide(description: "Natural language description of the frequency patterns")
    var frequencyInsight: String

    @Guide(description: "Best time of day or day of week for this activity, if a pattern exists")
    var optimalTiming: String?

    @Guide(description: "Names of other event types that correlate with this one")
    var relatedEvents: [String]?

    @Guide(description: "Personalized tip based on the user's history with this event type")
    var personalizedTip: String
}

// MARK: - Anomaly Alert

/// Alert for unusual patterns or missed habits
@Generable
struct AnomalyAlert: Codable {
    @Guide(description: "Type of anomaly: missed_habit, unusual_spike, or pattern_break")
    var anomalyType: String

    @Guide(description: "Clear, friendly description of what's unusual")
    var description: String

    @Guide(description: "How significant this is: minor, notable, or significant")
    var significance: String

    @Guide(description: "Suggested action to address this, if appropriate")
    var suggestedAction: String?
}

// MARK: - Quick Insight

/// Brief insight for contextual suggestions
@Generable
struct QuickInsight: Codable {
    @Guide(description: "Short, encouraging message about recent activity (max 50 chars)")
    var message: String

    @Guide(description: "Emoji that represents this insight")
    var emoji: String
}

// MARK: - Correlation Summary

/// Simplified summary of correlation for the model
struct CorrelationSummary: Sendable {
    let eventTypeAName: String
    let eventTypeBName: String
    let coefficient: Double
    let direction: String  // positive, negative, neutral
    let confidence: String  // high, medium, low
    let sampleSize: Int
}

// MARK: - Streak Summary

/// Simplified summary of streak for the model
struct StreakSummary: Sendable {
    let eventTypeName: String
    let currentStreak: Int
    let longestStreak: Int
    let isActive: Bool
}

// MARK: - Weekly Change

/// Week-over-week change summary
struct WeeklyChange: Sendable {
    let eventTypeName: String
    let thisWeekCount: Int
    let lastWeekCount: Int
    let changePercent: Double
    let direction: String  // up, down, same
}

// MARK: - Event Summary

/// Simplified event summary for context
struct EventSummary: Sendable {
    let eventTypeName: String
    let timestamp: Date
    let hasNotes: Bool
    let dayOfWeek: String
    let timeOfDay: String  // morning, afternoon, evening, night
}

// MARK: - Event Type Statistics

/// Statistics for a single event type
struct EventTypeStatistics: Sendable {
    let name: String
    let totalCount: Int
    let last7DaysCount: Int
    let last30DaysCount: Int
    let averagePerWeek: Double
    let trend: String  // increasing, decreasing, stable
}

// MARK: - Time Pattern

/// Time-based pattern summary
struct TimePattern: Sendable {
    let eventTypeName: String
    let patternType: String  // time_of_day, day_of_week
    let description: String
    let confidence: String
}
