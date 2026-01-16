//
//  HealthKitService+DebugQueries.swift
//  trendy
//
//  Debug queries for HealthKit data inspection
//

import Foundation
import HealthKit

// MARK: - Debug Queries

extension HealthKitService {

    /// Debug: Query daily step counts from HealthKit for the last 7 days
    func debugQueryStepData() async -> [(date: Date, steps: Double, source: String)] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }

        let calendar = Calendar.current
        let now = Date()

        var results: [(date: Date, steps: Double, source: String)] = []

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
                ) { _, statistics, _ in
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
                ) { _, statistics, _ in
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

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, error in
                if let error = error {
                    Log.healthKit.debug("Debug workout query error", error: error)
                    continuation.resume(returning: [])
                    return
                }

                guard let workouts = results as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let data = workouts.map { workout in
                    (
                        start: workout.startDate,
                        end: workout.endDate,
                        duration: workout.duration,
                        workoutType: workout.workoutActivityType.name,
                        calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        distance: workout.totalDistance?.doubleValue(for: .meter()),
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

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, error in
                if let error = error {
                    Log.healthKit.debug("Debug sleep query error", error: error)
                    continuation.resume(returning: [])
                    return
                }

                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let data = samples.map { sample in
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
}
