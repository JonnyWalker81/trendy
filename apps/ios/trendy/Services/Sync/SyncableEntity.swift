//
//  SyncableEntity.swift
//  trendy
//
//  Protocol for entities that can be synced with the backend server.
//

import Foundation
import SwiftData

/// Protocol for entities that support synchronization with the backend.
/// Entities conforming to this protocol have a local UUID and an optional server-generated ID.
protocol SyncableEntity: PersistentModel {
    /// Local SwiftData identifier
    var id: UUID { get }

    /// Server-generated ID - nil until synced with backend
    var serverId: String? { get set }

    /// Current sync status
    var syncStatus: SyncStatus { get set }

    /// Raw sync status string (for SwiftData persistence)
    var syncStatusRaw: String { get set }
}

/// Extension with convenience methods
extension SyncableEntity {
    /// Whether this entity has been synced with the server
    var isSynced: Bool {
        serverId != nil && syncStatus == .synced
    }

    /// Whether this entity is pending sync
    var isPending: Bool {
        syncStatus == .pending
    }

    /// Whether this entity failed to sync
    var isFailed: Bool {
        syncStatus == .failed
    }

    /// Mark this entity as synced with the given server ID
    func markSynced(withServerId id: String) {
        self.serverId = id
        self.syncStatus = .synced
    }

    /// Mark this entity as failed
    func markFailed() {
        self.syncStatus = .failed
    }

    /// Mark this entity as pending
    func markPending() {
        self.syncStatus = .pending
    }
}
