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

    private let healthStore: HKHealthStore
    private let modelContext: ModelContext
    private let eventStore: EventStore
    private let notificationManager: NotificationManager?

    /// App Group identifier for shared UserDefaults (persists across app reinstalls)
    private static let appGroupIdentifier = "group.com.memento.trendy"

    /// Whether the App Group UserDefaults is working (vs falling back to standard)
    private static var isUsingAppGroup: Bool = false

    /// Shared UserDefaults that persists across app reinstalls
    /// Falls back to .standard if App Group is not available, but logs a warning
    private static var sharedDefaults: UserDefaults {
        if let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            isUsingAppGroup = true
            return appGroupDefaults
        } else {
            // This should not happen if entitlements are configured correctly
            print("⚠️ WARNING: App Group UserDefaults not available! Falling back to standard UserDefaults.")
            print("⚠️ This means HealthKit settings will NOT persist across app reinstalls.")
            print("⚠️ Check that '\(appGroupIdentifier)' is in both entitlements AND provisioning profile.")
            isUsingAppGroup = false
            return .standard
        }
    }

    /// Key for tracking if authorization was requested
    private static let authorizationRequestedKey = "healthKitAuthorizationRequested"

    /// Key for verifying App Group is working
    private static let appGroupVerificationKey = "healthKitAppGroupVerified"

    /// Whether authorization has been requested (stored in UserDefaults)
    /// Note: HealthKit does NOT report read authorization status for privacy reasons.
    /// We track whether the user has been prompted, and assume they granted access if the request completed.
    private var authorizationRequestedInDefaults: Bool {
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
                print("📱 HealthKit: Found enabled categories, restoring authorization flag")
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
    private var hasEnabledCategories: Bool {
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

    /// Active observer queries for background delivery
    private var observerQueries: [HealthDataCategory: HKObserverQuery] = [:]

    /// Processed sample identifiers to prevent duplicates
    private var processedSampleIds: Set<String> = []

    /// Last processed date for daily step aggregation
    private var lastStepDate: Date?

    /// Last processed date for daily sleep aggregation
    private var lastSleepDate: Date?

    /// Last processed date for daily active energy aggregation
    private var lastActiveEnergyDate: Date?

    /// Anchors for incremental fetching
    private var queryAnchors: [HealthDataCategory: HKQueryAnchor] = [:]

    // MARK: - Constants

    private let processedSampleIdsKey = "healthKitProcessedSampleIds"
    private let lastStepDateKey = "healthKitLastStepDate"
    private let lastSleepDateKey = "healthKitLastSleepDate"
    private let lastActiveEnergyDateKey = "healthKitLastActiveEnergyDate"
    private let maxProcessedSampleIds = 1000
    private static let migrationCompletedKey = "healthKitMigrationToAppGroupCompleted"

    /// Date formatter for consistent date-only sampleIds (no timezone issues)
    private static let dateOnlyFormatter: DateFormatter = {
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

        // Debug: Log current state
        #if DEBUG
        logCurrentState()
        #endif
    }

    /// Verify that the App Group UserDefaults is properly set up
    private func verifyAppGroupSetup() {
        // Force access to sharedDefaults to trigger the isUsingAppGroup check
        let testKey = "healthKitAppGroupTest"
        let testValue = "verified-\(Date().timeIntervalSince1970)"

        // Write a test value
        Self.sharedDefaults.set(testValue, forKey: testKey)
        Self.sharedDefaults.synchronize()

        // Read it back
        let readValue = Self.sharedDefaults.string(forKey: testKey)

        if readValue == testValue {
            print("✅ HealthKit: App Group UserDefaults is working correctly")
            print("   Using App Group: \(Self.isUsingAppGroup)")
            print("   App Group ID: \(Self.appGroupIdentifier)")
        } else {
            print("❌ HealthKit: App Group UserDefaults verification FAILED!")
            print("   Written: \(testValue)")
            print("   Read back: \(readValue ?? "nil")")
        }

        // Clean up test value
        Self.sharedDefaults.removeObject(forKey: testKey)
    }

    /// Log current HealthKit state for debugging
    private func logCurrentState() {
        print("📊 HealthKit Service State:")
        print("   App Group ID: \(Self.appGroupIdentifier)")
        print("   isUsingAppGroup: \(Self.isUsingAppGroup)")
        print("   authorizationInDefaults: \(authorizationRequestedInDefaults)")
        print("   authorizationRequested (combined): \(authorizationRequested)")
        print("   hasHealthKitAuthorization: \(hasHealthKitAuthorization)")
        print("   lastStepDate: \(lastStepDate?.description ?? "nil")")
        print("   lastSleepDate: \(lastSleepDate?.description ?? "nil")")
        print("   processedSampleIds count: \(processedSampleIds.count)")

        // Log HealthKitSettings state
        HealthKitSettings.shared.logCurrentState()
    }

    // MARK: - Migration

    /// Migrate data from UserDefaults.standard to App Group UserDefaults
    /// This ensures continuity when upgrading from versions that used standard UserDefaults
    private func migrateFromStandardUserDefaults() {
        // Check if migration already completed
        guard !Self.sharedDefaults.bool(forKey: Self.migrationCompletedKey) else { return }

        let standardDefaults = UserDefaults.standard

        // Migrate processed sample IDs
        if let data = standardDefaults.data(forKey: processedSampleIdsKey),
           Self.sharedDefaults.data(forKey: processedSampleIdsKey) == nil {
            Self.sharedDefaults.set(data, forKey: processedSampleIdsKey)
            print("Migrated processedSampleIds to App Group")
        }

        // Migrate last step date
        if let date = standardDefaults.object(forKey: lastStepDateKey) as? Date,
           Self.sharedDefaults.object(forKey: lastStepDateKey) == nil {
            Self.sharedDefaults.set(date, forKey: lastStepDateKey)
            print("Migrated lastStepDate to App Group")
        }

        // Migrate last sleep date
        if let date = standardDefaults.object(forKey: lastSleepDateKey) as? Date,
           Self.sharedDefaults.object(forKey: lastSleepDateKey) == nil {
            Self.sharedDefaults.set(date, forKey: lastSleepDateKey)
            print("Migrated lastSleepDate to App Group")
        }

        // Migrate authorization requested flag
        if standardDefaults.bool(forKey: Self.authorizationRequestedKey),
           !Self.sharedDefaults.bool(forKey: Self.authorizationRequestedKey) {
            Self.sharedDefaults.set(true, forKey: Self.authorizationRequestedKey)
            print("Migrated authorizationRequested to App Group")
        }

        // Mark migration as completed
        Self.sharedDefaults.set(true, forKey: Self.migrationCompletedKey)
        print("HealthKit UserDefaults migration completed")
    }

    // MARK: - Authorization

    /// Request HealthKit authorization for all supported data types
    @MainActor
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            print("HealthKit is not available on this device")
            return
        }

        // Build set of types to read
        var typesToRead: Set<HKSampleType> = []

        for category in HealthDataCategory.allCases {
            if let sampleType = category.hkSampleType {
                typesToRead.insert(sampleType)
            }
        }

        // Add heart rate for workout enrichment
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(heartRateType)
        }

        // We don't write any data
        let typesToWrite: Set<HKSampleType> = []

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

        // Mark that we've requested authorization
        // Note: HealthKit doesn't tell us if the user granted or denied read access for privacy reasons.
        // If the request completed without throwing, the user has seen the permission prompt.
        authorizationRequested = true

        print("HealthKit authorization completed")
    }

    /// Check if we have sufficient authorization for HealthKit monitoring
    /// Note: For read-only access, HealthKit doesn't report actual status for privacy.
    /// We rely on whether the user has been prompted for authorization.
    var hasHealthKitAuthorization: Bool {
        isAuthorized
    }

    /// Reset authorization state (for debugging/testing)
    func resetAuthorizationState() {
        authorizationRequested = false
    }

    // MARK: - Monitoring Management

    /// Start monitoring all enabled HealthKit categories
    func startMonitoringAllConfigurations() {
        guard isHealthKitAvailable else {
            print("HealthKit is not available on this device")
            return
        }

        let enabledCategories = HealthKitSettings.shared.enabledCategories

        for category in enabledCategories {
            startMonitoring(category: category)
        }

        print("Started monitoring \(enabledCategories.count) HealthKit configurations")
    }

    /// Start monitoring a specific HealthKit category
    /// - Parameter category: The HealthKit data category to monitor
    func startMonitoring(category: HealthDataCategory) {
        // Skip if already monitoring this category
        if observerQueries[category] != nil {
            print("Already monitoring \(category.displayName)")
            return
        }

        guard let sampleType = category.hkSampleType else {
            print("No sample type for category: \(category.displayName)")
            return
        }

        Task {
            // Only request authorization if HealthKit says we need to
            // This prevents showing prompts for already-authorized categories
            if await shouldRequestAuthorization(for: sampleType) {
                await requestAuthorizationForCategory(category)
            }
            await startObserverQuery(for: category, sampleType: sampleType)
        }
    }

    /// Request authorization for a specific HealthKit category
    @MainActor
    private func requestAuthorizationForCategory(_ category: HealthDataCategory) async {
        guard isHealthKitAvailable else { return }

        var typesToRead: Set<HKSampleType> = []

        if let sampleType = category.hkSampleType {
            typesToRead.insert(sampleType)
        }

        // Add heart rate for workout enrichment
        if category == .workout, let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(heartRateType)
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            authorizationRequested = true
            print("✅ HealthKit: Authorization requested for \(category.displayName)")
        } catch {
            print("⚠️ HealthKit: Failed to request authorization for \(category.displayName): \(error.localizedDescription)")
        }
    }

    /// Check if authorization needs to be requested for a specific type
    /// Uses HealthKit's official API to determine if the user has already seen the permission prompt
    private func shouldRequestAuthorization(for type: HKSampleType) async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [type]) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }

    /// Start the observer query for a category (called after authorization)
    @MainActor
    private func startObserverQuery(for category: HealthDataCategory, sampleType: HKSampleType) async {
        // Double-check we're not already monitoring
        guard observerQueries[category] == nil else { return }

        // Create observer query
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self = self else {
                completionHandler()
                return
            }

            if let error = error {
                print("Observer query error for \(category.displayName): \(error.localizedDescription)")
                completionHandler()
                return
            }

            print("HealthKit update received for \(category.displayName)")

            // Process new samples
            Task {
                await self.handleNewSamples(for: category)
            }

            completionHandler()
        }

        healthStore.execute(query)
        observerQueries[category] = query

        // Enable background delivery
        await enableBackgroundDelivery(for: category)

        print("Started monitoring: \(category.displayName)")
    }

    /// Stop monitoring a specific HealthKit category
    /// - Parameter category: The HealthKit data category to stop monitoring
    func stopMonitoring(category: HealthDataCategory) {
        if let query = observerQueries[category] {
            healthStore.stop(query)
            observerQueries.removeValue(forKey: category)
            print("Stopped monitoring: \(category.displayName)")
        }
    }

    /// Stop monitoring all HealthKit configurations
    func stopMonitoringAll() {
        for (category, query) in observerQueries {
            healthStore.stop(query)
            print("Stopped monitoring: \(category.displayName)")
        }
        observerQueries.removeAll()
    }

    /// Refresh monitored configurations
    func refreshMonitoring() {
        stopMonitoringAll()
        startMonitoringAllConfigurations()
    }

    // MARK: - Background Delivery

    /// Enable background delivery for a specific category
    private func enableBackgroundDelivery(for category: HealthDataCategory) async {
        guard let sampleType = category.hkSampleType else { return }

        do {
            try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: category.backgroundDeliveryFrequency)
            print("Background delivery enabled for \(category.displayName)")
        } catch {
            print("Failed to enable background delivery for \(category.displayName): \(error.localizedDescription)")
        }
    }

    // MARK: - Sample Processing

    /// Handle new samples for a category
    @MainActor
    private func handleNewSamples(for category: HealthDataCategory) async {
        guard let sampleType = category.hkSampleType else { return }

        // Create predicate for recent samples (last 24 hours to catch any missed)
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)

        // Execute query
        let samples = await withCheckedContinuation { (continuation: CheckedContinuation<[HKSample], Never>) in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    print("Sample query error for \(category.displayName): \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }

        // Process samples based on category
        for sample in samples {
            await processSample(sample, category: category)
        }
    }

    /// Process a single sample based on its category
    @MainActor
    private func processSample(_ sample: HKSample, category: HealthDataCategory) async {
        // Check for duplicates using individual sample UUID
        let sampleId = sample.uuid.uuidString
        guard !processedSampleIds.contains(sampleId) else {
            return
        }

        switch category {
        case .workout:
            if let workout = sample as? HKWorkout {
                await processWorkoutSample(workout)
            }
        case .sleep:
            if let categorySample = sample as? HKCategorySample {
                await processSleepSample(categorySample)
            }
        case .steps:
            // Steps are handled via daily aggregation
            // Mark this individual sample as processed first to avoid redundant calls
            markSampleAsProcessed(sampleId)
            await aggregateDailySteps()
        case .activeEnergy:
            if let quantitySample = sample as? HKQuantitySample {
                // Mark this individual sample as processed first to avoid redundant calls
                markSampleAsProcessed(sampleId)
                await processActiveEnergySample(quantitySample)
            }
        case .mindfulness:
            if let categorySample = sample as? HKCategorySample {
                await processMindfulnessSample(categorySample)
            }
        case .water:
            if let quantitySample = sample as? HKQuantitySample {
                await processWaterSample(quantitySample)
            }
        }
    }

    // MARK: - Workout Processing

    /// Process a workout sample
    @MainActor
    private func processWorkoutSample(_ workout: HKWorkout) async {
        let sampleId = workout.uuid.uuidString

        // In-memory duplicate check (fast path)
        guard !processedSampleIds.contains(sampleId) else { return }

        // Database-level duplicate check (handles race conditions where observer fires twice)
        // This is critical because multiple concurrent calls can pass the in-memory check
        // before either marks the sample as processed
        if await eventExistsWithHealthKitSampleId(sampleId) {
            Log.data.debug("Workout already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add("workoutType", workout.workoutActivityType.name)
            })
            markSampleAsProcessed(sampleId)
            return
        }

        print("Processing workout: \(workout.workoutActivityType.name)")

        // Ensure EventType exists
        guard let eventType = await ensureEventType(for: .workout) else {
            print("Failed to get/create EventType for workout")
            return
        }

        // Fetch heart rate stats for this workout
        let (avgHR, maxHR) = await fetchHeartRateStats(for: workout)

        // Build properties
        var properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: workout.duration),
            "Workout Type": PropertyValue(type: .text, value: workout.workoutActivityType.name),
            "Started At": PropertyValue(type: .date, value: workout.startDate),
            "Ended At": PropertyValue(type: .date, value: workout.endDate)
        ]

        // Add calories if available
        if let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) {
            properties["Calories"] = PropertyValue(type: .number, value: calories)
        }

        // Add distance if available
        if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
            properties["Distance (m)"] = PropertyValue(type: .number, value: distance)
        }

        // Add heart rate if available
        if let avgHR = avgHR {
            properties["Avg Heart Rate"] = PropertyValue(type: .number, value: avgHR)
        }
        if let maxHR = maxHR {
            properties["Max Heart Rate"] = PropertyValue(type: .number, value: maxHR)
        }

        // Create event
        await createEvent(
            eventType: eventType,
            category: .workout,
            timestamp: workout.startDate,
            endDate: workout.endDate,
            notes: "Auto-logged: \(workout.workoutActivityType.name)",
            properties: properties,
            healthKitSampleId: sampleId
        )

        // Mark as processed
        markSampleAsProcessed(sampleId)
    }

    /// Fetch heart rate statistics for a workout
    private func fetchHeartRateStats(for workout: HKWorkout) async -> (avg: Double?, max: Double?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let values = samples.map { $0.quantity.doubleValue(for: bpmUnit) }

                let avg = values.reduce(0, +) / Double(values.count)
                let max = values.max()

                continuation.resume(returning: (avg, max))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Processing (Daily Aggregation)

    /// Process a sleep sample - redirects to daily aggregation
    @MainActor
    private func processSleepSample(_ sample: HKCategorySample) async {
        // Sleep is handled via daily aggregation, similar to steps
        await aggregateDailySleep()
    }

    /// Aggregate daily sleep and create a single event per night
    /// Sleep sessions are attributed to the day they end (wake-up day)
    /// Improved to handle third-party apps (EightSleep, Whoop) that may sync data with delays
    @MainActor
    private func aggregateDailySleep() async {
        let calendar = Calendar.current
        let now = Date()

        // Query a broader window to catch late-synced data from third-party apps
        // Look back 48 hours to ensure we don't miss any sleep sessions
        let queryStart = calendar.date(byAdding: .hour, value: -48, to: now) ?? now
        let queryEnd = now

        print("🌙 Sleep aggregation: querying \(queryStart) to \(queryEnd)")

        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)

        let samples = await withCheckedContinuation { (continuation: CheckedContinuation<[HKCategorySample], Never>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error = error {
                    print("🌙 Sleep query error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        print("🌙 Found \(samples.count) sleep samples")

        if samples.isEmpty {
            print("🌙 No sleep samples found in HealthKit")
            return
        }

        // Group samples by "sleep night" based on when sleep ended
        // Sleep ending before noon = attribute to previous day
        // Sleep ending after noon = attribute to that day (likely a nap)
        var sleepNights: [Date: [HKCategorySample]] = [:]

        for sample in samples {
            let endHour = calendar.component(.hour, from: sample.endDate)
            let sleepDate: Date
            if endHour < 12 {
                // Sleep ended before noon - attribute to previous day
                sleepDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: sample.endDate)) ?? sample.endDate
            } else {
                // Sleep ended after noon - attribute to that day
                sleepDate = calendar.startOfDay(for: sample.endDate)
            }
            sleepNights[sleepDate, default: []].append(sample)
        }

        print("🌙 Grouped into \(sleepNights.count) sleep night(s)")

        // Process each sleep night
        for (sleepDate, nightSamples) in sleepNights.sorted(by: { $0.key < $1.key }) {
            let sampleId = "sleep-\(Self.dateOnlyFormatter.string(from: sleepDate))"

            // Skip if already processed
            if processedSampleIds.contains(sampleId) {
                print("🌙 Already processed: \(sampleId)")
                continue
            }

            // Database-level deduplication
            if await eventExistsWithHealthKitSampleId(sampleId) {
                print("🌙 Already in database: \(sampleId)")
                markSampleAsProcessed(sampleId)
                continue
            }

            // Aggregate this night's samples
            var totalSleepDuration: TimeInterval = 0
            var coreSleepDuration: TimeInterval = 0
            var deepSleepDuration: TimeInterval = 0
            var remSleepDuration: TimeInterval = 0
            var awakeDuration: TimeInterval = 0
            var sleepStart: Date?
            var sleepEnd: Date?

            for sample in nightSamples {
                guard let sleepValue = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
                let duration = sample.endDate.timeIntervalSince(sample.startDate)

                switch sleepValue {
                case .inBed:
                    if sleepStart == nil || sample.startDate < sleepStart! { sleepStart = sample.startDate }
                    if sleepEnd == nil || sample.endDate > sleepEnd! { sleepEnd = sample.endDate }
                case .asleepUnspecified:
                    totalSleepDuration += duration
                case .asleepCore:
                    coreSleepDuration += duration
                    totalSleepDuration += duration
                case .asleepDeep:
                    deepSleepDuration += duration
                    totalSleepDuration += duration
                case .asleepREM:
                    remSleepDuration += duration
                    totalSleepDuration += duration
                case .awake:
                    awakeDuration += duration
                @unknown default:
                    break
                }

                // Track sleep start/end from actual sleep samples
                if sleepValue != .awake && sleepValue != .inBed {
                    if sleepStart == nil || sample.startDate < sleepStart! { sleepStart = sample.startDate }
                    if sleepEnd == nil || sample.endDate > sleepEnd! { sleepEnd = sample.endDate }
                }
            }

            // Require at least 30 minutes of sleep
            guard totalSleepDuration >= 1800 else {
                print("🌙 Not enough sleep for \(sampleId): \(Int(totalSleepDuration / 60)) minutes")
                continue
            }

            let hours = Int(totalSleepDuration / 3600)
            let minutes = Int((totalSleepDuration.truncatingRemainder(dividingBy: 3600)) / 60)
            print("🌙 Creating event for \(sampleId): \(hours)h \(minutes)m")

            guard let eventType = await ensureEventType(for: .sleep) else {
                print("🌙 Failed to get/create EventType for sleep")
                continue
            }

            // Build properties
            var properties: [String: PropertyValue] = [
                "Total Sleep": PropertyValue(type: .duration, value: totalSleepDuration),
                "Date": PropertyValue(type: .date, value: sleepDate)
            ]

            if let start = sleepStart {
                properties["Bedtime"] = PropertyValue(type: .date, value: start)
            }
            if let end = sleepEnd {
                properties["Wake Time"] = PropertyValue(type: .date, value: end)
            }
            if coreSleepDuration > 0 {
                properties["Core Sleep"] = PropertyValue(type: .duration, value: coreSleepDuration)
            }
            if deepSleepDuration > 0 {
                properties["Deep Sleep"] = PropertyValue(type: .duration, value: deepSleepDuration)
            }
            if remSleepDuration > 0 {
                properties["REM Sleep"] = PropertyValue(type: .duration, value: remSleepDuration)
            }
            if awakeDuration > 0 {
                properties["Time Awake"] = PropertyValue(type: .duration, value: awakeDuration)
            }

            let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

            await createEvent(
                eventType: eventType,
                category: .sleep,
                timestamp: sleepStart ?? sleepDate,
                endDate: sleepEnd,
                notes: "Auto-logged: \(durationText) of sleep",
                properties: properties,
                healthKitSampleId: sampleId
            )

            markSampleAsProcessed(sampleId)
            lastSleepDate = sleepDate
            saveLastSleepDate()
        }
    }

    // MARK: - Steps Processing (Daily Aggregation)

    /// Aggregate daily steps and create a single event per day
    @MainActor
    private func aggregateDailySteps() async {
        let today = Calendar.current.startOfDay(for: Date())

        // Use consistent date-only format for sampleId (no timezone issues)
        let sampleId = "steps-\(Self.dateOnlyFormatter.string(from: today))"

        // Throttle: don't process more than once per 5 minutes for the same day
        // This prevents excessive processing while still allowing updates throughout the day
        if let lastDate = lastStepDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today),
           Date().timeIntervalSince(lastDate) < 300 {
            return
        }

        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let startOfDay = today
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        let totalSteps = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }

        guard let steps = totalSteps, steps > 0 else { return }

        // Check for existing event to update
        if let existingEvent = await findEventByHealthKitSampleId(sampleId) {
            // Compare values - only update if step count changed significantly (>= 1 step)
            let existingSteps = existingEvent.properties["Step Count"]?.doubleValue ?? 0
            if abs(existingSteps - steps) < 1 {
                // No significant change, skip update but update throttle timestamp
                lastStepDate = Date()
                saveLastStepDate()
                return
            }

            Log.data.info("Updating daily steps", context: .with { ctx in
                ctx.add("previousSteps", Int(existingSteps))
                ctx.add("newSteps", Int(steps))
            })

            let properties: [String: PropertyValue] = [
                "Step Count": PropertyValue(type: .number, value: steps),
                "Date": PropertyValue(type: .date, value: today)
            ]

            await updateHealthKitEvent(
                existingEvent,
                properties: properties,
                notes: "Auto-logged: \(Int(steps)) steps"
            )

            lastStepDate = Date()
            saveLastStepDate()
            return
        }

        // No existing event - create new one
        Log.data.info("Creating daily steps event", context: .with { ctx in
            ctx.add("steps", Int(steps))
        })

        guard let eventType = await ensureEventType(for: .steps) else {
            Log.data.error("Failed to get/create EventType for steps")
            return
        }

        let properties: [String: PropertyValue] = [
            "Step Count": PropertyValue(type: .number, value: steps),
            "Date": PropertyValue(type: .date, value: today)
        ]

        await createEvent(
            eventType: eventType,
            category: .steps,
            timestamp: today,
            endDate: nil,
            notes: "Auto-logged: \(Int(steps)) steps",
            properties: properties,
            healthKitSampleId: sampleId
        )

        // Don't mark as processed - daily aggregates can be updated throughout the day
        lastStepDate = Date()
        saveLastStepDate()
    }

    // MARK: - Active Energy Processing

    /// Process an active energy sample
    @MainActor
    private func processActiveEnergySample(_ sample: HKQuantitySample) async {
        // For active energy, we aggregate daily similar to steps
        // Skip individual samples and do daily aggregation
        await aggregateDailyActiveEnergy()
    }

    /// Aggregate daily active energy
    @MainActor
    private func aggregateDailyActiveEnergy() async {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        let today = Calendar.current.startOfDay(for: Date())

        // Use consistent date-only format for sampleId (no timezone issues)
        let sampleId = "activeEnergy-\(Self.dateOnlyFormatter.string(from: today))"

        // Throttle: don't process more than once per 5 minutes for the same day
        // This prevents excessive processing while still allowing updates throughout the day
        if let lastDate = lastActiveEnergyDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today),
           Date().timeIntervalSince(lastDate) < 300 {
            return
        }

        let startOfDay = today
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        let totalCalories = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: .kilocalorie()))
            }
            healthStore.execute(query)
        }

        guard let calories = totalCalories, calories > 0 else { return }

        // Check for existing event to update
        if let existingEvent = await findEventByHealthKitSampleId(sampleId) {
            // Compare values - only update if calories changed significantly (>= 1 kcal)
            let existingCalories = existingEvent.properties["Calories"]?.doubleValue ?? 0
            if abs(existingCalories - calories) < 1 {
                // No significant change, skip update but update throttle timestamp
                lastActiveEnergyDate = Date()
                saveLastActiveEnergyDate()
                return
            }

            Log.data.info("Updating daily active energy", context: .with { ctx in
                ctx.add("previousCalories", Int(existingCalories))
                ctx.add("newCalories", Int(calories))
            })

            let properties: [String: PropertyValue] = [
                "Calories": PropertyValue(type: .number, value: calories),
                "Date": PropertyValue(type: .date, value: today)
            ]

            await updateHealthKitEvent(
                existingEvent,
                properties: properties,
                notes: "Auto-logged: \(Int(calories)) kcal burned"
            )

            lastActiveEnergyDate = Date()
            saveLastActiveEnergyDate()
            return
        }

        // No existing event - create new one
        Log.data.info("Creating daily active energy event", context: .with { ctx in
            ctx.add("calories", Int(calories))
        })

        guard let eventType = await ensureEventType(for: .activeEnergy) else {
            Log.data.error("Failed to get/create EventType for activeEnergy")
            return
        }

        let properties: [String: PropertyValue] = [
            "Calories": PropertyValue(type: .number, value: calories),
            "Date": PropertyValue(type: .date, value: today)
        ]

        await createEvent(
            eventType: eventType,
            category: .activeEnergy,
            timestamp: today,
            endDate: nil,
            notes: "Auto-logged: \(Int(calories)) kcal burned",
            properties: properties,
            healthKitSampleId: sampleId
        )

        // Don't mark as processed - daily aggregates can be updated throughout the day
        lastActiveEnergyDate = Date()
        saveLastActiveEnergyDate()
    }

    // MARK: - Mindfulness Processing

    /// Process a mindfulness sample
    @MainActor
    private func processMindfulnessSample(_ sample: HKCategorySample) async {
        let sampleId = sample.uuid.uuidString

        // In-memory duplicate check (fast path)
        guard !processedSampleIds.contains(sampleId) else { return }

        // Database-level duplicate check (handles race conditions)
        if await eventExistsWithHealthKitSampleId(sampleId) {
            Log.data.debug("Mindfulness session already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
            })
            markSampleAsProcessed(sampleId)
            return
        }

        print("Processing mindfulness session")

        guard let eventType = await ensureEventType(for: .mindfulness) else { return }

        let duration = sample.endDate.timeIntervalSince(sample.startDate)

        let properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: duration),
            "Started At": PropertyValue(type: .date, value: sample.startDate)
        ]

        await createEvent(
            eventType: eventType,
            category: .mindfulness,
            timestamp: sample.startDate,
            endDate: sample.endDate,
            notes: "Auto-logged: Mindfulness session",
            properties: properties,
            healthKitSampleId: sampleId
        )

        markSampleAsProcessed(sampleId)
    }

    // MARK: - Water Processing

    /// Process a water intake sample
    @MainActor
    private func processWaterSample(_ sample: HKQuantitySample) async {
        let sampleId = sample.uuid.uuidString

        // In-memory duplicate check (fast path)
        guard !processedSampleIds.contains(sampleId) else { return }

        // Database-level duplicate check (handles race conditions)
        if await eventExistsWithHealthKitSampleId(sampleId) {
            Log.data.debug("Water intake already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
            })
            markSampleAsProcessed(sampleId)
            return
        }

        let milliliters = sample.quantity.doubleValue(for: .literUnit(with: .milli))

        print("Processing water intake: \(Int(milliliters)) ml")

        guard let eventType = await ensureEventType(for: .water) else { return }

        let properties: [String: PropertyValue] = [
            "Amount (ml)": PropertyValue(type: .number, value: milliliters),
            "Time": PropertyValue(type: .date, value: sample.startDate)
        ]

        await createEvent(
            eventType: eventType,
            category: .water,
            timestamp: sample.startDate,
            endDate: nil,
            notes: "Auto-logged: \(Int(milliliters)) ml water",
            properties: properties,
            healthKitSampleId: sampleId
        )

        markSampleAsProcessed(sampleId)
    }

    // MARK: - Event Creation

    /// Create an event for a HealthKit sample
    @MainActor
    private func createEvent(
        eventType: EventType,
        category: HealthDataCategory,
        timestamp: Date,
        endDate: Date?,
        notes: String,
        properties: [String: PropertyValue],
        healthKitSampleId: String
    ) async {
        let event = Event(
            timestamp: timestamp,
            eventType: eventType,
            notes: notes,
            sourceType: .healthKit,
            isAllDay: false,
            endDate: endDate,
            healthKitSampleId: healthKitSampleId,
            healthKitCategory: category.rawValue,
            properties: properties
        )

        modelContext.insert(event)

        do {
            try modelContext.save()
            print("Created HealthKit event: \(category.displayName)")

            // Send notification if configured
            await sendNotificationIfEnabled(for: category, eventTypeName: eventType.name, details: notes)

            // Sync to backend (SyncEngine handles offline queueing)
            await eventStore.syncEventToBackend(event)

        } catch {
            print("Failed to save HealthKit event: \(error.localizedDescription)")
        }
    }

    /// Check if an event with the given HealthKit sample ID already exists in SwiftData
    /// This provides database-level deduplication as a final safety net
    @MainActor
    private func eventExistsWithHealthKitSampleId(_ sampleId: String) async -> Bool {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitSampleId == sampleId
            }
        )

        do {
            let existingEvents = try modelContext.fetch(descriptor)
            return !existingEvents.isEmpty
        } catch {
            print("Error checking for existing HealthKit event: \(error.localizedDescription)")
            // In case of error, assume it doesn't exist to avoid blocking new events
            return false
        }
    }

    /// Find an event by its HealthKit sample ID
    /// Returns the actual Event object for updates, not just existence check
    @MainActor
    private func findEventByHealthKitSampleId(_ sampleId: String) async -> Event? {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitSampleId == sampleId
            }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Log.data.error("Error finding HealthKit event", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add(error: error)
            })
            return nil
        }
    }

    /// Update an existing HealthKit event with new values
    /// Used when daily aggregated metrics (steps, active energy) change throughout the day
    @MainActor
    private func updateHealthKitEvent(
        _ event: Event,
        properties: [String: PropertyValue],
        notes: String
    ) async {
        event.properties = properties
        event.notes = notes
        event.syncStatus = .pending

        do {
            try modelContext.save()
            Log.data.info("Updated HealthKit event locally", context: .with { ctx in
                ctx.add("category", event.healthKitCategory ?? "unknown")
                ctx.add("sampleId", event.healthKitSampleId ?? "none")
                ctx.add("event_id", event.id)
            })

            // Use UPDATE sync (not CREATE) to ensure backend receives the new values
            // CREATE would return 409 Conflict for existing events and the update would be lost
            await eventStore.syncHealthKitEventUpdate(event)
        } catch {
            Log.data.error("Failed to update HealthKit event", context: .with { ctx in
                ctx.add(error: error)
            })
        }
    }

    // MARK: - Auto-Create EventType

    /// Ensures an EventType exists for the category, creating one if needed
    @MainActor
    private func ensureEventType(for category: HealthDataCategory) async -> EventType? {
        let settings = HealthKitSettings.shared

        // 1. Check if settings already has a linked EventType (by id)
        if let eventTypeId = settings.eventTypeId(for: category) {
            let eventTypeDescriptor = FetchDescriptor<EventType>(
                predicate: #Predicate { eventType in eventType.id == eventTypeId }
            )
            if let eventType = try? modelContext.fetch(eventTypeDescriptor).first {
                return eventType
            }
            // ID stored but EventType not found locally - might need sync
            print("⚠️ HealthKit: EventType with id \(eventTypeId) not found locally for \(category.displayName)")
        }

        // 2. Check if an EventType with the default name already exists
        let defaultName = category.defaultEventTypeName
        let existingDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { eventType in eventType.name == defaultName }
        )

        if let existing = try? modelContext.fetch(existingDescriptor).first {
            // Link existing EventType to settings using id
            settings.setEventTypeId(existing.id, for: category)
            return existing
        }

        // 3. Create new EventType with defaults (UUIDv7 id is immediately available)
        let newEventType = EventType(
            name: category.defaultEventTypeName,
            colorHex: category.defaultColor,
            iconName: category.defaultIcon
        )
        modelContext.insert(newEventType)

        do {
            try modelContext.save()
        } catch {
            print("Failed to create EventType for \(category.displayName): \(error.localizedDescription)")
            return nil
        }

        // 4. Sync to backend (SyncEngine handles offline queueing)
        await eventStore.syncEventTypeToBackend(newEventType)

        // 5. Link new EventType to settings using id (available immediately with UUIDv7)
        settings.setEventTypeId(newEventType.id, for: category)

        print("Auto-created EventType '\(newEventType.name)' for \(category.rawValue)")
        return newEventType
    }

    // MARK: - Notifications

    /// Send notification if enabled for this category
    private func sendNotificationIfEnabled(for category: HealthDataCategory, eventTypeName: String, details: String?) async {
        // Check if notifications are enabled for this category using HealthKitSettings
        guard HealthKitSettings.shared.notifyOnDetection(for: category) else { return }
        guard let notificationManager = notificationManager else { return }

        await notificationManager.sendNotification(
            title: "\(category.displayName) Detected",
            body: details ?? "Logged: \(eventTypeName)",
            categoryIdentifier: "HEALTHKIT_DETECTION"
        )
    }

    // MARK: - Persistence

    /// Mark a sample ID as processed
    private func markSampleAsProcessed(_ sampleId: String) {
        processedSampleIds.insert(sampleId)

        // Limit set size using FIFO
        if processedSampleIds.count > maxProcessedSampleIds {
            // Remove oldest entries (this is approximate since Set doesn't maintain order)
            let excess = processedSampleIds.count - maxProcessedSampleIds
            for _ in 0..<excess {
                if let first = processedSampleIds.first {
                    processedSampleIds.remove(first)
                }
            }
        }

        saveProcessedSampleIds()
    }

    /// Load processed sample IDs from shared UserDefaults (persists across reinstalls)
    private func loadProcessedSampleIds() {
        if let data = Self.sharedDefaults.data(forKey: processedSampleIdsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            processedSampleIds = decoded
        }
    }

    /// Save processed sample IDs to shared UserDefaults (persists across reinstalls)
    private func saveProcessedSampleIds() {
        if let encoded = try? JSONEncoder().encode(processedSampleIds) {
            Self.sharedDefaults.set(encoded, forKey: processedSampleIdsKey)
        }
    }

    /// Load last step date from shared UserDefaults (persists across reinstalls)
    private func loadLastStepDate() {
        lastStepDate = Self.sharedDefaults.object(forKey: lastStepDateKey) as? Date
    }

    /// Save last step date to shared UserDefaults (persists across reinstalls)
    private func saveLastStepDate() {
        Self.sharedDefaults.set(lastStepDate, forKey: lastStepDateKey)
    }

    /// Load last sleep date from shared UserDefaults (persists across reinstalls)
    private func loadLastSleepDate() {
        lastSleepDate = Self.sharedDefaults.object(forKey: lastSleepDateKey) as? Date
    }

    /// Save last sleep date to shared UserDefaults (persists across reinstalls)
    private func saveLastSleepDate() {
        Self.sharedDefaults.set(lastSleepDate, forKey: lastSleepDateKey)
    }

    /// Load last active energy date from shared UserDefaults (persists across reinstalls)
    private func loadLastActiveEnergyDate() {
        lastActiveEnergyDate = Self.sharedDefaults.object(forKey: lastActiveEnergyDateKey) as? Date
    }

    /// Save last active energy date to shared UserDefaults (persists across reinstalls)
    private func saveLastActiveEnergyDate() {
        Self.sharedDefaults.set(lastActiveEnergyDate, forKey: lastActiveEnergyDateKey)
    }

    // MARK: - Debug Properties (Available in all builds)

    /// Debug: Last sleep date for diagnostics
    var lastSleepDateDebug: Date? { lastSleepDate }

    /// Debug: Last step date for diagnostics
    var lastStepDateDebug: Date? { lastStepDate }

    /// Debug: Last active energy date for diagnostics
    var lastActiveEnergyDateDebug: Date? { lastActiveEnergyDate }

    /// Debug: Active observer categories
    var activeObserverCategories: [HealthDataCategory] {
        Array(observerQueries.keys)
    }

    /// Debug: Count of processed sample IDs
    var processedSampleIdsCount: Int {
        processedSampleIds.count
    }

    /// Debug: Whether using App Group storage
    var isUsingAppGroupStorage: Bool {
        Self.isUsingAppGroup
    }

    /// Debug: Query daily step counts from HealthKit for the last 7 days
    func debugQueryStepData() async -> [(date: Date, steps: Double, source: String)] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()
        let queryStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now

        var results: [(date: Date, steps: Double, source: String)] = []

        // Query each day separately for better granularity
        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

            let daySteps = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    guard let sum = statistics?.sumQuantity() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: sum.doubleValue(for: .count()))
                }
                healthStore.execute(query)
            }

            if let steps = daySteps, steps > 0 {
                results.append((date: dayStart, steps: steps, source: "HealthKit"))
            }
        }

        return results.sorted { $0.date > $1.date }
    }

    /// Debug: Query daily active energy totals from HealthKit for the last 7 days
    func debugQueryActiveEnergyData() async -> [(date: Date, calories: Double, source: String)] {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()

        var results: [(date: Date, calories: Double, source: String)] = []

        // Query each day separately for better granularity
        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

            let dayCalories = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
                let query = HKStatisticsQuery(
                    quantityType: energyType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    guard let sum = statistics?.sumQuantity() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: sum.doubleValue(for: .kilocalorie()))
                }
                healthStore.execute(query)
            }

            if let calories = dayCalories, calories > 0 {
                results.append((date: dayStart, calories: calories, source: "HealthKit"))
            }
        }

        return results.sorted { $0.date > $1.date }
    }

    /// Debug: Query workout data from HealthKit for the last 7 days
    func debugQueryWorkoutData() async -> [(start: Date, end: Date, duration: TimeInterval, workoutType: String, calories: Double?, distance: Double?, source: String)] {
        let calendar = Calendar.current
        let now = Date()
        let queryStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: now, options: .strictStartDate)

        return await withCheckedContinuation { (continuation: CheckedContinuation<[(start: Date, end: Date, duration: TimeInterval, workoutType: String, calories: Double?, distance: Double?, source: String)], Never>) in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, error in
                if let error = error {
                    print("Debug workout query error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let workouts = results as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let data = workouts.map { workout -> (start: Date, end: Date, duration: TimeInterval, workoutType: String, calories: Double?, distance: Double?, source: String) in
                    let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    let distance = workout.totalDistance?.doubleValue(for: .meter())

                    return (
                        start: workout.startDate,
                        end: workout.endDate,
                        duration: workout.duration,
                        workoutType: workout.workoutActivityType.name,
                        calories: calories,
                        distance: distance,
                        source: workout.sourceRevision.source.name
                    )
                }

                continuation.resume(returning: data)
            }
            healthStore.execute(query)
        }
    }

    /// Debug: Query raw sleep data from HealthKit for the last 48 hours
    func debugQuerySleepData() async -> [(start: Date, end: Date, duration: TimeInterval, sleepType: String, source: String)] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()
        let queryStart = calendar.date(byAdding: .hour, value: -48, to: now) ?? now

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: now, options: .strictStartDate)

        return await withCheckedContinuation { (continuation: CheckedContinuation<[(start: Date, end: Date, duration: TimeInterval, sleepType: String, source: String)], Never>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, error in
                if let error = error {
                    print("Debug sleep query error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let data = samples.map { sample -> (start: Date, end: Date, duration: TimeInterval, sleepType: String, source: String) in
                    let sleepValue = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    let sleepTypeStr: String
                    switch sleepValue {
                    case .inBed: sleepTypeStr = "In Bed"
                    case .asleepUnspecified: sleepTypeStr = "Asleep"
                    case .asleepCore: sleepTypeStr = "Core"
                    case .asleepDeep: sleepTypeStr = "Deep"
                    case .asleepREM: sleepTypeStr = "REM"
                    case .awake: sleepTypeStr = "Awake"
                    default: sleepTypeStr = "Unknown (\(sample.value))"
                    }

                    return (
                        start: sample.startDate,
                        end: sample.endDate,
                        duration: sample.endDate.timeIntervalSince(sample.startDate),
                        sleepType: sleepTypeStr,
                        source: sample.sourceRevision.source.name
                    )
                }

                continuation.resume(returning: data)
            }
            healthStore.execute(query)
        }
    }

    /// Debug: Force sleep aggregation check (bypasses date cache)
    func forceSleepCheck() async {
        print("🔧 Debug: Forcing sleep aggregation check...")
        // Temporarily clear the lastSleepDate to force a check
        let savedDate = lastSleepDate
        lastSleepDate = nil
        await aggregateDailySleep()
        // If no event was created, restore the date
        if lastSleepDate == nil {
            lastSleepDate = savedDate
        }
    }

    /// Debug: Force steps aggregation check (bypasses date cache)
    @MainActor
    func forceStepsCheck() async {
        print("🔧 Debug: Forcing steps aggregation check...")
        // Temporarily clear the lastStepDate to force a check
        let savedDate = lastStepDate
        lastStepDate = nil

        // Also remove the daily step sampleId from processed set
        let today = Calendar.current.startOfDay(for: Date())
        let sampleId = "steps-\(Self.dateOnlyFormatter.string(from: today))"
        processedSampleIds.remove(sampleId)

        await aggregateDailySteps()

        // If no event was created, restore the date
        if lastStepDate == nil {
            lastStepDate = savedDate
        }
    }

    /// Debug: Force active energy aggregation check (bypasses date cache)
    @MainActor
    func forceActiveEnergyCheck() async {
        print("🔧 Debug: Forcing active energy aggregation check...")
        // Temporarily clear the lastActiveEnergyDate to force a check
        let savedDate = lastActiveEnergyDate
        lastActiveEnergyDate = nil

        // Also remove the daily active energy sampleId from processed set
        let today = Calendar.current.startOfDay(for: Date())
        let sampleId = "activeEnergy-\(Self.dateOnlyFormatter.string(from: today))"
        processedSampleIds.remove(sampleId)

        await aggregateDailyActiveEnergy()

        // If no event was created, restore the date
        if lastActiveEnergyDate == nil {
            lastActiveEnergyDate = savedDate
        }
    }

    /// Debug: Force refresh all enabled HealthKit categories
    /// This actively queries HealthKit for each category instead of waiting for observer callbacks
    @MainActor
    func forceRefreshAllCategories() async {
        print("🔧 Debug: Force refreshing all HealthKit categories...")
        let enabledCategories = HealthKitSettings.shared.enabledCategories

        for category in enabledCategories {
            print("🔧 Refreshing: \(category.displayName)")
            await handleNewSamples(for: category)
        }

        print("🔧 Debug: Force refresh complete for \(enabledCategories.count) categories")
    }

    /// Debug: Clear sleep processing cache
    func clearSleepCache() {
        print("🔧 Debug: Clearing sleep cache...")
        lastSleepDate = nil
        Self.sharedDefaults.removeObject(forKey: lastSleepDateKey)

        // Remove sleep-related processed sample IDs
        processedSampleIds = processedSampleIds.filter { !$0.hasPrefix("sleep-") }
        saveProcessedSampleIds()
        print("🔧 Debug: Sleep cache cleared")
    }

    /// Debug: Clear steps processing cache
    func clearStepsCache() {
        print("🔧 Debug: Clearing steps cache...")
        lastStepDate = nil
        Self.sharedDefaults.removeObject(forKey: lastStepDateKey)

        // Remove steps-related processed sample IDs
        processedSampleIds = processedSampleIds.filter { !$0.hasPrefix("steps-") }
        saveProcessedSampleIds()
        print("🔧 Debug: Steps cache cleared")
    }

    /// Debug: Clear active energy processing cache
    func clearActiveEnergyCache() {
        print("🔧 Debug: Clearing active energy cache...")
        lastActiveEnergyDate = nil
        Self.sharedDefaults.removeObject(forKey: lastActiveEnergyDateKey)

        // Remove active energy-related processed sample IDs
        processedSampleIds = processedSampleIds.filter { !$0.hasPrefix("activeEnergy-") }
        saveProcessedSampleIds()
        print("🔧 Debug: Active energy cache cleared")
    }

    /// Debug: Refresh all observers
    func refreshAllObservers() {
        print("🔧 Debug: Refreshing all observers...")
        stopMonitoringAll()
        startMonitoringAllConfigurations()
    }

    // MARK: - Debug/Testing (Simulation)

    #if DEBUG || STAGING
    /// Simulate a workout detection for testing purposes
    func simulateWorkoutDetection() async {
        print("DEBUG: Simulating workout detection")

        guard let eventType = await ensureEventType(for: .workout) else {
            print("Failed to get/create EventType for simulated workout")
            return
        }

        let properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: 1800.0),
            "Calories": PropertyValue(type: .number, value: 250.0),
            "Workout Type": PropertyValue(type: .text, value: "Running"),
            "Started At": PropertyValue(type: .date, value: Date().addingTimeInterval(-1800)),
            "Ended At": PropertyValue(type: .date, value: Date())
        ]

        await createEvent(
            eventType: eventType,
            category: .workout,
            timestamp: Date().addingTimeInterval(-1800),
            endDate: Date(),
            notes: "Simulated: Running workout",
            properties: properties,
            healthKitSampleId: "sim-\(UUID().uuidString)"
        )
    }

    /// Simulate a sleep detection for testing purposes
    func simulateSleepDetection() async {
        print("DEBUG: Simulating sleep detection")

        guard let eventType = await ensureEventType(for: .sleep) else {
            print("Failed to get/create EventType for simulated sleep")
            return
        }

        let startDate = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
        let endDate = Date()

        let properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: endDate.timeIntervalSince(startDate)),
            "Sleep Stage": PropertyValue(type: .text, value: "Asleep"),
            "Started At": PropertyValue(type: .date, value: startDate),
            "Ended At": PropertyValue(type: .date, value: endDate)
        ]

        await createEvent(
            eventType: eventType,
            category: .sleep,
            timestamp: startDate,
            endDate: endDate,
            notes: "Simulated: Sleep",
            properties: properties,
            healthKitSampleId: "sim-\(UUID().uuidString)"
        )
    }
    #endif
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .cricket: return "Cricket"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian Sports"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind and Body"
        case .paddleSports: return "Paddle Sports"
        case .play: return "Play"
        case .preparationAndRecovery: return "Preparation and Recovery"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating Sports"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing Sports"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track and Field"
        case .traditionalStrengthTraining: return "Traditional Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .flexibility: return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .pilates: return "Pilates"
        case .snowboarding: return "Snowboarding"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .wheelchairWalkPace: return "Wheelchair Walk Pace"
        case .wheelchairRunPace: return "Wheelchair Run Pace"
        case .taiChi: return "Tai Chi"
        case .mixedCardio: return "Mixed Cardio"
        case .handCycling: return "Hand Cycling"
        case .discSports: return "Disc Sports"
        case .fitnessGaming: return "Fitness Gaming"
        case .cardioDance: return "Cardio Dance"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .cooldown: return "Cooldown"
        case .swimBikeRun: return "Triathlon"
        case .transition: return "Transition"
        case .underwaterDiving: return "Underwater Diving"
        default: return "Other"
        }
    }
}
