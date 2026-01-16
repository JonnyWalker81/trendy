//
//  GeofenceError.swift
//  trendy
//
//  Custom error types for geofence operations
//

import Foundation

/// Errors that can occur during geofence operations
enum GeofenceError: LocalizedError {
    /// Failed to save a geofence entry event
    /// - Parameters:
    ///   - String: The geofence name
    ///   - Error: The underlying error
    case entryEventSaveFailed(String, Error)

    /// Failed to save a geofence exit event
    /// - Parameters:
    ///   - String: The geofence name
    ///   - Error: The underlying error
    case exitEventSaveFailed(String, Error)

    /// Geofence not found in database
    /// - Parameter String: The geofence identifier
    case geofenceNotFound(String)

    /// EventType not found for geofence
    /// - Parameter String: The geofence name
    case eventTypeMissing(String)

    var errorDescription: String? {
        switch self {
        case .entryEventSaveFailed(let name, _):
            return "Failed to save entry event for '\(name)'"
        case .exitEventSaveFailed(let name, _):
            return "Failed to save exit event for '\(name)'"
        case .geofenceNotFound(let identifier):
            return "Geofence not found: \(identifier)"
        case .eventTypeMissing(let name):
            return "Event type missing for geofence '\(name)'"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .entryEventSaveFailed, .exitEventSaveFailed:
            return "The event could not be saved. Please check your storage and try again."
        case .geofenceNotFound:
            return "The geofence may have been deleted. Please refresh your geofences."
        case .eventTypeMissing:
            return "Please assign an event type to this geofence in settings."
        }
    }

    /// The underlying error, if any
    var underlyingError: Error? {
        switch self {
        case .entryEventSaveFailed(_, let error),
             .exitEventSaveFailed(_, let error):
            return error
        case .geofenceNotFound, .eventTypeMissing:
            return nil
        }
    }
}
