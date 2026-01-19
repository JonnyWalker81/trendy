//
//  HealthKitService+Debug.swift
//  trendy
//
//  Debug utilities, force checks, simulation, and cache clearing
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Debug Properties (Available in all builds)

extension HealthKitService {

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

    /// Categories with persisted anchors (for debug view)
    var categoriesWithAnchors: [HealthDataCategory] {
        Array(queryAnchors.keys).sorted { $0.rawValue < $1.rawValue }
    }

    /// Debug: Count of processed sample IDs
    var processedSampleIdsCount: Int {
        processedSampleIds.count
    }

    /// Debug: Whether using App Group storage
    var isUsingAppGroupStorage: Bool {
        Self.isUsingAppGroup
    }
}

// MARK: - Force Check Methods

extension HealthKitService {

    /// Debug: Force sleep aggregation check (bypasses date cache)
    @MainActor
    func forceSleepCheck() async {
        Log.healthKit.debug("Forcing sleep aggregation check")

        isRefreshing = true
        refreshingCategories.insert(.sleep)

        // Temporarily clear the lastSleepDate to force a check
        let savedDate = lastSleepDate
        lastSleepDate = nil
        await aggregateDailySleep()
        // If no event was created, restore the date
        if lastSleepDate == nil {
            lastSleepDate = savedDate
        }

        refreshingCategories.remove(.sleep)
        isRefreshing = !refreshingCategories.isEmpty
    }

    /// Debug: Force steps aggregation check (bypasses date cache)
    @MainActor
    func forceStepsCheck() async {
        Log.healthKit.debug("Forcing steps aggregation check")

        isRefreshing = true
        refreshingCategories.insert(.steps)

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

        refreshingCategories.remove(.steps)
        isRefreshing = !refreshingCategories.isEmpty
    }

    /// Debug: Force active energy aggregation check (bypasses date cache)
    @MainActor
    func forceActiveEnergyCheck() async {
        Log.healthKit.debug("Forcing active energy aggregation check")

        isRefreshing = true
        refreshingCategories.insert(.activeEnergy)

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

        refreshingCategories.remove(.activeEnergy)
        isRefreshing = !refreshingCategories.isEmpty
    }

    /// Refresh daily aggregates (steps and active energy) for today
    /// Call this when the app becomes active to ensure fresh HealthKit data
    @MainActor
    public func refreshDailyAggregates() async {
        let enabledCategories = HealthKitSettings.shared.enabledCategories

        // Only refresh if steps or active energy are enabled
        let hasSteps = enabledCategories.contains(.steps)
        let hasActiveEnergy = enabledCategories.contains(.activeEnergy)

        guard hasSteps || hasActiveEnergy else { return }

        isRefreshingDailyAggregates = true
        defer { isRefreshingDailyAggregates = false }

        if hasSteps {
            await forceStepsCheck()
        }

        if hasActiveEnergy {
            await forceActiveEnergyCheck()
        }
    }

    /// Debug: Force refresh all enabled HealthKit categories
    @MainActor
    func forceRefreshAllCategories() async {
        Log.healthKit.debug("Force refreshing all categories")
        let enabledCategories = HealthKitSettings.shared.enabledCategories

        isRefreshing = true
        refreshingCategories = enabledCategories

        for category in enabledCategories {
            Log.healthKit.debug("Refreshing category", context: .with { ctx in
                ctx.add("category", category.displayName)
            })

            switch category {
            case .steps:
                await forceStepsCheck()
            case .sleep:
                await forceSleepCheck()
            case .activeEnergy:
                await forceActiveEnergyCheck()
            case .workout, .mindfulness, .water:
                await handleNewSamples(for: category)
            }

            recordCategoryUpdate(for: category)
            refreshingCategories.remove(category)
        }

        isRefreshing = false
        refreshingCategories = []

        Log.healthKit.debug("Force refresh complete", context: .with { ctx in
            ctx.add("categoryCount", enabledCategories.count)
        })
    }

    /// Reconcile HealthKit data with local storage for the last N days.
    /// This queries HealthKit for historical data and imports any items not present locally.
    /// Call this after sync to ensure HealthKit data that wasn't synced to server is recovered.
    ///
    /// - Parameter days: Number of days to look back (default 30)
    /// - Returns: Number of items reconciled (imported or updated)
    @MainActor
    @discardableResult
    func reconcileHealthKitData(days: Int = 30) async -> Int {
        let enabledCategories = HealthKitSettings.shared.enabledCategories
        guard !enabledCategories.isEmpty else {
            Log.healthKit.debug("Reconciliation skipped - no enabled categories")
            return 0
        }

        Log.healthKit.info("Starting HealthKit reconciliation", context: .with { ctx in
            ctx.add("days", days)
            ctx.add("categories", enabledCategories.count)
        })

        isRefreshing = true
        refreshingCategories = enabledCategories

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var totalReconciled = 0

        for category in enabledCategories {
            let reconciledCount = await reconcileCategory(category, since: startDate)
            totalReconciled += reconciledCount
            refreshingCategories.remove(category)
        }

        isRefreshing = false
        refreshingCategories = []

        Log.healthKit.info("HealthKit reconciliation complete", context: .with { ctx in
            ctx.add("total_reconciled", totalReconciled)
            ctx.add("days_checked", days)
        })

        return totalReconciled
    }

