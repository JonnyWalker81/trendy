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

    /// Aggregate daily steps and create a single event per day (defaults to today)
    @MainActor
    func aggregateDailySteps(isBulkImport: Bool = false) async {
        await aggregateDailyStepsForDate(Date(), isBulkImport: isBulkImport, skipThrottle: false)
    }

    /// Aggregate daily steps for a specific date.
    /// Use this for historical reconciliation after sync.
    ///
    /// - Parameters:
    ///   - date: The date to aggregate steps for
    ///   - isBulkImport: Whether this is part of a bulk import
    ///   - skipThrottle: If true, bypass the 5-minute throttle (for historical imports)
    /// - Returns: True if an event was created or updated, false otherwise
    @MainActor
    @discardableResult
    func aggregateDailyStepsForDate(_ date: Date, isBulkImport: Bool = false, skipThrottle: Bool = false) async -> Bool {
        let targetDay = Calendar.current.startOfDay(for: date)
        let isToday = Calendar.current.isDateInToday(targetDay)

        // Use consistent date-only format for sampleId (no timezone issues)
        let sampleId = "steps-\(Self.dateOnlyFormatter.string(from: targetDay))"

        // Throttle: don't process more than once per 5 minutes for the same day
        // Only apply throttle for today's data and when not skipping throttle
        if !skipThrottle && isToday {
            if let lastDate = lastStepDate,
               Calendar.current.isDate(lastDate, inSameDayAs: targetDay),
               Date().timeIntervalSince(lastDate) < 300 {
                return false
            }
        }

        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return false }

        let startOfDay = targetDay
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: targetDay) ?? Date()

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

        guard let steps = totalSteps, steps > 0 else { return false }

        // Check for existing event to update
        if let existingEvent = await findEventByHealthKitSampleId(sampleId) {
            // Compare values - only update if step count changed significantly (>= 1 step)
            let existingSteps = existingEvent.properties["Step Count"]?.doubleValue ?? 0
            if abs(existingSteps - steps) < 1 {
                // No significant change, skip update but update throttle timestamp for today
                if isToday {
                    lastStepDate = Date()
                    saveLastStepDate()
                }
                return false
            }

            Log.data.info("Updating daily steps", context: .with { ctx in
                ctx.add("date", Self.dateOnlyFormatter.string(from: targetDay))
                ctx.add("previousSteps", Int(existingSteps))
                ctx.add("newSteps", Int(steps))
            })

            let properties: [String: PropertyValue] = [
                "Step Count": PropertyValue(type: .number, value: steps),
                "Date": PropertyValue(type: .date, value: targetDay)
            ]

            do {
                try await updateHealthKitEvent(
                    existingEvent,
                    properties: properties,
                    notes: "Auto-logged: \(Int(steps)) steps",
                    isAllDay: true
                )

                if isToday {
                    lastStepDate = Date()
                    saveLastStepDate()
                }
                return true
            } catch {
                // Error already logged in updateHealthKitEvent
                // Will retry on next aggregation
                return false
            }
        }

        // No existing event - create new one
        Log.data.info("Creating daily steps event", context: .with { ctx in
            ctx.add("date", Self.dateOnlyFormatter.string(from: targetDay))
            ctx.add("steps", Int(steps))
        })

        guard let eventType = await ensureEventType(for: .steps) else {
            Log.data.error("Failed to get/create EventType for steps")
            return false
        }

        let properties: [String: PropertyValue] = [
            "Step Count": PropertyValue(type: .number, value: steps),
            "Date": PropertyValue(type: .date, value: targetDay)
        ]

        do {
            try await createEvent(
                eventType: eventType,
                category: .steps,
                timestamp: targetDay,
                endDate: nil,
                notes: "Auto-logged: \(Int(steps)) steps",
                properties: properties,
                healthKitSampleId: sampleId,
                isAllDay: true,
                isBulkImport: isBulkImport
            )

            // Don't mark as processed - daily aggregates can be updated throughout the day
            if isToday {
                lastStepDate = Date()
                saveLastStepDate()
            }
            return true
        } catch {
            // Error already logged in createEvent
            // Will retry on next aggregation
            return false
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

    /// Aggregate daily active energy (defaults to today)
    @MainActor
    func aggregateDailyActiveEnergy(isBulkImport: Bool = false) async {
        await aggregateDailyActiveEnergyForDate(Date(), isBulkImport: isBulkImport, skipThrottle: false)
    }

    /// Aggregate daily active energy for a specific date.
    /// Use this for historical reconciliation after sync.
    ///
    /// - Parameters:
    ///   - date: The date to aggregate active energy for
    ///   - isBulkImport: Whether this is part of a bulk import
    ///   - skipThrottle: If true, bypass the 5-minute throttle (for historical imports)
    /// - Returns: True if an event was created or updated, false otherwise
    @MainActor
    @discardableResult
    func aggregateDailyActiveEnergyForDate(_ date: Date, isBulkImport: Bool = false, skipThrottle: Bool = false) async -> Bool {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            Log.healthKit.error("[ACTIVE_ENERGY] Failed to get activeEnergyBurned quantity type")
            return false
        }

        let targetDay = Calendar.current.startOfDay(for: date)
        let isToday = Calendar.current.isDateInToday(targetDay)

        // Use consistent date-only format for sampleId (no timezone issues)
        let dateStr = Self.dateOnlyFormatter.string(from: targetDay)
        let sampleId = "activeEnergy-\(dateStr)"

        Log.healthKit.debug("[ACTIVE_ENERGY] aggregateDailyActiveEnergyForDate called", context: .with { ctx in
            ctx.add("input_date", Self.dateOnlyFormatter.string(from: date))
            ctx.add("targetDay", dateStr)
            ctx.add("isToday", isToday)
            ctx.add("sampleId", sampleId)
            ctx.add("skipThrottle", skipThrottle)
        })

        // Throttle: don't process more than once per 5 minutes for the same day
        // Only apply throttle for today's data and when not skipping throttle
        if !skipThrottle && isToday {
            if let lastDate = lastActiveEnergyDate,
               Calendar.current.isDate(lastDate, inSameDayAs: targetDay),
               Date().timeIntervalSince(lastDate) < 300 {
                return false
            }
        }

        let startOfDay = targetDay
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: targetDay) ?? Date()

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        Log.healthKit.debug("[ACTIVE_ENERGY] Querying HealthKit", context: .with { ctx in
            ctx.add("date", dateStr)
            ctx.add("startOfDay", startOfDay.ISO8601Format())
            ctx.add("endOfDay", endOfDay.ISO8601Format())
        })

        let totalCalories = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    Log.healthKit.error("[ACTIVE_ENERGY] HealthKit query error", error: error)
                }
                guard let sum = statistics?.sumQuantity() else {
                    Log.healthKit.debug("[ACTIVE_ENERGY] HealthKit returned no sum quantity")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: .kilocalorie()))
            }
            healthStore.execute(query)
        }

        Log.healthKit.debug("[ACTIVE_ENERGY] HealthKit query result", context: .with { ctx in
            ctx.add("date", dateStr)
            ctx.add("calories", totalCalories ?? -1)
        })

        guard let calories = totalCalories, calories > 0 else {
            Log.healthKit.debug("[ACTIVE_ENERGY] No calories or zero calories for date", context: .with { ctx in
                ctx.add("date", dateStr)
                ctx.add("totalCalories", totalCalories ?? -999)
            })
            return false
        }

        // Check for existing event to update
        Log.healthKit.debug("[ACTIVE_ENERGY] Checking for existing event to update", context: .with { ctx in
            ctx.add("date", dateStr)
            ctx.add("sampleId", sampleId)
        })

        if let existingEvent = await findEventByHealthKitSampleId(sampleId) {
            Log.healthKit.debug("[ACTIVE_ENERGY] Found existing event - will update", context: .with { ctx in
                ctx.add("date", dateStr)
                ctx.add("eventId", existingEvent.id)
                ctx.add("existingNotes", existingEvent.notes ?? "nil")
            })

            // Compare values - only update if calories changed significantly (>= 1 kcal)
            let existingCalories = existingEvent.properties["Calories"]?.doubleValue ?? 0
            if abs(existingCalories - calories) < 1 {
                Log.healthKit.debug("[ACTIVE_ENERGY] No significant change, skipping update", context: .with { ctx in
                    ctx.add("date", dateStr)
                    ctx.add("existingCalories", Int(existingCalories))
                    ctx.add("newCalories", Int(calories))
                })
                // No significant change, skip update but update throttle timestamp for today
                if isToday {
                    lastActiveEnergyDate = Date()
                    saveLastActiveEnergyDate()
                }
                return false
            }

            Log.data.info("Updating daily active energy", context: .with { ctx in
                ctx.add("date", Self.dateOnlyFormatter.string(from: targetDay))
                ctx.add("previousCalories", Int(existingCalories))
                ctx.add("newCalories", Int(calories))
            })

            let properties: [String: PropertyValue] = [
                "Calories": PropertyValue(type: .number, value: calories),
                "Date": PropertyValue(type: .date, value: targetDay)
            ]

            do {
                try await updateHealthKitEvent(
                    existingEvent,
                    properties: properties,
                    notes: "Auto-logged: \(Int(calories)) kcal burned",
                    isAllDay: true
                )

                if isToday {
                    lastActiveEnergyDate = Date()
                    saveLastActiveEnergyDate()
                }
                return true
            } catch {
                // Error already logged in updateHealthKitEvent
                // Will retry on next aggregation
                return false
            }
        }

        // No existing event - create new one
        Log.healthKit.debug("[ACTIVE_ENERGY] No existing event found - will create new", context: .with { ctx in
            ctx.add("date", dateStr)
            ctx.add("sampleId", sampleId)
            ctx.add("calories", Int(calories))
        })

        Log.data.info("Creating daily active energy event", context: .with { ctx in
            ctx.add("date", Self.dateOnlyFormatter.string(from: targetDay))
            ctx.add("calories", Int(calories))
        })

        guard let eventType = await ensureEventType(for: .activeEnergy) else {
            Log.data.error("Failed to get/create EventType for activeEnergy")
            return false
        }

        let properties: [String: PropertyValue] = [
            "Calories": PropertyValue(type: .number, value: calories),
            "Date": PropertyValue(type: .date, value: targetDay)
        ]

        do {
            try await createEvent(
                eventType: eventType,
                category: .activeEnergy,
                timestamp: targetDay,
                endDate: nil,
                notes: "Auto-logged: \(Int(calories)) kcal burned",
                properties: properties,
                healthKitSampleId: sampleId,
                isAllDay: true,
                isBulkImport: isBulkImport
            )

            // Don't mark as processed - daily aggregates can be updated throughout the day
            if isToday {
                lastActiveEnergyDate = Date()
                saveLastActiveEnergyDate()
            }
            return true
        } catch {
            // Error already logged in createEvent
            // Will retry on next aggregation
            return false
        }
    }
}
