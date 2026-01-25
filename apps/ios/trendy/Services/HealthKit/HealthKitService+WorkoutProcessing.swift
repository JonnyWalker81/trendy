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

    /// Generate a unique key for a workout based on its timestamps.
    /// Used to prevent concurrent processing of the same workout from different sources.
    /// Truncates start time to the second to handle minor timestamp variations.
    private func workoutTimestampKey(start: Date, end: Date) -> String {
        // Truncate to second precision to catch workouts with minor timestamp differences
        let startTruncated = start.timeIntervalSince1970.rounded(.down)
        let endTruncated = end.timeIntervalSince1970.rounded(.down)
        return "workout-\(Int(startTruncated))-\(Int(endTruncated))"
    }

    /// Process a workout sample
    ///
    /// - Parameters:
    ///   - workout: The HKWorkout sample to process
    ///   - isBulkImport: If true, skips notifications and immediate sync (for historical data import)
    ///   - useFreshContext: If true, uses a fresh ModelContext for dedup checks to see the latest persisted data.
    ///                      Use this during reconciliation flows after bootstrap when modelContext may be stale.
    @MainActor
    func processWorkoutSample(_ workout: HKWorkout, isBulkImport: Bool = false, useFreshContext: Bool = false) async {
        let sampleId = workout.uuid.uuidString

        // In-memory duplicate check with early claim to prevent race condition.
        // HKObserverQuery can fire multiple times rapidly (app foreground + background delivery).
        // Without early claim, concurrent calls both pass this check before either saves,
        // resulting in duplicate events with different UUIDv7 IDs.
        guard !processedSampleIds.contains(sampleId) else { return }

        // RACE CONDITION FIX #1: Immediately claim this sampleId before async operations.
        // This acts as a synchronous mutex - only the first call to reach this point
        // will proceed, subsequent concurrent calls will exit at the guard above.
        processedSampleIds.insert(sampleId)

        // RACE CONDITION FIX #2: Workout-level mutex using timestamp as key.
        // The same physical workout can be reported by HealthKit with DIFFERENT sample IDs
        // from different sources (Apple Watch vs iPhone, or different apps).
        // Without this, concurrent calls with different sampleIds but same workout timestamps
        // would both pass the sampleId check and race through the async checks below.
        // By claiming the timestamp SYNCHRONOUSLY here, we ensure only one concurrent call proceeds.
        let timestampKey = workoutTimestampKey(start: workout.startDate, end: workout.endDate)
        guard !processingWorkoutTimestamps.contains(timestampKey) else {
            Log.healthKit.debug("Workout with same timestamps already being processed, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add("timestampKey", timestampKey)
                ctx.add("workoutType", workout.workoutActivityType.name)
            })
            // Keep sampleId in processedSampleIds to prevent reprocessing later
            saveProcessedSampleIds()
            return
        }
        processingWorkoutTimestamps.insert(timestampKey)

        // Ensure we release the timestamp lock when done (success or failure)
        defer { processingWorkoutTimestamps.remove(timestampKey) }

        // Database-level duplicate check (handles app restarts where in-memory set is reset)
        // Use fresh context during reconciliation to see events saved by SyncEngine's context
        if await eventExistsWithHealthKitSampleId(sampleId, useFreshContext: useFreshContext) {
            Log.data.debug("Workout already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add("workoutType", workout.workoutActivityType.name)
            })
            saveProcessedSampleIds() // Persist the claim
            return
        }

        // Timestamp-based duplicate check (handles different sample IDs for same workout)
        // Use fresh context during reconciliation to see events saved by SyncEngine's context
        if await eventExistsWithMatchingWorkoutTimestamp(
            startDate: workout.startDate,
            endDate: workout.endDate,
            useFreshContext: useFreshContext
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
