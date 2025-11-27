//
//  InsightDetailSheet.swift
//  trendy
//
//  Detail sheet for viewing insight information
//

import SwiftUI

struct InsightDetailSheet: View {
    let insight: APIInsight
    let viewModel: InsightsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with icon
                    HStack(spacing: 12) {
                        insightTypeIcon
                            .font(.largeTitle)
                            .foregroundStyle(iconColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.insightType.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(insight.title)
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)

                        Text(insight.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Metrics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            metricCard(
                                title: metricLabel,
                                value: metricValue,
                                color: iconColor
                            )

                            if let pValue = insight.pValue {
                                metricCard(
                                    title: "P-Value",
                                    value: String(format: "%.4f", pValue),
                                    color: pValue < 0.05 ? .green : .orange
                                )
                            }

                            metricCard(
                                title: "Confidence",
                                value: insight.confidence.rawValue.capitalized,
                                color: viewModel.confidenceColor(for: insight.confidence)
                            )

                            metricCard(
                                title: "Sample Size",
                                value: "\(insight.sampleSize) days",
                                color: .blue
                            )
                        }
                    }

                    // Direction indicator for correlations
                    if insight.insightType == .correlation {
                        directionSection
                    }

                    // Event types involved
                    if insight.eventTypeA != nil || insight.eventTypeB != nil {
                        eventTypesSection
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Insight Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var insightTypeIcon: some View {
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

    private var metricLabel: String {
        switch insight.insightType {
        case .correlation:
            return "Correlation"
        case .pattern:
            return "Score"
        case .streak:
            return "Days"
        case .summary:
            return "Value"
        }
    }

    private var metricValue: String {
        switch insight.insightType {
        case .correlation:
            return viewModel.formatCorrelation(insight.metricValue)
        case .streak:
            return "\(Int(insight.metricValue))"
        default:
            return String(format: "%.2f", insight.metricValue)
        }
    }

    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Direction")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: directionIcon)
                    .font(.title2)
                    .foregroundStyle(viewModel.correlationColor(for: insight.direction))

                VStack(alignment: .leading, spacing: 2) {
                    Text(directionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(directionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var directionIcon: String {
        switch insight.direction {
        case .positive:
            return "arrow.up.right"
        case .negative:
            return "arrow.down.right"
        case .neutral:
            return "arrow.right"
        }
    }

    private var directionTitle: String {
        switch insight.direction {
        case .positive:
            return "Positive Correlation"
        case .negative:
            return "Negative Correlation"
        case .neutral:
            return "No Correlation"
        }
    }

    private var directionDescription: String {
        switch insight.direction {
        case .positive:
            return "When one increases, the other tends to increase too"
        case .negative:
            return "When one increases, the other tends to decrease"
        case .neutral:
            return "No significant relationship detected"
        }
    }

    @ViewBuilder
    private var eventTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Types")
                .font(.headline)

            VStack(spacing: 8) {
                if let eventTypeA = insight.eventTypeA {
                    eventTypeRow(eventTypeA)
                }

                if let eventTypeB = insight.eventTypeB {
                    eventTypeRow(eventTypeB)
                }
            }
        }
    }

    private func eventTypeRow(_ eventType: APIEventType) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: eventType.color) ?? .blue)
                .frame(width: 12, height: 12)

            Image(systemName: eventType.icon)
                .foregroundStyle(Color(hex: eventType.color) ?? .blue)

            Text(eventType.name)
                .font(.subheadline)

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Helper Extensions

extension APIInsightType {
    var displayName: String {
        switch self {
        case .correlation:
            return "Correlation"
        case .pattern:
            return "Pattern"
        case .streak:
            return "Streak"
        case .summary:
            return "Summary"
        }
    }
}
