//
//  HealthKitService+Authorization.swift
//  trendy
//
//  Authorization request and status methods
//

import Foundation
import HealthKit

// MARK: - Authorization

extension HealthKitService {

    /// Request HealthKit authorization for all supported data types
    @MainActor
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            Log.healthKit.warning("HealthKit is not available on this device")
            return
        }

        // Build set of types to read
        var typesToRead: Set<HKSampleType> = []

        for category in HealthDataCategory.allCases {
            if let sampleType = category.hkSampleType {
                typesToRead.insert(sampleType)
            }
        }

        // Add heart rate for workout enrichment
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(heartRateType)
        }

        // We don't write any data
        let typesToWrite: Set<HKSampleType> = []

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

        // Mark that we've requested authorization
        // Note: HealthKit doesn't tell us if the user granted or denied read access for privacy reasons.
        // If the request completed without throwing, the user has seen the permission prompt.
        authorizationRequested = true

        Log.healthKit.info("Authorization completed")
    }

    /// Check if we have sufficient authorization for HealthKit monitoring
    /// Note: For read-only access, HealthKit doesn't report actual status for privacy.
    /// We rely on whether the user has been prompted for authorization.
    var hasHealthKitAuthorization: Bool {
        isAuthorized
    }

    /// Reset authorization state (for debugging/testing)
    func resetAuthorizationState() {
        authorizationRequested = false
    }

    /// Request authorization for a specific HealthKit category
    /// - Throws: HealthKitError.authorizationFailed if authorization request fails
    @MainActor
    func requestAuthorizationForCategory(_ category: HealthDataCategory) async throws {
        guard isHealthKitAvailable else { return }

        var typesToRead: Set<HKSampleType> = []

        if let sampleType = category.hkSampleType {
            typesToRead.insert(sampleType)
        }

        // Add heart rate for workout enrichment
        if category == .workout, let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(heartRateType)
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            authorizationRequested = true
            Log.healthKit.info("Authorization requested", context: .with { ctx in
                ctx.add("category", category.displayName)
            })
        } catch {
            Log.healthKit.error("Failed to request authorization", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            throw HealthKitError.authorizationFailed(error)
        }
    }

    /// Check if authorization needs to be requested for a specific type
    /// Uses HealthKit's official API to determine if the user has already seen the permission prompt
    func shouldRequestAuthorization(for type: HKSampleType) async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [type]) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }
}
