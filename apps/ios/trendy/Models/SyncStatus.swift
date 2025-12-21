//
//  SyncStatus.swift
//  trendy
//
//  Represents the synchronization status of an entity with the backend.
//

import Foundation

/// Represents the sync status of a local entity
enum SyncStatus: String, Codable, CaseIterable {
    /// Entity created locally, awaiting server ID assignment
    case pending = "pending"

    /// Entity has been synced with server and has a valid server ID
    case synced = "synced"

    /// Sync failed and needs retry
    case failed = "failed"

    /// Human-readable description for UI display
    var description: String {
        switch self {
        case .pending:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .failed:
            return "Sync failed"
        }
    }

    /// SF Symbol icon name for this status
    var iconName: String {
        switch self {
        case .pending:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
