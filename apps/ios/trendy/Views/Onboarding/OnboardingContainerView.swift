//
//  OnboardingContainerView.swift
//  trendy
//
//  Container view that coordinates onboarding navigation
//

import SwiftUI
import SwiftData

/// Container view that manages the onboarding flow
/// Handles initialization, navigation between steps, and completion
struct OnboardingContainerView: View {
    @Environment(\.supabaseService) private var supabaseService
    @Environment(\.apiClient) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncHistoryStore.self) private var syncHistoryStore
    @Environment(AppRouter.self) private var appRouter
    @Environment(OnboardingStatusService.self) private var onboardingStatusService

    @State private var viewModel: OnboardingViewModel?
    @State private var eventStore: EventStore?
    @State private var isInitialized = false

    var body: some View {
        Group {
            if isInitialized, let viewModel = viewModel, let eventStore = eventStore {
                OnboardingNavigationView(viewModel: viewModel, eventStore: eventStore)
            } else {
                // Loading state while initializing
                OnboardingLoadingView()
            }
        }
        .task {
            await initializeOnboarding()
        }
    }

    private func initializeOnboarding() async {
        guard let supabaseService = supabaseService,
              let apiClient = apiClient else {
            Log.auth.error("Missing required services for onboarding")
            return
        }

        // Create view model
        let vm = OnboardingViewModel(supabaseService: supabaseService)

        // Create event store
        let store = EventStore(apiClient: apiClient)
        store.setModelContext(modelContext, syncHistoryStore: syncHistoryStore)

        // Connect dependencies to view model
        vm.setEventStore(store)
        vm.setAppRouter(appRouter)
        vm.setOnboardingStatusService(onboardingStatusService)

        // Determine initial state
        await vm.determineInitialState()

        // If onboarding is already complete, transition to main app
        if vm.isComplete {
            appRouter.transitionToAuthenticated()
            return
        }

        // Load event types if authenticated (for skip logic)
        if supabaseService.isAuthenticated {
            await store.fetchData(force: true)
        }

        // Set state
        self.viewModel = vm
        self.eventStore = store
        self.isInitialized = true
    }
}

/// Navigation view that displays the current onboarding step
/// Handles step transitions with accessibility support including:
/// - Focus management for VoiceOver users
/// - Reduce Motion compliant transitions
struct OnboardingNavigationView: View {
    @Bindable var viewModel: OnboardingViewModel
    let eventStore: EventStore

    /// Focus state enum for VoiceOver focus management
    enum OnboardingFocusField: Hashable {
        case welcome, auth, createEvent, logEvent, permissions, finish
    }

    /// Tracks VoiceOver focus for accessibility
    @AccessibilityFocusState private var focusedField: OnboardingFocusField?

    /// Respects user's Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeView(viewModel: viewModel, focusedField: $focusedField)
                    .id(OnboardingStep.welcome)

            case .auth:
                OnboardingAuthView(viewModel: viewModel, focusedField: $focusedField)
                    .id(OnboardingStep.auth)

            case .createEventType:
                CreateEventTypeView(viewModel: viewModel, focusedField: $focusedField)
                    .environment(eventStore)
                    .id(OnboardingStep.createEventType)

            case .logFirstEvent:
                LogFirstEventView(viewModel: viewModel, focusedField: $focusedField)
                    .environment(eventStore)
                    .id(OnboardingStep.logFirstEvent)

            case .permissions:
                PermissionsView(viewModel: viewModel, focusedField: $focusedField)
                    .id(OnboardingStep.permissions)

            case .finish:
                OnboardingFinishView(viewModel: viewModel, focusedField: $focusedField)
                    .id(OnboardingStep.finish)
            }
        }
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
            value: viewModel.currentStep
        )
        .onChange(of: viewModel.currentStep) { _, newStep in
            // Move VoiceOver focus to new step title after animation starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = focusField(for: newStep)
            }
        }
        // NOTE: viewModel.completeOnboarding() now calls appRouter.handleOnboardingComplete() directly
        // No need to observe isComplete here anymore
    }

    /// Maps an OnboardingStep to its corresponding focus field
    private func focusField(for step: OnboardingStep) -> OnboardingFocusField {
        switch step {
        case .welcome: return .welcome
        case .auth: return .auth
        case .createEventType: return .createEvent
        case .logFirstEvent: return .logEvent
        case .permissions: return .permissions
        case .finish: return .finish
        }
    }
}

// MARK: - Onboarding Loading View

private struct OnboardingLoadingView: View {
    @State private var isPulsing = false

    /// Respects user's Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.dsBackground
                .ignoresSafeArea()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(Color.dsPrimary)
                .shadow(color: Color.dsPrimary.opacity(0.5), radius: isPulsing && !reduceMotion ? 20 : 10)
                .scaleEffect(isPulsing && !reduceMotion ? 1.05 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .accessibilityHidden(true)
                .onAppear {
                    if !reduceMotion {
                        isPulsing = true
                    }
                }
        }
    }
}

#Preview {
    // Create preview configuration
    let previewSupabaseConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewAPIConfig = APIConfiguration(baseURL: "http://127.0.0.1:8080/api/v1")
    let previewSupabase = SupabaseService(configuration: previewSupabaseConfig)
    let previewAPIClient = APIClient(configuration: previewAPIConfig, supabaseService: previewSupabase)
    let previewOnboardingService = OnboardingStatusService(apiClient: previewAPIClient, supabaseService: previewSupabase)
    let previewAppRouter = AppRouter(supabaseService: previewSupabase, onboardingService: previewOnboardingService)

    OnboardingContainerView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
        .environment(\.supabaseService, previewSupabase)
        .environment(\.apiClient, previewAPIClient)
        .environment(previewAppRouter)
        .environment(previewOnboardingService)
        .preferredColorScheme(.dark)
}
