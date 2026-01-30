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
// import FullDisclosureSDK

/// App Group identifier for sharing data with widgets
let appGroupIdentifier = "group.com.memento.trendy"

@main
struct trendyApp: App {
    // MARK: - App Delegate

    /// AppDelegate for handling background location launches.
    /// This must be declared first to ensure it's initialized before SwiftUI scene lifecycle begins.
    /// When iOS relaunches the app due to a geofence event, the AppDelegate receives pending events.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Configuration and Services

    /// App configuration initialized from Info.plist (which reads from xcconfig files)
    private let appConfiguration: AppConfiguration

    /// Supabase service for authentication
    private let supabaseService: SupabaseService

    /// API client for backend communication
    private let apiClient: APIClient

    /// Foundation Model service for AI insights
    private let foundationModelService: FoundationModelService

    /// Onboarding status service
    private let onboardingStatusService: OnboardingStatusService

    /// App router for navigation state
    private let appRouter: AppRouter

    // MARK: - View Models

    @State private var authViewModel: AuthViewModel
    @State private var themeManager: ThemeManager
    @State private var insightsViewModel: InsightsViewModel
    @State private var syncStatusViewModel = SyncStatusViewModel()
    @State private var syncHistoryStore = SyncHistoryStore()

    // MARK: - Persistence

    /// Centralized persistence controller - manages all ModelContext lifecycle
    private let persistenceController: PersistenceController

    // MARK: - SwiftData

    var sharedModelContainer: ModelContainer = {
        // Schema V2: Uses UUIDv7 String IDs (single canonical ID)
        // Note: Migration from V1 requires database reset (UUID→String type change)
        // Note: QueuedOperation was removed - replaced by PendingMutation
        let schema = Schema([
            Event.self,
            EventType.self,
            Geofence.self,
            PropertyDefinition.self,
            PendingMutation.self,
            HealthKitConfiguration.self
        ])

        // Screenshot mode: Use in-memory container for complete isolation from real data
        let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode") ||
                               ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_MODE"] == "1"

        if isScreenshotMode {
            Log.general.debug("📸 Screenshot mode: Using in-memory database (no persistence)")
            let inMemoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
            do {
                let container = try ModelContainer(for: schema, configurations: [inMemoryConfig])
                Log.general.debug("📸 In-memory ModelContainer created successfully")
                return container
            } catch {
                fatalError("📸 Could not create in-memory ModelContainer for screenshots: \(error)")
            }
        }

        // Normal production path: Use app's private container (not App Group)
        // Migrate database from App Group to private container on first launch after update
        migrateFromAppGroupIfNeeded()

        // Check if we need to clear container data (set by DebugStorageView)
        if UserDefaults.standard.bool(forKey: "debug_clear_container_on_launch") {
            Log.data.info("🗑️ Debug: Clearing App Group container on launch...")
            UserDefaults.standard.removeObject(forKey: "debug_clear_container_on_launch")
            UserDefaults.standard.synchronize()
            clearDatabaseFiles()
            Log.data.info("🗑️ Debug: Container cleared")
        }

        // IMPORTANT: Store database in app's PRIVATE container, NOT the App Group.
        // Previously, the database was in the App Group container to share with widgets.
        // This caused 0xdead10cc crashes because iOS terminates apps that hold SQLite
        // file locks in shared containers during background suspension.
        //
        // Widgets now receive data via a lightweight JSON file in the App Group
        // (see WidgetDataBridge.swift), eliminating all SQLite access from the
        // shared container.
        //
        // See: https://ryanashcraft.com/sqlite-databases-in-app-group-containers/
        // See: https://scottdriggers.com/blog/0xdead10cc-crash-caused-by-swiftdata-modelcontainer/
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none  // Disable iCloud/CloudKit sync
        )

