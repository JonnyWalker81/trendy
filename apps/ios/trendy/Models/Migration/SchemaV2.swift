//
//  SchemaV2.swift
//  trendy
//
//  Current schema (V2) - Uses UUIDv7 String id (single canonical ID)
//  This schema represents the new offline-first pattern with client-generated UUIDv7 IDs
//

import Foundation
import SwiftData

/// Schema V2: Unified ID schema with client-generated UUIDv7 string IDs
/// Migrated from V1's dual-ID pattern (UUID id + serverId) to single String id
/// Note: QueuedOperation was removed - replaced by PendingMutation
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Event.self,
            EventType.self,
            Geofence.self,
            PropertyDefinition.self,
            PendingMutation.self,
            HealthKitConfiguration.self
        ]
    }
}
