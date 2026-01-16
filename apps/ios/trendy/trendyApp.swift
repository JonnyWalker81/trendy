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
import PostHog
import FullDisclosureSDK

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
        // Schema V2: Uses UUIDv7 String IDs (single canonical ID)
        // Note: Migration from V1 requires database reset (UUID→String type change)
        let schema = Schema([
            Event.self,
            EventType.self,
            Geofence.self,
            PropertyDefinition.self,
            QueuedOperation.self,
            PendingMutation.self,
            HealthKitConfiguration.self
        ])

        // Screenshot mode: Use in-memory container for complete isolation from real data
        let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode") ||
                               ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_MODE"] == "1"

        if isScreenshotMode {
            print("📸 Screenshot mode: Using in-memory database (no persistence)")
            let inMemoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
            do {
                let container = try ModelContainer(for: schema, configurations: [inMemoryConfig])
                print("📸 In-memory ModelContainer created successfully")
                return container
            } catch {
                fatalError("📸 Could not create in-memory ModelContainer for screenshots: \(error)")
            }
        }

        // Normal production path: Use persistent App Group container
        // Ensure App Group container directories exist before SwiftData tries to use them
        ensureAppGroupDirectoriesExist()

        // Check if we need to clear container data (set by DebugStorageView)
        if UserDefaults.standard.bool(forKey: "debug_clear_container_on_launch") {
            print("🗑️ Debug: Clearing App Group container on launch...")
            UserDefaults.standard.removeObject(forKey: "debug_clear_container_on_launch")
            UserDefaults.standard.synchronize()
            clearDatabaseFiles()
            print("🗑️ Debug: Container cleared")
        }

        // Use App Group container for widget sharing
        // Explicitly disable CloudKit sync - we use our own backend for sync
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .none  // Disable iCloud/CloudKit sync
        )

        // Try to create the container
        // Note: We don't use a migration plan because SwiftData cannot auto-migrate
        // UUID→String type changes. Old V1 users will get a schema error and reset.
        var container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("📦 ModelContainer created successfully")
        } catch {
            print("⚠️ Failed to create ModelContainer: \(error)")
            print("⚠️ This likely means schema changed (V1→V2 migration)")
            print("⚠️ Clearing database and will resync from backend...")

            // Clear database and resync from backend
            clearDatabaseFiles()
            markForPostMigrationResync()

            // Try again with a fresh database
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("   ✅ Created fresh V2 database successfully")
                print("   ⚠️ User will need to resync from backend")
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }

        // Verify schema by testing access to all tables individually
        // If ANY table fails, we need to reset the database
        let context = container.mainContext
        var failedModels: [String] = []
        var modelCounts: [String: Int] = [:]

        // Helper to check each model independently
        func checkModel<T: PersistentModel>(_ type: T.Type, name: String) {
            do {
                let count = try context.fetchCount(FetchDescriptor<T>())
                modelCounts[name] = count
            } catch {
                print("⚠️ Schema check failed for \(name): \(error)")
                failedModels.append(name)
            }
        }

        // Check each model - continue even if some fail
        checkModel(Event.self, name: "Event")
        checkModel(EventType.self, name: "EventType")
        checkModel(Geofence.self, name: "Geofence")
        checkModel(PropertyDefinition.self, name: "PropertyDefinition")
        checkModel(HealthKitConfiguration.self, name: "HealthKitConfiguration")
        checkModel(QueuedOperation.self, name: "QueuedOperation")
        checkModel(PendingMutation.self, name: "PendingMutation")

        let schemaValid = failedModels.isEmpty

        if schemaValid {
            // DIAGNOSTIC: Log counts on app launch
            print("🔧 Schema validation passed - existing data:")
            print("   EventTypes: \(modelCounts["EventType"] ?? 0)")
            print("   Events: \(modelCounts["Event"] ?? 0)")
            print("   Geofences: \(modelCounts["Geofence"] ?? 0)")
            print("   PropertyDefinitions: \(modelCounts["PropertyDefinition"] ?? 0)")
            print("   HealthKitConfigs: \(modelCounts["HealthKitConfiguration"] ?? 0)")
            print("   QueuedOperations: \(modelCounts["QueuedOperation"] ?? 0)")
            print("   PendingMutations: \(modelCounts["PendingMutation"] ?? 0)")

            // Force a save to ensure the database file is created on disk
            // This prevents "No such file or directory" errors during later saves
            do {
                try context.save()
                print("📦 Database file initialized on disk")
            } catch {
                print("⚠️ Failed to initialize database file: \(error)")
            }
        } else {
            print("⚠️ Schema validation failed for: \(failedModels.joined(separator: ", "))")
        }

        if !schemaValid {
            print("⚠️ Database schema is incomplete. Resetting database...")
            clearDatabaseFiles()
            markForPostMigrationResync()

            // Create a new container with fresh database
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: TrendySchemaMigrationPlan.self,
                    configurations: [modelConfiguration]
                )
                print("   ✅ Created fresh database with complete schema")

                // Force a save to ensure the database file is created on disk
                let freshContext = container.mainContext
                try freshContext.save()
                print("   📦 Database file initialized on disk")
            } catch {
                fatalError("Could not create ModelContainer after schema reset: \(error)")
            }
        }

        // Log SwiftData container location
        #if DEBUG
        print("📦 SwiftData using App Group: \(appGroupIdentifier)")
        print("📦 Schema version: V2 (UUIDv7 String IDs)")
        #endif

        return container
    }()

    /// Ensure the App Group container directories exist before SwiftData tries to use them
    private static func ensureAppGroupDirectoriesExist() {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("⚠️ Could not get App Group container URL")
            return
        }

        let applicationSupportURL = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: applicationSupportURL.path) {
            do {
                try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
                print("📁 Created App Group directory: Library/Application Support")
            } catch {
                print("⚠️ Failed to create App Group directories: \(error)")
            }
        }
    }

    /// Clear the SwiftData database files from the App Group container
    private static func clearDatabaseFiles() {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("⚠️ Could not get App Group container URL")
            return
        }

        let fileManager = FileManager.default

        // Delete all contents of the App Group container
        if let contents = try? fileManager.contentsOfDirectory(at: appGroupURL, includingPropertiesForKeys: nil) {
            for item in contents {
                do {
                    try fileManager.removeItem(at: item)
                    print("   Deleted: \(item.lastPathComponent)")
                } catch {
                    print("   Failed to delete \(item.lastPathComponent): \(error)")
                }
            }
        }

        // Recreate the Library/Application Support directory that SwiftData expects
        let applicationSupportURL = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        do {
            try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
            print("   ✅ Recreated: Library/Application Support")
        } catch {
            print("   ⚠️ Failed to recreate Application Support directory: \(error)")
        }
    }

    /// Mark that a post-migration resync is needed
    private static func markForPostMigrationResync() {
        // Clear sync cursors to force full resync
        UserDefaults.standard.removeObject(forKey: "sync_cursor")
        UserDefaults.standard.removeObject(forKey: "lastSyncCursor")

        // Set flag for UI to show resync prompt if needed
        UserDefaults.standard.set(true, forKey: "schema_migration_v1_to_v2_completed")
        UserDefaults.standard.synchronize()
    }

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

        // Initialize PostHog analytics (TestFlight builds only for now)
        if let posthog = appConfiguration.posthogConfiguration {
            let posthogConfig = PostHogConfig(
                apiKey: posthog.apiKey,
                host: posthog.host
            )

            // DISABLED: Session replay causes severe UI performance issues
            // The screenshotMode=true (required for SwiftUI) captures full screenshots
            // on every UI change, flooding the main thread and causing:
            // - "System gesture gate timed out" errors
            // - UI freezes during tab switching and scrolling
            // - Memory pressure from rapid screenshot generation
            // Re-enable only after PostHog provides a more performant SwiftUI solution.
            posthogConfig.sessionReplay = false
            // posthogConfig.sessionReplayConfig.screenshotMode = true  // Required for SwiftUI
            // posthogConfig.sessionReplayConfig.captureLogs = true
            // posthogConfig.sessionReplayConfig.captureLogsConfig.minLogLevel = .info
            // posthogConfig.sessionReplayConfig.maskAllTextInputs = true
            // posthogConfig.sessionReplayConfig.maskAllImages = false

            // Enable SDK debug logging in debug builds
            #if DEBUG
            posthogConfig.debug = true
            #endif

            posthogConfig.captureApplicationLifecycleEvents = true
            PostHogSDK.shared.setup(posthogConfig)
            print("📊 PostHog initialized (session replay DISABLED for performance)")

            // Send app launch event to verify setup
            PostHogSDK.shared.capture("app_launched", properties: [
                "environment": appConfiguration.environment.rawValue,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            ])
        }

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

        // Identify user in PostHog and FullDisclosure if already authenticated (session restore)
        let supabase = supabaseService
        let hasPostHog = appConfiguration.posthogConfiguration != nil
        Task {
            await supabase.restoreSession()
            // Get session directly from auth client to avoid race condition
            if let session = try? await supabase.client.auth.session {
                let userId = session.user.id.uuidString
                let email = session.user.email

                // Identify user in PostHog (if configured)
                if hasPostHog {
                    var userProperties: [String: Any] = [:]
                    if let email = email {
                        userProperties["email"] = email
                    }
                    print("📊 PostHog identify (session restore): user_id=\(userId), email=\(email ?? "nil")")
                    PostHogSDK.shared.identify(userId, userProperties: userProperties)
                }

                // Identify user in FullDisclosure for feedback submissions
                do {
                    try await FullDisclosure.shared.identify(
                        userId: userId,
                        email: email
                    )
                    print("📝 FullDisclosure identify (session restore): user_id=\(userId), email=\(email ?? "nil")")
                } catch {
                    print("⚠️ FullDisclosure identify failed: \(error)")
                }
            }
        }
        
        
        // Initialize FullDisclosure feedback SDK
        let fdConfig = FullDisclosureSDK.Configuration.default
            .with(baseURL: URL(string: "http://localhost:8080")!)  // Your local API
            .with(showContactFields: false)  // Hide email/name fields - use identified user instead
            .with(debugLogging: true)  // Enable logging to see requests

        FullDisclosure.shared.initialize(
            token: "sdk_565562e99899d6a5ede9f5e45d8a4d453630d401cb9a0d8a39e08073e4c73f7b",
            configuration: fdConfig
        )

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

