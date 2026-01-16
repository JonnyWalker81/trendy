//
//  HealthKitService+SleepProcessing.swift
//  trendy
//
//  Sleep sample aggregation and daily sleep events
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Sleep Processing (Daily Aggregation)

extension HealthKitService {

    /// Process a sleep sample - redirects to daily aggregation
    @MainActor
    func processSleepSample(_ sample: HKCategorySample, isBulkImport: Bool = false) async {
        // Sleep is handled via daily aggregation, similar to steps
        await aggregateDailySleep(isBulkImport: isBulkImport)
    }

    /// Aggregate daily sleep and create a single event per night
    /// Sleep sessions are attributed to the day they end (wake-up day)
    /// Improved to handle third-party apps (EightSleep, Whoop) that may sync data with delays
    @MainActor
    func aggregateDailySleep(isBulkImport: Bool = false) async {
        let calendar = Calendar.current
        let now = Date()

        // Query a broader window to catch late-synced data from third-party apps
        // Look back 48 hours to ensure we don't miss any sleep sessions
        let queryStart = calendar.date(byAdding: .hour, value: -48, to: now) ?? now
        let queryEnd = now

        Log.healthKit.debug("Sleep aggregation query", context: .with { ctx in
            ctx.add("queryStart", queryStart.ISO8601Format())
            ctx.add("queryEnd", queryEnd.ISO8601Format())
        })

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
                    Log.healthKit.error("Sleep query error", error: error)
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        Log.healthKit.debug("Sleep samples found", context: .with { ctx in
            ctx.add("count", samples.count)
        })

        if samples.isEmpty {
            Log.healthKit.debug("No sleep samples found in HealthKit")
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

        Log.healthKit.debug("Sleep nights grouped", context: .with { ctx in
            ctx.add("nights", sleepNights.count)
        })

        // Process each sleep night
        for (sleepDate, nightSamples) in sleepNights.sorted(by: { $0.key < $1.key }) {
            let sampleId = "sleep-\(Self.dateOnlyFormatter.string(from: sleepDate))"

            // Aggregate this night's samples first (before checking for updates)
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
                Log.healthKit.debug("Not enough sleep to record", context: .with { ctx in
                    ctx.add("sampleId", sampleId)
                    ctx.add("minutes", Int(totalSleepDuration / 60))
                })
                continue
            }

            let hours = Int(totalSleepDuration / 3600)
            let minutes = Int((totalSleepDuration.truncatingRemainder(dividingBy: 3600)) / 60)
            let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

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

            // Check for existing event to update
            if let existingEvent = await findEventByHealthKitSampleId(sampleId) {
                // Compare total sleep duration - only update if changed significantly (>= 1 minute)
                let existingSleep = existingEvent.properties["Total Sleep"]?.doubleValue ?? 0
                if abs(existingSleep - totalSleepDuration) < 60 {
                    // No significant change, skip update
                    Log.healthKit.debug("No significant sleep change", context: .with { ctx in
                        ctx.add("sampleId", sampleId)
                        ctx.add("existingMin", Int(existingSleep / 60))
                        ctx.add("newMin", Int(totalSleepDuration / 60))
                    })
                    markSampleAsProcessed(sampleId)
                    continue
                }

                Log.data.info("Updating daily sleep", context: .with { ctx in
                    ctx.add("previousSleep", Int(existingSleep / 60))
                    ctx.add("newSleep", Int(totalSleepDuration / 60))
                })

                do {
                    try await updateHealthKitEvent(
                        existingEvent,
                        properties: properties,
                        notes: "Auto-logged: \(durationText) of sleep",
                        isAllDay: true
                    )

                    markSampleAsProcessed(sampleId)
                    lastSleepDate = sleepDate
                    saveLastSleepDate()
                } catch {
                    // Error already logged in updateHealthKitEvent
                    // Don't mark as processed - will retry on next aggregation
                }
                continue
            }

            // No existing event - create new one
            Log.healthKit.info("Creating sleep event", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add("hours", hours)
                ctx.add("minutes", minutes)
            })

            guard let eventType = await ensureEventType(for: .sleep) else {
                Log.healthKit.error("Failed to get/create EventType for sleep")
                continue
            }

            do {
                try await createEvent(
                    eventType: eventType,
                    category: .sleep,
                    timestamp: sleepStart ?? sleepDate,
                    endDate: sleepEnd,
                    notes: "Auto-logged: \(durationText) of sleep",
                    properties: properties,
                    healthKitSampleId: sampleId,
                    isAllDay: true,
                    isBulkImport: isBulkImport
                )

                markSampleAsProcessed(sampleId)
                lastSleepDate = sleepDate
                saveLastSleepDate()
            } catch {
                // Error already logged in createEvent
                // Don't mark as processed - will retry on next aggregation
            }
        }
    }
}
