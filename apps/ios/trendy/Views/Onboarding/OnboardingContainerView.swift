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
        store.setModelContext(modelContext)

        // Connect event store to view model
        vm.setEventStore(store)

        // Determine initial state
        await vm.determineInitialState()

        // If onboarding is already complete, don't show onboarding UI
        // The parent view should handle routing
        if vm.isComplete {
            NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
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
struct OnboardingNavigationView: View {
    @Bindable var viewModel: OnboardingViewModel
    let eventStore: EventStore

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeView(viewModel: viewModel)

            case .auth:
                OnboardingAuthView(viewModel: viewModel)

            case .createEventType:
                CreateEventTypeView(viewModel: viewModel)
                    .environment(eventStore)

            case .logFirstEvent:
                LogFirstEventView(viewModel: viewModel)
                    .environment(eventStore)

            case .permissions:
                PermissionsView(viewModel: viewModel)

            case .finish:
                OnboardingFinishView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
        .onChange(of: viewModel.isComplete) { _, isComplete in
            if isComplete {
                // Onboarding finished, notify parent
                NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
            }
        }
    }
}

// MARK: - Onboarding Loading View

private struct OnboardingLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

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
    let previewSupabaseConfig = SupabaseConfiguration(
        url: "http://127.0.0.1:54321",
        anonKey: "preview_key"
    )
    let previewAPIConfig = APIConfiguration(baseURL: "http://127.0.0.1:8080/api/v1")
    let previewSupabase = SupabaseService(configuration: previewSupabaseConfig)
    let previewAPIClient = APIClient(configuration: previewAPIConfig, supabaseService: previewSupabase)

    OnboardingContainerView()
        .modelContainer(for: [Event.self, EventType.self], inMemory: true)
        .environment(\.supabaseService, previewSupabase)
        .environment(\.apiClient, previewAPIClient)
        .preferredColorScheme(.dark)
}
