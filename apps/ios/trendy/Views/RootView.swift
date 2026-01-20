//
//  RootView.swift
//  trendy
//
//  Top-level view that switches based on AppRouter state
//  Replaces ContentView as the main routing container
//

import SwiftUI

/// Root view that displays content based on current route
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        Group {
            switch router.currentRoute {
            case .loading:
                // Brief loading state - only shown for cache miss
                // Matches launch screen aesthetic per CONTEXT.md
                LaunchLoadingView()

            case .onboarding(let step):
                // Onboarding flow with starting step
                OnboardingContainerView()

            case .login:
                // Returning unauthenticated user - show login directly
                // Skip welcome/intro since they've seen it before
                LoginView()

            case .authenticated:
                // Main app
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: router.currentRoute)
    }
}

/// Loading view matching launch screen aesthetic
/// Per CONTEXT.md: "Loading screen matches Launch Screen aesthetic (seamless transition)"
/// Uses pulsing icon animation instead of spinner for polished feel
private struct LaunchLoadingView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.dsBackground
                .ignoresSafeArea()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(Color.dsPrimary)
                .shadow(color: Color.dsPrimary.opacity(0.5), radius: isPulsing ? 20 : 10)
                .scaleEffect(isPulsing ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
        }
    }
}

#Preview("Loading") {
    let previewConfig = SupabaseConfiguration(url: "http://127.0.0.1:54321", anonKey: "preview")
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let previewAPIConfig = APIConfiguration(baseURL: "http://127.0.0.1:8080/api/v1")
    let previewAPIClient = APIClient(configuration: previewAPIConfig, supabaseService: previewSupabase)
    let previewOnboardingService = OnboardingStatusService(apiClient: previewAPIClient, supabaseService: previewSupabase)
    let previewRouter = AppRouter(supabaseService: previewSupabase, onboardingService: previewOnboardingService)

    return LaunchLoadingView()
        .environment(previewRouter)
        .environment(AuthViewModel(supabaseService: previewSupabase))
}

#Preview("Authenticated") {
    let previewConfig = SupabaseConfiguration(url: "http://127.0.0.1:54321", anonKey: "preview")
    let previewSupabase = SupabaseService(configuration: previewConfig)
    let previewAPIConfig = APIConfiguration(baseURL: "http://127.0.0.1:8080/api/v1")
    let previewAPIClient = APIClient(configuration: previewAPIConfig, supabaseService: previewSupabase)
    let previewOnboardingService = OnboardingStatusService(apiClient: previewAPIClient, supabaseService: previewSupabase)
    let previewRouter = AppRouter(supabaseService: previewSupabase, onboardingService: previewOnboardingService)

    return MainTabView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
        .environment(previewRouter)
        .environment(AuthViewModel(supabaseService: previewSupabase))
}
