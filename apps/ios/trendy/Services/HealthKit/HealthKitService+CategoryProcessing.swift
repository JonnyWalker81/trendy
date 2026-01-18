//
//  HealthKitService+CategoryProcessing.swift
//  trendy
//
//  Mindfulness and water sample processing, plus sample dispatch
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Sample Processing

extension HealthKitService {

    /// Handle new samples for a category using anchored query
    @MainActor
    func handleNewSamples(for category: HealthDataCategory) async {
        guard let sampleType = category.hkSampleType else { return }

        // Get current anchor (may be nil for first query)
        let currentAnchor = queryAnchors[category]

        // Build predicate: limit to last N days for initial sync (no anchor)
        let predicate: NSPredicate?
        if currentAnchor == nil {
            let daysToImport = HealthKitSettings.shared.historicalImportDays
            let startDate = Calendar.current.date(byAdding: .day, value: -daysToImport, to: Date()) ?? Date()
            predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
            Log.healthKit.info("Initial sync: limiting to last \(daysToImport) days", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("startDate", startDate.ISO8601Format())
            })
        } else {
            // Subsequent fetches: get all new data since anchor (no date limit)
            predicate = nil
        }

        // Execute anchored query
        let (samples, newAnchor) = await withCheckedContinuation { (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Never>) in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: currentAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, addedSamples, _, newAnchor, error in
                if let error = error {
                    Log.healthKit.error("Anchored query error", error: error, context: .with { ctx in
                        ctx.add("category", category.displayName)
                    })
                    continuation.resume(returning: ([], nil))
                    return
                }
                continuation.resume(returning: (addedSamples ?? [], newAnchor))
            }
            healthStore.execute(query)
        }

        // Update and persist anchor if we got new samples or a new anchor
        if let newAnchor = newAnchor {
            queryAnchors[category] = newAnchor
            saveAnchor(newAnchor, for: category)
        }

        // Bulk import if no previous anchor (first-time fetch of historical data)
        let isBulkImport = currentAnchor == nil && samples.count > 5

        // Log sample counts
        if !samples.isEmpty {
            Log.healthKit.info("Processing new samples", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("count", samples.count)
                ctx.add("hadPreviousAnchor", currentAnchor != nil)
                ctx.add("isBulkImport", isBulkImport)
            })
        }

        // Process only truly new samples
        let totalCount = samples.count
        for (index, sample) in samples.enumerated() {
            // Log progress for bulk imports (every 50 samples or at the end)
            if isBulkImport && (index % 50 == 0 || index == totalCount - 1) {
                Log.healthKit.info("Bulk import progress", context: .with { ctx in
                    ctx.add("category", category.displayName)
                    ctx.add("processed", index + 1)
                    ctx.add("total", totalCount)
                    ctx.add("percent", Int(Double(index + 1) / Double(totalCount) * 100))
                })
            }
            await processSample(sample, category: category, isBulkImport: isBulkImport)
        }

        // Record update time for freshness display
        if !samples.isEmpty {
            recordCategoryUpdate(for: category)
        }

        // Batch sync after initial bulk import (first-time sync with no anchor)
        // Individual events skip sync during bulk import to avoid flooding.
        // Now that processing is complete, queue all events for sync.
        if isBulkImport && totalCount > 0 {
            Log.healthKit.info("Starting batch sync for initial bulk import", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("count", totalCount)
            })
            await eventStore.resyncHealthKitEvents()
        }
    }

    /// Cancel the current historical import
    @MainActor
    func cancelHistoricalImport() {
        guard isHistoricalImportInProgress else { return }
        Log.healthKit.info("Historical import cancellation requested")
        isHistoricalImportCancelled = true
    }

    /// Import all historical data for a category (no date limit)
    /// Used for user-triggered "Import Historical Data" action
    /// - Parameters:
    ///   - category: The health data category to import
    ///   - progressHandler: Called with (processed, total) counts during import
    /// - Returns: True if import completed, false if cancelled
    @MainActor
    @discardableResult
    func importAllHistoricalData(for category: HealthDataCategory, progressHandler: @escaping (Int, Int) -> Void) async -> Bool {
        guard let sampleType = category.hkSampleType else { return false }

        // Reset cancellation flag at start
        isHistoricalImportCancelled = false
        isHistoricalImportInProgress = true

        Log.healthKit.info("Starting full historical import", context: .with { ctx in
            ctx.add("category", category.displayName)
        })

        // Query ALL data (no predicate, no anchor)
        let (samples, newAnchor) = await withCheckedContinuation { (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Never>) in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,  // No date limit for historical import
                anchor: nil,     // Start from beginning
                limit: HKObjectQueryNoLimit
            ) { _, addedSamples, _, newAnchor, error in
                if let error = error {
                    Log.healthKit.error("Historical import query error", error: error, context: .with { ctx in
                        ctx.add("category", category.displayName)
                    })
                    continuation.resume(returning: ([], nil))
                    return
                }
                continuation.resume(returning: (addedSamples ?? [], newAnchor))
            }
            healthStore.execute(query)
        }

        // Check if cancelled during query
        if isHistoricalImportCancelled {
            Log.healthKit.info("Historical import cancelled before processing")
            isHistoricalImportInProgress = false
            return false
        }

        // Update anchor
        if let newAnchor = newAnchor {
            queryAnchors[category] = newAnchor
            saveAnchor(newAnchor, for: category)
        }

        let totalCount = samples.count
        Log.healthKit.info("Historical import: \(totalCount) samples to process", context: .with { ctx in
            ctx.add("category", category.displayName)
        })

        // Process with progress updates
        // Report initial progress immediately
        progressHandler(0, totalCount)

        var processedCount = 0
        for (index, sample) in samples.enumerated() {
            // Check for cancellation
            if isHistoricalImportCancelled {
                Log.healthKit.info("Historical import cancelled", context: .with { ctx in
                    ctx.add("category", category.displayName)
                    ctx.add("processed", processedCount)
                    ctx.add("total", totalCount)
                    ctx.add("percent", Int(Double(processedCount) / Double(totalCount) * 100))
                })
                isHistoricalImportInProgress = false
                return false
            }

            // Report progress every 10 samples or at start/end
            if index % 10 == 0 || index == totalCount - 1 {
                progressHandler(index + 1, totalCount)
                // Yield to allow UI to update - without this the UI freezes
                await Task.yield()
            }
            await processSample(sample, category: category, isBulkImport: true)
            processedCount += 1
        }

        // Record update time for freshness display
        if !samples.isEmpty {
            recordCategoryUpdate(for: category)
        }

        isHistoricalImportInProgress = false

        Log.healthKit.info("Historical import complete", context: .with { ctx in
            ctx.add("category", category.displayName)
            ctx.add("processed", totalCount)
        })

        // Batch sync all imported events to backend
        // During bulk import, individual events skip sync to avoid flooding.
        // Now that import is complete, queue all HealthKit events for sync.
        if totalCount > 0 {
            Log.healthKit.info("Starting batch sync for imported HealthKit events")
            await eventStore.resyncHealthKitEvents()
        }

        return true
    }

    /// Process a single sample based on its category
    /// - Parameter isBulkImport: If true, skips notifications and sync (for historical data)
    @MainActor
    func processSample(_ sample: HKSample, category: HealthDataCategory, isBulkImport: Bool = false) async {
        // Check for duplicates using individual sample UUID
        let sampleId = sample.uuid.uuidString
        guard !processedSampleIds.contains(sampleId) else {
            return
        }

        switch category {
        case .workout:
            if let workout = sample as? HKWorkout {
                await processWorkoutSample(workout, isBulkImport: isBulkImport)
            }
        case .sleep:
            if let categorySample = sample as? HKCategorySample {
                await processSleepSample(categorySample, isBulkImport: isBulkImport)
            }
        case .steps:
            // Steps are handled via daily aggregation
            // Mark this individual sample as processed first to avoid redundant calls
            markSampleAsProcessed(sampleId)
            await aggregateDailySteps(isBulkImport: isBulkImport)
        case .activeEnergy:
            if let quantitySample = sample as? HKQuantitySample {
                // Mark this individual sample as processed first to avoid redundant calls
                markSampleAsProcessed(sampleId)
                await processActiveEnergySample(quantitySample, isBulkImport: isBulkImport)
            }
        case .mindfulness:
            if let categorySample = sample as? HKCategorySample {
                await processMindfulnessSample(categorySample, isBulkImport: isBulkImport)
            }
        case .water:
            if let quantitySample = sample as? HKQuantitySample {
                await processWaterSample(quantitySample, isBulkImport: isBulkImport)
            }
        }
    }
}

