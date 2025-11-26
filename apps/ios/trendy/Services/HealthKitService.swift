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

    /// Current authorization status (simplified)
    var isAuthorized: Bool = false

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

    /// Anchors for incremental fetching
    private var queryAnchors: [HealthDataCategory: HKQueryAnchor] = [:]

    // MARK: - Constants

    private let processedSampleIdsKey = "healthKitProcessedSampleIds"
    private let lastStepDateKey = "healthKitLastStepDate"
    private let maxProcessedSampleIds = 1000

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

        loadProcessedSampleIds()
        loadLastStepDate()
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

        // Update authorization status
        await checkAuthorizationStatus()

        print("HealthKit authorization completed")
    }

    /// Check current authorization status
    @MainActor
    func checkAuthorizationStatus() async {
        // Check if we have authorization for at least workouts
        if let workoutType = HKWorkoutType.workoutType() as? HKObjectType {
            let status = healthStore.authorizationStatus(for: workoutType)
            isAuthorized = (status == .sharingAuthorized)
        }
    }

    /// Check if we have sufficient authorization for HealthKit monitoring
    var hasHealthKitAuthorization: Bool {
        isAuthorized
    }

    // MARK: - Monitoring Management

    /// Start monitoring all enabled HealthKit configurations
    func startMonitoringAllConfigurations() {
        guard isHealthKitAvailable else {
            print("HealthKit is not available on this device")
            return
        }

        // Fetch all enabled configurations from SwiftData
        let descriptor = FetchDescriptor<HealthKitConfiguration>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let configurations = try? modelContext.fetch(descriptor) else {
            print("Failed to fetch HealthKit configurations")
            return
        }

        for config in configurations {
            startMonitoring(configuration: config)
        }

        print("Started monitoring \(configurations.count) HealthKit configurations")
    }

    /// Start monitoring a specific HealthKit configuration
    /// - Parameter configuration: The HealthKit configuration to monitor
    func startMonitoring(configuration: HealthKitConfiguration) {
        let category = configuration.category

        // Skip if already monitoring this category
        if observerQueries[category] != nil {
            print("Already monitoring \(category.displayName)")
            return
        }

        guard let sampleType = category.hkSampleType else {
            print("No sample type for category: \(category.displayName)")
            return
        }

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
        Task {
            await enableBackgroundDelivery(for: category)
        }

        print("Started monitoring: \(category.displayName)")
    }

    /// Stop monitoring a specific HealthKit configuration
    /// - Parameter configuration: The HealthKit configuration to stop monitoring
    func stopMonitoring(configuration: HealthKitConfiguration) {
        let category = configuration.category

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
        // Check for duplicates
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
            await aggregateDailySteps()
        case .activeEnergy:
            if let quantitySample = sample as? HKQuantitySample {
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
        guard !processedSampleIds.contains(sampleId) else { return }

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

    // MARK: - Sleep Processing

    /// Process a sleep sample
    @MainActor
    private func processSleepSample(_ sample: HKCategorySample) async {
        let sampleId = sample.uuid.uuidString
        guard !processedSampleIds.contains(sampleId) else { return }

        // Determine sleep stage
        let sleepStage: String
        if let sleepValue = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            switch sleepValue {
            case .inBed:
                sleepStage = "In Bed"
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                sleepStage = "Asleep"
            case .awake:
                sleepStage = "Awake"
            @unknown default:
                sleepStage = "Unknown"
            }
        } else {
            sleepStage = "Unknown"
        }

        // Only track actual sleep, not "in bed" or "awake"
        guard sleepStage == "Asleep" else { return }

        print("Processing sleep: \(sleepStage)")

        guard let eventType = await ensureEventType(for: .sleep) else {
            print("Failed to get/create EventType for sleep")
            return
        }

        let duration = sample.endDate.timeIntervalSince(sample.startDate)

        let properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: duration),
            "Sleep Stage": PropertyValue(type: .text, value: sleepStage),
            "Started At": PropertyValue(type: .date, value: sample.startDate),
            "Ended At": PropertyValue(type: .date, value: sample.endDate)
        ]

        await createEvent(
            eventType: eventType,
            category: .sleep,
            timestamp: sample.startDate,
            endDate: sample.endDate,
            notes: "Auto-logged: Sleep",
            properties: properties,
            healthKitSampleId: sampleId
        )

        markSampleAsProcessed(sampleId)
    }

    // MARK: - Steps Processing (Daily Aggregation)

    /// Aggregate daily steps and create a single event per day
    @MainActor
    private func aggregateDailySteps() async {
        let today = Calendar.current.startOfDay(for: Date())

        // Skip if already processed today
        if let lastDate = lastStepDate, Calendar.current.isDate(lastDate, inSameDayAs: today) {
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

        print("Processing daily steps: \(Int(steps))")

        guard let eventType = await ensureEventType(for: .steps) else {
            print("Failed to get/create EventType for steps")
            return
        }

        let properties: [String: PropertyValue] = [
            "Step Count": PropertyValue(type: .number, value: steps),
            "Date": PropertyValue(type: .date, value: today)
        ]

        // Use date-based ID for deduplication
        let sampleId = "steps-\(ISO8601DateFormatter().string(from: today))"

        guard !processedSampleIds.contains(sampleId) else { return }

        await createEvent(
            eventType: eventType,
            category: .steps,
            timestamp: today,
            endDate: nil,
            notes: "Auto-logged: \(Int(steps)) steps",
            properties: properties,
            healthKitSampleId: sampleId
        )

        markSampleAsProcessed(sampleId)
        lastStepDate = today
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

        let sampleId = "activeEnergy-\(ISO8601DateFormatter().string(from: today))"
        guard !processedSampleIds.contains(sampleId) else { return }

        print("Processing daily active energy: \(Int(calories)) kcal")

        guard let eventType = await ensureEventType(for: .activeEnergy) else { return }

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

        markSampleAsProcessed(sampleId)
    }

    // MARK: - Mindfulness Processing

    /// Process a mindfulness sample
    @MainActor
    private func processMindfulnessSample(_ sample: HKCategorySample) async {
        let sampleId = sample.uuid.uuidString
        guard !processedSampleIds.contains(sampleId) else { return }

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
        guard !processedSampleIds.contains(sampleId) else { return }

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

            // Sync to backend if using backend mode
            if eventStore.useBackend {
                await eventStore.syncEventToBackend(event)
            }

        } catch {
            print("Failed to save HealthKit event: \(error.localizedDescription)")
        }
    }

    // MARK: - Auto-Create EventType

    /// Ensures an EventType exists for the category, creating one if needed
    @MainActor
    private func ensureEventType(for category: HealthDataCategory) async -> EventType? {
        // 1. Check if configuration already has a linked EventType
        let configDescriptor = FetchDescriptor<HealthKitConfiguration>(
            predicate: #Predicate { config in config.healthDataCategory == category.rawValue && config.isEnabled }
        )

        if let config = try? modelContext.fetch(configDescriptor).first,
           let eventTypeID = config.eventTypeID {
            let eventTypeDescriptor = FetchDescriptor<EventType>(
                predicate: #Predicate { eventType in eventType.id == eventTypeID }
            )
            if let eventType = try? modelContext.fetch(eventTypeDescriptor).first {
                return eventType
            }
        }

        // 2. Check if an EventType with the default name already exists
        let defaultName = category.defaultEventTypeName
        let existingDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { eventType in eventType.name == defaultName }
        )

        if let existing = try? modelContext.fetch(existingDescriptor).first {
            // Link existing EventType to configuration
            await linkEventType(existing, to: category)
            return existing
        }

        // 3. Create new EventType with defaults
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

        // 4. Sync to backend if needed
        if eventStore.useBackend {
            await eventStore.syncEventTypeToBackend(newEventType)
        }

        // 5. Create/update configuration to link to new EventType
        await linkEventType(newEventType, to: category)

        print("Auto-created EventType '\(newEventType.name)' for \(category.rawValue)")
        return newEventType
    }

    /// Links an EventType to a HealthKit category configuration
    @MainActor
    private func linkEventType(_ eventType: EventType, to category: HealthDataCategory) async {
        let descriptor = FetchDescriptor<HealthKitConfiguration>(
            predicate: #Predicate { config in config.healthDataCategory == category.rawValue }
        )

        if let config = try? modelContext.fetch(descriptor).first {
            config.eventTypeID = eventType.id
            config.isEnabled = true
            config.updatedAt = Date()
        } else {
            // Create new configuration
            let config = HealthKitConfiguration(
                category: category,
                eventTypeID: eventType.id,
                isEnabled: true,
                notifyOnDetection: false
            )
            modelContext.insert(config)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to link EventType to configuration: \(error.localizedDescription)")
        }
    }

    // MARK: - Notifications

    /// Send notification if enabled for this category
    private func sendNotificationIfEnabled(for category: HealthDataCategory, eventTypeName: String, details: String?) async {
        // Check if notifications are enabled for this category
        let descriptor = FetchDescriptor<HealthKitConfiguration>(
            predicate: #Predicate { config in config.healthDataCategory == category.rawValue && config.notifyOnDetection }
        )

        guard let _ = try? modelContext.fetch(descriptor).first else { return }
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

    /// Load processed sample IDs from UserDefaults
    private func loadProcessedSampleIds() {
        if let data = UserDefaults.standard.data(forKey: processedSampleIdsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            processedSampleIds = decoded
        }
    }

    /// Save processed sample IDs to UserDefaults
    private func saveProcessedSampleIds() {
        if let encoded = try? JSONEncoder().encode(processedSampleIds) {
            UserDefaults.standard.set(encoded, forKey: processedSampleIdsKey)
        }
    }

    /// Load last step date from UserDefaults
    private func loadLastStepDate() {
        lastStepDate = UserDefaults.standard.object(forKey: lastStepDateKey) as? Date
    }

    /// Save last step date to UserDefaults
    private func saveLastStepDate() {
        UserDefaults.standard.set(lastStepDate, forKey: lastStepDateKey)
    }

    // MARK: - Debug/Testing

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