    /// Reconcile a single category with HealthKit data since a given date.
    /// Queries HealthKit directly (bypassing anchors) and imports missing items.
    ///
    /// - Parameters:
    ///   - category: The health data category to reconcile
    ///   - startDate: The earliest date to check
    /// - Returns: Number of items reconciled
    @MainActor
    private func reconcileCategory(_ category: HealthDataCategory, since startDate: Date) async -> Int {
        guard let sampleType = category.hkSampleType else { return 0 }

        Log.healthKit.debug("Reconciling category", context: .with { ctx in
            ctx.add("category", category.displayName)
            ctx.add("since", startDate.ISO8601Format())
        })

        // Query HealthKit directly with date predicate (no anchor - get all historical data)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)

        let samples = await withCheckedContinuation { (continuation: CheckedContinuation<[HKSample], Never>) in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error = error {
                    Log.healthKit.error("Reconciliation query error", error: error, context: .with { ctx in
                        ctx.add("category", category.displayName)
                    })
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: results ?? [])
            }
            healthStore.execute(query)
        }

        Log.healthKit.debug("Reconciliation: found samples in HealthKit", context: .with { ctx in
            ctx.add("category", category.displayName)
            ctx.add("count", samples.count)
        })

        if samples.isEmpty { return 0 }

        // Get all local healthKitSampleIds for this category
        let localSampleIds = await getLocalHealthKitSampleIds(for: category)

        Log.healthKit.debug("Reconciliation: local sample IDs", context: .with { ctx in
            ctx.add("category", category.displayName)
            ctx.add("local_count", localSampleIds.count)
        })

        // Process samples that aren't in local storage
        var reconciledCount = 0
        for sample in samples {
            let sampleId = sample.uuid.uuidString

            // Skip if already in local storage
            if localSampleIds.contains(sampleId) {
                continue
            }

            // Skip if already in processedSampleIds (prevents infinite loop)
            if processedSampleIds.contains(sampleId) {
                // But wait - if it's in processedSampleIds but NOT in local storage,
                // that means it was deleted. Remove from processedSampleIds to allow re-import.
                processedSampleIds.remove(sampleId)
                saveProcessedSampleIds()
            }

            // Process this sample (will create event if not a duplicate)
            await processSample(sample, category: category, isBulkImport: true)
            reconciledCount += 1
        }

        // Handle daily aggregates differently (steps, active energy, sleep use date-based sampleIds)
        if category == .steps || category == .activeEnergy || category == .sleep {
            // These are already handled by the processSample -> aggregateDaily* flow
            // But we need to ensure we process all days, not just today
            let reconciledAggregates = await reconcileDailyAggregates(category: category, since: startDate)
            reconciledCount += reconciledAggregates
        }

        if reconciledCount > 0 {
            Log.healthKit.info("Reconciliation: imported missing samples", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("reconciled", reconciledCount)
            })

            recordCategoryUpdate(for: category)
        }

        return reconciledCount
    }

    /// Get all healthKitSampleId values from local events for a category
    @MainActor
    private func getLocalHealthKitSampleIds(for category: HealthDataCategory) async -> Set<String> {
        let categoryRaw = category.rawValue
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitCategory == categoryRaw && event.healthKitSampleId != nil
            }
        )

        do {
            let events = try modelContext.fetch(descriptor)
            return Set(events.compactMap { $0.healthKitSampleId })
        } catch {
            Log.healthKit.error("Failed to fetch local HealthKit sample IDs", error: error)
            return []
        }
    }

    /// Reconcile daily aggregate categories (steps, active energy, sleep) by checking each day.
    /// For each day that doesn't have a local event, query HealthKit and create the event.
    @MainActor
    private func reconcileDailyAggregates(category: HealthDataCategory, since startDate: Date) async -> Int {
        var reconciledCount = 0
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())

        Log.healthKit.debug("Reconciling daily aggregates", context: .with { ctx in
            ctx.add("category", category.displayName)
            ctx.add("start_date", Self.dateOnlyFormatter.string(from: currentDate))
            ctx.add("end_date", Self.dateOnlyFormatter.string(from: today))
        })

        // Iterate through each day from startDate to today
        while currentDate <= today {
            let dateStr = Self.dateOnlyFormatter.string(from: currentDate)
            let sampleId: String
            switch category {
            case .steps:
                sampleId = "steps-\(dateStr)"
            case .activeEnergy:
                sampleId = "activeEnergy-\(dateStr)"
            case .sleep:
                sampleId = "sleep-\(dateStr)"
            default:
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
                continue
            }

            // DEBUG: Log every date we check (especially Jan 12)
            Log.healthKit.debug("[RECONCILE] Checking date", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("date", dateStr)
                ctx.add("sampleId", sampleId)
            })

            // Check if this day's aggregate exists locally
            let existingEvent = await findEventByHealthKitSampleId(sampleId)

            // DEBUG: Log whether event was found
            Log.healthKit.debug("[RECONCILE] Event lookup result", context: .with { ctx in
                ctx.add("date", dateStr)
                ctx.add("sampleId", sampleId)
                ctx.add("eventFound", existingEvent != nil)
                if let event = existingEvent {
                    ctx.add("eventId", event.id)
                    ctx.add("eventNotes", event.notes ?? "nil")
                }
            })

            if existingEvent == nil {
                // Remove from processedSampleIds to allow import
                processedSampleIds.remove(sampleId)
                saveProcessedSampleIds()

                // Query HealthKit for this specific day and create event if data exists
                let created: Bool
                switch category {
                case .steps:
                    created = await aggregateDailyStepsForDate(currentDate, isBulkImport: true, skipThrottle: true)
                case .activeEnergy:
                    created = await aggregateDailyActiveEnergyForDate(currentDate, isBulkImport: true, skipThrottle: true)
                case .sleep:
                    // TODO: Implement aggregateDailySleepForDate when needed
                    created = false
                default:
                    created = false
                }

                if created {
                    reconciledCount += 1
                    Log.healthKit.debug("Reconciled missing day", context: .with { ctx in
                        ctx.add("category", category.displayName)
                        ctx.add("date", Self.dateOnlyFormatter.string(from: currentDate))
                    })
                }
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
        }

        if reconciledCount > 0 {
            Log.healthKit.info("Daily aggregate reconciliation complete", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("reconciled_days", reconciledCount)
            })
        }

        return reconciledCount
    }
}