// MARK: - Mindfulness Processing

extension HealthKitService {

    /// Process a mindfulness sample
    @MainActor
    func processMindfulnessSample(_ sample: HKCategorySample, isBulkImport: Bool = false) async {
        let sampleId = sample.uuid.uuidString

        // In-memory duplicate check with early claim to prevent race condition.
        guard !processedSampleIds.contains(sampleId) else { return }

        // RACE CONDITION FIX: Immediately claim this sampleId before async operations.
        processedSampleIds.insert(sampleId)

        // Database-level duplicate check (handles app restarts where in-memory set is reset)
        if await eventExistsWithHealthKitSampleId(sampleId) {
            Log.data.debug("Mindfulness session already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
            })
            saveProcessedSampleIds() // Persist the claim
            return
        }

        Log.healthKit.debug("Processing mindfulness session")

        guard let eventType = await ensureEventType(for: .mindfulness) else { return }

        let duration = sample.endDate.timeIntervalSince(sample.startDate)

        let properties: [String: PropertyValue] = [
            "Duration": PropertyValue(type: .duration, value: duration),
            "Started At": PropertyValue(type: .date, value: sample.startDate)
        ]

        do {
            try await createEvent(
                eventType: eventType,
                category: .mindfulness,
                timestamp: sample.startDate,
                endDate: sample.endDate,
                notes: "Auto-logged: Mindfulness session",
                properties: properties,
                healthKitSampleId: sampleId,
                isBulkImport: isBulkImport
            )
            markSampleAsProcessed(sampleId)
        } catch {
            // Error already logged in createEvent
            // Don't mark as processed - will retry on next observer callback
        }
    }
}

