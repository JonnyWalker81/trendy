//
//  EventError.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation

enum EventError: LocalizedError {
    case saveFailed
    case deleteFailed
    case fetchFailed
    case eventTypeNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save event"
        case .deleteFailed:
            return "Failed to delete event"
        case .fetchFailed:
            return "Failed to fetch events"
        case .eventTypeNotFound:
            return "Event type not found"
        case .invalidData:
            return "Invalid data provided"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .saveFailed, .deleteFailed, .fetchFailed:
            return "Please try again. If the problem persists, restart the app."
        case .eventTypeNotFound:
            return "Please create an event type first."
        case .invalidData:
            return "Please check your input and try again."
        }
    }
}