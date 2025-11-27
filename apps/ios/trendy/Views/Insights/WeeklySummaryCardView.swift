//
//  WeeklySummaryCardView.swift
//  trendy
//
//  Card view for displaying weekly summary comparison
//

import SwiftUI

struct WeeklySummaryCardView: View {
    let summary: APIWeeklySummary
    let viewModel: InsightsViewModel

    private var eventTypeColor: Color {
        Color(hex: summary.eventTypeColor) ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            // Event type icon
            ZStack {
                Circle()
                    .fill(eventTypeColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: summary.eventTypeIcon)
                    .font(.title3)
                    .foregroundStyle(eventTypeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.eventTypeName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Text("\(summary.thisWeekCount)x this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if summary.lastWeekCount > 0 {
                        Text("(was \(summary.lastWeekCount))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Change indicator
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.directionIcon(for: summary.direction))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(viewModel.directionColor(for: summary.direction))

                    Text(viewModel.formatChange(summary.changePercent))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.directionColor(for: summary.direction))
                }

                Text("vs last week")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Weekly Summary Section View

struct WeeklySummarySectionView: View {
    let summaries: [APIWeeklySummary]
    let viewModel: InsightsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)

                Text("This Week vs Last")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal)

            if summaries.isEmpty {
                Text("No activity this week yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(summaries) { summary in
                        WeeklySummaryCardView(summary: summary, viewModel: viewModel)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Compact Weekly Summary for Dashboard

struct WeeklySummaryCompactView: View {
    let summaries: [APIWeeklySummary]
    let viewModel: InsightsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(summaries.prefix(3)) { summary in
                HStack {
                    // Color dot
                    Circle()
                        .fill(Color(hex: summary.eventTypeColor) ?? .blue)
                        .frame(width: 8, height: 8)

                    Text(summary.eventTypeName)
                        .font(.caption2)
                        .lineLimit(1)

                    Spacer()

                    Text("\(summary.thisWeekCount)x")
                        .font(.caption2)
                        .fontWeight(.medium)

                    Image(systemName: viewModel.directionIcon(for: summary.direction))
                        .font(.system(size: 8))
                        .foregroundStyle(viewModel.directionColor(for: summary.direction))
                }
            }
        }
        .padding(10)
        .frame(width: 140, height: 80)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
