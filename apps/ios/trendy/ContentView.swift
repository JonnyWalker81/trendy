//
//  ContentView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.supabaseService) private var supabaseService

    /// Whether onboarding has been completed
    @State private var onboardingComplete = false

    /// Whether we've checked onboarding status
    @State private var hasCheckedOnboarding = false

    /// Local storage key for onboarding completion
    private static let onboardingCompleteKey = "onboarding_complete"

    #if DEBUG
    /// Check if running in screenshot mode for UI tests
    private var isScreenshotMode: Bool {
        ScreenshotMockData.isScreenshotMode
    }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if isScreenshotMode {
                // Screenshot mode: skip auth, go directly to main app
                MainTabView()
                    .onAppear {
                        setupScreenshotMode()
                    }
            } else {
                authenticatedContent
            }
            #else
            authenticatedContent
            #endif
        }
        .task {
            await checkOnboardingStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
            withAnimation {
                onboardingComplete = true
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if !hasCheckedOnboarding {
            // Still checking onboarding status
            LoadingStateView()
        } else if authViewModel.isAuthenticated && onboardingComplete {
            // Authenticated and onboarding complete - show main app
            MainTabView()
        } else {
            // Not authenticated OR onboarding not complete - show onboarding flow
            // OnboardingContainerView handles both auth and onboarding steps
            OnboardingContainerView()
        }
    }

    /// Check if onboarding has been completed
    private func checkOnboardingStatus() async {
        // Check local storage first (fast path)
        if UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey) {
            onboardingComplete = true
            hasCheckedOnboarding = true
            return
        }

        // If authenticated, check profile in backend
        if authViewModel.isAuthenticated, let supabaseService = supabaseService {
            let profileService = ProfileService(supabaseService: supabaseService)
            do {
                if let profile = try await profileService.fetchProfile() {
                    onboardingComplete = profile.onboardingComplete
                    // Cache locally for faster future checks
                    if profile.onboardingComplete {
                        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
                    }
                }
            } catch {
                // If we can't fetch profile, default to not complete
                // Onboarding flow will handle creating/checking profile
                Log.auth.error("Failed to check onboarding status", error: error)
            }
        }

        hasCheckedOnboarding = true
    }

    #if DEBUG
    /// Set up screenshot mode with mock data
    private func setupScreenshotMode() {
        // Inject mock data for screenshots
        ScreenshotMockData.injectMockData(into: modelContext)
    }
    #endif
}

// MARK: - Loading State View

private struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(Color.dsMutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
    }
}

#Preview {
    // Create preview configuration
    let previewConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let previewAuthViewModel = AuthViewModel(supabaseService: previewSupabase)

    return ContentView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
        .environment(previewAuthViewModel)
}
