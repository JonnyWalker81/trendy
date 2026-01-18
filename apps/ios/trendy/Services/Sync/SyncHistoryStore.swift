//
//  SyncHistoryStore.swift
//  trendy
//
//  Persists sync history with bounded storage.
//  Records up to 10 sync operations for display in settings.
//

import Foundation

// MARK: - SyncHistoryEntry

/// A single sync operation record
struct SyncHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let eventsCount: Int
    let eventTypesCount: Int
    let status: Status
    let errorMessage: String?
    let durationMs: Int

    enum Status: String, Codable {
        case success
        case partialSuccess
        case failed
    }

    /// Human-readable summary of sync counts
    var summary: String {
        var parts: [String] = []
        if eventsCount > 0 {
            parts.append("\(eventsCount) event\(eventsCount == 1 ? "" : "s")")
        }
        if eventTypesCount > 0 {
            parts.append("\(eventTypesCount) event type\(eventTypesCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }

    /// Duration formatted as human-readable string
    var formattedDuration: String {
        if durationMs < 1000 {
            return "\(durationMs)ms"
        } else {
            let seconds = Double(durationMs) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}

// MARK: - SyncHistoryStore

/// Persistent store for sync history with bounded storage
@Observable
final class SyncHistoryStore {

    // MARK: - Constants

    private static let storageKey = "sync_history"
    private static let maxEntries = 10

    // MARK: - Properties

    /// All stored sync history entries (newest first)
    private(set) var entries: [SyncHistoryEntry] = []

    // MARK: - Initialization

    init() {
        loadFromStorage()
    }

    // MARK: - Public Methods

    /// Record a new sync history entry
    /// - Parameter entry: The entry to record
    func record(_ entry: SyncHistoryEntry) {
        entries.insert(entry, at: 0)

        // Prune to max entries
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }

        saveToStorage()
    }

    /// Convenience method to record a successful sync
    /// - Parameters:
    ///   - events: Number of events synced
    ///   - eventTypes: Number of event types synced
    ///   - durationMs: Duration of sync in milliseconds
    func recordSuccess(events: Int, eventTypes: Int, durationMs: Int) {
        let entry = SyncHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            eventsCount: events,
            eventTypesCount: eventTypes,
            status: .success,
            errorMessage: nil,
            durationMs: durationMs
        )
        record(entry)
    }

    /// Convenience method to record a failed sync
    /// - Parameters:
    ///   - errorMessage: Description of the error
    ///   - durationMs: Duration before failure in milliseconds
    func recordFailure(errorMessage: String, durationMs: Int) {
        let entry = SyncHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            eventsCount: 0,
            eventTypesCount: 0,
            status: .failed,
            errorMessage: errorMessage,
            durationMs: durationMs
        )
        record(entry)
    }

    /// Clear all sync history
    func clearHistory() {
        entries = []
        saveToStorage()
    }

    // MARK: - Private Methods

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            // No stored data - start with empty array
            return
        }

        do {
            let decoded = try JSONDecoder().decode([SyncHistoryEntry].self, from: data)
            entries = decoded
        } catch {
            // If decode fails, start with empty array (don't crash)
            Log.sync.warning("Failed to decode sync history, starting fresh", context: .with { ctx in
                ctx.add("error", error.localizedDescription)
            })
            entries = []
        }
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            Log.sync.error("Failed to save sync history", error: error)
        }
    }
}
