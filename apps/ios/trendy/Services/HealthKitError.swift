//
//  HealthKitError.swift
//  trendy
//
//  Custom error types for HealthKit operations
//

import Foundation

/// Errors that can occur during HealthKit operations
enum HealthKitError: LocalizedError {
    /// HKHealthStore.requestAuthorization threw an error
    case authorizationFailed(Error)

    /// enableBackgroundDelivery threw an error for a category
    case backgroundDeliveryFailed(String, Error)

    /// modelContext.insert/save threw when saving an event
    case eventSaveFailed(Error)

    /// modelContext.fetch threw when looking up an event
    case eventLookupFailed(Error)

    /// Updating an existing event failed
    case eventUpdateFailed(Error)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let error):
            return "Failed to request HealthKit authorization: \(error.localizedDescription)"
        case .backgroundDeliveryFailed(let category, let error):
            return "Failed to enable background delivery for \(category): \(error.localizedDescription)"
        case .eventSaveFailed(let error):
            return "Failed to save HealthKit event: \(error.localizedDescription)"
        case .eventLookupFailed(let error):
            return "Failed to look up HealthKit event: \(error.localizedDescription)"
        case .eventUpdateFailed(let error):
            return "Failed to update HealthKit event: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authorizationFailed:
            return "Please check that HealthKit access is enabled in Settings > Privacy > Health."
        case .backgroundDeliveryFailed:
            return "Background delivery may be unavailable. Try restarting the app."
        case .eventSaveFailed, .eventUpdateFailed:
            return "Please try again. If the problem persists, restart the app."
        case .eventLookupFailed:
            return "The event data may be temporarily unavailable. Try again later."
        }
    }

    /// The underlying error for debugging
    var underlyingError: Error {
        switch self {
        case .authorizationFailed(let error),
             .backgroundDeliveryFailed(_, let error),
             .eventSaveFailed(let error),
             .eventLookupFailed(let error),
             .eventUpdateFailed(let error):
            return error
        }
    }
}
