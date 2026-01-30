//
//  WidgetDataManager.swift
//  TrendyWidgets
//
//  Handles all data operations for the widget extension by reading from a
//  JSON snapshot written by the main app to the App Group container.
//
//  ARCHITECTURE NOTE: This NO LONGER opens a SwiftData/SQLite database.
//  Previously, the widget opened the same SQLite database as the main app
//  via the App Group container. This caused 0xdead10cc crashes because iOS
//  terminates apps that hold SQLite file locks in shared containers during
//  background suspension.
//
//  Now, the main app writes a JSON snapshot to the App Group, and the widget
//  reads this lightweight file. Interactive widget actions (QuickLog) write
//  a pending event JSON that the main app picks up on next foreground.
//

import Foundation
import WidgetKit

/// App Group identifier for sharing data with the main app
private let widgetAppGroupIdentifier = "group.com.memento.trendy"

// MARK: - Shared Data Models (mirrored from WidgetDataBridge.swift in main app)

/// Snapshot of data needed by widgets.
/// This must match the struct in the main app's WidgetDataBridge.swift.
struct WidgetSnapshot: Codable {
    let updatedAt: Date
    let eventTypes: [WidgetEventType]
    let recentEvents: [WidgetEvent]
    let todayEvents: [WidgetEvent]

    struct WidgetEventType: Codable, Identifiable {
        let id: String
        let name: String
        let colorHex: String
        let iconName: String
    }

    struct WidgetEvent: Codable, Identifiable {
        let id: String
        let eventTypeId: String
        let timestamp: Date
        let sourceTypeRaw: String
        let notes: String?
        let endDate: Date?
        let geofenceId: String?
        let healthKitSampleId: String?
    }
}

/// A pending event created by the widget that the main app will import.
struct WidgetPendingEvent: Codable, Identifiable {
    let id: String
    let eventTypeId: String
    let timestamp: Date
    let createdAt: Date

    init(eventTypeId: String, timestamp: Date) {
        self.id = UUID().uuidString  // Simple UUID for widget-created events
        self.eventTypeId = eventTypeId
        self.timestamp = timestamp
        self.createdAt = Date()
    }
}

// MARK: - File Paths

private enum WidgetBridgeFiles {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetAppGroupIdentifier)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget_snapshot.json")
    }

    static var pendingEventsURL: URL? {
        containerURL?.appendingPathComponent("widget_pending_events.json")
    }
}

// MARK: - Widget Data Manager

/// Manages data access for widgets using the JSON bridge.
/// All data is read from a JSON file written by the main app.
final class WidgetDataManager {
    static let shared = WidgetDataManager()

    /// Cached snapshot for performance (avoids re-reading file on every call)
    private var cachedSnapshot: WidgetSnapshot?
    private var cacheTimestamp: Date?
    private let cacheMaxAge: TimeInterval = 5.0  // Re-read file if older than 5 seconds

    private init() {}

    // MARK: - Snapshot Access

    /// Get the current widget data snapshot, using cache if fresh enough.
    private func getSnapshot() -> WidgetSnapshot? {
        // Return cache if fresh
        if let cached = cachedSnapshot,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheMaxAge {
            return cached
        }

        // Read from file
        guard let url = WidgetBridgeFiles.snapshotURL else { return nil }

        let coordinator = NSFileCoordinator()
        var readError: NSError?
        var snapshot: WidgetSnapshot?

        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try? decoder.decode(WidgetSnapshot.self, from: data)
        }