// MARK: - Cache Clearing

extension HealthKitService {

    /// Debug: Clear sleep processing cache
    func clearSleepCache() {
        Log.healthKit.debug("Clearing sleep cache")
        lastSleepDate = nil
        Self.sharedDefaults.removeObject(forKey: lastSleepDateKey)

        processedSampleIds = processedSampleIds.filter { !$0.hasPrefix("sleep-") }
        saveProcessedSampleIds()
        Log.healthKit.debug("Sleep cache cleared")
    }

    /// Debug: Clear steps processing cache
    func clearStepsCache() {
        Log.healthKit.debug("Clearing steps cache")
        lastStepDate = nil
        Self.sharedDefaults.removeObject(forKey: lastStepDateKey)

        processedSampleIds = processedSampleIds.filter { !$0.hasPrefix("steps-") }
        saveProcessedSampleIds()
        Log.healthKit.debug("Steps cache cleared")
    }

    /// Debug: Clear active energy processing cache
    func clearActiveEnergyCache() {
        Log.healthKit.debug("Clearing active energy cache")
        lastActiveEnergyDate = nil
        Self.sharedDefaults.removeObject(forKey: lastActiveEnergyDateKey)

        processedSampleIds = processedSampleIds.filter { !$0.hasPrefix("activeEnergy-") }
        saveProcessedSampleIds()
        Log.healthKit.debug("Active energy cache cleared")
    }

    /// Debug: Refresh all observers
    func refreshAllObservers() {
        Log.healthKit.debug("Refreshing all observers")
        stopMonitoringAll()
        startMonitoringAllConfigurations()
    }
}

// MARK: - Debug/Testing (Simulation)

#if DEBUG || STAGING
extension HealthKitService {

    /// Simulate a workout detection for testing purposes
    func simulateWorkoutDetection() async {
        Log.healthKit.debug("Simulating workout detection")

        guard let eventType = await ensureEventType(for: .workout) else {
            Log.healthKit.error("Failed to get/create EventType for simulated workout")
            return
        }

        let properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: 1800.0),
            "Calories": PropertyValue(type: .number, value: 250.0),
            "Workout Type": PropertyValue(type: .text, value: "Running"),
            "Started At": PropertyValue(type: .date, value: Date().addingTimeInterval(-1800)),
            "Ended At": PropertyValue(type: .date, value: Date())
        ]

        do {
            try await createEvent(
                eventType: eventType,
                category: .workout,
                timestamp: Date().addingTimeInterval(-1800),
                endDate: Date(),
                notes: "Simulated: Running workout",
                properties: properties,
                healthKitSampleId: "sim-\(UUID().uuidString)"
            )
        } catch {
            Log.healthKit.error("Failed to save simulated workout", error: error)
        }
    }

    /// Simulate a sleep detection for testing purposes
    func simulateSleepDetection() async {
        Log.healthKit.debug("Simulating sleep detection")

        guard let eventType = await ensureEventType(for: .sleep) else {
            Log.healthKit.error("Failed to get/create EventType for simulated sleep")
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

        do {
            try await createEvent(
                eventType: eventType,
                category: .sleep,
                timestamp: startDate,
                endDate: endDate,
                notes: "Simulated: Sleep",
                properties: properties,
                healthKitSampleId: "sim-\(UUID().uuidString)"
            )
        } catch {
            Log.healthKit.error("Failed to save simulated sleep", error: error)
        }
    }
}
#endif
