//
//  WelcomeView.swift
//  trendy
//
//  Welcome screen for onboarding - value proposition and CTAs
//

import SwiftUI

struct WelcomeView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App Icon / Logo
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 80))
                .foregroundStyle(Color.dsPrimary)
                .padding(.bottom, 8)

            // Title and Subtitle
            VStack(spacing: 12) {
                Text("Track anything.")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("See patterns.")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsPrimary)

                Text("Log events, discover insights, and understand your habits over time.")
                    .font(.body)
                    .foregroundStyle(Color.dsMutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            Spacer()

            // Feature highlights
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

                FeatureHighlightRow(
                    icon: "bell.fill",
                    title: "Reminders",
                    description: "Never miss what matters to you"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // CTA Buttons
            VStack(spacing: 12) {
                Button {
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

                Button {
                    viewModel.isSignInMode = true
                    viewModel.jumpToStep(.auth)
                } label: {
                    Text("I already have an account")
                        .foregroundStyle(Color.dsLink)
                }
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
    }
}

#Preview {
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let viewModel = OnboardingViewModel(supabaseService: previewSupabase)

    return WelcomeView(viewModel: viewModel)
        .preferredColorScheme(.dark)
}
