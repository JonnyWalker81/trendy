//
//  AIBriefingView.swift
//  trendy
//
//  Displays AI-generated daily briefing with streaming support
//

import SwiftUI
import FoundationModels

/// Compact banner view for AI daily briefing
struct AIBriefingBannerView: View {
    @Bindable var viewModel: InsightsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isAIAvailable {
                if let briefing = viewModel.dailyBriefing {
                    briefingContent(briefing)
                } else if viewModel.isGeneratingAI {
                    generatingView
                } else {
                    generatePrompt
                }
            } else {
                aiUnavailableView
            }
        }
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: DailyBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Briefing")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)
                Spacer()
                Button {
                    Task {
                        await AIInsightCache.shared.invalidateDailyBriefing()
                        await viewModel.generateDailyBriefing()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Greeting
            Text(briefing.greeting)
                .font(.subheadline)
                .fontWeight(.medium)

            // Highlights
            ForEach(briefing.highlights, id: \.self) { highlight in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(highlight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Suggestion
            if !briefing.suggestion.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(briefing.suggestion)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            // Motivation
            if !briefing.motivation.isEmpty {
                Text(briefing.motivation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Generating View

    private var generatingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Generating your briefing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Generate Prompt

    private var generatePrompt: some View {
        Button {
            Task {
                await viewModel.generateDailyBriefing()
            }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Generate AI Briefing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Unavailable

    private var aiUnavailableView: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Insights Unavailable")
                    .font(.caption)
                    .fontWeight(.medium)
                if let reason = viewModel.aiUnavailabilityReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Weekly Reflection View

/// View for displaying weekly reflection
struct WeeklyReflectionView: View {
    @Bindable var viewModel: InsightsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reflection = viewModel.weeklyReflection {
                reflectionContent(reflection)
            } else if viewModel.isGeneratingAI {
                generatingView
            } else if viewModel.isAIAvailable {
                generatePrompt
            }
        }
    }

    @ViewBuilder
    private func reflectionContent(_ reflection: WeeklyReflection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(.purple)
                Text("Week in Review")
                    .font(.headline)
                Spacer()
                Button {
                    Task {
                        await AIInsightCache.shared.invalidateWeeklyReflection()
                        await viewModel.generateWeeklyReflection()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Summary
            Text(reflection.summary)
                .font(.subheadline)

            // Wins
            if !reflection.wins.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Wins", systemImage: "trophy.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)

                    ForEach(reflection.wins, id: \.self) { win in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption2)
                            Text(win)
                                .font(.caption)
                        }
                    }
                }
            }

            // Areas to Improve
            if !reflection.areasToImprove.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Focus Areas", systemImage: "target")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)

                    ForEach(reflection.areasToImprove, id: \.self) { area in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.blue)
                                .font(.caption2)
                            Text(area)
                                .font(.caption)
                        }
                    }
                }
            }

            // Next Week Goal
            if !reflection.nextWeekGoal.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next Week", systemImage: "flag.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)

                    Text(reflection.nextWeekGoal)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var generatingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Reflecting on your week...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var generatePrompt: some View {
        Button {
            Task {
                await viewModel.generateWeeklyReflection()
            }
        } label: {
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(.purple)
                Text("Generate Weekly Reflection")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Insights Section

/// Section view that combines all AI insights
struct AIInsightsSectionView: View {
    @Bindable var viewModel: InsightsViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Insights")
                    .font(.headline)
                Spacer()

                if !viewModel.isAIAvailable {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isAIAvailable {
                Picker("Insight Type", selection: $selectedTab) {
                    Text("Briefing").tag(0)
                    Text("Weekly").tag(1)
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case 0:
                    AIBriefingBannerView(viewModel: viewModel)
                case 1:
                    WeeklyReflectionView(viewModel: viewModel)
                default:
                    EmptyView()
                }
            } else {
                unavailableMessage
            }
        }
    }

    private var unavailableMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.gray)

            Text("AI Insights Unavailable")
                .font(.subheadline)
                .fontWeight(.medium)

            if let reason = viewModel.aiUnavailabilityReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
