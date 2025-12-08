//
//  SyncEngine.swift
//  trendy
//
//  Centralized data synchronization service.
//  Backend is the single source of truth.
//

import Foundation
import SwiftData
import Network

/// Progress tracking for sync operations
struct SyncProgress: Equatable {
    var total: Int = 0
    var completed: Int = 0
    var phase: String = ""

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

/// Centralized sync service that manages bidirectional synchronization
/// between local SwiftData and the backend API.
@Observable
@MainActor
class SyncEngine {
    // MARK: - Sync State

    enum SyncState: Equatable {
        case idle
        case syncing(SyncPhase)
        case error(String)
    }

    enum SyncPhase: Equatable {
        case uploading
        case downloading
        case reconciling

        var description: String {
            switch self {
            case .uploading: return "Uploading changes..."
            case .downloading: return "Downloading events..."
            case .reconciling: return "Syncing..."
            }
        }
    }

    // MARK: - Observable Properties

    private(set) var state: SyncState = .idle
    private(set) var progress: SyncProgress = SyncProgress()

    // MARK: - Dependencies

    private let apiClient: APIClient
    private var modelContext: ModelContext
    private var idMappings: IDMappings

    // MARK: - Network Monitoring

    private let monitor = NWPathMonitor()
    private(set) var isOnline = false

    // MARK: - Initialization

    init(apiClient: APIClient, modelContext: ModelContext) {
        self.apiClient = apiClient
        self.modelContext = modelContext
        self.idMappings = IDMappings()

        // Set up network monitoring
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = !(self?.isOnline ?? false)
                self?.isOnline = (path.status == .satisfied)

                // Auto-sync when coming back online
                if wasOffline && (self?.isOnline ?? false) {
                    await self?.handleNetworkRestored()
                }
            }
        }
        let queue = DispatchQueue(label: "com.trendy.sync-network-monitor")
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Public API

    /// Perform a full bidirectional sync
    /// 1. Process queued offline operations
    /// 2. Upload any local items without backend IDs
    /// 3. Download all backend data
    /// 4. Reconcile (backend wins)
    func performFullSync() async throws {
        guard isOnline else {
            Log.sync.info("Skipping sync - offline")
            return
        }

        guard state == .idle || state != .syncing(.uploading) else {
            Log.sync.info("Sync already in progress")
            return
        }

        Log.sync.info("Starting full sync")
        progress = SyncProgress()

        do {
            // Phase 1: Process any queued offline operations first
            try await processQueuedOperations()

            // Phase 2: Upload offline-created items
            state = .syncing(.uploading)
            try await uploadOfflineCreated()

            // Phase 3: Download all backend data
            state = .syncing(.downloading)
            let (backendEventTypes, backendEvents, backendGeofences) = try await downloadFromBackend()

            // Phase 4: Reconcile - backend wins
            state = .syncing(.reconciling)
            try await reconcile(
                backendEventTypes: backendEventTypes,
                backendEvents: backendEvents,
                backendGeofences: backendGeofences
            )

            // Save mappings
            idMappings.saveToUserDefaults()

            state = .idle
            Log.sync.info("Full sync completed successfully")

        } catch {
            Log.sync.error("Sync failed", error: error)
            state = .error(error.localizedDescription)
            throw error
        }
    }

    /// Called when network is restored
    func handleNetworkRestored() async {
        Log.sync.info("Network restored - starting sync")
        do {
            try await performFullSync()
        } catch {
            Log.sync.error("Sync after network restore failed", error: error)
        }
    }

    /// Get current ID mappings (for EventStore to use)
    func getMappings() -> IDMappings {
        idMappings
    }

    /// Update ID mappings (for EventStore to use after local operations)
    func updateMappings(_ mappings: IDMappings) {
        self.idMappings = mappings
        idMappings.saveToUserDefaults()
    }

    // MARK: - Phase 1: Process Queued Operations

