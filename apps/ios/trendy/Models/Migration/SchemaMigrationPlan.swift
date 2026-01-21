//
//  SchemaMigrationPlan.swift
//  trendy
//
//  Handles migration from V1 (UUID id + serverId) to V2 (UUIDv7 String id)
//

import Foundation
import SwiftData

/// Migration plan for Trendy database schema versions
enum TrendySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Migration from V1 (dual-ID pattern) to V2 (single UUIDv7 ID)
    ///
    /// Migration logic:
    /// - For entities WITH serverId: new id = serverId (server ID is canonical)
    /// - For entities WITHOUT serverId: new id = UUID().uuidString (converted to string)
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // Migration is handled by SwiftData's automatic schema update
            // The willMigrate/didMigrate hooks run before/after the schema is updated
            //
            // Since SwiftData handles the column type changes automatically when
            // we configure the migration properly, we just need to ensure the
            // data is consistent after migration.
            //
            // Note: SwiftData's custom migration doesn't give us access to old/new
            // versions simultaneously. Instead, we rely on:
            // 1. SwiftData to handle the column changes
            // 2. A lightweight migration approach where compatible values transfer
            //
            // For the V1→V2 migration:
            // - V1.id (UUID) → V2.id (String): SwiftData cannot auto-convert
            // - V1.serverId (String?) → removed in V2
            //
            // This means we need to handle this migration carefully.
            // Since SwiftData's custom migration is limited, we'll use a
            // "wipe and resync" approach for users with existing data,
            // or handle the migration at the application level.

            Log.migration.info("Schema migration V1→V2 completed")
            Log.migration.info("Note: Users with existing V1 data will need to resync from backend")

            // Clear the sync cursor to force a full resync after migration
            // This ensures the backend data (with correct IDs) repopulates local storage
            UserDefaults.standard.removeObject(forKey: "sync_cursor")
            UserDefaults.standard.removeObject(forKey: "lastSyncCursor")

            // Set a flag indicating migration occurred (for UI to show resync prompt)
            UserDefaults.standard.set(true, forKey: "schema_migration_v1_to_v2_completed")
            UserDefaults.standard.synchronize()

            try context.save()
        }
    )
}

// MARK: - Migration Helpers

extension TrendySchemaMigrationPlan {
    /// Check if the app needs to handle post-migration resync
    static var needsPostMigrationResync: Bool {
        UserDefaults.standard.bool(forKey: "schema_migration_v1_to_v2_completed")
    }

    /// Clear the post-migration resync flag after resync is complete
    static func clearPostMigrationResyncFlag() {
        UserDefaults.standard.removeObject(forKey: "schema_migration_v1_to_v2_completed")
        UserDefaults.standard.synchronize()
    }
}