        cachedSnapshot = snapshot
        cacheTimestamp = Date()
        return snapshot
    }

    // MARK: - Read Operations

    /// Fetches all EventTypes sorted by name
    func getAllEventTypes() async throws -> [WidgetSnapshot.WidgetEventType] {
        guard let snapshot = getSnapshot() else { return [] }
        return snapshot.eventTypes.sorted { $0.name < $1.name }
    }

    /// Fetches a specific EventType by its ID
    func getEventType(id: String) async throws -> WidgetSnapshot.WidgetEventType? {
        guard let snapshot = getSnapshot() else { return nil }
        return snapshot.eventTypes.first { $0.id == id }
    }

    /// Fetches today's events for a specific EventType
    func getTodayEvents(for eventTypeId: String) async throws -> [WidgetSnapshot.WidgetEvent] {
        guard let snapshot = getSnapshot() else { return [] }
        return snapshot.todayEvents.filter { $0.eventTypeId == eventTypeId }
    }

    /// Fetches today's total event count for a specific EventType
    func getTodayCount(for eventTypeId: String) async throws -> Int {
        let events = try await getTodayEvents(for: eventTypeId)
        return events.count
    }

    /// Fetches recent events across all types
    func getRecentEvents(limit: Int = 5) async throws -> [WidgetSnapshot.WidgetEvent] {
        guard let snapshot = getSnapshot() else { return [] }
        return Array(snapshot.recentEvents.prefix(limit))
    }

    /// Fetches today's events across all types
    func getTodayEventsAll() async throws -> [WidgetSnapshot.WidgetEvent] {
        guard let snapshot = getSnapshot() else { return [] }
        return snapshot.todayEvents
    }

    /// Calculates the current streak for an EventType.
    /// Note: Streak calculation requires historical data beyond today.
    /// The snapshot only contains today's events and recent events, so streak
    /// calculation is approximate (based on what's in the recent events list).
    func getStreak(for eventTypeId: String) async throws -> Int {
        guard let snapshot = getSnapshot() else { return 0 }

        // Filter events for this type from all available events
        let typeEvents = (snapshot.recentEvents + snapshot.todayEvents)
            .filter { $0.eventTypeId == eventTypeId }
            .sorted { $0.timestamp > $1.timestamp }

        return calculateStreak(from: typeEvents)
    }

    /// Gets the last event timestamp for an EventType
    func getLastEventTime(for eventTypeId: String) async throws -> Date? {
        guard let snapshot = getSnapshot() else { return nil }

        // Check today's events first (most recent), then recent events
        let todayMatch = snapshot.todayEvents
            .filter { $0.eventTypeId == eventTypeId }
            .sorted { $0.timestamp > $1.timestamp }
            .first

        let recentMatch = snapshot.recentEvents
            .filter { $0.eventTypeId == eventTypeId }
            .first

        return todayMatch?.timestamp ?? recentMatch?.timestamp
    }

    // MARK: - Streak Calculation

    private func calculateStreak(from events: [WidgetSnapshot.WidgetEvent]) -> Int {
        guard !events.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())

        // Check if there's an event today
        let todayEvents = events.filter { calendar.isDate($0.timestamp, inSameDayAs: currentDate) }
        if todayEvents.isEmpty {
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }

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

    /// Creates a pending event for the main app to process.
    /// The event is written to a JSON file in the App Group.
    /// The main app will import it into SwiftData on next foreground.
    func createEvent(eventTypeId: String, timestamp: Date = Date()) async throws {
        guard WidgetBridgeFiles.pendingEventsURL != nil else {
            throw WidgetDataError.containerNotAvailable
        }

        let pendingEvent = WidgetPendingEvent(eventTypeId: eventTypeId, timestamp: timestamp)
        writePendingEvent(pendingEvent)

        // Notify main app via Darwin notification
        notifyMainAppOfChange()
    }

    /// Write a pending event to the App Group JSON file
    private func writePendingEvent(_ event: WidgetPendingEvent) {
        guard let url = WidgetBridgeFiles.pendingEventsURL else { return }

        let coordinator = NSFileCoordinator()
        var coordError: NSError?

        coordinator.coordinate(readingItemAt: url, options: [], writingItemAt: url, options: .forReplacing, error: &coordError) { readURL, writeURL in
            var events: [WidgetPendingEvent] = []
            if let data = try? Data(contentsOf: readURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                events = (try? decoder.decode([WidgetPendingEvent].self, from: data)) ?? []
            }

            events.append(event)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(events) {
                try? data.write(to: writeURL, options: .atomic)
            }
        }
    }

    /// Sends a Darwin notification to wake the main app for processing
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
