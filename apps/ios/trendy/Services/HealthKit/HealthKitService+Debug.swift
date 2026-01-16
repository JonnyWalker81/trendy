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
