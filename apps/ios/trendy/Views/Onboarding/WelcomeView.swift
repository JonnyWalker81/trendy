//
//  WelcomeView.swift
//  trendy
//
//  Welcome screen for onboarding - value proposition and CTAs
//  Redesigned with hero layout pattern per CONTEXT.md
//

import SwiftUI

struct WelcomeView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// Focus binding for VoiceOver focus management
    @AccessibilityFocusState.Binding var focusedField: OnboardingNavigationView.OnboardingFocusField?

    /// Trigger for haptic feedback on primary button tap
    @State private var stepAdvanced = 0

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top (step 1 of flow, 0% progress)
            OnboardingProgressBar(
                progress: 0.0,
                stepName: "Welcome",
                stepNumber: 1,
                totalSteps: 6
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)

            // Hero area with gradient and SF Symbol
            OnboardingHeroView(
                symbolName: "chart.line.uptrend.xyaxis",
                gradientColors: [Color.dsPrimary, Color.dsAccent]
            )

            Spacer()

            // Content area - minimal text density per CONTEXT.md
            VStack(spacing: 12) {
                Text("Track anything.")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsForeground)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedField, equals: .welcome)

                Text("See patterns.")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsAccent)

                Text("Log events, discover insights, and understand your habits over time.")
                    .font(.body)
                    .foregroundStyle(Color.dsMutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Feature highlights - simplified to 2 rows per CONTEXT.md
            VStack(spacing: 20) {
                FeatureHighlightRow(
                    icon: "hand.tap.fill",
                    title: "Quick Logging",
                    description: "Tap to track any event instantly"
                )

                FeatureHighlightRow(
                    icon: "chart.bar.fill",
                    title: "Smart Insights",
                    description: "Discover patterns in your data"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // Action buttons pinned at bottom
            VStack(spacing: 12) {
                Button {
                    stepAdvanced += 1
                    Task {
                        await viewModel.advanceToNextStep()
                    }
                } label: {
                    Text("Get Started")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.dsPrimary)
                        .foregroundStyle(Color.dsPrimaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: stepAdvanced)
                .accessibilityLabel("Get started")
                .accessibilityHint("Creates your account to begin tracking")

                Button {
                    viewModel.isSignInMode = true
                    viewModel.jumpToStep(.auth)
                } label: {
                    Text("I already have an account")
                        .foregroundStyle(Color.dsLink)
                }
                .accessibilityLabel("Sign in to existing account")
                .accessibilityHint("Opens sign in form")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color.dsBackground)
    }
}

// MARK: - Feature Highlight Row

private struct FeatureHighlightRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.dsPrimary)
                .frame(width: 44, height: 44)
                .background(Color.dsAccent)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.dsForeground)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Color.dsMutedForeground)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @AccessibilityFocusState var focusedField: OnboardingNavigationView.OnboardingFocusField?

    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)

    return WelcomeView(viewModel: viewModel, focusedField: $focusedField)
        .preferredColorScheme(.dark)
}
