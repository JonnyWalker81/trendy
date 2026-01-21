//
//  OnboardingFinishView.swift
//  trendy
//
//  Finish screen for onboarding - success confirmation
//

import SwiftUI
import ConfettiSwiftUI

struct OnboardingFinishView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// Focus binding for VoiceOver focus management
    @AccessibilityFocusState.Binding var focusedField: OnboardingNavigationView.OnboardingFocusField?

    /// Respects user's Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCheckmark = false
    @State private var showContent = false
    @State private var confettiTrigger = 0

    var body: some View {
        VStack(spacing: 32) {
            // Progress bar at top showing 100% complete
            OnboardingProgressBar(
                progress: 1.0,
                stepName: "Complete",
                stepNumber: 6,
                totalSteps: 6
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()

            // Success Animation
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.dsSuccess.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)

                // Inner filled circle
                Circle()
                    .fill(Color.dsSuccess)
                    .frame(width: 100, height: 100)
                    .scaleEffect(reduceMotion ? 1.0 : (showCheckmark ? 1.0 : 0.5))
                    .opacity(reduceMotion ? 1.0 : (showCheckmark ? 1.0 : 0.0))

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(reduceMotion ? 1.0 : (showCheckmark ? 1.0 : 0.3))
                    .opacity(reduceMotion ? 1.0 : (showCheckmark ? 1.0 : 0.0))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7), value: showCheckmark)
            .accessibilityLabel("Success checkmark")

            // Content
            VStack(spacing: 16) {
                Text("You're all set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dsForeground)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedField, equals: .finish)

                Text("Start tracking and discover patterns in your daily life.")
                    .font(.body)
                    .foregroundStyle(Color.dsMutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .opacity(reduceMotion ? 1.0 : (showContent ? 1.0 : 0.0))
            .offset(y: reduceMotion ? 0 : (showContent ? 0 : 20))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.3), value: showContent)

            Spacer()

            // Summary Card
            if let eventType = viewModel.createdEventType {
                SummaryCard(eventType: eventType)
                    .opacity(reduceMotion ? 1.0 : (showContent ? 1.0 : 0.0))
                    .offset(y: reduceMotion ? 0 : (showContent ? 0 : 20))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.4), value: showContent)
            }

            Spacer()

            // CTA Button
            Button {
                // Complete onboarding - this will trigger navigation to main app
                Task {
                    await viewModel.advanceToNextStep()
                }
            } label: {
                HStack {
                    Text("Go to Dashboard")
                    Image(systemName: "arrow.right")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.dsPrimary)
                .foregroundStyle(Color.dsPrimaryForeground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .opacity(reduceMotion ? 1.0 : (showContent ? 1.0 : 0.0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.5), value: showContent)
            .accessibilityLabel("Go to dashboard")
            .accessibilityHint("Completes setup and opens the main app")

            Spacer(minLength: 40)
        }
        .background(Color.dsBackground)
        .confettiCannon(
            trigger: $confettiTrigger,
            num: reduceMotion ? 0 : 50,
            colors: [.dsChart1, .dsChart2, .dsChart3, .dsChart4, .dsChart5, .dsPrimary],
            confettiSize: 10,
            radius: 300,
            hapticFeedback: !reduceMotion
        )
        .onAppear {
            if reduceMotion {
                // Instant appearance for Reduce Motion
                showCheckmark = true
                showContent = true
            } else {
                // Trigger animations
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showCheckmark = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showContent = true
                }
                // Trigger confetti after checkmark animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    confettiTrigger += 1
                }
            }
        }
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let eventType: EventType

    var body: some View {
        VStack(spacing: 16) {
            Text("Ready to track")
                .font(.subheadline)
                .foregroundStyle(Color.dsMutedForeground)

            HStack(spacing: 16) {
                Image(systemName: eventType.iconName)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(eventType.color)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(eventType.name)
                        .font(.headline)
                        .foregroundStyle(Color.dsForeground)

                    Text("Your first event type")
                        .font(.caption)
                        .foregroundStyle(Color.dsMutedForeground)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dsSuccess)
                    .accessibilityHidden(true)
            }
        }
        .padding()
        .background(Color.dsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.dsBorder, lineWidth: 1)
        )
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ready to track \(eventType.name)")
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

    return OnboardingFinishView(viewModel: viewModel, focusedField: $focusedField)
        .preferredColorScheme(.dark)
}
