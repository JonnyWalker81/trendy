//
//  trendyApp.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData
import WidgetKit
import FoundationModels

/// App Group identifier for sharing data with widgets
let appGroupIdentifier = "group.com.memento.trendy"

@main
struct trendyApp: App {
    // MARK: - Configuration and Services

    /// App configuration initialized from Info.plist (which reads from xcconfig files)
    private let appConfiguration: AppConfiguration

    /// Supabase service for authentication
    private let supabaseService: SupabaseService

    /// API client for backend communication
    private let apiClient: APIClient

    /// Foundation Model service for AI insights
    private let foundationModelService: FoundationModelService

    // MARK: - View Models

    @State private var authViewModel: AuthViewModel
    @State private var themeManager: ThemeManager
    @State private var insightsViewModel: InsightsViewModel

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

        // Use App Group container for widget sharing
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupIdentifier)
        )

        // Try to create the container, with fallback to reset if schema is corrupted
        var container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("⚠️ Failed to create ModelContainer: \(error)")
            print("⚠️ Attempting to reset database due to schema incompatibility...")

            // Delete the corrupted database files
            if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
                let storeURL = appGroupURL.appendingPathComponent("Library/Application Support")
                let filesToDelete = ["default.store", "default.store-wal", "default.store-shm"]
                for file in filesToDelete {
                    let fileURL = storeURL.appendingPathComponent(file)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                print("   Deleted old database files")
            }

            // Try again with a fresh database
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("   ✅ Created fresh database successfully")
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }

        // Verify schema by testing access to all tables
        let context = container.mainContext
        var schemaValid = true

        // Test each table - if any fails, we need to reset
        do {
            _ = try context.fetchCount(FetchDescriptor<EventType>())
            _ = try context.fetchCount(FetchDescriptor<Event>())
            _ = try context.fetchCount(FetchDescriptor<QueuedOperation>())
            _ = try context.fetchCount(FetchDescriptor<Geofence>())
            _ = try context.fetchCount(FetchDescriptor<PropertyDefinition>())
            _ = try context.fetchCount(FetchDescriptor<HealthKitConfiguration>())
        } catch {
            print("⚠️ Schema validation failed: \(error)")
            schemaValid = false
        }

        if !schemaValid {
            print("⚠️ Database schema is incomplete. Resetting database...")

            // Delete the corrupted database files
            if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
                let storeURL = appGroupURL.appendingPathComponent("Library/Application Support")
                let filesToDelete = ["default.store", "default.store-wal", "default.store-shm"]
                for file in filesToDelete {
                    let fileURL = storeURL.appendingPathComponent(file)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                print("   Deleted old database files")
            }

            // Create a new container with fresh database
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("   ✅ Created fresh database with complete schema")
            } catch {
                fatalError("Could not create ModelContainer after schema reset: \(error)")
            }
        }

        // Log SwiftData container location
        #if DEBUG
        print("📦 SwiftData using App Group: \(appGroupIdentifier)")
        #endif

        return container
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

        // Initialize Foundation Model service for AI insights
        self.foundationModelService = FoundationModelService()

        // Initialize AuthViewModel with Supabase service
        _authViewModel = State(initialValue: AuthViewModel(supabaseService: supabaseService))

        // Initialize ThemeManager
        _themeManager = State(initialValue: ThemeManager())

        // Initialize InsightsViewModel
        let insights = InsightsViewModel()
        insights.configure(with: apiClient)
        _insightsViewModel = State(initialValue: insights)

        // Register background tasks for AI insight generation
        AIBackgroundTaskScheduler.shared.registerTasks()
    }

    // MARK: - Body

    /// Check if UI testing dark mode is enabled via launch argument
    private var isUITestingDarkMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingDarkModeEnabled")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .environment(themeManager)
                .environment(insightsViewModel)
                .environment(\.supabaseService, supabaseService)
                .environment(\.apiClient, apiClient)
                .environment(\.foundationModelService, foundationModelService)
                .preferredColorScheme(isUITestingDarkMode ? .dark : themeManager.currentTheme.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Foundation Model Service Environment Key

/// Environment key for FoundationModelService
struct FoundationModelServiceKey: EnvironmentKey {
    static let defaultValue: FoundationModelService? = nil
}

extension EnvironmentValues {
    var foundationModelService: FoundationModelService? {
        get { self[FoundationModelServiceKey.self] }
        set { self[FoundationModelServiceKey.self] = newValue }
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