    private func processQueuedOperations() async throws {
        let descriptor = FetchDescriptor<QueuedOperation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let operations = try modelContext.fetch(descriptor)

        guard !operations.isEmpty else {
            Log.sync.debug("No queued operations to process")
            return
        }

        Log.sync.info("Processing \(operations.count) queued operations")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for operation in operations {
            do {
                try await processOperation(operation, decoder: decoder)
                modelContext.delete(operation)
            } catch {
                operation.attempts += 1
                operation.lastError = error.localizedDescription

                if operation.attempts >= 5 {
                    Log.sync.warning("Removing operation after 5 failed attempts", context: .with { ctx in
                        ctx.add("type", operation.operationType)
                        ctx.add("error", error.localizedDescription)
                    })
                    modelContext.delete(operation)
                }
            }
        }

        try modelContext.save()
    }

    private func processOperation(_ operation: QueuedOperation, decoder: JSONDecoder) async throws {
        switch operation.operationType {
        case OperationType.createEvent.rawValue:
            let request = try decoder.decode(CreateEventRequest.self, from: operation.payload)
            let apiEvent = try await apiClient.createEvent(request)
            idMappings.setEventBackendId(apiEvent.id, for: operation.entityId)

        case OperationType.updateEvent.rawValue:
            // For updates, we need the backend ID which should be in our mappings
            if let backendId = idMappings.eventBackendId(for: operation.entityId) {
                let request = try decoder.decode(UpdateEventRequest.self, from: operation.payload)
                _ = try await apiClient.updateEvent(id: backendId, request)
            }

        case OperationType.deleteEvent.rawValue:
            let backendId = String(decoding: operation.payload, as: UTF8.self)
            try await apiClient.deleteEvent(id: backendId)

        case OperationType.createEventType.rawValue:
            let request = try decoder.decode(CreateEventTypeRequest.self, from: operation.payload)
            let apiEventType = try await apiClient.createEventType(request)
            idMappings.setEventTypeBackendId(apiEventType.id, for: operation.entityId)

        case OperationType.updateEventType.rawValue:
            let queuedUpdate = try decoder.decode(QueuedEventTypeUpdate.self, from: operation.payload)
            _ = try await apiClient.updateEventType(id: queuedUpdate.backendId, queuedUpdate.request)

        case OperationType.deleteEventType.rawValue:
            let backendId = String(decoding: operation.payload, as: UTF8.self)
            try await apiClient.deleteEventType(id: backendId)

        case OperationType.createGeofence.rawValue:
            let request = try decoder.decode(CreateGeofenceRequest.self, from: operation.payload)
            let apiGeofence = try await apiClient.createGeofence(request)
            // Update the local geofence with the backend ID
            let entityId = operation.entityId
            let descriptor = FetchDescriptor<Geofence>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let geofence = try? modelContext.fetch(descriptor).first {
                geofence.backendId = apiGeofence.id
            }

        case OperationType.updateGeofence.rawValue:
            let queuedUpdate = try decoder.decode(QueuedGeofenceUpdate.self, from: operation.payload)
            _ = try await apiClient.updateGeofence(id: queuedUpdate.backendId, queuedUpdate.request)

        case OperationType.deleteGeofence.rawValue:
            let backendId = String(decoding: operation.payload, as: UTF8.self)
            try await apiClient.deleteGeofence(id: backendId)

        default:
            Log.sync.warning("Unknown operation type: \(operation.operationType)")
        }
    }

    // MARK: - Phase 2: Upload Offline-Created Items

    private func uploadOfflineCreated() async throws {
        progress.phase = "Uploading changes..."

        // Upload EventTypes first (Events depend on them)
        try await uploadOfflineEventTypes()

        // Upload Geofences before Events (Events may reference Geofences)
        try await uploadOfflineGeofences()

        // Upload Events last (depend on both EventTypes and Geofences)
        try await uploadOfflineEvents()

        idMappings.saveToUserDefaults()
    }

