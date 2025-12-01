//
//  InsightsViewModel.swift
//  trendy
//
//  ViewModel for managing insights, correlations, streaks, and weekly summaries
//

import Foundation
import SwiftUI
import FoundationModels

@Observable
@MainActor
class InsightsViewModel {
    // MARK: - Published Properties

    private(set) var insights: APIInsightsResponse?
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var lastRefreshed: Date?

    // MARK: - AI Insight Properties

    private(set) var dailyBriefing: DailyBriefing?
    private(set) var weeklyReflection: WeeklyReflection?
    private(set) var aiExplanations: [String: PatternExplanation] = [:]
    private(set) var isGeneratingAI = false
    private(set) var aiError: AIInsightError?

    /// Check if Foundation Model is available
    var isAIAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Reason why AI is unavailable
    var aiUnavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable:
            return "Apple Intelligence is not available on this device"
        @unknown default:
            return "Unknown availability status"
        }
    }

    // MARK: - AI Dependencies

    private var foundationModelService: FoundationModelService?
    private var insightDataProvider: InsightDataProvider?

    // Computed convenience properties
    var correlations: [APIInsight] { insights?.correlations ?? [] }
    var patterns: [APIInsight] { insights?.patterns ?? [] }
    var streaks: [APIInsight] { insights?.streaks ?? [] }
    var weeklySummary: [APIWeeklySummary] { insights?.weeklySummary ?? [] }
    var dataSufficient: Bool { insights?.dataSufficient ?? false }

    /// Top insights to show in dashboard banner (max 3)
    var topInsights: [APIInsight] {
        var top: [APIInsight] = []

        // Add active streaks first (most engaging)
        let activeStreaks = streaks.filter { $0.metricValue >= 2 }.prefix(2)
        top.append(contentsOf: activeStreaks)

        // Add top correlation
        if let topCorrelation = correlations.first, top.count < 3 {
            top.append(topCorrelation)
        }

        return Array(top.prefix(3))
    }

    /// Check if we have any insights to show
    var hasInsights: Bool {
        !correlations.isEmpty || !patterns.isEmpty || !streaks.isEmpty || !weeklySummary.isEmpty
    }

    // MARK: - Dependencies

    private var apiClient: APIClient?

    // MARK: - Public Methods

    /// Configure the view model with an API client
    func configure(with apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Fetch all insights from the backend
    func fetchInsights() async {
        guard let apiClient = apiClient else {
            Log.api.warning("InsightsViewModel: API client not configured")
            return
        }

        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            Log.api.info("Fetching insights from backend")
            let response = try await apiClient.getInsights()
            insights = response
            lastRefreshed = Date()
            Log.api.info("Insights fetched successfully", context: .with { ctx in
                ctx.add("correlations", response.correlations.count)
                ctx.add("patterns", response.patterns.count)
                ctx.add("streaks", response.streaks.count)
                ctx.add("weeklySummary", response.weeklySummary.count)
            })
        } catch {
            self.error = error
            Log.api.error("Failed to fetch insights", error: error)
        }

        isLoading = false
    }

    /// Force refresh insights (recompute on backend)
    func refreshInsights() async {
        guard let apiClient = apiClient else { return }

        isLoading = true
        error = nil

        do {
            Log.api.info("Force refreshing insights")
            try await apiClient.refreshInsights()
            // After refresh, fetch the new insights
            let response = try await apiClient.getInsights()
            insights = response
            lastRefreshed = Date()
            Log.api.info("Insights refreshed successfully")
        } catch {
            self.error = error
            Log.api.error("Failed to refresh insights", error: error)
        }

        isLoading = false
    }

    /// Fetch weekly summary only
    func fetchWeeklySummary() async {
        guard let apiClient = apiClient else { return }

        do {
            let response = try await apiClient.getWeeklySummary()
            // Update only weekly summary portion
            if var currentInsights = insights {
                // Create a new response with updated weekly summary
                insights = APIInsightsResponse(
                    correlations: currentInsights.correlations,
                    patterns: currentInsights.patterns,
                    streaks: currentInsights.streaks,
                    weeklySummary: response.weeklySummary,
                    computedAt: currentInsights.computedAt,
                    dataSufficient: currentInsights.dataSufficient,
                    minDaysNeeded: currentInsights.minDaysNeeded,
                    totalDays: currentInsights.totalDays
                )
            }
        } catch {
            Log.api.error("Failed to fetch weekly summary", error: error)
        }
    }

    // MARK: - Helper Methods

    /// Get color for a weekly summary direction
    func directionColor(for direction: String) -> Color {
        switch direction {
        case "up":
            return .green
        case "down":
            return .red
        default:
            return .secondary
        }
    }

    /// Get icon for a weekly summary direction
    func directionIcon(for direction: String) -> String {
        switch direction {
        case "up":
            return "arrow.up"
        case "down":
            return "arrow.down"
        default:
            return "minus"
        }
    }

    /// Get color for confidence level
    func confidenceColor(for confidence: APIConfidence) -> Color {
        switch confidence {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .gray
        }
    }

    /// Get color for correlation direction
    func correlationColor(for direction: APIDirection) -> Color {
        switch direction {
        case .positive:
            return .green
        case .negative:
            return .red
        case .neutral:
            return .secondary
        }
    }

    /// Format correlation coefficient for display
    func formatCorrelation(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))"
    }

    /// Format percentage change for display
    func formatChange(_ percent: Double) -> String {
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", percent))%"
    }

    /// Check if insights need refresh (older than 6 hours)
    var needsRefresh: Bool {
        guard let lastRefreshed = lastRefreshed else { return true }
        return Date().timeIntervalSince(lastRefreshed) > 6 * 60 * 60
    }

    /// Get insufficient data message
    var insufficientDataMessage: String {
        if let minDays = insights?.minDaysNeeded, minDays > 0 {
            return "Keep tracking for \(minDays) more days to see insights"
        }
        return "Keep tracking for 2 more weeks to see insights"
    }

    // MARK: - AI Configuration

    /// Configure AI services
    func configureAI(
        foundationModelService: FoundationModelService,
        eventStore: EventStore
    ) {
        self.foundationModelService = foundationModelService
        self.insightDataProvider = InsightDataProvider(eventStore: eventStore, insightsViewModel: self)
    }

    // MARK: - AI Insight Generation

    /// Generate a daily briefing
    func generateDailyBriefing() async {
        guard isAIAvailable else {
            aiError = .modelUnavailable(reason: aiUnavailabilityReason ?? "Unknown")
            return
        }

        guard let service = foundationModelService,
              let provider = insightDataProvider else {
            Log.api.warning("AI services not configured")
            return
        }

        // Check cache first
        if let cached = await AIInsightCache.shared.getDailyBriefing() {
            dailyBriefing = cached
            return
        }

        isGeneratingAI = true
        aiError = nil

        do {
            let context = await provider.buildContext()
            let briefing = try await service.generateDailyBriefing(context: context)
            dailyBriefing = briefing
            await AIInsightCache.shared.setDailyBriefing(briefing)
            Log.api.info("Daily briefing generated successfully")
        } catch let error as AIInsightError {
            aiError = error
            Log.api.error("Daily briefing generation failed", error: error)
        } catch {
            aiError = .generationFailed(underlying: error)
            Log.api.error("Daily briefing generation failed", error: error)
        }

        isGeneratingAI = false
    }

    /// Generate a weekly reflection
    func generateWeeklyReflection() async {
        guard isAIAvailable else {
            aiError = .modelUnavailable(reason: aiUnavailabilityReason ?? "Unknown")
            return
        }

        guard let service = foundationModelService,
              let provider = insightDataProvider else {
            Log.api.warning("AI services not configured")
            return
        }

        // Check cache first
        if let cached = await AIInsightCache.shared.getWeeklyReflection() {
            weeklyReflection = cached
            return
        }

        isGeneratingAI = true
        aiError = nil

        do {
            let context = await provider.buildContext()
            let reflection = try await service.generateWeeklyReflection(context: context)
            weeklyReflection = reflection
            await AIInsightCache.shared.setWeeklyReflection(reflection)
            Log.api.info("Weekly reflection generated successfully")
        } catch let error as AIInsightError {
            aiError = error
            Log.api.error("Weekly reflection generation failed", error: error)
        } catch {
            aiError = .generationFailed(underlying: error)
            Log.api.error("Weekly reflection generation failed", error: error)
        }

        isGeneratingAI = false
    }

    /// Generate AI explanation for an insight
    func explainInsight(_ insight: APIInsight) async -> PatternExplanation? {
        guard isAIAvailable else {
            aiError = .modelUnavailable(reason: aiUnavailabilityReason ?? "Unknown")
            return nil
        }

        guard let service = foundationModelService,
              let provider = insightDataProvider else {
            Log.api.warning("AI services not configured")
            return nil
        }

        // Check cache first
        if let cached = await AIInsightCache.shared.getPatternExplanation(for: insight.id) {
            aiExplanations[insight.id] = cached
            return cached
        }

        isGeneratingAI = true
        aiError = nil

        do {
            let context = await provider.buildContext()
            let explanation = try await service.explainInsight(insight, context: context)
            aiExplanations[insight.id] = explanation
            await AIInsightCache.shared.setPatternExplanation(explanation, for: insight.id)
            Log.api.info("Pattern explanation generated", context: .with { ctx in
                ctx.add("insight_id", insight.id)
            })
            isGeneratingAI = false
            return explanation
        } catch let error as AIInsightError {
            aiError = error
            Log.api.error("Pattern explanation failed", error: error)
        } catch {
            aiError = .generationFailed(underlying: error)
            Log.api.error("Pattern explanation failed", error: error)
        }

        isGeneratingAI = false
        return nil
    }

    /// Get cached explanation for an insight
    func getCachedExplanation(for insight: APIInsight) async -> PatternExplanation? {
        if let cached = aiExplanations[insight.id] {
            return cached
        }
        return await AIInsightCache.shared.getPatternExplanation(for: insight.id)
    }

    /// Check if an insight has a cached explanation
    func hasExplanation(for insight: APIInsight) -> Bool {
        aiExplanations[insight.id] != nil
    }

    /// Clear AI cache
    func clearAICache() async {
        await AIInsightCache.shared.clearAll()
        dailyBriefing = nil
        weeklyReflection = nil
        aiExplanations.removeAll()
    }
}
