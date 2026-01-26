//
//  HealthKitService+Persistence.swift
//  trendy
//
//  UserDefaults persistence for anchors, sample IDs, and dates
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Migration

extension HealthKitService {

    /// Verify that the App Group UserDefaults is properly set up
    func verifyAppGroupSetup() {
        // Force access to sharedDefaults to trigger the isUsingAppGroup check
        let testKey = "healthKitAppGroupTest"
        let testValue = "verified-\(Date().timeIntervalSince1970)"

        // Write a test value
        Self.sharedDefaults.set(testValue, forKey: testKey)
        Self.sharedDefaults.synchronize()

        // Read it back
        let readValue = Self.sharedDefaults.string(forKey: testKey)

        if readValue == testValue {
            Log.healthKit.info("App Group UserDefaults verified", context: .with { ctx in
                ctx.add("isUsingAppGroup", Self.isUsingAppGroup)
                ctx.add("appGroupId", Self.appGroupIdentifier)
            })
        } else {
            Log.healthKit.error("App Group UserDefaults verification FAILED", context: .with { ctx in
                ctx.add("written", testValue)
                ctx.add("readBack", readValue ?? "nil")
            })
        }

        // Clean up test value
        Self.sharedDefaults.removeObject(forKey: testKey)
    }

    /// Log current HealthKit state for debugging
    #if DEBUG
    func logCurrentState() {
        Log.healthKit.debug("Service state", context: .with { ctx in
            ctx.add("appGroupId", Self.appGroupIdentifier)
            ctx.add("isUsingAppGroup", Self.isUsingAppGroup)
            ctx.add("authInDefaults", authorizationRequestedInDefaults)
            ctx.add("authRequested", authorizationRequested)
            ctx.add("hasAuthorization", hasHealthKitAuthorization)
            ctx.add("processedSampleCount", processedSampleIds.count)
        })

        // Log HealthKitSettings state
        HealthKitSettings.shared.logCurrentState()
    }
    #endif

    /// Migrate data from UserDefaults.standard to App Group UserDefaults
    /// This ensures continuity when upgrading from versions that used standard UserDefaults
    func migrateFromStandardUserDefaults() {
        // Check if migration already completed
        guard !Self.sharedDefaults.bool(forKey: Self.migrationCompletedKey) else { return }

        let standardDefaults = UserDefaults.standard

        // Migrate processed sample IDs
        if let data = standardDefaults.data(forKey: processedSampleIdsKey),
           Self.sharedDefaults.data(forKey: processedSampleIdsKey) == nil {
            Self.sharedDefaults.set(data, forKey: processedSampleIdsKey)
            Log.healthKit.info("Migrated processedSampleIds to App Group")
        }

        // Migrate last step date
        if let date = standardDefaults.object(forKey: lastStepDateKey) as? Date,
           Self.sharedDefaults.object(forKey: lastStepDateKey) == nil {
            Self.sharedDefaults.set(date, forKey: lastStepDateKey)
            Log.healthKit.info("Migrated lastStepDate to App Group")
        }

        // Migrate last sleep date
        if let date = standardDefaults.object(forKey: lastSleepDateKey) as? Date,
           Self.sharedDefaults.object(forKey: lastSleepDateKey) == nil {
            Self.sharedDefaults.set(date, forKey: lastSleepDateKey)
            Log.healthKit.info("Migrated lastSleepDate to App Group")
        }

        // Migrate authorization requested flag
        if standardDefaults.bool(forKey: Self.authorizationRequestedKey),
           !Self.sharedDefaults.bool(forKey: Self.authorizationRequestedKey) {
            Self.sharedDefaults.set(true, forKey: Self.authorizationRequestedKey)
            Log.healthKit.info("Migrated authorizationRequested to App Group")
        }

        // Mark migration as completed
        Self.sharedDefaults.set(true, forKey: Self.migrationCompletedKey)
        Log.healthKit.info("UserDefaults migration to App Group completed")
    }
}