    private func uploadOfflineEventTypes() async throws {
        let descriptor = FetchDescriptor<EventType>()
        let localEventTypes = try modelContext.fetch(descriptor)

        let unmappedTypes = localEventTypes.filter { type in
            idMappings.eventTypeBackendId(for: type.id) == nil
        }

        guard !unmappedTypes.isEmpty else { return }

        Log.sync.info("Uploading \(unmappedTypes.count) offline-created EventTypes")
        progress.total += unmappedTypes.count

        for eventType in unmappedTypes {
            let request = CreateEventTypeRequest(
                name: eventType.name,
                color: eventType.colorHex,
                icon: eventType.iconName
            )

            do {
                let apiEventType = try await apiClient.createEventType(request)
                idMappings.setEventTypeBackendId(apiEventType.id, for: eventType.id)
                progress.completed += 1
            } catch {
                Log.sync.error("Failed to upload EventType", error: error, context: .with { ctx in
                    ctx.add("name", eventType.name)
                })
                // Continue with other types
            }
        }
    }

    private func uploadOfflineEvents() async throws {
        let descriptor = FetchDescriptor<Event>()
        let localEvents = try modelContext.fetch(descriptor)

        let unmappedEvents = localEvents.filter { event in
            idMappings.eventBackendId(for: event.id) == nil
        }

        guard !unmappedEvents.isEmpty else { return }

        Log.sync.info("Uploading \(unmappedEvents.count) offline-created Events")

        // Build batch requests (only for events with mapped EventTypes)
        var eventRequests: [(Event, CreateEventRequest)] = []

        for event in unmappedEvents {
            guard let eventType = event.eventType,
                  let backendTypeId = idMappings.eventTypeBackendId(for: eventType.id) else {
                Log.sync.warning("Skipping event without mapped EventType", context: .with { ctx in
                    ctx.add("eventId", event.id.uuidString)
                })
                continue
            }

            let apiProperties = convertLocalPropertiesToAPI(event.properties)

            // Event.geofenceId is already a backend ID (String) - use directly
            let request = CreateEventRequest(
                eventTypeId: backendTypeId,
                timestamp: event.timestamp,
                notes: event.notes,
                isAllDay: event.isAllDay,
                endDate: event.endDate,
                sourceType: event.sourceType.rawValue,
                externalId: event.externalId,
                originalTitle: event.originalTitle,
                geofenceId: event.geofenceId,
                locationLatitude: event.locationLatitude,
                locationLongitude: event.locationLongitude,
                locationName: event.locationName,
                properties: apiProperties
            )

            eventRequests.append((event, request))
        }

        progress.total += eventRequests.count

        // Batch upload (100 at a time)
        let batches = eventRequests.chunked(into: 100)

        for batch in batches {
            let requests = batch.map { $0.1 }

            do {
                let response = try await apiClient.createEventsBatch(requests)

                // Map local IDs to backend IDs from response
                for (index, apiEvent) in response.created.enumerated() {
                    if index < batch.count {
                        let localEvent = batch[index].0
                        idMappings.setEventBackendId(apiEvent.id, for: localEvent.id)
                    }
                }

                progress.completed += batch.count

            } catch {
                Log.sync.error("Batch upload failed", error: error)
                // Continue with next batch
            }
        }
    }

