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

        // Debug: Log current state
        #if DEBUG
        logCurrentState()
        #endif
    }
}
