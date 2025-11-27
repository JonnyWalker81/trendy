//
//  InsightCardView.swift
//  trendy
//
//  A generic card view for displaying insights
//

import SwiftUI

struct InsightCardView: View {
    let insight: APIInsight
    let viewModel: InsightsViewModel

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

            // Metadata row
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

                directionIndicator
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
