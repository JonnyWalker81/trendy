//
//  MigrationManager.swift
//  trendy
//
//  Manages migration of local SwiftData to backend API
//

import Foundation
import SwiftData

/// Manager for migrating local data to backend
@Observable
class MigrationManager {
    // Progress tracking
    private(set) var totalEventTypes = 0
    private(set) var migratedEventTypes = 0
    private(set) var totalPropertyDefinitions = 0
    private(set) var migratedPropertyDefinitions = 0
    private(set) var totalEvents = 0
    private(set) var migratedEvents = 0
    private(set) var currentOperation = ""
    private(set) var isComplete = false
    private(set) var errorMessage: String?

    // UUID mapping: iOS UUID → Backend UUID string
    private var eventTypeMapping: [UUID: String] = [:]
    private var propertyDefinitionMapping: [UUID: String] = [:]

    private let apiClient: APIClient
    private let modelContext: ModelContext

    /// Initialize MigrationManager with dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData context for local data access
    ///   - apiClient: API client for backend communication
    init(modelContext: ModelContext, apiClient: APIClient) {
        self.modelContext = modelContext
        self.apiClient = apiClient
    }

    // MARK: - Migration Progress

    var progress: Double {
        let totalItems = Double(totalEventTypes + totalPropertyDefinitions + totalEvents)
        guard totalItems > 0 else { return 0 }
        let completedItems = Double(migratedEventTypes + migratedPropertyDefinitions + migratedEvents)
        return completedItems / totalItems
    }

    var progressText: String {
        if isComplete {
            return "Migration complete!"
        } else if !errorMessage.isNone {
            return "Migration failed"
        } else {
            return currentOperation
        }
    }

    // MARK: - Main Migration Flow