    private func uploadOfflineGeofences() async throws {
        // Find geofences without a backend ID (created offline)
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.backendId == nil }
        )
        let unsyncedGeofences = try modelContext.fetch(descriptor)

        guard !unsyncedGeofences.isEmpty else { return }

        Log.sync.info("Uploading \(unsyncedGeofences.count) offline-created Geofences")
        progress.total += unsyncedGeofences.count

        for geofence in unsyncedGeofences {
            let backendEntryTypeId: String? = geofence.eventTypeEntryID.flatMap { idMappings.eventTypeBackendId(for: $0) }
            let backendExitTypeId: String? = geofence.eventTypeExitID.flatMap { idMappings.eventTypeBackendId(for: $0) }

            // Don't send local ID - let backend generate the ID
            let request = CreateGeofenceRequest(
                name: geofence.name,
                latitude: geofence.latitude,
                longitude: geofence.longitude,
                radius: geofence.radius,
                eventTypeEntryId: backendEntryTypeId,
                eventTypeExitId: backendExitTypeId,
                isActive: geofence.isActive,
                notifyOnEntry: geofence.notifyOnEntry,
                notifyOnExit: geofence.notifyOnExit
            )

            do {
                let apiGeofence = try await apiClient.createGeofence(request)
                // Update local geofence with backend ID
                geofence.backendId = apiGeofence.id
                progress.completed += 1
            } catch {
                Log.sync.error("Failed to upload Geofence", error: error, context: .with { ctx in
                    ctx.add("name", geofence.name)
                })
                // Continue with other geofences
            }
        }

        try modelContext.save()
    }

    // MARK: - Phase 3: Download from Backend

    private func downloadFromBackend() async throws -> ([APIEventType], [APIEvent], [APIGeofence]) {
        progress.phase = "Downloading events..."

        let backendEventTypes = try await apiClient.getEventTypes()
        let backendEvents = try await apiClient.getAllEvents()
        let backendGeofences = try await apiClient.getGeofences()

        progress.total += backendEventTypes.count + backendEvents.count + backendGeofences.count

        Log.sync.info("Downloaded from backend", context: .with { ctx in
            ctx.add("eventTypes", backendEventTypes.count)
            ctx.add("events", backendEvents.count)
            ctx.add("geofences", backendGeofences.count)
        })

        return (backendEventTypes, backendEvents, backendGeofences)
    }

    // MARK: - Phase 4: Reconcile (Backend Wins)

    private func reconcile(
        backendEventTypes: [APIEventType],
        backendEvents: [APIEvent],
        backendGeofences: [APIGeofence]
    ) async throws {
        progress.phase = "Syncing..."

        // Build lookup sets for deletion detection
        let backendEventTypeIds = Set(backendEventTypes.map(\.id))
        let backendEventIds = Set(backendEvents.map(\.id))
        let backendGeofenceIds = Set(backendGeofences.map(\.id))

        // Reconcile EventTypes first (Events depend on them)
        try await reconcileEventTypes(backendEventTypes)

        // Reconcile Events
        try await reconcileEvents(backendEvents)

        // Reconcile Geofences
        try await reconcileGeofences(backendGeofences)

        // Delete local items that were deleted on backend
        try await deleteOrphanedItems(
            backendEventTypeIds: backendEventTypeIds,
            backendEventIds: backendEventIds,
            backendGeofenceIds: backendGeofenceIds
        )

        try modelContext.save()
    }

    private func reconcileEventTypes(_ backendTypes: [APIEventType]) async throws {
        let localDescriptor = FetchDescriptor<EventType>()
        let localTypes = try modelContext.fetch(localDescriptor)

        // Build lookup: local ID -> EventType
        let localTypeById = Dictionary(uniqueKeysWithValues: localTypes.map { ($0.id, $0) })

        for apiType in backendTypes {
            if let localId = idMappings.localEventTypeId(for: apiType.id),
               let existingType = localTypeById[localId] {
                // UPDATE existing - backend wins
                existingType.name = apiType.name
                existingType.colorHex = apiType.color
                existingType.iconName = apiType.icon
            } else {
                // Check for unmapped type with same name (case-insensitive)
                if let existingByName = localTypes.first(where: {
                    $0.name.lowercased() == apiType.name.lowercased() &&
                    idMappings.eventTypeBackendId(for: $0.id) == nil
                }) {
                    // Link existing to backend
                    existingByName.colorHex = apiType.color
                    existingByName.iconName = apiType.icon
                    idMappings.setEventTypeBackendId(apiType.id, for: existingByName.id)
                } else {
                    // CREATE new local EventType
                    let newType = EventType(
                        name: apiType.name,
                        colorHex: apiType.color,
                        iconName: apiType.icon
                    )
                    modelContext.insert(newType)
                    idMappings.setEventTypeBackendId(apiType.id, for: newType.id)
                }
            }
            progress.completed += 1
        }
    }

    private func reconcileEvents(_ backendEvents: [APIEvent]) async throws {
        let localDescriptor = FetchDescriptor<Event>()
        let localEvents = try modelContext.fetch(localDescriptor)

        // Build lookup: local ID -> Event
        let localEventById = Dictionary(uniqueKeysWithValues: localEvents.map { ($0.id, $0) })

        for apiEvent in backendEvents {
            // Find local EventType by backend ID
            guard let localTypeId = idMappings.localEventTypeId(for: apiEvent.eventTypeId) else {
                Log.sync.warning("Skipping event - no local EventType for backend ID: \(apiEvent.eventTypeId)")
                progress.completed += 1
                continue
            }

            let typeDescriptor = FetchDescriptor<EventType>(
                predicate: #Predicate { $0.id == localTypeId }
            )
            guard let localType = try modelContext.fetch(typeDescriptor).first else {
                progress.completed += 1
                continue
            }

            let localProperties = convertAPIPropertiesToLocal(apiEvent.properties)

            if let localId = idMappings.localEventId(for: apiEvent.id),
               let existingEvent = localEventById[localId] {
                // UPDATE existing - backend wins
                existingEvent.timestamp = apiEvent.timestamp
                existingEvent.eventType = localType
                existingEvent.notes = apiEvent.notes
                existingEvent.isAllDay = apiEvent.isAllDay
                existingEvent.endDate = apiEvent.endDate
                existingEvent.properties = localProperties
                existingEvent.sourceType = EventSourceType(rawValue: apiEvent.sourceType) ?? .manual
                existingEvent.externalId = apiEvent.externalId
                existingEvent.originalTitle = apiEvent.originalTitle
            } else {
                // Check for unmapped event by timestamp+type match
                let timestampTarget = apiEvent.timestamp
                if let existingByMatch = localEvents.first(where: { event in
                    event.eventType?.id == localTypeId &&
                    abs(event.timestamp.timeIntervalSince(timestampTarget)) < 1.0 &&
                    idMappings.eventBackendId(for: event.id) == nil
                }) {
                    // Link and update
                    existingByMatch.notes = apiEvent.notes
                    existingByMatch.isAllDay = apiEvent.isAllDay
                    existingByMatch.endDate = apiEvent.endDate
                    existingByMatch.properties = localProperties
                    idMappings.setEventBackendId(apiEvent.id, for: existingByMatch.id)
                } else {
                    // CREATE new local Event
                    let newEvent = Event(
                        timestamp: apiEvent.timestamp,
                        eventType: localType,
                        notes: apiEvent.notes,
                        sourceType: EventSourceType(rawValue: apiEvent.sourceType) ?? .manual,
                        externalId: apiEvent.externalId,
                        originalTitle: apiEvent.originalTitle,
                        isAllDay: apiEvent.isAllDay,
                        endDate: apiEvent.endDate,
                        properties: localProperties
                    )
                    modelContext.insert(newEvent)
                    idMappings.setEventBackendId(apiEvent.id, for: newEvent.id)
                }
            }
            progress.completed += 1
        }
    }

    private func reconcileGeofences(_ backendGeofences: [APIGeofence]) async throws {
        let localDescriptor = FetchDescriptor<Geofence>()
        let localGeofences = try modelContext.fetch(localDescriptor)

        // Build lookup: backendId -> Geofence (for geofences already synced)
        let localByBackendId = Dictionary(uniqueKeysWithValues:
            localGeofences.compactMap { g in g.backendId.map { ($0, g) } }
        )

        for apiGeofence in backendGeofences {
            // Resolve backend EventType IDs to local UUIDs
            let localEntryTypeId: UUID? = apiGeofence.eventTypeEntryId.flatMap { idMappings.localEventTypeId(for: $0) }
            let localExitTypeId: UUID? = apiGeofence.eventTypeExitId.flatMap { idMappings.localEventTypeId(for: $0) }

            if let existingGeofence = localByBackendId[apiGeofence.id] {
                // UPDATE existing - backend wins
                existingGeofence.name = apiGeofence.name
                existingGeofence.latitude = apiGeofence.latitude
                existingGeofence.longitude = apiGeofence.longitude
                existingGeofence.radius = apiGeofence.radius
                existingGeofence.eventTypeEntryID = localEntryTypeId
                existingGeofence.eventTypeExitID = localExitTypeId
                existingGeofence.isActive = apiGeofence.isActive
                existingGeofence.notifyOnEntry = apiGeofence.notifyOnEntry
                existingGeofence.notifyOnExit = apiGeofence.notifyOnExit
            } else {
                // Check for unsynced geofence by name+location match
                let targetName = apiGeofence.name
                let targetLat = apiGeofence.latitude
                let targetLon = apiGeofence.longitude

                if let existingByMatch = localGeofences.first(where: { geofence in
                    geofence.name == targetName &&
                    abs(geofence.latitude - targetLat) < 0.0001 &&
                    abs(geofence.longitude - targetLon) < 0.0001 &&
                    geofence.backendId == nil
                }) {
                    // Link and update
                    existingByMatch.backendId = apiGeofence.id
                    existingByMatch.radius = apiGeofence.radius
                    existingByMatch.eventTypeEntryID = localEntryTypeId
                    existingByMatch.eventTypeExitID = localExitTypeId
                    existingByMatch.isActive = apiGeofence.isActive
                    existingByMatch.notifyOnEntry = apiGeofence.notifyOnEntry
                    existingByMatch.notifyOnExit = apiGeofence.notifyOnExit
                } else {
                    // CREATE new local Geofence with backend ID
                    let newGeofence = Geofence(
                        name: apiGeofence.name,
                        latitude: apiGeofence.latitude,
                        longitude: apiGeofence.longitude,
                        radius: apiGeofence.radius,
                        eventTypeEntryID: localEntryTypeId,
                        eventTypeExitID: localExitTypeId,
                        isActive: apiGeofence.isActive,
                        notifyOnEntry: apiGeofence.notifyOnEntry,
                        notifyOnExit: apiGeofence.notifyOnExit
                    )
                    newGeofence.backendId = apiGeofence.id
                    modelContext.insert(newGeofence)
                }
            }
            progress.completed += 1
        }
    }

    private func deleteOrphanedItems(
        backendEventTypeIds: Set<String>,
        backendEventIds: Set<String>,
        backendGeofenceIds: Set<String>
    ) async throws {
        // Delete Events that were deleted on backend
        let eventDescriptor = FetchDescriptor<Event>()
        let localEvents = try modelContext.fetch(eventDescriptor)

        for event in localEvents {
            if let backendId = idMappings.eventBackendId(for: event.id),
               !backendEventIds.contains(backendId) {
                modelContext.delete(event)
                idMappings.removeEventMapping(for: event.id)
            }
        }

        // Delete Geofences that were deleted on backend
        let geofenceDescriptor = FetchDescriptor<Geofence>()
        let localGeofences = try modelContext.fetch(geofenceDescriptor)

        for geofence in localGeofences {
            // Only delete if it was synced (has backendId) but no longer exists on backend
            if let backendId = geofence.backendId,
               !backendGeofenceIds.contains(backendId) {
                modelContext.delete(geofence)
            }
        }

        // Delete EventTypes that were deleted on backend (only if no events reference them)
        let typeDescriptor = FetchDescriptor<EventType>()
        let localTypes = try modelContext.fetch(typeDescriptor)

        for eventType in localTypes {
            if let backendId = idMappings.eventTypeBackendId(for: eventType.id),
               !backendEventTypeIds.contains(backendId) {
                // Only delete if no events reference this type
                if eventType.events?.isEmpty ?? true {
                    modelContext.delete(eventType)
                    idMappings.removeEventTypeMapping(for: eventType.id)
                }
            }
        }
    }

    // MARK: - Property Conversion Helpers

    private func convertAPIPropertiesToLocal(_ apiProperties: [String: APIPropertyValue]?) -> [String: PropertyValue] {
        guard let apiProperties = apiProperties else { return [:] }

        var localProperties: [String: PropertyValue] = [:]
        for (key, apiValue) in apiProperties {
            guard let propType = PropertyType(rawValue: apiValue.type) else { continue }
            localProperties[key] = PropertyValue(type: propType, value: apiValue.value.value)
        }
        return localProperties
    }

    private func convertLocalPropertiesToAPI(_ properties: [String: PropertyValue]) -> [String: APIPropertyValue] {
        // Always return a dict (even if empty) - backend requires non-null properties
        return properties.mapValues { propValue in
            APIPropertyValue(
                type: propValue.type.rawValue,
                value: propValue.value
            )
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
