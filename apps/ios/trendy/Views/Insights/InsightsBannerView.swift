//
//  InsightsBannerView.swift
//  trendy
//
//  Horizontal scrollable banner showing key insights for the dashboard
//

import SwiftUI

struct InsightsBannerView: View {
    let viewModel: InsightsViewModel
    var onTapInsight: ((APIInsight) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)

                Text("Insights")
                    .font(.headline)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal)

            if viewModel.hasInsights {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Active streaks
                        ForEach(viewModel.streaks.filter { $0.metricValue >= 2 }.prefix(2)) { streak in
                            InsightCompactCardView(insight: streak, viewModel: viewModel)
                                .onTapGesture {
                                    onTapInsight?(streak)
                                }
                        }

                        // Top correlation
                        if let topCorrelation = viewModel.correlations.first {
                            InsightCompactCardView(insight: topCorrelation, viewModel: viewModel)
                                .onTapGesture {
                                    onTapInsight?(topCorrelation)
                                }
                        }

                        // Weekly summary compact
                        if !viewModel.weeklySummary.isEmpty {
                            WeeklySummaryCompactView(
                                summaries: viewModel.weeklySummary,
                                viewModel: viewModel
                            )
                        }

                        // Top pattern
                        if let topPattern = viewModel.patterns.first {
                            InsightCompactCardView(insight: topPattern, viewModel: viewModel)
                                .onTapGesture {
                                    onTapInsight?(topPattern)
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            } else if !viewModel.dataSufficient {
                // Insufficient data message
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.secondary)

                    Text(viewModel.insufficientDataMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Insights Section for Analytics View

struct InsightsSectionView: View {
    let viewModel: InsightsViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header with tabs
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)

                Text("Insights")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task {
                            await viewModel.refreshInsights()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.hasInsights {
                // Tab picker
                Picker("Insight Type", selection: $selectedTab) {
                    Text("Discoveries").tag(0)
                    Text("Streaks").tag(1)
                    Text("This Week").tag(2)
                    Text("Patterns").tag(3)
                }
                .pickerStyle(.segmented)

                // Tab content
                switch selectedTab {
                case 0:
                    correlationsSection
                case 1:
                    streaksSection
                case 2:
                    weeklySummarySection
                case 3:
                    patternsSection
                default:
                    EmptyView()
                }
            } else {
                insufficientDataView
            }
        }
        .padding()
    }

    // MARK: - Tab Content Views

    @ViewBuilder
    private var correlationsSection: some View {
        if viewModel.correlations.isEmpty {
            emptyStateView(
                icon: "arrow.left.arrow.right",
                message: "No correlations found yet"
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.correlations) { correlation in
                    InsightCardView(insight: correlation, viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private var streaksSection: some View {
        if viewModel.streaks.isEmpty {
            emptyStateView(
                icon: "flame",
                message: "Start a streak by logging daily!"
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.streaks) { streak in
                    StreakCardView(streak: streak)
                }
            }
        }
    }

    @ViewBuilder
    private var weeklySummarySection: some View {
        WeeklySummarySectionView(
            summaries: viewModel.weeklySummary,
            viewModel: viewModel
        )
    }

    @ViewBuilder
    private var patternsSection: some View {
        if viewModel.patterns.isEmpty {
            emptyStateView(
                icon: "clock.badge.checkmark",
                message: "Keep tracking to discover patterns"
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.patterns) { pattern in
                    InsightCardView(insight: pattern, viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var insufficientDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Building Your Insights")
                .font(.headline)

            Text(viewModel.insufficientDataMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("We need at least 2 weeks of data to find meaningful patterns and correlations.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