    /// Perform full migration from local to backend
    func performMigration() async throws {
        Log.migration.info("Starting migration")

        do {
            // Check if there's any data to migrate
            try await checkDataToMigrate()

            guard totalEventTypes > 0 || totalEvents > 0 else {
                // No data to migrate, mark as complete
                Log.migration.info("No data to migrate")
                isComplete = true
                return
            }

            // Step 1: Migrate EventTypes
            try await migrateEventTypes()

            // Step 2: Migrate PropertyDefinitions
            try await migratePropertyDefinitions()

            // Step 3: Migrate Events
            try await migrateEvents()

            // Mark as complete
            await MainActor.run {
                self.isComplete = true
                self.currentOperation = "Migration completed successfully!"
            }

            Log.migration.info("Migration completed successfully", context: .with { ctx in
                ctx.add("event_types", migratedEventTypes)
                ctx.add("property_definitions", migratedPropertyDefinitions)
                ctx.add("events", migratedEvents)
            })
        } catch {
            Log.migration.error("Migration failed", error: error)
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.currentOperation = "Migration failed"
            }
            throw error
        }
    }

    // MARK: - Data Check

    private func checkDataToMigrate() async throws {
        let eventTypeDescriptor = FetchDescriptor<EventType>()
        let propertyDefDescriptor = FetchDescriptor<PropertyDefinition>()
        let eventDescriptor = FetchDescriptor<Event>()

        let eventTypes = try modelContext.fetch(eventTypeDescriptor)
        let propertyDefs = try modelContext.fetch(propertyDefDescriptor)
        let events = try modelContext.fetch(eventDescriptor)

        await MainActor.run {
            self.totalEventTypes = eventTypes.count
            self.totalPropertyDefinitions = propertyDefs.count
            self.totalEvents = events.count
            self.currentOperation = "Found \(eventTypes.count) event types, \(propertyDefs.count) properties, and \(events.count) events to sync"
        }

        // Give UI a moment to update
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    // MARK: - EventType Migration

    private func migrateEventTypes() async throws {
        await MainActor.run {
            self.currentOperation = "Syncing event types..."
        }

        let descriptor = FetchDescriptor<EventType>()
        let localEventTypes = try modelContext.fetch(descriptor)

        // Get existing backend event types for duplicate detection
        let backendEventTypes = try await apiClient.getEventTypes()

        for (index, localType) in localEventTypes.enumerated() {
            // Check if event type already exists on backend (by name, case-insensitive)
            if let existingType = backendEventTypes.first(where: {
                $0.name.lowercased() == localType.name.lowercased()
            }) {
                // Use existing backend event type
                eventTypeMapping[localType.id] = existingType.id
                Log.migration.debug("EventType already exists on backend", context: .with { ctx in
                    ctx.add("name", localType.name)
                    ctx.add("backend_id", existingType.id)
                })
            } else {
                // Create new event type on backend
                let request = CreateEventTypeRequest(
                    name: localType.name,
                    color: localType.colorHex,
                    icon: localType.iconName
                )

                let created = try await apiClient.createEventType(request)
                eventTypeMapping[localType.id] = created.id
                Log.migration.debug("Created EventType on backend", context: .with { ctx in
                    ctx.add("name", localType.name)
                    ctx.add("backend_id", created.id)
                })
            }

            await MainActor.run {
                self.migratedEventTypes = index + 1
                self.currentOperation = "Synced \(index + 1)/\(self.totalEventTypes) event types"
            }
        }
    }

    // MARK: - PropertyDefinition Migration

    private func migratePropertyDefinitions() async throws {
        await MainActor.run {
            self.currentOperation = "Syncing property definitions..."
        }

        let descriptor = FetchDescriptor<PropertyDefinition>()
        let localPropertyDefs = try modelContext.fetch(descriptor)

        for (index, localPropDef) in localPropertyDefs.enumerated() {
            // Get backend event type ID for this property definition
            guard let backendEventTypeId = eventTypeMapping[localPropDef.eventTypeId] else {
                Log.migration.debug("Skipping property definition without mapped event type", context: .with { ctx in
                    ctx.add("property_id", localPropDef.id)
                })
                await MainActor.run {
                    self.migratedPropertyDefinitions = index + 1
                }
                continue
            }

            // Convert default value to AnyCodable
            let defaultValue: AnyCodable? = localPropDef.defaultValue

            // Create request
            let request = CreatePropertyDefinitionRequest(
                eventTypeId: backendEventTypeId,
                key: localPropDef.key,
                label: localPropDef.label,
                propertyType: localPropDef.propertyType.rawValue,
                options: localPropDef.propertyType == .select ? localPropDef.options : nil,
                defaultValue: defaultValue,
                displayOrder: localPropDef.displayOrder
            )

            // Create on backend
            let created = try await apiClient.createPropertyDefinition(
                eventTypeId: backendEventTypeId,
                request
            )
            propertyDefinitionMapping[localPropDef.id] = created.id
            Log.migration.debug("Created PropertyDefinition on backend", context: .with { ctx in
                ctx.add("label", localPropDef.label)
                ctx.add("backend_id", created.id)
            })

            await MainActor.run {
                self.migratedPropertyDefinitions = index + 1
                self.currentOperation = "Synced \(index + 1)/\(self.totalPropertyDefinitions) property definitions"
            }
        }
    }

    // MARK: - Event Migration

    private func migrateEvents() async throws {
        await MainActor.run {
            self.currentOperation = "Syncing events..."
        }

        let descriptor = FetchDescriptor<Event>()
        let localEvents = try modelContext.fetch(descriptor)

        // Process events in batches to avoid timeout
        let batchSize = 50
        var batch: [Event] = []

        for (index, localEvent) in localEvents.enumerated() {
            batch.append(localEvent)

            // Process batch when full or at end
            if batch.count >= batchSize || index == localEvents.count - 1 {
                try await processBatch(batch)
                batch.removeAll()
            }

            await MainActor.run {
                self.migratedEvents = index + 1
                self.currentOperation = "Synced \(index + 1)/\(self.totalEvents) events"
            }
        }
    }

    private func processBatch(_ events: [Event]) async throws {
        for event in events {
            try await migrateEvent(event)
        }
    }

    private func migrateEvent(_ localEvent: Event) async throws {
        // Skip events without event type
        guard let eventType = localEvent.eventType,
              let backendEventTypeId = eventTypeMapping[eventType.id] else {
            Log.migration.debug("Skipping event without event type", context: .with { ctx in
                ctx.add("event_id", localEvent.id)
            })
            return
        }

        // Check for duplicate by externalId (if it's an imported event)
        if let externalId = localEvent.externalId {
            let existing = try? await apiClient.getEventByExternalId(externalId)
            if existing != nil {
                Log.migration.debug("Event with externalId already exists, skipping", context: .with { ctx in
                    ctx.add("external_id", externalId)
                })
                return
            }
        }

        // Convert properties to API format
        let apiProperties: [String: APIPropertyValue]? = localEvent.properties.isEmpty ? nil : localEvent.properties.mapValues { propValue in
            APIPropertyValue(
                type: propValue.type.rawValue,
                value: propValue.value
            )
        }

        // Create request
        let request = CreateEventRequest(
            eventTypeId: backendEventTypeId,
            timestamp: localEvent.timestamp,
            notes: localEvent.notes,
            isAllDay: localEvent.isAllDay,
            endDate: localEvent.endDate,
            sourceType: localEvent.sourceType.rawValue,
            externalId: localEvent.externalId,
            originalTitle: localEvent.originalTitle,
            geofenceId: nil,
            locationLatitude: nil,
            locationLongitude: nil,
            locationName: nil,
            properties: apiProperties
        )

        // Create on backend
        let _ = try await apiClient.createEvent(request)
    }

    // MARK: - Retry Logic

    /// Retry migration from last failure point
    func retryMigration() async throws {
        await MainActor.run {
            self.errorMessage = nil
            self.currentOperation = "Retrying migration..."
        }

        try await performMigration()
    }

    // MARK: - Skip Migration

    /// Skip migration and mark as complete (for fresh installs with no local data)
    func skipMigration() {
        isComplete = true
        currentOperation = "Migration skipped - no local data to sync"
    }
}

// MARK: - Helper Extensions

extension Optional where Wrapped == String {
    var isNone: Bool {
        return self == nil
    }
}
