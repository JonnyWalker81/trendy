//
//  FoundationModelService.swift
//  trendy
//
//  Service for generating AI-driven insights using Apple's Foundation Models framework
//

import Foundation
import FoundationModels

/// Errors that can occur during AI insight generation
enum AIInsightError: Error, LocalizedError {
    case modelUnavailable(reason: String)
    case insufficientData(minimumRequired: Int, actual: Int)
    case generationFailed(underlying: Error)
    case contextTooLarge
    case sessionCreationFailed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return "AI model is unavailable: \(reason)"
        case .insufficientData(let minimum, let actual):
            return "Need at least \(minimum) days of data (currently have \(actual) days)"
        case .generationFailed(let error):
            return "Failed to generate insight: \(error.localizedDescription)"
        case .contextTooLarge:
            return "Too much data to process at once"
        case .sessionCreationFailed:
            return "Failed to create AI session"
        }
    }
}

/// Service for generating AI-driven insights using Foundation Models
@Observable
@MainActor
final class FoundationModelService {
    // MARK: - Properties

    private var patternSession: LanguageModelSession?
    private var briefingSession: LanguageModelSession?
    private var reflectionSession: LanguageModelSession?

    /// Check if the Foundation Model is available
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Get the reason why the model is unavailable
    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable:
            return describeUnavailabilityReason()
        @unknown default:
            return "Unknown availability status"
        }
    }

    // MARK: - System Instructions

    private let patternInstructions = """
    You are an insightful personal data analyst for Trendy, an event tracking app.
    Your role is to explain statistical patterns in the user's behavioral data.

    Guidelines:
    - Be encouraging and supportive, never judgmental
    - Use specific data points to back up insights
    - Keep responses concise and actionable
    - Acknowledge when data is insufficient for strong conclusions
    - Focus on patterns the user can act on
    - Use the user's event type names exactly as provided
    - Explain correlations in plain English that anyone can understand
    """

    private let briefingInstructions = """
    You are a friendly personal wellness assistant for Trendy, an event tracking app.
    Your role is to provide a brief, encouraging morning summary.

    Guidelines:
    - Be warm and motivating
    - Highlight achievements and progress
    - Keep suggestions practical and achievable
    - Reference specific data but keep it conversational
    - Never be preachy or lecture the user
    - Focus on one actionable thing for today
    """

    private let reflectionInstructions = """
    You are a thoughtful personal coach for Trendy, an event tracking app.
    Your role is to provide meaningful weekly reflections.

    Guidelines:
    - Celebrate wins, no matter how small
    - Be constructive about areas for improvement
    - Connect patterns across the week
    - Suggest realistic goals for next week
    - Be encouraging about the user's tracking consistency
    """

    // MARK: - Initialization

    init() {
        setupSessions()
    }

    private func setupSessions() {
        guard isAvailable else { return }

        patternSession = LanguageModelSession(instructions: patternInstructions)
        briefingSession = LanguageModelSession(instructions: briefingInstructions)
        reflectionSession = LanguageModelSession(instructions: reflectionInstructions)
    }

    // MARK: - Pattern Explanation (Primary Feature)

    /// Generate a natural language explanation for a correlation
    func explainPattern(
        correlation: CorrelationSummary,
        context: InsightContext
    ) async throws -> PatternExplanation {
        guard isAvailable else {
            throw AIInsightError.modelUnavailable(reason: unavailabilityReason ?? "Unknown")
        }

        guard context.hasEnoughData else {
            throw AIInsightError.insufficientData(minimumRequired: 7, actual: context.trackingDays)
        }

        guard let session = patternSession else {
            setupSessions()
            guard let session = patternSession else {
                throw AIInsightError.sessionCreationFailed
            }
            return try await explainPatternWithSession(session, correlation: correlation, context: context)
        }

        return try await explainPatternWithSession(session, correlation: correlation, context: context)
    }

    private func explainPatternWithSession(
        _ session: LanguageModelSession,
        correlation: CorrelationSummary,
        context: InsightContext
    ) async throws -> PatternExplanation {
        let prompt = """
        Explain this behavioral correlation discovered in the user's data:

        \(context.formatForCorrelation(correlation))

        Provide a clear, helpful explanation that helps the user understand and act on this pattern.
        """

        do {
            let response = try await session.respond(to: prompt, generating: PatternExplanation.self)
            return response.content
        } catch {
            Log.api.error("Pattern explanation failed", error: error)
            throw AIInsightError.generationFailed(underlying: error)
        }
    }

    /// Explain a pattern from an APIInsight
    func explainInsight(
        _ insight: APIInsight,
        context: InsightContext
    ) async throws -> PatternExplanation {
        guard let eventTypeA = insight.eventTypeA,
              let eventTypeB = insight.eventTypeB else {
            // For non-correlation insights, create a simpler explanation
            return try await explainGenericInsight(insight, context: context)
        }

        let correlation = CorrelationSummary(
            eventTypeAName: eventTypeA.name,
            eventTypeBName: eventTypeB.name,
            coefficient: insight.metricValue,
            direction: insight.direction.rawValue,
            confidence: insight.confidence.rawValue,
            sampleSize: insight.sampleSize
        )

        return try await explainPattern(correlation: correlation, context: context)
    }

    private func explainGenericInsight(
        _ insight: APIInsight,
        context: InsightContext
    ) async throws -> PatternExplanation {
        guard isAvailable else {
            throw AIInsightError.modelUnavailable(reason: unavailabilityReason ?? "Unknown")
        }

        guard let session = patternSession else {
            throw AIInsightError.sessionCreationFailed
        }

        let prompt = """
        Explain this pattern discovered in the user's data:

        Type: \(insight.insightType.rawValue)
        Title: \(insight.title)
        Description: \(insight.description)
        Metric: \(insight.metricValue)
        Confidence: \(insight.confidence.rawValue)

        Additional context:
        \(context.formatForPrompt())

        Provide a clear, helpful explanation.
        """

        do {
            let response = try await session.respond(to: prompt, generating: PatternExplanation.self)
            return response.content
        } catch {
            Log.api.error("Generic insight explanation failed", error: error)
            throw AIInsightError.generationFailed(underlying: error)
        }
    }

    // MARK: - Daily Briefing

    /// Generate a personalized daily briefing
    func generateDailyBriefing(context: InsightContext) async throws -> DailyBriefing {
        guard isAvailable else {
            throw AIInsightError.modelUnavailable(reason: unavailabilityReason ?? "Unknown")
        }

        guard let session = briefingSession else {
            throw AIInsightError.sessionCreationFailed
        }

        let prompt = """
        Generate a personalized morning briefing based on this user's data:

        \(context.formatForPrompt())

        Create a warm, encouraging summary for their \(context.timeOfDay.rawValue).
        """

        do {
            let response = try await session.respond(to: prompt, generating: DailyBriefing.self)
            return response.content
        } catch {
            Log.api.error("Daily briefing generation failed", error: error)
            throw AIInsightError.generationFailed(underlying: error)
        }
    }

    /// Stream a daily briefing for progressive UI updates
    func streamDailyBriefing(
        context: InsightContext
    ) -> AsyncThrowingStream<LanguageModelSession.ResponseStream<DailyBriefing>.Snapshot, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard self.isAvailable else {
                    continuation.finish(throwing: AIInsightError.modelUnavailable(reason: self.unavailabilityReason ?? "Unknown"))
                    return
                }

                guard let session = self.briefingSession else {
                    continuation.finish(throwing: AIInsightError.sessionCreationFailed)
                    return
                }

                let prompt = """
                Generate a personalized morning briefing based on this user's data:

                \(context.formatForPrompt())

                Create a warm, encouraging summary for their \(context.timeOfDay.rawValue).
                """

                do {
                    let stream = session.streamResponse(to: prompt, generating: DailyBriefing.self)
                    for try await snapshot in stream {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    Log.api.error("Daily briefing streaming failed", error: error)
                    continuation.finish(throwing: AIInsightError.generationFailed(underlying: error))
                }
            }
        }
    }

    // MARK: - Weekly Reflection

    /// Generate an end-of-week reflection
    func generateWeeklyReflection(context: InsightContext) async throws -> WeeklyReflection {
        guard isAvailable else {
            throw AIInsightError.modelUnavailable(reason: unavailabilityReason ?? "Unknown")
        }

        guard let session = reflectionSession else {
            throw AIInsightError.sessionCreationFailed
        }

        let prompt = """
        Generate a thoughtful weekly reflection based on this user's data:

        \(context.formatForPrompt())

        Summarize their week, celebrate wins, and set them up for success next week.
        """

        do {
            let response = try await session.respond(to: prompt, generating: WeeklyReflection.self)
            return response.content
        } catch {
            Log.api.error("Weekly reflection generation failed", error: error)
            throw AIInsightError.generationFailed(underlying: error)
        }
    }

    // MARK: - Event Type Analysis

    /// Generate deep analysis for a specific event type
    func analyzeEventType(
        name: String,
        context: InsightContext
    ) async throws -> EventTypeAnalysis {
        guard isAvailable else {
            throw AIInsightError.modelUnavailable(reason: unavailabilityReason ?? "Unknown")
        }

        guard let session = patternSession else {
            throw AIInsightError.sessionCreationFailed
        }

        // Find stats for this event type
        let stats = context.eventTypeStats.first { $0.name == name }
        let relatedCorrelations = context.correlations.filter {
            $0.eventTypeAName == name || $0.eventTypeBName == name
        }
        let streak = context.streaks.first { $0.eventTypeName == name }

        let prompt = """
        Analyze this user's activity for "\(name)":

        Statistics:
        - Total events: \(stats?.totalCount ?? 0)
        - Last 7 days: \(stats?.last7DaysCount ?? 0)
        - Average per week: \(String(format: "%.1f", stats?.averagePerWeek ?? 0))
        - Trend: \(stats?.trend ?? "unknown")

        \(streak.map { "Current streak: \($0.currentStreak) days (longest: \($0.longestStreak))" } ?? "No streak data")

        Related correlations:
        \(relatedCorrelations.map { "- Correlated with \($0.eventTypeAName == name ? $0.eventTypeBName : $0.eventTypeAName) (r=\(String(format: "%.2f", $0.coefficient)))" }.joined(separator: "\n"))

        Overall context:
        \(context.formatForPrompt())

        Provide helpful analysis and tips.
        """

        do {
            let response = try await session.respond(to: prompt, generating: EventTypeAnalysis.self)
            return response.content
        } catch {
            Log.api.error("Event type analysis failed", error: error)
            throw AIInsightError.generationFailed(underlying: error)
        }
    }

    // MARK: - Quick Insight

    /// Generate a quick contextual insight
    func generateQuickInsight(context: InsightContext) async throws -> QuickInsight {
        guard isAvailable else {
            throw AIInsightError.modelUnavailable(reason: unavailabilityReason ?? "Unknown")
        }

        guard let session = briefingSession else {
            throw AIInsightError.sessionCreationFailed
        }

        let prompt = """
        Based on this user's recent activity, generate a brief, encouraging message:

        \(context.formatForPrompt())

        Keep it under 50 characters and add a relevant emoji.
        """

        do {
            let response = try await session.respond(to: prompt, generating: QuickInsight.self)
            return response.content
        } catch {
            Log.api.error("Quick insight generation failed", error: error)
            throw AIInsightError.generationFailed(underlying: error)
        }
    }

    // MARK: - Helpers

    private func describeUnavailabilityReason() -> String {
        // Get the availability status and describe it
        let availability = SystemLanguageModel.default.availability
        if case .unavailable = availability {
            return "Apple Intelligence is not available on this device"
        }
        return "The AI model is unavailable"
    }
}