        // Try to create the container
        // Note: We don't use a migration plan because SwiftData cannot auto-migrate
        // UUID→String type changes. Old V1 users will get a schema error and reset.
        var container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            Log.data.info("📦 ModelContainer created successfully")
        } catch {
            Log.data.warning("⚠️ Failed to create ModelContainer", error: error)
            Log.data.warning("⚠️ This likely means schema changed (V1→V2 migration)")
            Log.data.warning("⚠️ Clearing database and will resync from backend...")

            // Clear database and resync from backend
            clearDatabaseFiles()
            markForPostMigrationResync()

            // Try again with a fresh database
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                Log.data.info("✅ Created fresh V2 database successfully")
                Log.data.warning("⚠️ User will need to resync from backend")
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
                Log.data.warning("⚠️ Schema check failed", context: .with { ctx in
                    ctx.add("model", name)
                    ctx.add(error: error)
                })
                failedModels.append(name)
            }
        }

        // Check each model - continue even if some fail
        checkModel(Event.self, name: "Event")
        checkModel(EventType.self, name: "EventType")
        checkModel(Geofence.self, name: "Geofence")
        checkModel(PropertyDefinition.self, name: "PropertyDefinition")
        checkModel(HealthKitConfiguration.self, name: "HealthKitConfiguration")
        checkModel(PendingMutation.self, name: "PendingMutation")

        let schemaValid = failedModels.isEmpty

        if schemaValid {
            // DIAGNOSTIC: Log counts on app launch
            Log.data.debug("🔧 Schema validation passed - existing data", context: .with { ctx in
                ctx.add("event_types", modelCounts["EventType"] ?? 0)
                ctx.add("events", modelCounts["Event"] ?? 0)
                ctx.add("geofences", modelCounts["Geofence"] ?? 0)
                ctx.add("property_definitions", modelCounts["PropertyDefinition"] ?? 0)
                ctx.add("healthkit_configs", modelCounts["HealthKitConfiguration"] ?? 0)
                ctx.add("pending_mutations", modelCounts["PendingMutation"] ?? 0)
            })

            // Force a save to ensure the database file is created on disk
            // This prevents "No such file or directory" errors during later saves
            do {
                try context.save()
                Log.data.debug("📦 Database file initialized on disk")
            } catch {
                Log.data.warning("⚠️ Failed to initialize database file", error: error)
            }
        } else {
            Log.data.warning("⚠️ Schema validation failed", context: .with { ctx in
                ctx.add("failed_models", failedModels.joined(separator: ", "))
            })
        }

        if !schemaValid {
            Log.data.warning("⚠️ Database schema is incomplete. Resetting database...")
            clearDatabaseFiles()
            markForPostMigrationResync()

            // Create a new container with fresh database
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: TrendySchemaMigrationPlan.self,
                    configurations: [modelConfiguration]
                )
                Log.data.info("✅ Created fresh database with complete schema")

                // Force a save to ensure the database file is created on disk
                let freshContext = container.mainContext
                try freshContext.save()
                Log.data.debug("📦 Database file initialized on disk")
            } catch {
                fatalError("Could not create ModelContainer after schema reset: \(error)")
            }
        }

        // CRITICAL: Disable autosave on the container's mainContext.
        // SwiftData's default (autosaveEnabled=true) can trigger SQLite writes during
        // background suspension, which causes iOS to kill the app with 0xdead10cc
        // (holding file locks in suspended state). All saves must be explicit and
        // wrapped in background task protection via PersistenceController.
        container.mainContext.autosaveEnabled = false

        // Log SwiftData container location
        #if DEBUG
        Log.data.debug("📦 SwiftData using private container (not App Group)", context: .with { ctx in
            ctx.add("note", "Widgets use JSON bridge via App Group")
            ctx.add("schema_version", "V2 (UUIDv7 String IDs)")
            ctx.add("autosaveEnabled", false)
        })
        #endif

        return container
    }()

    /// Migrate SwiftData database from App Group container to app's private container.
    ///
    /// Previously, the database was stored in the App Group container to share with widgets.
    /// This caused 0xdead10cc crashes. On first launch after the update, we move the database
    /// files to the app's private Library/Application Support directory, which is the default
    /// location for SwiftData with `groupContainer: .none`.
    ///
    /// After migration, the old database files in the App Group are deleted to free space
    /// and prevent the widget from accidentally opening them.
    private static func migrateFromAppGroupIfNeeded() {
        let migrationKey = "database_migrated_from_app_group_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let fileManager = FileManager.default

        // Source: App Group container's Application Support
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            Log.data.warning("Could not get App Group container URL for migration")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let appGroupAppSupport = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        // Destination: App's private Application Support (where SwiftData with groupContainer: .none stores)
        guard let privateAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Log.data.warning("Could not get private Application Support directory")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Ensure destination directory exists
        if !fileManager.fileExists(atPath: privateAppSupport.path) {
            do {
                try fileManager.createDirectory(at: privateAppSupport, withIntermediateDirectories: true)
            } catch {
                Log.data.warning("Failed to create Application Support directory", error: error)
            }
        }

        // Check if old database exists in App Group
        let oldStoreFile = appGroupAppSupport.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: oldStoreFile.path) else {
            Log.data.info("No database in App Group container - fresh install or already migrated")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Check if new location already has a database (don't overwrite)
        let newStoreFile = privateAppSupport.appendingPathComponent("default.store")
        if fileManager.fileExists(atPath: newStoreFile.path) {
            Log.data.info("Database already exists in private container - skipping migration, cleaning up App Group")
            // Clean up old database from App Group
            cleanupAppGroupDatabase(appGroupAppSupport: appGroupAppSupport)
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Move all database files (default.store, default.store-shm, default.store-wal)
        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
        var migrationSuccess = true

        for fileName in storeFiles {
            let source = appGroupAppSupport.appendingPathComponent(fileName)
            let destination = privateAppSupport.appendingPathComponent(fileName)

            guard fileManager.fileExists(atPath: source.path) else { continue }

            do {
                try fileManager.moveItem(at: source, to: destination)
                Log.data.info("Migrated database file from App Group", context: .with { ctx in
                    ctx.add("file", fileName)
                })
            } catch {
                Log.data.warning("Failed to migrate database file", context: .with { ctx in
                    ctx.add("file", fileName)
                    ctx.add(error: error)
                })
                migrationSuccess = false
            }
        }

        if migrationSuccess {
            Log.data.info("Successfully migrated SwiftData database from App Group to private container")
            // Clean up any remaining database files in App Group
            cleanupAppGroupDatabase(appGroupAppSupport: appGroupAppSupport)
        } else {
            Log.data.warning("Database migration incomplete - will resync from backend on next launch")
            // Mark for resync since migration was partial
            markForPostMigrationResync()
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Remove old database files from the App Group container.
    /// This prevents the widget from accidentally opening the old SQLite database
    /// and also frees storage space.
    private static func cleanupAppGroupDatabase(appGroupAppSupport: URL) {
        let fileManager = FileManager.default
        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]

        for fileName in storeFiles {
            let fileURL = appGroupAppSupport.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.removeItem(at: fileURL)
                    Log.data.debug("Cleaned up old App Group database file", context: .with { ctx in
                        ctx.add("file", fileName)
                    })
                } catch {
                    Log.data.warning("Failed to clean up App Group database file", context: .with { ctx in
                        ctx.add("file", fileName)
                        ctx.add(error: error)
                    })
                }
            }
        }
    }

    /// Clear the SwiftData database files from the app's private container
    private static func clearDatabaseFiles() {
        let fileManager = FileManager.default

        // Clear from private Application Support (current location)
        if let privateAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
            for fileName in storeFiles {
                let fileURL = privateAppSupport.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        Log.data.debug("Deleted database file", context: .with { ctx in
                            ctx.add("file", fileName)
                        })
                    } catch {
                        Log.data.warning("Failed to delete database file", context: .with { ctx in
                            ctx.add("file", fileName)
                            ctx.add(error: error)
                        })
                    }
                }
            }
        }

        // Also clear from App Group container (legacy location)
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let appGroupAppSupport = appGroupURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            cleanupAppGroupDatabase(appGroupAppSupport: appGroupAppSupport)
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
        // Initialize MetricKit subscriber for production telemetry.
        // Must be done early to capture all metrics from app launch.
        _ = MetricsSubscriber.shared

        // Initialize configuration from Info.plist
        do {
            self.appConfiguration = try AppConfiguration()
        } catch {
            fatalError("Failed to initialize app configuration: \(error.localizedDescription)")
        }

        // Print configuration for debugging (in debug builds only)
        #if DEBUG
        let configDebugDesc = appConfiguration.debugDescription
        Log.general.debug("=== App Configuration ===", context: .with { ctx in
            ctx.add("config", configDebugDesc)
        })
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
            Log.general.info("📊 PostHog initialized (session replay DISABLED for performance)")

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

        // Initialize onboarding status service
        self.onboardingStatusService = OnboardingStatusService(
            apiClient: apiClient,
            supabaseService: supabaseService
        )

        // Initialize app router
        self.appRouter = AppRouter(
            supabaseService: supabaseService,
            onboardingService: onboardingStatusService
        )

        // Determine initial route SYNCHRONOUSLY before body renders
        // This is the key to preventing loading flash
        // Uses CACHE-FIRST strategy - does not wait for session restore
        appRouter.determineInitialRoute()

        // Start listening to auth state changes for session events
        // This handles: session restore completion, sign out, token refresh
        appRouter.startAuthStateListener()

        // Initialize AuthViewModel with Supabase service
        _authViewModel = State(initialValue: AuthViewModel(supabaseService: supabaseService))

        // Initialize ThemeManager
        _themeManager = State(initialValue: ThemeManager())

        // Initialize InsightsViewModel
        let insights = InsightsViewModel()
        insights.configure(with: apiClient)
        _insightsViewModel = State(initialValue: insights)

        // Identify user in PostHog after session restore (via auth state listener)
        let supabase = supabaseService
        let hasPostHog = appConfiguration.posthogConfiguration != nil
        Task {
            // Wait for initial session to be restored via auth state listener
            // This is reliable - uses Supabase SDK events, not arbitrary timeouts
            for await event in supabase.authStateChanges {
                if case .initialSession(let session) = event {
                    if let session = session {
                        let userId = session.user.id.uuidString
                        let email = session.user.email

                        // Identify user in PostHog (if configured)
                        if hasPostHog {
                            var userProperties: [String: Any] = [:]
                            if let email = email {
                                userProperties["email"] = email
                            }
                            Log.general.debug("PostHog identify (session restore)", context: .with { ctx in
                                ctx.add("user_id", userId)
                                ctx.add("email", email)
                            })
                            PostHogSDK.shared.identify(userId, userProperties: userProperties)
                        }
                    }
                    break
                }
            }
        }
        
        
