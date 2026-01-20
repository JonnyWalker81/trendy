//
//  OnboardingHeroView.swift
//  trendy
//
//  Hero view component for onboarding screens with gradient background and SF Symbol
//

import SwiftUI

/// A full-width hero component for onboarding screens that displays
/// an SF Symbol on a gradient background with optional pulse animation.
///
/// The hero view provides a consistent visual pattern across all onboarding
/// screens, featuring:
/// - LinearGradient background from topLeading to bottomTrailing
/// - Centered SF Symbol with large presentation (80pt)
/// - White foreground with subtle glow effect
/// - Optional subtle pulse animation for visual interest
///
/// - Note: This component adapts to both light and dark modes via the gradient colors provided.
struct OnboardingHeroView: View {
    /// The SF Symbol name to display
    let symbolName: String

    /// The gradient colors for the background (applied from topLeading to bottomTrailing)
    let gradientColors: [Color]

    /// Whether to show a subtle pulse animation on the symbol (default: true)
    var symbolAnimation: Bool = true

    /// State for the pulse animation
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // SF Symbol with glow effect
            Image(systemName: symbolName)
                .font(.system(size: 80, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.4), radius: 16)
                .shadow(color: .white.opacity(0.2), radius: 32)
                .scaleEffect(symbolAnimation && isPulsing ? 1.05 : 1.0)
                .animation(
                    symbolAnimation
                        ? .easeInOut(duration: 2.5).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .onAppear {
            if symbolAnimation {
                isPulsing = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Welcome Hero") {
    VStack(spacing: 0) {
        OnboardingHeroView(
            symbolName: "sparkles",
            gradientColors: [Color.dsPrimary, Color.dsChart4]
        )

        Spacer()

        VStack(spacing: 12) {
            Text("Welcome to Trendy")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.dsForeground)

            Text("Track the moments that matter")
                .font(.body)
                .foregroundStyle(Color.dsMutedForeground)
        }
        .padding(.horizontal, 32)

        Spacer()
    }
    .background(Color.dsBackground)
}

#Preview("Notification Hero") {
    VStack(spacing: 0) {
        OnboardingHeroView(
            symbolName: "bell.badge.fill",
            gradientColors: [Color.dsWarning, Color.dsChart3]
        )

        Spacer()

        VStack(spacing: 12) {
            Text("Stay Informed")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.dsForeground)

            Text("Get gentle reminders to track")
                .font(.body)
                .foregroundStyle(Color.dsMutedForeground)
        }
        .padding(.horizontal, 32)

        Spacer()
    }
    .background(Color.dsBackground)
}

#Preview("Location Hero") {
    VStack(spacing: 0) {
        OnboardingHeroView(
            symbolName: "location.fill",
            gradientColors: [Color.dsSuccess, Color.dsChart2]
        )

        Spacer()

        VStack(spacing: 12) {
            Text("Automatic Tracking")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.dsForeground)

            Text("Log events when you arrive at places")
                .font(.body)
                .foregroundStyle(Color.dsMutedForeground)
        }
        .padding(.horizontal, 32)

        Spacer()
    }
    .background(Color.dsBackground)
}

#Preview("Static (No Animation)") {
    VStack(spacing: 0) {
        OnboardingHeroView(
            symbolName: "checkmark.seal.fill",
            gradientColors: [Color.dsSuccess, Color.dsChart2],
            symbolAnimation: false
        )

        Spacer()

        VStack(spacing: 12) {
            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.dsForeground)

            Text("Start tracking your first event")
                .font(.body)
                .foregroundStyle(Color.dsMutedForeground)
        }
        .padding(.horizontal, 32)

        Spacer()
    }
    .background(Color.dsBackground)
}

#Preview("Different Symbols") {
    ScrollView {
        VStack(spacing: 24) {
            OnboardingHeroView(
                symbolName: "figure.walk",
                gradientColors: [.blue, .cyan]
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            OnboardingHeroView(
                symbolName: "heart.fill",
                gradientColors: [.pink, .red]
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            OnboardingHeroView(
                symbolName: "brain.fill",
                gradientColors: [.purple, .indigo]
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .background(Color.dsBackground)
}
