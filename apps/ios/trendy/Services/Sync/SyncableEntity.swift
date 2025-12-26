//
//  SyncableEntity.swift
//  trendy
//
//  Protocol for entities that can be synced with the backend server.
//  With UUIDv7, the same ID is used locally and on the server.
//

import Foundation
import SwiftData

/// Protocol for entities that support synchronization with the backend.
/// With UUIDv7, entities have a single ID that is the same locally and on the server.
protocol SyncableEntity: PersistentModel {
    /// UUIDv7 identifier - same on client and server
    var id: String { get }

    /// Current sync status
    var syncStatus: SyncStatus { get set }

    /// Raw sync status string (for SwiftData persistence)
    var syncStatusRaw: String { get set }
}

/// Extension with convenience methods
extension SyncableEntity {
    /// Whether this entity has been synced with the server
    var isSynced: Bool {
        syncStatus == .synced
    }

    /// Whether this entity is pending sync
    var isPending: Bool {
        syncStatus == .pending
    }

    /// Whether this entity failed to sync
    var isFailed: Bool {
        syncStatus == .failed
    }

    /// Mark this entity as synced
    func markSynced() {
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
