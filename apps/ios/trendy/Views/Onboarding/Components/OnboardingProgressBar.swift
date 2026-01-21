//
//  OnboardingProgressBar.swift
//  trendy
//
//  Animated progress bar for onboarding flow
//

import SwiftUI

/// A progress bar component for the onboarding flow that displays
/// completion status with smooth spring animations.
///
/// The progress bar shows a filled portion representing completed progress
/// against an unfilled track. Progress changes animate with a spring curve
/// for a responsive, iOS-native feel.
///
/// - Note: This component is display-only and not interactive.
/// - Accessibility: Announces step name and position to VoiceOver.
///   Respects Reduce Motion preference for animations.
struct OnboardingProgressBar: View {
    /// The current progress value (0.0 to 1.0)
    let progress: Double

    /// The name of the current step (e.g., "Welcome", "Account")
    let stepName: String

    /// The current step number (1-based)
    let stepNumber: Int

    /// The total number of steps in the flow
    let totalSteps: Int

    /// Respects user's Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track (unfilled portion)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.dsBorder)

                // Fill (progress portion)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.dsPrimary)
                    .frame(width: max(0, geometry.size.width * CGFloat(clampedProgress)))
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                        value: progress
                    )
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(stepName), step \(stepNumber) of \(totalSteps)")
    }

    /// Clamps progress value between 0.0 and 1.0
    private var clampedProgress: Double {
        min(max(progress, 0.0), 1.0)
    }
}

// MARK: - Preview

#Preview("Progress States") {
    VStack(spacing: 40) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 1: Welcome (0%)")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(
                progress: 0.0,
                stepName: "Welcome",
                stepNumber: 1,
                totalSteps: 6
            )
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Step 2: Account (17%)")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(
                progress: 0.167,
                stepName: "Account",
                stepNumber: 2,
                totalSteps: 6
            )
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Step 3: Event Type (33%)")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(
                progress: 0.333,
                stepName: "Event Type",
                stepNumber: 3,
                totalSteps: 6
            )
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Step 5: Permissions (67%)")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(
                progress: 0.667,
                stepName: "Permissions",
                stepNumber: 5,
                totalSteps: 6
            )
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Step 6: Complete (100%)")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(
                progress: 1.0,
                stepName: "Complete",
                stepNumber: 6,
                totalSteps: 6
            )
        }
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dsBackground)
}

#Preview("Animated Progress") {
    struct AnimatedPreview: View {
        @State private var progress: Double = 0.0
        @State private var stepIndex: Int = 0

        private let steps = [
            (name: "Welcome", number: 1),
            (name: "Account", number: 2),
            (name: "Event Type", number: 3),
            (name: "First Event", number: 4),
            (name: "Permissions", number: 5),
            (name: "Complete", number: 6)
        ]

        var body: some View {
            VStack(spacing: 40) {
                Text("Tap to advance progress")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsMutedForeground)

                OnboardingProgressBar(
                    progress: progress,
                    stepName: steps[stepIndex].name,
                    stepNumber: steps[stepIndex].number,
                    totalSteps: 6
                )
                .padding(.horizontal, 24)

                Text("\(steps[stepIndex].name) - \(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.dsForeground)

                Button("Advance") {
                    if stepIndex >= steps.count - 1 {
                        stepIndex = 0
                        progress = 0.0
                    } else {
                        stepIndex += 1
                        progress = Double(stepIndex) / Double(steps.count - 1)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
        }
    }

    return AnimatedPreview()
}
