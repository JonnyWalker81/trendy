//
//  WidgetDataManager.swift
//  TrendyWidgets
//
//  Handles all SwiftData operations for the widget extension.
//

import Foundation
import SwiftData
import WidgetKit

/// Manages data access for widgets using the shared App Group SwiftData store
@MainActor
final class WidgetDataManager {
    static let shared = WidgetDataManager()

    private var modelContainer: ModelContainer?

    private init() {
        setupModelContainer()
    }

    private func setupModelContainer() {
        let schema = Schema([
            Event.self,
            EventType.self,
            PropertyDefinition.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupIdentifier)
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Widget: Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Read Operations

    /// Fetches all EventTypes sorted by name
    func getAllEventTypes() async throws -> [EventType] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<EventType>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    /// Fetches a specific EventType by its UUID
    func getEventType(id: UUID) async throws -> EventType? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Fetches today's events for a specific EventType
    func getTodayEvents(for eventTypeId: UUID) async throws -> [Event] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.eventType?.id == eventTypeId &&
                event.timestamp >= startOfDay &&
                event.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetches today's total event count for a specific EventType
    func getTodayCount(for eventTypeId: UUID) async throws -> Int {
        let events = try await getTodayEvents(for: eventTypeId)
        return events.count
    }

    /// Fetches recent events across all types
    func getRecentEvents(limit: Int = 5) async throws -> [Event] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)

        var descriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Fetches today's events across all types
    func getTodayEventsAll() async throws -> [Event] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.timestamp >= startOfDay &&
                event.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Calculates the current streak for an EventType
    func getStreak(for eventTypeId: UUID) async throws -> Int {
        guard let container = modelContainer else { return 0 }
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.eventType?.id == eventTypeId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let events = try context.fetch(descriptor)

        return calculateStreak(from: events)
    }

    /// Gets the last event timestamp for an EventType
    func getLastEventTime(for eventTypeId: UUID) async throws -> Date? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)

        var descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.eventType?.id == eventTypeId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let events = try context.fetch(descriptor)
        return events.first?.timestamp
    }

    // MARK: - Streak Calculation

    private func calculateStreak(from events: [Event]) -> Int {
        guard !events.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())

        // Check if there's an event today
        let todayEvents = events.filter { calendar.isDate($0.timestamp, inSameDayAs: currentDate) }
        if todayEvents.isEmpty {
            // Check yesterday - streak is still active if yesterday had events
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

        // Count consecutive days with events
        while true {
            let dayEvents = events.filter { calendar.isDate($0.timestamp, inSameDayAs: currentDate) }
            if dayEvents.isEmpty {
                break
            }
            streak += 1
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

        return streak
    }

    // MARK: - Write Operations

    /// Creates a new event for quick logging from widgets
    func createEvent(eventTypeId: UUID, timestamp: Date = Date()) async throws {
        guard let container = modelContainer else {
            throw WidgetDataError.containerNotAvailable
        }

        let context = ModelContext(container)

        // Find the EventType
        let typeDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.id == eventTypeId }
        )
        guard let eventType = try context.fetch(typeDescriptor).first else {
            throw WidgetDataError.eventTypeNotFound
        }

        // Create the new event
        let newEvent = Event(
            timestamp: timestamp,
            eventType: eventType,
            sourceType: .manual
        )

        context.insert(newEvent)
        try context.save()

        // Notify main app of the change via Darwin notification
        notifyMainAppOfChange()
    }

    /// Sends a Darwin notification to wake the main app for backend sync
    private func notifyMainAppOfChange() {
        let notificationName = "com.memento.trendy.widgetDataChanged" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName),
            nil,
            nil,
            true
        )
    }
}

// MARK: - Error Types

enum WidgetDataError: Error, LocalizedError {
    case containerNotAvailable
    case eventTypeNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "Widget data container is not available"
        case .eventTypeNotFound:
            return "Event type not found"
        case .saveFailed:
            return "Failed to save event"
        }
    }
}