// MARK: - Water Processing

extension HealthKitService {

    /// Process a water intake sample
    @MainActor
    func processWaterSample(_ sample: HKQuantitySample, isBulkImport: Bool = false) async {
        let sampleId = sample.uuid.uuidString

        // In-memory duplicate check with early claim to prevent race condition.
        guard !processedSampleIds.contains(sampleId) else { return }

        // RACE CONDITION FIX: Immediately claim this sampleId before async operations.
        processedSampleIds.insert(sampleId)

        // Database-level duplicate check (handles app restarts where in-memory set is reset)
        if await eventExistsWithHealthKitSampleId(sampleId) {
            Log.data.debug("Water intake already in database, skipping", context: .with { ctx in
                ctx.add("sampleId", sampleId)
            })
            saveProcessedSampleIds() // Persist the claim
            return
        }

        let milliliters = sample.quantity.doubleValue(for: .literUnit(with: .milli))

        Log.healthKit.debug("Processing water intake", context: .with { ctx in
            ctx.add("milliliters", Int(milliliters))
        })

        guard let eventType = await ensureEventType(for: .water) else { return }

        let properties: [String: PropertyValue] = [
            "Amount (ml)": PropertyValue(type: .number, value: milliliters),
            "Time": PropertyValue(type: .date, value: sample.startDate)
        ]

        do {
            try await createEvent(
                eventType: eventType,
                category: .water,
                timestamp: sample.startDate,
                endDate: nil,
                notes: "Auto-logged: \(Int(milliliters)) ml water",
                properties: properties,
                healthKitSampleId: sampleId,
                isBulkImport: isBulkImport
            )
            markSampleAsProcessed(sampleId)
        } catch {
            // Error already logged in createEvent
            // Don't mark as processed - will retry on next observer callback
        }
    }
}
