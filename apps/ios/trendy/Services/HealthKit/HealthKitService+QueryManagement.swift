//
//  HealthKitService+QueryManagement.swift
//  trendy
//
//  Observer query setup, background delivery, and monitoring management
//

import Foundation
import HealthKit

// MARK: - Monitoring Management

extension HealthKitService {

    /// Start monitoring all enabled HealthKit categories
    func startMonitoringAllConfigurations() {
        guard isHealthKitAvailable else {
            Log.healthKit.warning("HealthKit is not available on this device")
            return
        }

        let enabledCategories = HealthKitSettings.shared.enabledCategories

        for category in enabledCategories {
            startMonitoring(category: category)
        }

        Log.healthKit.info("Started monitoring configurations", context: .with { ctx in
            ctx.add("count", enabledCategories.count)
        })
    }

    /// Start monitoring a specific HealthKit category
    /// - Parameter category: The HealthKit data category to monitor
    func startMonitoring(category: HealthDataCategory) {
        // Skip if already monitoring this category
        if observerQueries[category] != nil {
            Log.healthKit.debug("Already monitoring category", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            return
        }

        guard let sampleType = category.hkSampleType else {
            Log.healthKit.warning("No sample type for category", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            return
        }

        Task {
            // Only request authorization if HealthKit says we need to
            // This prevents showing prompts for already-authorized categories
            if await shouldRequestAuthorization(for: sampleType) {
                do {
                    try await requestAuthorizationForCategory(category)
                } catch {
                    // Error already logged in requestAuthorizationForCategory
                    // Continue to try observer query - it may still work
                }
            }
            await startObserverQuery(for: category, sampleType: sampleType)
        }
    }

    /// Start the observer query for a category (called after authorization)
    @MainActor
    func startObserverQuery(for category: HealthDataCategory, sampleType: HKSampleType) async {
        // Double-check we're not already monitoring
        guard observerQueries[category] == nil else { return }

        // Create observer query
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self = self else {
                completionHandler()
                return
            }

            if let error = error {
                Log.healthKit.error("Observer query error", error: error, context: .with { ctx in
                    ctx.add("category", category.displayName)
                })
                completionHandler()
                return
            }

            Log.healthKit.debug("Update received", context: .with { ctx in
                ctx.add("category", category.displayName)
            })

            // Process new samples
            Task {
                await self.handleNewSamples(for: category)
            }

            completionHandler()
        }

        healthStore.execute(query)
        observerQueries[category] = query

        // Enable background delivery
        do {
            try await enableBackgroundDelivery(for: category)
        } catch {
            // Error already logged in enableBackgroundDelivery
            // Observer query still works, just won't get background updates
        }

        Log.healthKit.info("Started monitoring", context: .with { ctx in
            ctx.add("category", category.displayName)
        })
    }

    /// Stop monitoring a specific HealthKit category
    /// - Parameter category: The HealthKit data category to stop monitoring
    func stopMonitoring(category: HealthDataCategory) {
        if let query = observerQueries[category] {
            healthStore.stop(query)
            observerQueries.removeValue(forKey: category)
            Log.healthKit.info("Stopped monitoring", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
        }
    }

    /// Stop monitoring all HealthKit configurations
    func stopMonitoringAll() {
        for (category, query) in observerQueries {
            healthStore.stop(query)
            Log.healthKit.debug("Stopped monitoring", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
        }
        observerQueries.removeAll()
    }

    /// Refresh monitored configurations
    func refreshMonitoring() {
        stopMonitoringAll()
        startMonitoringAllConfigurations()
    }

    // MARK: - Background Delivery

    /// Enable background delivery for a specific category
    /// - Throws: HealthKitError.backgroundDeliveryFailed if enabling fails
    func enableBackgroundDelivery(for category: HealthDataCategory) async throws {
        guard let sampleType = category.hkSampleType else { return }

        do {
            try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: category.backgroundDeliveryFrequency)
            Log.healthKit.info("Background delivery enabled", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
        } catch {
            Log.healthKit.error("Failed to enable background delivery", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            throw HealthKitError.backgroundDeliveryFailed(category.displayName, error)
        }
    }
}
