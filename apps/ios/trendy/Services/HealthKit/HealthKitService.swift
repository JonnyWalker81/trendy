//
//  HealthKitService.swift
//  trendy
//
//  Manages HealthKit monitoring and automatic event creation
//

import Foundation
import HealthKit
import SwiftData
import Observation

/// Manages HealthKit data monitoring and automatic event creation
@Observable
class HealthKitService: NSObject {

    // MARK: - Properties

    let healthStore: HKHealthStore
    let modelContext: ModelContext
    let modelContainer: ModelContainer
    let eventStore: EventStore
    let notificationManager: NotificationManager?

    /// App Group identifier for shared UserDefaults (persists across app reinstalls)
    static let appGroupIdentifier = "group.com.memento.trendy"

    /// Whether the App Group UserDefaults is working (vs falling back to standard)
    private(set) static var isUsingAppGroup: Bool = false

    /// Shared UserDefaults that persists across app reinstalls
    /// Falls back to .standard if App Group is not available, but logs a warning
    static var sharedDefaults: UserDefaults {
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            isUsingAppGroup = true
            return appGroupDefaults
        } else {
            // This should not happen if entitlements are configured correctly
            Log.healthKit.warning("App Group UserDefaults not available, falling back to standard UserDefaults", context: .with { ctx in
                ctx.add("appGroupId", appGroupIdentifier)
                ctx.add("consequence", "Settings will NOT persist across reinstalls")
            })
            isUsingAppGroup = false
            return .standard
        }
    }

    /// Key for tracking if authorization was requested
    static let authorizationRequestedKey = "healthKitAuthorizationRequested"

    /// Key for verifying App Group is working
    private static let appGroupVerificationKey = "healthKitAppGroupVerified"

    /// Whether authorization has been requested (stored in UserDefaults)
    /// Note: HealthKit does NOT report read authorization status for privacy reasons.
    /// We track whether the user has been prompted, and assume they granted access if the request completed.
    var authorizationRequestedInDefaults: Bool {
        get { Self.sharedDefaults.bool(forKey: Self.authorizationRequestedKey) }
        set {
            Self.sharedDefaults.set(newValue, forKey: Self.authorizationRequestedKey)
            Self.sharedDefaults.synchronize() // Force immediate write
        }
    }

    /// Whether authorization has been requested - checks both UserDefaults AND HealthKitSettings
    /// If categories are enabled in settings, the user must have previously authorized
    var authorizationRequested: Bool {
        get {
            // First check UserDefaults
            if authorizationRequestedInDefaults {
                return true
            }

            // Fallback: Check if any categories are enabled in settings
            // If they are, user previously set up health tracking, so consider authorized
            if !HealthKitSettings.shared.enabledCategories.isEmpty {
                // Sync the flag back to UserDefaults so future checks are faster
                Log.healthKit.debug("Found enabled categories, restoring authorization flag")
                authorizationRequestedInDefaults = true
                return true
            }

            return false
        }
        set {
            authorizationRequestedInDefaults = newValue
        }
    }

    /// Check if any HealthKit categories are enabled
    var hasEnabledCategories: Bool {
        !HealthKitSettings.shared.enabledCategories.isEmpty
    }

    /// Current authorization status - true if authorization was requested
    /// Since we only request read access, we can't determine if user granted or denied.
    /// We assume authorization after the request completes.
    var isAuthorized: Bool {
        authorizationRequested
    }

    /// Whether HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Whether daily aggregates (steps/active energy) are currently being refreshed
    var isRefreshingDailyAggregates: Bool = false

    /// Whether any HealthKit data is currently being refreshed
    internal(set) var isRefreshing: Bool = false

    /// Categories currently being refreshed
    internal(set) var refreshingCategories: Set<HealthDataCategory> = []

    /// Whether historical import should be cancelled
    internal(set) var isHistoricalImportCancelled: Bool = false

    /// Whether historical import is currently in progress
    internal(set) var isHistoricalImportInProgress: Bool = false

    /// Active observer queries for background delivery
    var observerQueries: [HealthDataCategory: HKObserverQuery] = [:]

    /// Processed sample identifiers to prevent duplicates
    var processedSampleIds: Set<String> = []

    /// Workout timestamps currently being processed - prevents race condition when same workout
    /// is reported with different sample IDs from different sources (Apple Watch vs iPhone).
    /// Key is workout start timestamp truncated to the second (ISO8601 format).
    /// This acts as a mutex at the workout level rather than sample ID level.
    var processingWorkoutTimestamps: Set<String> = []

    /// Last processed date for daily step aggregation
    var lastStepDate: Date?

    /// Last processed date for daily sleep aggregation
    var lastSleepDate: Date?

    /// Last processed date for daily active energy aggregation
    var lastActiveEnergyDate: Date?

    /// Anchors for incremental fetching
    var queryAnchors: [HealthDataCategory: HKQueryAnchor] = [:]

    /// Last update time per category (for UI display)
    internal(set) var lastUpdateTimes: [HealthDataCategory: Date] = [:]

    // MARK: - Constants

    let processedSampleIdsKey = "healthKitProcessedSampleIds"
    let lastStepDateKey = "healthKitLastStepDate"
    let lastSleepDateKey = "healthKitLastSleepDate"
    let lastActiveEnergyDateKey = "healthKitLastActiveEnergyDate"
    let maxProcessedSampleIds = 1000
    static let migrationCompletedKey = "healthKitMigrationToAppGroupCompleted"
    let queryAnchorKeyPrefix = "healthKitQueryAnchor_"
    let lastUpdateTimeKeyPrefix = "healthKitLastUpdate_"

    /// Date formatter for consistent date-only sampleIds (no timezone issues)
    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Initialization

    /// Initialize HealthKitService
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - eventStore: EventStore for creating/updating events
    ///   - notificationManager: Optional NotificationManager for sending notifications
    init(modelContext: ModelContext, eventStore: EventStore, notificationManager: NotificationManager? = nil) {
        self.healthStore = HKHealthStore()
        self.modelContext = modelContext
        self.modelContainer = modelContext.container
        self.eventStore = eventStore
        self.notificationManager = notificationManager

        super.init()

        // Verify App Group is working
        verifyAppGroupSetup()

        // Migrate from old UserDefaults.standard to App Group if needed
        migrateFromStandardUserDefaults()

        loadProcessedSampleIds()
        loadLastStepDate()
        loadLastSleepDate()
        loadLastActiveEnergyDate()
        loadAllAnchors()
        loadAllUpdateTimes()

        // Listen for bootstrap completion to reload processedSampleIds
        // This prevents duplicates when force resync downloads HealthKit events from server
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBootstrapCompleted),
            name: .syncEngineBootstrapCompleted,
            object: nil
        )

        // Debug: Log current state
        #if DEBUG
        logCurrentState()
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Handle bootstrap completion notification by resetting HealthKit import state.
    ///
    /// After a force resync (bootstrap), local events are deleted and replaced with server data.
    /// We must reset HealthKit tracking to allow re-import of data that:
    /// 1. Was deleted locally (processedSampleIds cleared to match database)
    /// 2. Doesn't exist on server but exists in HealthKit (anchors cleared to re-query)
    ///
    /// CRITICAL FIX (2026-01-18): Also clear anchors so HealthKit will re-query from scratch.
    /// Without this, data that was fetched before but never synced to server won't be re-imported,
    /// because anchored queries only return NEW data since the anchor position.
    ///
    /// CRITICAL FIX #2 (2026-01-18): After resetting state, actively trigger a refresh.
    /// Observer queries are PASSIVE - they only fire when new data arrives in HealthKit.
    /// We must ACTIVELY query HealthKit to re-import existing data after state reset.
    ///
    /// CRITICAL FIX #3 (2026-01-18): Use reconcileHealthKitData() instead of forceRefreshAllCategories().
    /// forceRefreshAllCategories() only processes TODAY for daily aggregates (steps, activeEnergy).
    /// reconcileHealthKitData() iterates through the last 30 days and queries HealthKit for each
    /// missing day, properly re-importing historical data that wasn't synced to the server.
    @objc private func handleBootstrapCompleted() {
        Log.healthKit.info("Received bootstrap completed notification - resetting HealthKit import state")
        Task { @MainActor in
            // Step 1: Clear all anchors so HealthKit will re-query from scratch
            // This allows re-import of data that exists in HealthKit but not on server
            clearAllAnchors()

            // Step 2: Clear daily aggregate throttle timestamps to allow immediate re-aggregation
            // Without this, steps/activeEnergy won't refresh until 5 minutes passes
            lastStepDate = nil
            lastActiveEnergyDate = nil
            lastSleepDate = nil
            saveLastStepDate()
            saveLastActiveEnergyDate()
            saveLastSleepDate()

            // Step 3: Replace processedSampleIds with only what's in the database
            // This clears old IDs from deleted events, allowing re-import
            reloadProcessedSampleIdsFromDatabase()

            Log.healthKit.info("HealthKit import state reset complete - triggering reconciliation")

            // Step 4: ACTIVELY reconcile HealthKit data for all enabled categories
            // This queries HealthKit for the last 30 days and imports any missing data.
            // Unlike forceRefreshAllCategories() which only processes TODAY for daily aggregates,
            // reconcileHealthKitData() iterates through each historical day.
            let reconciledCount = await reconcileHealthKitData(days: 30)

            Log.healthKit.info("HealthKit reconciliation after bootstrap complete", context: .with { ctx in
                ctx.add("reconciled_count", reconciledCount)
            })
        }
    }
}