//        // Initialize FullDisclosure feedback SDK
//        let fdConfig = FullDisclosureSDK.Configuration.default
//            .with(baseURL: URL(string: "http://localhost:8080")!)  // Your local API
//            .with(showContactFields: false)  // Hide email/name fields - use identified user instead
//            .with(debugLogging: true)  // Enable logging to see requests
//
//        FullDisclosure.shared.initialize(
//            token: "sdk_565562e99899d6a5ede9f5e45d8a4d453630d401cb9a0d8a39e08073e4c73f7b",
//            configuration: fdConfig
//        )

        // Register background tasks for AI insight generation
        AIBackgroundTaskScheduler.shared.registerTasks()

        // Initialize centralized persistence controller
        // This MUST happen after sharedModelContainer is created (it's a lazy var)
        let controller = PersistenceController(modelContainer: sharedModelContainer)
        PersistenceController.shared = controller
        self.persistenceController = controller
    }

    // MARK: - Body

    /// Check if UI testing dark mode is enabled via launch argument
    private var isUITestingDarkMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingDarkModeEnabled")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appRouter)
                .environment(onboardingStatusService)
                .environment(authViewModel)
                .environment(themeManager)
                .environment(insightsViewModel)
                .environment(syncStatusViewModel)
                .environment(syncHistoryStore)
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