// MARK: - Processed Sample IDs

extension HealthKitService {

    /// Mark a sample ID as processed
    func markSampleAsProcessed(_ sampleId: String) {
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

    /// Load processed sample IDs from shared UserDefaults (persists across reinstalls)
    func loadProcessedSampleIds() {
        if let data = Self.sharedDefaults.data(forKey: processedSampleIdsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            processedSampleIds = decoded
        }
    }

    /// Save processed sample IDs to shared UserDefaults (persists across reinstalls)
    func saveProcessedSampleIds() {
        if let encoded = try? JSONEncoder().encode(processedSampleIds) {
            Self.sharedDefaults.set(encoded, forKey: processedSampleIdsKey)
        }
    }

    /// Reload processedSampleIds from SwiftData after a full resync.
    /// This prevents duplicates when bootstrap downloads events that HealthKit would otherwise re-import.
    /// Call this after SyncEngine.bootstrapFetch() completes.
    ///
    /// IMPORTANT: Uses a fresh ModelContext to ensure we see the latest persisted data,
    /// not stale cached data from the original context.
    ///
    /// CRITICAL FIX (2026-01-18): This method now REPLACES processedSampleIds instead of merging.
    /// After bootstrap clears local events, we must clear old sample IDs too, otherwise
    /// HealthKit data that was deleted locally won't be re-imported because its sample ID
    /// is still marked as "processed". The only valid sample IDs after bootstrap are those
    /// from events that were downloaded from the server.
    @MainActor
    func reloadProcessedSampleIdsFromDatabase() {
        Log.healthKit.info("Reloading processedSampleIds from database after resync")

        // Use mainContext to avoid SQLite file locking issues with concurrent ModelContext instances.
        // This is @MainActor so mainContext is the correct choice.
        let context = modelContainer.mainContext

        // Query all events with healthKitSampleId from the database
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitSampleId != nil
            }
        )

        do {
            let events = try context.fetch(descriptor)
            var newSampleIds = Set<String>()
            for event in events {
                if let sampleId = event.healthKitSampleId {
                    newSampleIds.insert(sampleId)
                }
            }

            // CRITICAL FIX: REPLACE processedSampleIds entirely instead of merging.
            // After bootstrap, only events in the database are valid. Any sample IDs
            // from before the resync (that were deleted) should NOT block re-import.
            let oldCount = processedSampleIds.count
            processedSampleIds = newSampleIds  // REPLACE, not merge
            let newCount = processedSampleIds.count

            Log.healthKit.info("Replaced processedSampleIds after bootstrap", context: .with { ctx in
                ctx.add("from_database", newSampleIds.count)
                ctx.add("old_count", oldCount)
                ctx.add("new_count", newCount)
                ctx.add("cleared", oldCount - newCount)
            })

            // Persist the updated set
            saveProcessedSampleIds()
        } catch {
            Log.healthKit.error("Failed to reload processedSampleIds from database", error: error)
        }
    }
}

// MARK: - Date Persistence

extension HealthKitService {

    /// Load last step date from shared UserDefaults (persists across reinstalls)
    func loadLastStepDate() {
        lastStepDate = Self.sharedDefaults.object(forKey: lastStepDateKey) as? Date
    }

    /// Save last step date to shared UserDefaults (persists across reinstalls)
    func saveLastStepDate() {
        Self.sharedDefaults.set(lastStepDate, forKey: lastStepDateKey)
    }

    /// Load last sleep date from shared UserDefaults (persists across reinstalls)
    func loadLastSleepDate() {
        lastSleepDate = Self.sharedDefaults.object(forKey: lastSleepDateKey) as? Date
    }

    /// Save last sleep date to shared UserDefaults (persists across reinstalls)
    func saveLastSleepDate() {
        Self.sharedDefaults.set(lastSleepDate, forKey: lastSleepDateKey)
    }

