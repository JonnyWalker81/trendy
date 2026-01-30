//
//  WidgetDataBridge.swift
//  trendy
//
//  Shares data between the main app and widget extension via a JSON file
//  in the App Group container. This replaces the previous approach of sharing
//  the SwiftData SQLite database via the App Group container, which caused
//  0xdead10cc crashes because iOS terminates apps that hold SQLite file locks
//  in shared containers during background suspension.
//
//  Architecture:
//  - Main app WRITES widget data as JSON to the App Group container
//  - Widget extension READS this JSON for display
//  - Widget extension WRITES pending events as JSON to the App Group container
//  - Main app READS and processes pending widget events on launch/foreground
//
//  This eliminates all SQLite access from the App Group container, preventing
//  the 0xdead10cc termination that was the root cause of the "default.store"
//  error after background suspension.
//

import Foundation

/// App Group identifier for sharing data with widgets
private let widgetAppGroupIdentifier = "group.com.memento.trendy"

// MARK: - Widget Data Models

/// Snapshot of data needed by widgets, serialized to JSON in the App Group container.
/// The main app writes this after every data change.
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

/// A pending event created by the widget that needs to be imported into SwiftData.
struct WidgetPendingEvent: Codable, Identifiable {
    let id: String  // UUIDv7 string
    let eventTypeId: String
    let timestamp: Date
    let createdAt: Date

    init(eventTypeId: String, timestamp: Date) {
        self.id = UUIDv7.generate()
        self.eventTypeId = eventTypeId
        self.timestamp = timestamp
        self.createdAt = Date()
    }
}

// MARK: - File Paths

/// Centralized file path management for App Group shared files.
enum WidgetBridgeFiles {
    /// URL for the App Group container
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetAppGroupIdentifier)
    }

    /// Path for the widget data snapshot (main app writes, widget reads)
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget_snapshot.json")
    }

    /// Path for pending widget events (widget writes, main app reads)
    static var pendingEventsURL: URL? {
        containerURL?.appendingPathComponent("widget_pending_events.json")
    }
}

// MARK: - Main App Writer

/// Used by the main app to write widget data to the App Group container.
/// Call `writeSnapshot()` after any data change that widgets should reflect.
enum WidgetDataWriter {

    /// Write a snapshot of current data for widgets to read.
    /// This is a fire-and-forget operation -- widget data is best-effort.
    static func writeSnapshot(_ snapshot: WidgetSnapshot) {
        guard let url = WidgetBridgeFiles.snapshotURL else {
            Log.data.warning("WidgetDataWriter: cannot get App Group URL for snapshot")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)

            // Use NSFileCoordinator for safe cross-process writes
            let coordinator = NSFileCoordinator()
            var writeError: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &writeError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    Log.data.warning("WidgetDataWriter: failed to write snapshot", error: error)
                }
            }
            if let writeError = writeError {
                Log.data.warning("WidgetDataWriter: file coordination error", error: writeError)
            }
        } catch {
            Log.data.warning("WidgetDataWriter: failed to encode snapshot", error: error)
        }
    }

    /// Read and clear pending events written by the widget extension.
    /// Returns the pending events, or empty array if none.
    static func drainPendingEvents() -> [WidgetPendingEvent] {
        guard let url = WidgetBridgeFiles.pendingEventsURL else {
            return []
        }

        let coordinator = NSFileCoordinator()
        var readError: NSError?
        var events: [WidgetPendingEvent] = []

        coordinator.coordinate(readingItemAt: url, options: [], writingItemAt: url, options: .forReplacing, error: &readError) { readURL, writeURL in
            // Read existing events
            if let data = try? Data(contentsOf: readURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                events = (try? decoder.decode([WidgetPendingEvent].self, from: data)) ?? []
            }

            // Clear the file by writing empty array
            if !events.isEmpty {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if let emptyData = try? encoder.encode([WidgetPendingEvent]()) {
                    try? emptyData.write(to: writeURL, options: .atomic)
                }
            }
        }

        if let readError = readError {
            Log.data.warning("WidgetDataWriter: file coordination error reading pending events", error: readError)
        }

        if !events.isEmpty {
            Log.data.info("WidgetDataWriter: drained pending widget events", context: .with { ctx in
                ctx.add("count", events.count)
            })
        }

        return events
    }
}

// MARK: - Widget Reader (used by widget extension)

/// Used by the widget extension to read data from the App Group container.
/// This reads the JSON snapshot written by the main app.
enum WidgetDataReader {

    /// Read the current widget data snapshot.
    /// Returns nil if no snapshot exists or it cannot be read.
    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = WidgetBridgeFiles.snapshotURL else {
            return nil
        }

        let coordinator = NSFileCoordinator()
        var readError: NSError?
        var snapshot: WidgetSnapshot?

        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try? decoder.decode(WidgetSnapshot.self, from: data)
        }

        return snapshot
    }

    /// Write a pending event for the main app to process.
    /// Called by the widget's QuickLogIntent when creating an event.
    static func writePendingEvent(_ event: WidgetPendingEvent) {
        guard let url = WidgetBridgeFiles.pendingEventsURL else {
            return
        }

        let coordinator = NSFileCoordinator()
        var coordError: NSError?

        coordinator.coordinate(readingItemAt: url, options: [], writingItemAt: url, options: .forReplacing, error: &coordError) { readURL, writeURL in
            // Read existing pending events
            var events: [WidgetPendingEvent] = []
            if let data = try? Data(contentsOf: readURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                events = (try? decoder.decode([WidgetPendingEvent].self, from: data)) ?? []
            }

            // Append new event
            events.append(event)

            // Write back
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(events) {
                try? data.write(to: writeURL, options: .atomic)
            }
        }
    }
}
