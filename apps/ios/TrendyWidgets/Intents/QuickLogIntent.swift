//
//  QuickLogIntent.swift
//  TrendyWidgets
//
//  AppIntent for quick event logging from interactive widgets.
//

import AppIntents
import SwiftData
import WidgetKit

/// AppIntent that logs an event when user taps an interactive widget button
struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Event"
    static var description = IntentDescription("Quickly log an event from the widget")

    @Parameter(title: "Event Type ID")
    var eventTypeId: String

    init() {}

    init(eventTypeId: String) {
        self.eventTypeId = eventTypeId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let dataManager = WidgetDataManager.shared

        do {
            try await dataManager.createEvent(eventTypeId: eventTypeId, timestamp: Date())

            // Reload all widget timelines to reflect the new event
            WidgetCenter.shared.reloadAllTimelines()

            return .result()
        } catch {
            throw QuickLogError.saveFailed
        }
    }
}

enum QuickLogError: Error, LocalizedError {
    case invalidEventTypeId
    case eventTypeNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidEventTypeId:
            return "Invalid event type ID"
        case .eventTypeNotFound:
            return "Event type not found"
        case .saveFailed:
            return "Failed to save event"
        }
    }
}