    /// Load last active energy date from shared UserDefaults (persists across reinstalls)
    func loadLastActiveEnergyDate() {
        lastActiveEnergyDate = Self.sharedDefaults.object(forKey: lastActiveEnergyDateKey) as? Date
    }

    /// Save last active energy date to shared UserDefaults (persists across reinstalls)
    func saveLastActiveEnergyDate() {
        Self.sharedDefaults.set(lastActiveEnergyDate, forKey: lastActiveEnergyDateKey)
    }
}

// MARK: - Anchor Persistence

extension HealthKitService {

    /// Save anchor for a category to persistent storage
    func saveAnchor(_ anchor: HKQueryAnchor, for category: HealthDataCategory) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            Self.sharedDefaults.set(data, forKey: "\(queryAnchorKeyPrefix)\(category.rawValue)")
            Log.healthKit.debug("Saved anchor", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
        } catch {
            Log.healthKit.error("Failed to archive anchor", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
        }
    }

    /// Load anchor for a category from persistent storage
    func loadAnchor(for category: HealthDataCategory) -> HKQueryAnchor? {
        guard let data = Self.sharedDefaults.data(forKey: "\(queryAnchorKeyPrefix)\(category.rawValue)") else {
            return nil
        }
        do {
            let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
            Log.healthKit.debug("Loaded anchor", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("found", anchor != nil)
            })
            return anchor
        } catch {
            Log.healthKit.error("Failed to unarchive anchor", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            return nil
        }
    }

    /// Clear anchor for a category (useful for debug/reset)
    func clearAnchor(for category: HealthDataCategory) {
        Self.sharedDefaults.removeObject(forKey: "\(queryAnchorKeyPrefix)\(category.rawValue)")
        queryAnchors.removeValue(forKey: category)
        Log.healthKit.info("Cleared anchor", context: .with { ctx in
            ctx.add("category", category.displayName)
        })
    }

    /// Clear all anchors (useful for full refresh)
    func clearAllAnchors() {
        for category in HealthDataCategory.allCases {
            clearAnchor(for: category)
        }
        Log.healthKit.info("Cleared all anchors")
    }

    /// Load all persisted anchors into memory
    func loadAllAnchors() {
        for category in HealthDataCategory.allCases {
            if let anchor = loadAnchor(for: category) {
                queryAnchors[category] = anchor
            }
        }
        Log.healthKit.debug("Loaded anchors", context: .with { ctx in
            ctx.add("count", queryAnchors.count)
        })
    }
}

// MARK: - Update Time Tracking

extension HealthKitService {

    /// Record that a category received new data
    func recordCategoryUpdate(for category: HealthDataCategory) {
        let now = Date()
        lastUpdateTimes[category] = now
        Self.sharedDefaults.set(now.timeIntervalSince1970, forKey: "\(lastUpdateTimeKeyPrefix)\(category.rawValue)")
        Log.healthKit.debug("Recorded update", context: .with { ctx in
            ctx.add("category", category.displayName)
        })
    }

    /// Load all persisted update times into memory
    func loadAllUpdateTimes() {
        for category in HealthDataCategory.allCases {
            let timestamp = Self.sharedDefaults.double(forKey: "\(lastUpdateTimeKeyPrefix)\(category.rawValue)")
            if timestamp > 0 {
                lastUpdateTimes[category] = Date(timeIntervalSince1970: timestamp)
            }
        }
        Log.healthKit.debug("Loaded update times", context: .with { ctx in
            ctx.add("count", lastUpdateTimes.count)
        })
    }

    /// Get last update time for a specific category
    func lastUpdateTime(for category: HealthDataCategory) -> Date? {
        lastUpdateTimes[category]
    }

    /// Clear update time for a category
    func clearUpdateTime(for category: HealthDataCategory) {
        lastUpdateTimes.removeValue(forKey: category)
        Self.sharedDefaults.removeObject(forKey: "\(lastUpdateTimeKeyPrefix)\(category.rawValue)")
    }
}
