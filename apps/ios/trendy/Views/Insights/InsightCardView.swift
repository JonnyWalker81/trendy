//
//  InsightCardView.swift
//  trendy
//
//  A generic card view for displaying insights
//

import SwiftUI
import FoundationModels

struct InsightCardView: View {
    let insight: APIInsight
    let viewModel: InsightsViewModel
    var onExplainTapped: ((APIInsight) -> Void)?

    @State private var showingAIExplanation = false
    @State private var aiExplanation: PatternExplanation?
    @State private var isGeneratingExplanation = false
    @State private var explanationError: String?

    /// Check if AI explanation is available
    private var canExplainWithAI: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon and title
            HStack {
                insightIcon
                    .font(.title3)
                    .foregroundStyle(iconColor)

                Text(insight.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                confidenceBadge
            }

            // Description
            Text(insight.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // AI Explanation section (if available)
            if showingAIExplanation {
                aiExplanationSection
            }

            // Metadata row with AI button
            HStack {
                if let pValue = insight.pValue {
                    Text("p=\(String(format: "%.3f", pValue))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text("\(insight.sampleSize) days")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                // AI Explain button
                if canExplainWithAI && insight.insightType == .correlation {
                    Button {
                        if let onExplainTapped {
                            onExplainTapped(insight)
                        } else {
                            showingAIExplanation.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showingAIExplanation ? "sparkles" : "sparkles")
                            Text(showingAIExplanation ? "Hide" : "Explain")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }

                directionIndicator
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .task(id: showingAIExplanation) {
            guard showingAIExplanation, aiExplanation == nil else { return }

            isGeneratingExplanation = true
            explanationError = nil

            if let explanation = await viewModel.explainInsight(insight) {
                aiExplanation = explanation
            } else if let error = viewModel.aiError {
                explanationError = error.localizedDescription
            } else {
                explanationError = "Unable to generate explanation"
            }

            isGeneratingExplanation = false
        }
    }

    // MARK: - AI Explanation Section

    @ViewBuilder
    private var aiExplanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if isGeneratingExplanation {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating explanation...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if let error = explanationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let explanation = aiExplanation {
                VStack(alignment: .leading, spacing: 6) {
                    // Explanation
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .font(.caption)
                        Text(explanation.explanation)
                            .font(.subheadline)
                    }

                    // Possible reason
                    if !explanation.possibleReason.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(explanation.possibleReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Recommendation
                    if !explanation.recommendation.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(explanation.recommendation)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }

                    // AI confidence
                    HStack {
                        Spacer()
                        Text("AI Confidence: \(explanation.confidence.capitalized)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.2), value: showingAIExplanation)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var insightIcon: some View {
        switch insight.insightType {
        case .correlation:
            Image(systemName: "arrow.left.arrow.right")
        case .pattern:
            Image(systemName: "clock.badge.checkmark")
        case .streak:
            Image(systemName: "flame.fill")
        case .summary:
            Image(systemName: "chart.bar.fill")
        }
    }

    private var iconColor: Color {
        switch insight.insightType {
        case .correlation:
            return viewModel.correlationColor(for: insight.direction)
        case .pattern:
            return .purple
        case .streak:
            return .orange
        case .summary:
            return .blue
        }
    }

    private var confidenceBadge: some View {
        Text(insight.confidence.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(viewModel.confidenceColor(for: insight.confidence).opacity(0.2))
            .foregroundStyle(viewModel.confidenceColor(for: insight.confidence))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var directionIndicator: some View {
        HStack(spacing: 4) {
            switch insight.direction {
            case .positive:
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.green)
            case .negative:
                Image(systemName: "arrow.down.right")
                    .foregroundStyle(.red)
            case .neutral:
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }

            if insight.insightType == .correlation {
                Text(viewModel.formatCorrelation(insight.metricValue))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(viewModel.correlationColor(for: insight.direction))
            }
        }
    }
}

// MARK: - Compact Variant for Banner

struct InsightCompactCardView: View {
    let insight: APIInsight
    let viewModel: InsightsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                insightIcon
                    .font(.caption)
                    .foregroundStyle(iconColor)

                Spacer()

                if insight.insightType == .streak {
                    Text("\(Int(insight.metricValue)) days")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
            }

            Text(insight.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(compactDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(width: 140, height: 80)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var insightIcon: some View {
        switch insight.insightType {
        case .correlation:
            Image(systemName: "arrow.left.arrow.right")
        case .pattern:
            Image(systemName: "clock.badge.checkmark")
        case .streak:
            Image(systemName: "flame.fill")
        case .summary:
            Image(systemName: "chart.bar.fill")
        }
    }

    private var iconColor: Color {
        switch insight.insightType {
        case .streak: return .orange
        case .correlation: return viewModel.correlationColor(for: insight.direction)
        case .pattern: return .purple
        case .summary: return .blue
        }
    }

    private var compactDescription: String {
        if insight.insightType == .streak {
            return "in a row"
        }
        // Truncate description for compact view
        let maxLength = 40
        if insight.description.count > maxLength {
            return String(insight.description.prefix(maxLength)) + "..."
        }
        return insight.description
    }
}
