//
//  SchemaV1.swift
//  trendy
//
//  Legacy schema (V1) - Uses UUID id + optional serverId
//  This schema represents the old dual-ID pattern before UUIDv7 migration
//

import Foundation
import SwiftData

/// Schema V1: Original schema with UUID id + serverId pattern
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            EventV1.self,
            EventTypeV1.self,
            GeofenceV1.self,
            PropertyDefinitionV1.self,
            QueuedOperationV1.self,
            PendingMutationV1.self,
            HealthKitConfigurationV1.self
        ]
    }

    // MARK: - V1 Models

    @Model
    final class EventV1 {
        var id: UUID
        var serverId: String?
        var syncStatusRaw: String = "pending"
        var timestamp: Date
        var notes: String?
        @Relationship var eventType: EventTypeV1?
        var sourceTypeRaw: String = "manual"
        var externalId: String?
        var originalTitle: String?
        var isAllDay: Bool = false
        var endDate: Date?
        var calendarEventId: String?
        var geofenceId: String?
        var locationLatitude: Double?
        var locationLongitude: Double?
        var locationName: String?
        var healthKitSampleId: String?
        var healthKitCategory: String?
        var propertiesData: Data?

        init() {
            self.id = UUID()
            self.timestamp = Date()
        }
    }

    @Model
    final class EventTypeV1 {
        var id: UUID
        var serverId: String?
        var syncStatusRaw: String = "pending"
        var name: String
        var colorHex: String
        var iconName: String
        var createdAt: Date
        @Relationship(inverse: \EventV1.eventType) var events: [EventV1]?
        @Relationship(inverse: \PropertyDefinitionV1.eventType) var propertyDefinitions: [PropertyDefinitionV1]?

        init() {
            self.id = UUID()
            self.name = ""
            self.colorHex = "#007AFF"
            self.iconName = "circle.fill"
            self.createdAt = Date()
        }
    }

    @Model
    final class GeofenceV1 {
        var id: UUID
        var serverId: String?
        var syncStatusRaw: String = "pending"
        var name: String
        var latitude: Double
        var longitude: Double
        var radius: Double
        var eventTypeEntryID: String?
        var eventTypeExitID: String?
        var isActive: Bool
        var notifyOnEntry: Bool
        var notifyOnExit: Bool
        var createdAt: Date
        var updatedAt: Date

        init() {
            self.id = UUID()
            self.name = ""
            self.latitude = 0
            self.longitude = 0
            self.radius = 100
            self.isActive = true
            self.notifyOnEntry = false
            self.notifyOnExit = false
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    final class PropertyDefinitionV1 {
        var id: UUID
        var serverId: String?
        var syncStatusRaw: String = "pending"
        var eventTypeId: String
        var key: String
        var label: String
        var propertyTypeRaw: String
        var isRequired: Bool
        var defaultValueData: Data?
        var optionsData: Data?
        var displayOrder: Int
        var createdAt: Date
        @Relationship var eventType: EventTypeV1?

        init() {
            self.id = UUID()
            self.eventTypeId = ""
            self.key = ""
            self.label = ""
            self.propertyTypeRaw = "text"
            self.isRequired = false
            self.displayOrder = 0
            self.createdAt = Date()
        }
    }

    @Model
    final class QueuedOperationV1 {
        var id: UUID
        var operationType: String
        var entityType: String
        var entityId: String
        var payload: Data?
        var createdAt: Date
        var attemptCount: Int

        init() {
            self.id = UUID()
            self.operationType = ""
            self.entityType = ""
            self.entityId = ""
            self.createdAt = Date()
            self.attemptCount = 0
        }
    }

    @Model
    final class PendingMutationV1 {
        var id: UUID
        var clientRequestId: String
        var entityType: String
        var operation: String
        var entityId: String
        var payload: Data
        var createdAt: Date
        var attemptCount: Int
        var lastError: String?

        init() {
            self.id = UUID()
            self.clientRequestId = ""
            self.entityType = ""
            self.operation = ""
            self.entityId = ""
            self.payload = Data()
            self.createdAt = Date()
            self.attemptCount = 0
        }
    }

    @Model
    final class HealthKitConfigurationV1 {
        var id: UUID
        var healthDataCategory: String
        var eventTypeID: UUID?
        var isEnabled: Bool
        var notifyOnDetection: Bool
        var createdAt: Date
        var updatedAt: Date

        init() {
            self.id = UUID()
            self.healthDataCategory = ""
            self.isEnabled = true
            self.notifyOnDetection = false
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
}
