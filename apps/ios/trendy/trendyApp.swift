//
//  trendyApp.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

@main
struct trendyApp: App {
    // MARK: - Configuration and Services

    /// App configuration initialized from Info.plist (which reads from xcconfig files)
    private let appConfiguration: AppConfiguration

    /// Supabase service for authentication
    private let supabaseService: SupabaseService

    /// API client for backend communication
    private let apiClient: APIClient

    // MARK: - View Models

    @State private var authViewModel: AuthViewModel
    @State private var themeManager: ThemeManager

    // MARK: - SwiftData

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Event.self,
            EventType.self,
            QueuedOperation.self,
            Geofence.self,
            PropertyDefinition.self,
            HealthKitConfiguration.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - Initialization

    init() {
        // Initialize configuration from Info.plist
        do {
            self.appConfiguration = try AppConfiguration()
        } catch {
            fatalError("Failed to initialize app configuration: \(error.localizedDescription)")
        }

        // Print configuration for debugging (in debug builds only)
        #if DEBUG
        print("=== App Configuration ===")
        print(appConfiguration.debugDescription)
        print("========================")
        #endif

        // Initialize Supabase service with configuration
        self.supabaseService = SupabaseService(configuration: appConfiguration.supabaseConfiguration)

        // Initialize API client with configuration and Supabase service
        self.apiClient = APIClient(
            configuration: appConfiguration.apiConfiguration,
            supabaseService: supabaseService
        )

        // Initialize AuthViewModel with Supabase service
        _authViewModel = State(initialValue: AuthViewModel(supabaseService: supabaseService))

        // Initialize ThemeManager
        _themeManager = State(initialValue: ThemeManager())
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .environment(themeManager)
                .environment(\.supabaseService, supabaseService)
                .environment(\.apiClient, apiClient)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Environment Keys

/// Environment key for SupabaseService
struct SupabaseServiceKey: EnvironmentKey {
    static let defaultValue: SupabaseService? = nil
}

/// Environment key for APIClient
struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient? = nil
}

extension EnvironmentValues {
    var supabaseService: SupabaseService? {
        get { self[SupabaseServiceKey.self] }
        set { self[SupabaseServiceKey.self] = newValue }
    }

    var apiClient: APIClient? {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
