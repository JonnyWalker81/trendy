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
struct OnboardingProgressBar: View {
    /// The current progress value (0.0 to 1.0)
    let progress: Double

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
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 4)
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
            Text("0% Progress")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(progress: 0.0)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("25% Progress")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(progress: 0.25)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("50% Progress")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(progress: 0.5)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("75% Progress")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(progress: 0.75)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("100% Progress")
                .font(.caption)
                .foregroundStyle(Color.dsMutedForeground)
            OnboardingProgressBar(progress: 1.0)
        }
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dsBackground)
}

#Preview("Animated Progress") {
    struct AnimatedPreview: View {
        @State private var progress: Double = 0.0

        var body: some View {
            VStack(spacing: 40) {
                Text("Tap to advance progress")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsMutedForeground)

                OnboardingProgressBar(progress: progress)
                    .padding(.horizontal, 24)

                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.dsForeground)

                Button("Advance") {
                    if progress >= 1.0 {
                        progress = 0.0
                    } else {
                        progress += 0.25
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
