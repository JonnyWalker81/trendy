//
//  HealthKitService+WorkoutProcessing.swift
//  trendy
//
//  Workout sample processing with heart rate enrichment
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Workout Processing

extension HealthKitService {

    /// Process a workout sample
    @MainActor
    func processWorkoutSample(_ workout: HKWorkout, isBulkImport: Bool = false) async {
        let sampleId = workout.uuid.uuidString

        // In-memory duplicate check with early claim to prevent race condition.
        // HKObserverQuery can fire multiple times rapidly (app foreground + background delivery).
        // Without early claim, concurrent calls both pass this check before either saves,
        // resulting in duplicate events with different UUIDv7 IDs.
        guard !processedSampleIds.contains(sampleId) else { return }

        // RACE CONDITION FIX: Immediately claim this sampleId before async operations.
        // This acts as a synchronous mutex - only the first call to reach this point
        // will proceed, subsequent concurrent calls will exit at the guard above.
        processedSampleIds.insert(sampleId)

        // Database-level duplicate check (handles app restarts where in-memory set is reset)
        if await eventExistsWithHealthKitSampleId(sampleId) {
            Log.data.debug("Workout already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add("workoutType", workout.workoutActivityType.name)
            })
            saveProcessedSampleIds() // Persist the claim
            return
        }

        // Timestamp-based duplicate check (handles different sample IDs for same workout)
        if await eventExistsWithMatchingWorkoutTimestamp(
            startDate: workout.startDate,
            endDate: workout.endDate
        ) {
            Log.data.debug("Workout with matching timestamp already exists, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add("startDate", workout.startDate.ISO8601Format())
                ctx.add("endDate", workout.endDate.ISO8601Format())
                ctx.add("workoutType", workout.workoutActivityType.name)
            })
            saveProcessedSampleIds() // Persist the claim
            return
        }

        Log.healthKit.debug("Processing workout", context: .with { ctx in
            ctx.add("workoutType", workout.workoutActivityType.name)
        })

        // Ensure EventType exists
        guard let eventType = await ensureEventType(for: .workout) else {
            Log.healthKit.error("Failed to get/create EventType for workout")
            return
        }

        // Fetch heart rate stats for this workout (skip during bulk import for performance)
        // Each heart rate query takes 100-500ms, which adds up significantly for hundreds of workouts
        let (avgHR, maxHR): (Double?, Double?)
        if isBulkImport {
            // Skip heart rate enrichment during bulk import to avoid 500+ sequential HealthKit queries
            avgHR = nil
            maxHR = nil
        } else {
            (avgHR, maxHR) = await fetchHeartRateStats(for: workout)
        }

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
        do {
            try await createEvent(
                eventType: eventType,
                category: .workout,
                timestamp: workout.startDate,
                endDate: workout.endDate,
                notes: "Auto-logged: \(workout.workoutActivityType.name)",
                properties: properties,
                healthKitSampleId: sampleId,
                isBulkImport: isBulkImport
            )
            markSampleAsProcessed(sampleId)
        } catch {
            // Error already logged in createEvent
        }
    }

    /// Fetch heart rate statistics for a workout
    func fetchHeartRateStats(for workout: HKWorkout) async -> (avg: Double?, max: Double?) {
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
            ) { _, samples, _ in
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
}
