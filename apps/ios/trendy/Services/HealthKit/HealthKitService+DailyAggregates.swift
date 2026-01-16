//
//  HealthKitService+DailyAggregates.swift
//  trendy
//
//  Steps and active energy daily aggregation
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Steps Processing (Daily Aggregation)

extension HealthKitService {

    /// Aggregate daily steps and create a single event per day
    @MainActor
    func aggregateDailySteps(isBulkImport: Bool = false) async {
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

            do {
                try await updateHealthKitEvent(
                    existingEvent,
                    properties: properties,
                    notes: "Auto-logged: \(Int(steps)) steps",
                    isAllDay: true
                )

                lastStepDate = Date()
                saveLastStepDate()
            } catch {
                // Error already logged in updateHealthKitEvent
                // Will retry on next aggregation
            }
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

        do {
            try await createEvent(
                eventType: eventType,
                category: .steps,
                timestamp: today,
                endDate: nil,
                notes: "Auto-logged: \(Int(steps)) steps",
                properties: properties,
                healthKitSampleId: sampleId,
                isAllDay: true,
                isBulkImport: isBulkImport
            )

            // Don't mark as processed - daily aggregates can be updated throughout the day
            lastStepDate = Date()
            saveLastStepDate()
        } catch {
            // Error already logged in createEvent
            // Will retry on next aggregation
        }
    }
}

// MARK: - Active Energy Processing

extension HealthKitService {

    /// Process an active energy sample
    @MainActor
    func processActiveEnergySample(_ sample: HKQuantitySample, isBulkImport: Bool = false) async {
        // For active energy, we aggregate daily similar to steps
        // Skip individual samples and do daily aggregation
        await aggregateDailyActiveEnergy(isBulkImport: isBulkImport)
    }

    /// Aggregate daily active energy
    @MainActor
    func aggregateDailyActiveEnergy(isBulkImport: Bool = false) async {
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

            do {
                try await updateHealthKitEvent(
                    existingEvent,
                    properties: properties,
                    notes: "Auto-logged: \(Int(calories)) kcal burned",
                    isAllDay: true
                )

                lastActiveEnergyDate = Date()
                saveLastActiveEnergyDate()
            } catch {
                // Error already logged in updateHealthKitEvent
                // Will retry on next aggregation
            }
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

        do {
            try await createEvent(
                eventType: eventType,
                category: .activeEnergy,
                timestamp: today,
                endDate: nil,
                notes: "Auto-logged: \(Int(calories)) kcal burned",
                properties: properties,
                healthKitSampleId: sampleId,
                isAllDay: true,
                isBulkImport: isBulkImport
            )

            // Don't mark as processed - daily aggregates can be updated throughout the day
            lastActiveEnergyDate = Date()
            saveLastActiveEnergyDate()
        } catch {
            // Error already logged in createEvent
            // Will retry on next aggregation
        }
    }
}
