//
//  SyncEngine.swift
//  trendy
//
//  Swift actor responsible for synchronizing local SwiftData with the backend.
//  Implements single-flight sync, cursor-based incremental pull, and idempotent mutations.
//

import Foundation
import SwiftData

/// Observable state for the sync engine
enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)
}

/// Actor that manages synchronization between local SwiftData and the backend.
/// Uses single-flight pattern to prevent concurrent syncs and cursor-based
/// incremental pull for efficient data transfer.
actor SyncEngine {
    // MARK: - Dependencies

    private let apiClient: APIClient
    private let modelContainer: ModelContainer

    // MARK: - State

    private var lastSyncCursor: Int64 = 0
    private var isSyncing = false
    private var forceBootstrapOnNextSync = false

    // MARK: - Observable State (MainActor)

    @MainActor public private(set) var state: SyncState = .idle
    @MainActor public private(set) var pendingCount: Int = 0

    // MARK: - Constants

    /// Cursor key is environment-specific to prevent sync issues when switching between dev/prod
    private var cursorKey: String {
        "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
    }
    private let changeFeedLimit = 100

    // MARK: - Initialization

    init(apiClient: APIClient, modelContainer: ModelContainer) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
        // Use computed cursorKey which includes environment
        self.lastSyncCursor = Int64(UserDefaults.standard.integer(forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)"))
    }

    // MARK: - Public API

    /// Perform a full sync: flush pending mutations, then pull changes.
    /// This is idempotent and safe to call multiple times - only one sync
    /// will run at a time (single-flight pattern).
    func performSync() async {
        guard !isSyncing else {
            Log.sync.debug("Sync already in progress, skipping")
            return
        }

        isSyncing = true
        await updateState(.syncing)

        defer {
            isSyncing = false
        }

        do {
            Log.sync.info("Starting sync", context: .with { ctx in
                ctx.add("cursor", Int(lastSyncCursor))
                ctx.add("is_first_sync", lastSyncCursor == 0)
            })

            // Step 1: Flush any pending mutations to the server
            try await flushPendingMutations()

            // Step 2: If this is first sync (cursor=0) or force bootstrap is requested,
            // do a full bootstrap fetch. This handles the case where data existed
            // before change_log was implemented, or when user requests a full resync.
            let shouldBootstrap = lastSyncCursor == 0 || forceBootstrapOnNextSync
            let wasForceBootstrap = forceBootstrapOnNextSync
            if shouldBootstrap {
                Log.sync.info("Performing bootstrap fetch", context: .with { ctx in
                    ctx.add("cursor_was_zero", lastSyncCursor == 0)
                    ctx.add("force_bootstrap_flag", forceBootstrapOnNextSync)
                })
                forceBootstrapOnNextSync = false // Reset the flag
                try await bootstrapFetch()
            }

            // Step 3: Pull incremental changes from the server
            // SKIP pullChanges after a FORCED bootstrap - we already have current state
            // from direct API calls, and the change_log may have stale entries that
            // would re-create deleted events.
            if wasForceBootstrap {
                // After forced bootstrap, get the latest cursor (max change_log ID) from the backend.
                // This ensures we skip ALL existing change_log entries, only pulling truly new changes.
                do {
                    let latestCursor = try await apiClient.getLatestCursor()
                    lastSyncCursor = latestCursor
                    UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                    Log.sync.info("Skipped pullChanges after forced bootstrap, cursor set to latest", context: .with { ctx in
                        ctx.add("latest_cursor", Int(latestCursor))
                    })
                } catch {
                    // Fallback: if we can't get the latest cursor, use a high value
                    // This may skip some legitimate changes, but prevents stale data recreation
                    lastSyncCursor = 1_000_000_000
                    UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                    Log.sync.warning("Could not get latest cursor, using fallback", context: .with { ctx in
                        ctx.add("fallback_cursor", Int(lastSyncCursor))
                        ctx.add("error", error.localizedDescription)
                    })
                }
            } else {
                try await pullChanges()
            }

            await updateState(.idle)
            Log.sync.info("Sync completed successfully", context: .with { ctx in
                ctx.add("new_cursor", Int(lastSyncCursor))
            })
        } catch {
            Log.sync.error("Sync failed", error: error)
            await updateState(.error(error.localizedDescription))
        }
    }

    /// Force a full resync by resetting the cursor
    func forceFullResync() async {
        Log.sync.info("Force full resync requested")

        // If a sync is already running, wait for it to complete
        while isSyncing {
            Log.sync.debug("Waiting for in-progress sync to complete...")
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Reset cursor and set flag to force bootstrap
        lastSyncCursor = 0
        UserDefaults.standard.set(0, forKey: cursorKey)
        forceBootstrapOnNextSync = true

        Log.sync.info("Cursor reset to 0, starting forced bootstrap sync")
        await performSync()
    }

    /// Queue a mutation for sync. The mutation will be flushed on the next sync.
    func queueMutation(
        entityType: MutationEntityType,
        operation: MutationOperation,
        localEntityId: UUID,
        serverEntityId: String? = nil,
        payload: Data
    ) async throws {
        let context = ModelContext(modelContainer)

        let mutation = PendingMutation(
            entityType: entityType,
            operation: operation,
            localEntityId: localEntityId,
            serverEntityId: serverEntityId,
            payload: payload
        )

        context.insert(mutation)
        try context.save()

        await updatePendingCount()
        Log.sync.debug("Queued mutation", context: .with { ctx in
            ctx.add("entity_type", entityType.rawValue)
            ctx.add("operation", operation.rawValue)
            ctx.add("local_id", localEntityId.uuidString)
        })
    }

    /// Get the current pending mutation count
    func getPendingCount() async -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingMutation>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Private: Flush Pending Mutations

    private func flushPendingMutations() async throws {
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        let mutations = try localStore.fetchPendingMutations()
        guard !mutations.isEmpty else {
            Log.sync.debug("No pending mutations to flush")
            return
        }

        Log.sync.info("Flushing pending mutations", context: .with { ctx in
            ctx.add("count", mutations.count)
        })

        for mutation in mutations {
            do {
                try await flushMutation(mutation, localStore: localStore)
                context.delete(mutation)
            } catch let error as APIError where error.isDuplicateError {
                // Duplicate error - the event already exists on the server
                // This can happen if:
                // 1. The same event was created twice (race condition)
                // 2. Migration created duplicates
                // 3. Unique constraint violation
                Log.sync.warning("Duplicate detected, marking as synced", context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("operation", mutation.operation.rawValue)
                    ctx.add("local_id", mutation.localEntityId.uuidString)
                })
                // Mark the local entity as synced since equivalent data exists on server
                try markEntitySyncedAfterDuplicate(mutation, context: context)
                context.delete(mutation)
            } catch {
                mutation.recordFailure(error: error.localizedDescription)

                if mutation.hasExceededRetryLimit {
                    Log.sync.error("Mutation exceeded retry limit, marking entity as failed", context: .with { ctx in
                        ctx.add("entity_type", mutation.entityType.rawValue)
                        ctx.add("operation", mutation.operation.rawValue)
                        ctx.add("attempts", mutation.attempts)
                    })
                    // Mark the entity as failed
                    try markEntityFailed(mutation, context: context)
                    context.delete(mutation)
                }
            }
        }

        try context.save()
        await updatePendingCount()
    }

    private func flushMutation(_ mutation: PendingMutation, localStore: LocalStore) async throws {
        switch mutation.operation {
        case .create:
            try await flushCreate(mutation, localStore: localStore)
        case .update:
            try await flushUpdate(mutation)
        case .delete:
            try await flushDelete(mutation)
        }
    }

    private func flushCreate(_ mutation: PendingMutation, localStore: LocalStore) async throws {
        switch mutation.entityType {
        case .event:
            let request = try JSONDecoder().decode(CreateEventRequest.self, from: mutation.payload)
            let response = try await apiClient.createEventWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try localStore.reconcilePendingEvent(localId: mutation.localEntityId, serverId: response.id)

        case .eventType:
            let request = try JSONDecoder().decode(CreateEventTypeRequest.self, from: mutation.payload)
            let response = try await apiClient.createEventTypeWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try localStore.reconcilePendingEventType(localId: mutation.localEntityId, serverId: response.id)

        case .geofence:
            let request = try JSONDecoder().decode(CreateGeofenceRequest.self, from: mutation.payload)
            let response = try await apiClient.createGeofenceWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try localStore.reconcilePendingGeofence(localId: mutation.localEntityId, serverId: response.id)

        case .propertyDefinition:
            // PropertyDefinitions are created via event type endpoint
            // This requires special handling
            Log.sync.warning("PropertyDefinition create not yet implemented in flush")
        }

        try localStore.save()
    }

    private func flushUpdate(_ mutation: PendingMutation) async throws {
        guard let serverId = mutation.serverEntityId else {
            throw SyncError.missingServerId
        }

        switch mutation.entityType {
        case .event:
            let request = try JSONDecoder().decode(UpdateEventRequest.self, from: mutation.payload)
            _ = try await apiClient.updateEvent(id: serverId, request)

        case .eventType:
            let request = try JSONDecoder().decode(UpdateEventTypeRequest.self, from: mutation.payload)
            _ = try await apiClient.updateEventType(id: serverId, request)

        case .geofence:
            let request = try JSONDecoder().decode(UpdateGeofenceRequest.self, from: mutation.payload)
            _ = try await apiClient.updateGeofence(id: serverId, request)

        case .propertyDefinition:
            let request = try JSONDecoder().decode(UpdatePropertyDefinitionRequest.self, from: mutation.payload)
            _ = try await apiClient.updatePropertyDefinition(id: serverId, request)
        }
    }

    private func flushDelete(_ mutation: PendingMutation) async throws {
        guard let serverId = mutation.serverEntityId else {
            throw SyncError.missingServerId
        }

        switch mutation.entityType {
        case .event:
            try await apiClient.deleteEvent(id: serverId)
        case .eventType:
            try await apiClient.deleteEventType(id: serverId)
        case .geofence:
            try await apiClient.deleteGeofence(id: serverId)
        case .propertyDefinition:
            try await apiClient.deletePropertyDefinition(id: serverId)
        }
    }

    private func markEntityFailed(_ mutation: PendingMutation, context: ModelContext) throws {
        let entityId = mutation.localEntityId

        switch mutation.entityType {
        case .event:
            let descriptor = FetchDescriptor<Event>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let event = try context.fetch(descriptor).first {
                event.syncStatus = .failed
            }

        case .eventType:
            let descriptor = FetchDescriptor<EventType>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let eventType = try context.fetch(descriptor).first {
                eventType.syncStatus = .failed
            }

        case .geofence:
            let descriptor = FetchDescriptor<Geofence>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let geofence = try context.fetch(descriptor).first {
                geofence.syncStatus = .failed
            }

        case .propertyDefinition:
            let descriptor = FetchDescriptor<PropertyDefinition>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let propDef = try context.fetch(descriptor).first {
                propDef.syncStatus = .failed
            }
        }
    }

    /// Handle duplicate error by deleting the local entity.
    /// The server already has equivalent data, so we delete the local version
    /// and let the next sync pull the server's authoritative copy.
    private func markEntitySyncedAfterDuplicate(_ mutation: PendingMutation, context: ModelContext) throws {
        let entityId = mutation.localEntityId

        switch mutation.entityType {
        case .event:
            let descriptor = FetchDescriptor<Event>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let event = try context.fetch(descriptor).first {
                // Delete the local duplicate - server's version will be pulled on next sync
                context.delete(event)
                Log.sync.info("Deleted local duplicate event", context: .with { ctx in
                    ctx.add("local_id", entityId.uuidString)
                })
            }

        case .eventType:
            let descriptor = FetchDescriptor<EventType>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let eventType = try context.fetch(descriptor).first {
                context.delete(eventType)
                Log.sync.info("Deleted local duplicate event type", context: .with { ctx in
                    ctx.add("local_id", entityId.uuidString)
                })
            }

        case .geofence:
            let descriptor = FetchDescriptor<Geofence>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let geofence = try context.fetch(descriptor).first {
                context.delete(geofence)
                Log.sync.info("Deleted local duplicate geofence", context: .with { ctx in
                    ctx.add("local_id", entityId.uuidString)
                })
            }

        case .propertyDefinition:
            let descriptor = FetchDescriptor<PropertyDefinition>(
                predicate: #Predicate { $0.id == entityId }
            )
            if let propDef = try context.fetch(descriptor).first {
                context.delete(propDef)
                Log.sync.info("Deleted local duplicate property definition", context: .with { ctx in
                    ctx.add("local_id", entityId.uuidString)
                })
            }
        }
    }

    // MARK: - Private: Pull Changes

    private func pullChanges() async throws {
        var hasMore = true

        while hasMore {
            let response = try await apiClient.getChanges(
                since: lastSyncCursor,
                limit: changeFeedLimit
            )

            if !response.changes.isEmpty {
                try await applyChanges(response.changes)
            }

            // Only update cursor if it advances forward
            // This prevents cursor reset to 0 causing duplicate bootstrap syncs
            if response.nextCursor > lastSyncCursor {
                lastSyncCursor = response.nextCursor
                UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
            }
            hasMore = response.hasMore

            Log.sync.debug("Pulled changes", context: .with { ctx in
                ctx.add("count", response.changes.count)
                ctx.add("cursor", Int(lastSyncCursor))
                ctx.add("has_more", hasMore)
            })
        }
    }

    private func applyChanges(_ changes: [ChangeEntry]) async throws {
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        for change in changes {
            do {
                try applyChange(change, localStore: localStore)
            } catch {
                Log.sync.error("Failed to apply change", error: error, context: .with { ctx in
                    ctx.add("change_id", Int(change.id))
                    ctx.add("entity_type", change.entityType)
                    ctx.add("operation", change.operation)
                })
                // Continue with other changes even if one fails
            }
        }

        try context.save()
    }

    private func applyChange(_ change: ChangeEntry, localStore: LocalStore) throws {
        switch change.operation {
        case "create", "update":
            try applyUpsert(change, localStore: localStore)
        case "delete":
            try applyDelete(change, localStore: localStore)
        default:
            Log.sync.warning("Unknown operation", context: .with { ctx in
                ctx.add("operation", change.operation)
            })
        }
    }

    private func applyUpsert(_ change: ChangeEntry, localStore: LocalStore) throws {
        guard let data = change.data else {
            Log.sync.warning("Missing data for upsert", context: .with { ctx in
                ctx.add("change_id", Int(change.id))
            })
            return
        }

        switch change.entityType {
        case "event":
            try localStore.upsertEvent(serverId: change.entityId) { event in
                // Apply data from change
                if let timestamp = data.timestamp {
                    event.timestamp = timestamp
                }
                if let notes = data.notes {
                    event.notes = notes
                }
                if let isAllDay = data.isAllDay {
                    event.isAllDay = isAllDay
                }
                if let endDate = data.endDate {
                    event.endDate = endDate
                }
                // Event type ID needs special handling - look up local EventType by serverId
                if let eventTypeId = data.eventTypeId {
                    event.eventTypeServerId = eventTypeId
                    // Establish the SwiftData relationship
                    if let localEventType = try? localStore.findEventType(byServerId: eventTypeId) {
                        event.eventType = localEventType
                    }
                }
                if let sourceType = data.sourceType {
                    event.sourceType = EventSourceType(rawValue: sourceType) ?? .manual
                }
                if let externalId = data.externalId {
                    event.externalId = externalId
                }
                if let originalTitle = data.originalTitle {
                    event.originalTitle = originalTitle
                }
                if let geofenceId = data.geofenceId {
                    event.geofenceServerId = geofenceId
                }
                if let lat = data.locationLatitude, let lon = data.locationLongitude {
                    event.locationLatitude = lat
                    event.locationLongitude = lon
                }
                if let locationName = data.locationName {
                    event.locationName = locationName
                }
                // Sync properties from change feed
                if let apiProperties = data.properties {
                    event.properties = Self.convertAPIProperties(apiProperties)
                }
            }

        case "event_type":
            try localStore.upsertEventType(serverId: change.entityId) { eventType in
                if let name = data.name {
                    eventType.name = name
                }
                if let color = data.color {
                    eventType.colorHex = color
                }
                if let icon = data.icon {
                    eventType.iconName = icon
                }
            }

        case "geofence":
            try localStore.upsertGeofence(serverId: change.entityId) { geofence in
                if let name = data.name {
                    geofence.name = name
                }
                if let lat = data.latitude {
                    geofence.latitude = lat
                }
                if let lon = data.longitude {
                    geofence.longitude = lon
                }
                if let radius = data.radius {
                    geofence.radius = radius
                }
                if let isActive = data.isActive {
                    geofence.isActive = isActive
                }
                if let notifyOnEntry = data.notifyOnEntry {
                    geofence.notifyOnEntry = notifyOnEntry
                }
                if let notifyOnExit = data.notifyOnExit {
                    geofence.notifyOnExit = notifyOnExit
                }
                // Event type IDs handled separately via lookup
                if let entryId = data.eventTypeEntryId {
                    // Need to look up local EventType by serverId and get its local ID
                    if let localEventType = try? localStore.findEventType(byServerId: entryId) {
                        geofence.eventTypeEntryID = localEventType.id
                    }
                }
                if let exitId = data.eventTypeExitId {
                    if let localEventType = try? localStore.findEventType(byServerId: exitId) {
                        geofence.eventTypeExitID = localEventType.id
                    }
                }
            }

        case "property_definition":
            // PropertyDefinitions need eventTypeId lookup
            if let eventTypeServerId = data.eventTypeId,
               let eventType = try? localStore.findEventType(byServerId: eventTypeServerId) {
                try localStore.upsertPropertyDefinition(serverId: change.entityId, eventTypeId: eventType.id) { propDef in
                    if let key = data.key {
                        propDef.key = key
                    }
                    if let label = data.label {
                        propDef.label = label
                    }
                    if let propertyType = data.propertyType {
                        propDef.propertyType = PropertyType(rawValue: propertyType) ?? .text
                    }
                    if let displayOrder = data.displayOrder {
                        propDef.displayOrder = displayOrder
                    }
                    if let options = data.options {
                        propDef.options = options
                    }
                }
            }

        default:
            Log.sync.warning("Unknown entity type", context: .with { ctx in
                ctx.add("entity_type", change.entityType)
            })
        }
    }

    private func applyDelete(_ change: ChangeEntry, localStore: LocalStore) throws {
        switch change.entityType {
        case "event":
            try localStore.deleteEventByServerId(change.entityId)
        case "event_type":
            try localStore.deleteEventTypeByServerId(change.entityId)
        case "geofence":
            try localStore.deleteGeofenceByServerId(change.entityId)
        case "property_definition":
            try localStore.deletePropertyDefinitionByServerId(change.entityId)
        default:
            Log.sync.warning("Unknown entity type for delete", context: .with { ctx in
                ctx.add("entity_type", change.entityType)
            })
        }
    }

    // MARK: - Private: Cleanup Orphaned Entities

    /// Remove local entities that don't have a serverId.
    /// These are orphaned local records that were never synced to the backend.
    /// During bootstrap, we want the backend to be the source of truth.
    private func cleanupOrphanedEntities(context: ModelContext) throws {
        // Delete EventTypes without serverId
        let orphanedEventTypes = FetchDescriptor<EventType>(
            predicate: #Predicate { $0.serverId == nil }
        )
        let eventTypesToDelete = try context.fetch(orphanedEventTypes)
        Log.sync.info("Cleanup: removing orphaned event types", context: .with { ctx in
            ctx.add("count", eventTypesToDelete.count)
        })
        for eventType in eventTypesToDelete {
            context.delete(eventType)
        }

        // Delete Events without serverId
        let orphanedEvents = FetchDescriptor<Event>(
            predicate: #Predicate { $0.serverId == nil }
        )
        let eventsToDelete = try context.fetch(orphanedEvents)
        Log.sync.info("Cleanup: removing orphaned events", context: .with { ctx in
            ctx.add("count", eventsToDelete.count)
        })
        for event in eventsToDelete {
            context.delete(event)
        }

        // Delete Geofences without serverId
        let orphanedGeofences = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.serverId == nil }
        )
        let geofencesToDelete = try context.fetch(orphanedGeofences)
        Log.sync.info("Cleanup: removing orphaned geofences", context: .with { ctx in
            ctx.add("count", geofencesToDelete.count)
        })
        for geofence in geofencesToDelete {
            context.delete(geofence)
        }

        // Delete PropertyDefinitions without serverId
        let orphanedPropDefs = FetchDescriptor<PropertyDefinition>(
            predicate: #Predicate { $0.serverId == nil }
        )
        let propDefsToDelete = try context.fetch(orphanedPropDefs)
        Log.sync.info("Cleanup: removing orphaned property definitions", context: .with { ctx in
            ctx.add("count", propDefsToDelete.count)
        })
        for propDef in propDefsToDelete {
            context.delete(propDef)
        }

        // Save the deletions
        try context.save()
        Log.sync.info("Cleanup: orphaned entities removed")
    }

    /// Remove local entities whose serverId is not in the set of valid backend IDs.
    /// This handles stale data from deleted backend records or sync issues.
    private func removeStaleEntities(
        context: ModelContext,
        validEventTypeIds: Set<String>,
        validEventIds: Set<String>,
        validGeofenceIds: Set<String>,
        validPropertyDefinitionIds: Set<String>
    ) throws {
        // Remove stale Events (have serverId but it's not in backend)
        let allEvents = FetchDescriptor<Event>()
        let localEvents = try context.fetch(allEvents)

        // Diagnostic logging
        let eventsWithNilServerId = localEvents.filter { $0.serverId == nil }.count
        let eventsWithServerId = localEvents.filter { $0.serverId != nil }.count
        Log.sync.info("Cleanup: event diagnostic", context: .with { ctx in
            ctx.add("total_local_events", localEvents.count)
            ctx.add("events_with_nil_serverId", eventsWithNilServerId)
            ctx.add("events_with_serverId", eventsWithServerId)
            ctx.add("valid_backend_event_ids", validEventIds.count)
        })

        var staleEventCount = 0
        var nilServerIdCount = 0
        for event in localEvents {
            if let serverId = event.serverId {
                if !validEventIds.contains(serverId) {
                    context.delete(event)
                    staleEventCount += 1
                }
            } else {
                // Also delete events with nil serverId (orphaned)
                context.delete(event)
                nilServerIdCount += 1
            }
        }
        Log.sync.info("Cleanup: removing stale events", context: .with { ctx in
            ctx.add("stale_count", staleEventCount)
            ctx.add("nil_serverId_count", nilServerIdCount)
            ctx.add("total_deleted", staleEventCount + nilServerIdCount)
        })

        // Remove stale EventTypes
        let allEventTypes = FetchDescriptor<EventType>()
        let localEventTypes = try context.fetch(allEventTypes)
        var staleEventTypeCount = 0
        for eventType in localEventTypes {
            if let serverId = eventType.serverId, !validEventTypeIds.contains(serverId) {
                context.delete(eventType)
                staleEventTypeCount += 1
            }
        }
        Log.sync.info("Cleanup: removing stale event types", context: .with { ctx in
            ctx.add("count", staleEventTypeCount)
        })

        // Remove stale Geofences
        let allGeofences = FetchDescriptor<Geofence>()
        let localGeofences = try context.fetch(allGeofences)
        var staleGeofenceCount = 0
        for geofence in localGeofences {
            if let serverId = geofence.serverId, !validGeofenceIds.contains(serverId) {
                context.delete(geofence)
                staleGeofenceCount += 1
            }
        }
        Log.sync.info("Cleanup: removing stale geofences", context: .with { ctx in
            ctx.add("count", staleGeofenceCount)
        })

        // Remove stale PropertyDefinitions
        let allPropDefs = FetchDescriptor<PropertyDefinition>()
        let localPropDefs = try context.fetch(allPropDefs)
        var stalePropDefCount = 0
        for propDef in localPropDefs {
            if let serverId = propDef.serverId, !validPropertyDefinitionIds.contains(serverId) {
                context.delete(propDef)
                stalePropDefCount += 1
            }
        }
        Log.sync.info("Cleanup: removing stale property definitions", context: .with { ctx in
            ctx.add("count", stalePropDefCount)
        })

        try context.save()
        Log.sync.info("Cleanup: stale entities removed")
    }

    // MARK: - Private: Bootstrap Fetch (Initial Sync)

    /// Fetch all data from the backend when cursor is 0 (first sync).
    /// This handles the case where data existed before the change_log was implemented.
    private func bootstrapFetch() async throws {
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        // First, clean up any orphaned local entities (those without serverId)
        // This prevents duplicates when backend data is fetched
        try cleanupOrphanedEntities(context: context)

        // Step 1: Fetch and upsert all EventTypes first (Events reference them)
        Log.sync.info("Bootstrap: fetching event types")
        let eventTypes = try await apiClient.getEventTypes()
        Log.sync.info("Bootstrap: received event types", context: .with { ctx in
            ctx.add("count", eventTypes.count)
            for (index, et) in eventTypes.prefix(5).enumerated() {
                ctx.add("event_type_\(index)", "\(et.id): \(et.name)")
            }
        })

        for apiEventType in eventTypes {
            try localStore.upsertEventType(serverId: apiEventType.id) { eventType in
                eventType.name = apiEventType.name
                eventType.colorHex = apiEventType.color
                eventType.iconName = apiEventType.icon
            }
        }

        // Step 2: Fetch and upsert all Geofences (Events may reference them)
        Log.sync.info("Bootstrap: fetching geofences")
        let geofences = try await apiClient.getGeofences()
        Log.sync.info("Bootstrap: received geofences", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        for apiGeofence in geofences {
            try localStore.upsertGeofence(serverId: apiGeofence.id) { geofence in
                geofence.name = apiGeofence.name
                geofence.latitude = apiGeofence.latitude
                geofence.longitude = apiGeofence.longitude
                geofence.radius = apiGeofence.radius
                geofence.isActive = apiGeofence.isActive
                geofence.notifyOnEntry = apiGeofence.notifyOnEntry
                geofence.notifyOnExit = apiGeofence.notifyOnExit
                // Look up local EventTypes by server ID for entry/exit references
                if let entryId = apiGeofence.eventTypeEntryId {
                    if let localEventType = try? localStore.findEventType(byServerId: entryId) {
                        geofence.eventTypeEntryID = localEventType.id
                    }
                }
                if let exitId = apiGeofence.eventTypeExitId {
                    if let localEventType = try? localStore.findEventType(byServerId: exitId) {
                        geofence.eventTypeExitID = localEventType.id
                    }
                }
            }
        }

        // Step 3: Fetch and upsert all Events
        Log.sync.info("Bootstrap: fetching events")
        let events = try await apiClient.getAllEvents()
        Log.sync.info("Bootstrap: received events", context: .with { ctx in
            ctx.add("count", events.count)
            for (index, ev) in events.prefix(5).enumerated() {
                ctx.add("event_\(index)", "\(ev.id): \(ev.eventTypeId) @ \(ev.timestamp)")
            }
        })

        for apiEvent in events {
            let event = try localStore.upsertEvent(serverId: apiEvent.id) { event in
                event.timestamp = apiEvent.timestamp
                event.notes = apiEvent.notes
                event.isAllDay = apiEvent.isAllDay
                event.endDate = apiEvent.endDate
                event.eventTypeServerId = apiEvent.eventTypeId
                event.sourceType = EventSourceType(rawValue: apiEvent.sourceType) ?? .manual
                event.externalId = apiEvent.externalId
                event.originalTitle = apiEvent.originalTitle
                event.geofenceServerId = apiEvent.geofenceId
                event.locationLatitude = apiEvent.locationLatitude
                event.locationLongitude = apiEvent.locationLongitude
                event.locationName = apiEvent.locationName
                // Sync properties from backend
                if let apiProperties = apiEvent.properties {
                    event.properties = Self.convertAPIProperties(apiProperties)
                }
            }
            // Establish the SwiftData relationship to EventType
            if let localEventType = try? localStore.findEventType(byServerId: apiEvent.eventTypeId) {
                event.eventType = localEventType
            }
        }

        // Step 4: Fetch property definitions for each event type
        Log.sync.info("Bootstrap: fetching property definitions")
        var allPropertyDefinitionIds: [String] = []
        for apiEventType in eventTypes {
            do {
                let propDefs = try await apiClient.getPropertyDefinitions(eventTypeId: apiEventType.id)
                if let localEventType = try? localStore.findEventType(byServerId: apiEventType.id) {
                    for apiPropDef in propDefs {
                        try localStore.upsertPropertyDefinition(serverId: apiPropDef.id, eventTypeId: localEventType.id) { propDef in
                            propDef.key = apiPropDef.key
                            propDef.label = apiPropDef.label
                            propDef.propertyType = PropertyType(rawValue: apiPropDef.propertyType) ?? .text
                            propDef.displayOrder = apiPropDef.displayOrder
                            propDef.options = apiPropDef.options ?? []
                        }
                        allPropertyDefinitionIds.append(apiPropDef.id)
                    }
                }
            } catch {
                Log.sync.warning("Failed to fetch property definitions for event type", context: .with { ctx in
                    ctx.add("event_type_id", apiEventType.id)
                    ctx.add("error", error.localizedDescription)
                })
                // Continue with other event types
            }
        }
        Log.sync.info("Bootstrap: received property definitions", context: .with { ctx in
            ctx.add("count", allPropertyDefinitionIds.count)
        })

        // Save all upserts
        try context.save()

        // Step 5: Remove stale local entities that no longer exist on the backend
        // This ensures local database matches backend exactly
        let validEventTypeIds = Set(eventTypes.map { $0.id })
        let validEventIds = Set(events.map { $0.id })
        let validGeofenceIds = Set(geofences.map { $0.id })
        let validPropertyDefinitionIds = Set(allPropertyDefinitionIds)

        try removeStaleEntities(
            context: context,
            validEventTypeIds: validEventTypeIds,
            validEventIds: validEventIds,
            validGeofenceIds: validGeofenceIds,
            validPropertyDefinitionIds: validPropertyDefinitionIds
        )

        // Verification: count remaining records after cleanup
        let finalEventCount = try context.fetchCount(FetchDescriptor<Event>())
        let finalEventTypeCount = try context.fetchCount(FetchDescriptor<EventType>())
        let finalGeofenceCount = try context.fetchCount(FetchDescriptor<Geofence>())

        Log.sync.info("Bootstrap fetch completed", context: .with { ctx in
            ctx.add("backend_event_types", eventTypes.count)
            ctx.add("backend_geofences", geofences.count)
            ctx.add("backend_events", events.count)
            ctx.add("backend_property_definitions", allPropertyDefinitionIds.count)
            ctx.add("final_local_events", finalEventCount)
            ctx.add("final_local_event_types", finalEventTypeCount)
            ctx.add("final_local_geofences", finalGeofenceCount)
        })
    }

    // MARK: - Private: State Updates

    @MainActor
    private func updateState(_ newState: SyncState) {
        state = newState
    }

    private func updatePendingCount() async {
        let count = await getPendingCount()
        await MainActor.run {
            pendingCount = count
        }
    }

    // MARK: - Private: Property Conversion

    /// Convert API property values to local PropertyValue format
    private static func convertAPIProperties(_ apiProperties: [String: APIPropertyValue]) -> [String: PropertyValue] {
        var localProperties: [String: PropertyValue] = [:]
        for (key, apiValue) in apiProperties {
            let propertyType = PropertyType(rawValue: apiValue.type) ?? .text
            localProperties[key] = PropertyValue(type: propertyType, value: apiValue.value.value)
        }
        return localProperties
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case missingServerId
    case encodingFailed
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .missingServerId:
            return "Server ID is required for update/delete operations"
        case .encodingFailed:
            return "Failed to encode mutation payload"
        case .unknown(let message):
            return message
        }
    }
}
