//
//  LocationPrimingScreen.swift
//  trendy
//
//  Pre-permission priming screen for location permission
//

import SwiftUI

/// A full-screen priming view that explains the benefits of location permissions
/// before triggering the system permission dialog.
///
/// This screen follows the FLOW-02 pattern: show custom priming content to explain
/// the value of the permission, then let the user choose to enable or skip.
struct LocationPrimingScreen: View {
    /// Current progress through the onboarding flow (0.0 to 1.0)
    let progress: Double

    /// Callback when user taps Enable button (requests actual permission)
    let onEnable: () async -> Void

    /// Callback when user taps Skip
    let onSkip: () -> Void

    /// Whether the enable action is in progress
    @State private var isLoading = false

    /// Whether to show the skip explanation text
    @State private var showSkipExplanation = false

    /// Permission type for this screen
    private let permissionType = OnboardingPermissionType.location

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            OnboardingProgressBar(progress: progress)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            // Hero view with gradient and icon
            OnboardingHeroView(
                symbolName: permissionType.iconName,
                gradientColors: permissionType.gradientColors
            )

            Spacer()

            // Content area
            VStack(spacing: 24) {
                // Title
                Text(permissionType.promptTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsForeground)
                    .multilineTextAlignment(.center)

                // Benefit bullets
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(permissionType.benefitBullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.dsSuccess)
                            Text(bullet)
                                .font(.body)
                                .foregroundStyle(Color.dsMutedForeground)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Action area
            VStack(spacing: 16) {
                // Enable button
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    Task {
                        isLoading = true
                        await onEnable()
                        isLoading = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .tint(Color.dsPrimaryForeground)
                        }
                        Text(permissionType.enableButtonText)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.dsPrimary)
                    .foregroundStyle(Color.dsPrimaryForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoading)

                // Skip link
                Button {
                    showSkipExplanation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onSkip()
                    }
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsMutedForeground)
                }
                .disabled(isLoading || showSkipExplanation)

                // Skip explanation (appears after skip tapped)
                if showSkipExplanation {
                    Text(permissionType.skipExplanation)
                        .font(.caption)
                        .foregroundStyle(Color.dsMutedForeground)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .animation(.easeInOut(duration: 0.3), value: showSkipExplanation)
        }
        .background(Color.dsBackground)
    }
}

// MARK: - Preview

#Preview("Location Priming") {
    LocationPrimingScreen(
        progress: 0.6,
        onEnable: {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        },
        onSkip: {}
    )
}

#Preview("Dark Mode") {
    LocationPrimingScreen(
        progress: 0.6,
        onEnable: {},
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}
