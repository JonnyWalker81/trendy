//
//  SyncEngine.swift
//  trendy
//
//  Swift actor responsible for synchronizing local SwiftData with the backend.
//  Uses UUIDv7 for all IDs - same ID on client and server, no reconciliation needed.
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
///
/// With UUIDv7:
/// - Client generates IDs at creation time
/// - No server/local ID distinction
/// - No reconciliation needed after create
/// - ID is the same everywhere
actor SyncEngine {
    // MARK: - Dependencies

    private let apiClient: APIClient
    private let modelContainer: ModelContainer

    // MARK: - State

    private var lastSyncCursor: Int64 = 0
    private var isSyncing = false
    private var forceBootstrapOnNextSync = false

    // MARK: - Circuit Breaker State

    /// Number of consecutive rate limit errors encountered
    private var consecutiveRateLimitErrors = 0

    /// Threshold for triggering circuit breaker (stop processing after this many 429s in a row)
    private let rateLimitCircuitBreakerThreshold = 3

    /// Timestamp when rate limit backoff expires
    private var rateLimitBackoffUntil: Date?

    /// Base backoff duration after rate limit circuit breaker trips (30 seconds)
    private let rateLimitBaseBackoff: TimeInterval = 30.0

    /// Maximum backoff duration (5 minutes)
    private let rateLimitMaxBackoff: TimeInterval = 300.0

    /// Current backoff multiplier (increases with each circuit breaker trip)
    private var rateLimitBackoffMultiplier = 1.0

    // MARK: - Observable State (MainActor)

    @MainActor public private(set) var state: SyncState = .idle
    @MainActor public private(set) var pendingCount: Int = 0
    @MainActor public private(set) var lastSyncTime: Date?

    /// Track entity IDs with pending DELETE mutations to prevent resurrection by pullChanges
    private var pendingDeleteIds: Set<String> = []

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
        let cursorKeyValue = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        self.lastSyncCursor = Int64(UserDefaults.standard.integer(forKey: cursorKeyValue))

        // DIAGNOSTIC: Log cursor state on init
        Log.sync.info("SyncEngine init", context: .with { ctx in
            ctx.add("cursor_key", cursorKeyValue)
            ctx.add("loaded_cursor", Int(self.lastSyncCursor))
            ctx.add("environment", AppEnvironment.current.rawValue)
            ctx.add("last_sync_time", "nil (fresh init)")
        })
    }

    // MARK: - Public API

    /// Perform a full sync: flush pending mutations, then pull changes.
    /// This is idempotent and safe to call multiple times - only one sync
    /// will run at a time (single-flight pattern).
    func performSync() async {
        let syncStartTime = Date()
        Log.sync.info("TIMING performSync [T+0.000s] START")

        guard !isSyncing else {
            Log.sync.debug("Sync already in progress, skipping")
            Log.sync.info("TIMING performSync [T+\(String(format: "%.3f", Date().timeIntervalSince(syncStartTime)))s] EXIT - already syncing")
            return
        }

        // Verify actual connectivity before starting sync
        // This catches captive portal situations where NWPathMonitor reports "satisfied"
        Log.sync.info("TIMING performSync [T+\(String(format: "%.3f", Date().timeIntervalSince(syncStartTime)))s] Before performHealthCheck")
        guard await performHealthCheck() else {
            Log.sync.info("Skipping sync - health check failed (likely captive portal)")
            Log.sync.info("TIMING performSync [T+\(String(format: "%.3f", Date().timeIntervalSince(syncStartTime)))s] EXIT - health check failed")
            return
        }
        Log.sync.info("TIMING performSync [T+\(String(format: "%.3f", Date().timeIntervalSince(syncStartTime)))s] After performHealthCheck - PASSED")

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

            // Capture IDs with pending DELETE mutations BEFORE flush
            // These should not be resurrected by pullChanges even if change_log has CREATE entries
            let deleteContext = ModelContext(modelContainer)
            let deleteStore = LocalStore(modelContext: deleteContext)
            let pendingDeletes = try deleteStore.fetchPendingMutations()
                .filter { $0.operation == .delete }
                .map { $0.entityId }
            pendingDeleteIds = Set(pendingDeletes)
            if !pendingDeleteIds.isEmpty {
                Log.sync.debug("Captured pending delete IDs to prevent resurrection", context: .with { ctx in
                    ctx.add("count", pendingDeletes.count)
                })
            }

            // Step 1: Flush any pending mutations to the server
            try await flushPendingMutations()

            // Step 2: If this is first sync (cursor=0) or force bootstrap is requested,
            // do a full bootstrap fetch. This handles the case where data existed
            // before change_log was implemented, or when user requests a full resync.
            let shouldBootstrap = lastSyncCursor == 0 || forceBootstrapOnNextSync
            let wasForceBootstrap = forceBootstrapOnNextSync

            // DIAGNOSTIC: Always log cursor state before deciding
            Log.sync.info("🔧 Sync decision point", context: .with { ctx in
                ctx.add("current_cursor", Int(lastSyncCursor))
                ctx.add("cursor_key", cursorKey)
                ctx.add("should_bootstrap", shouldBootstrap)
                ctx.add("force_bootstrap_flag", forceBootstrapOnNextSync)
            })

            if shouldBootstrap {
                Log.sync.info("Performing bootstrap fetch", context: .with { ctx in
                    ctx.add("cursor_was_zero", lastSyncCursor == 0)
                    ctx.add("force_bootstrap_flag", forceBootstrapOnNextSync)
                })
                forceBootstrapOnNextSync = false // Reset the flag
                try await bootstrapFetch()
            }

            // Step 3: Pull incremental changes from the server
            // SKIP pullChanges after ANY bootstrap - we already have current state
            // from direct API calls, and the change_log may have stale entries that
            // would re-create deleted events.
            if shouldBootstrap {
                // After bootstrap, get the latest cursor (max change_log ID) from the backend.
                // This ensures we skip ALL existing change_log entries, only pulling truly new changes.
                do {
                    let latestCursor = try await apiClient.getLatestCursor()
                    lastSyncCursor = latestCursor
                    UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                    UserDefaults.standard.synchronize() // Force immediate persistence
                    Log.sync.info("🔧 Cursor saved after bootstrap", context: .with { ctx in
                        ctx.add("cursor_key", cursorKey)
                        ctx.add("saved_cursor", Int(latestCursor))
                        ctx.add("was_forced", wasForceBootstrap)
                        // Verify it was saved
                        let verifyValue = UserDefaults.standard.integer(forKey: cursorKey)
                        ctx.add("verify_read_back", verifyValue)
                    })
                } catch {
                    // Fallback: if we can't get the latest cursor, use a high value
                    // This may skip some legitimate changes, but prevents stale data recreation
                    lastSyncCursor = 1_000_000_000
                    UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                    UserDefaults.standard.synchronize() // Force immediate persistence
                    Log.sync.warning("Could not get latest cursor, using fallback", context: .with { ctx in
                        ctx.add("fallback_cursor", Int(lastSyncCursor))
                        ctx.add("error", error.localizedDescription)
                    })
                }
            } else {
                try await pullChanges()

                // Step 4: Always sync geofences from server to ensure we have the latest state.
                // This handles:
                // - Geofences created before the change_log system was implemented
                // - Geofences created on other devices or via web app
                // - Any geofence changes that may have been missed
                Log.sync.info("Syncing geofences from server")
                do {
                    let syncedCount = try await syncGeofences()
                    Log.sync.info("Synced geofences from server", context: .with { ctx in
                        ctx.add("count", syncedCount)
                    })
                } catch {
                    Log.sync.warning("Failed to sync geofences from server", context: .with { ctx in
                        ctx.add("error", error.localizedDescription)
                    })
                    // Don't fail the entire sync for this
                }
            }

            await updateLastSyncTime()
            await updateState(.idle)
            Log.sync.info("Sync completed successfully", context: .with { ctx in
                ctx.add("new_cursor", Int(lastSyncCursor))
            })
            pendingDeleteIds.removeAll()  // Clear tracking after successful sync
        } catch {
            Log.sync.error("Sync failed", error: error)
            await updateState(.error(error.localizedDescription))
            pendingDeleteIds.removeAll()  // Clear tracking even on failure
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

    /// Manually restore broken Event→EventType relationships.
    /// Call this if events show "Unknown" instead of their proper event type name.
    func restoreEventRelationships() async {
        Log.sync.info("Manual event relationship restoration requested")
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        do {
            try restoreEventTypeRelationships(context: context, localStore: localStore)
        } catch {
            Log.sync.error("Failed to restore event relationships", error: error)
        }
    }

    /// Sync geofences from the server without doing a full bootstrap.
    /// This is useful when geofences exist on the server but weren't pulled
    /// during incremental sync (e.g., created before change_log was implemented).
    /// Returns the number of geofences synced.
    @discardableResult
    func syncGeofences() async throws -> Int {
        Log.sync.info("Syncing geofences from server")

        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        // Fetch geofences from API
        let geofences = try await apiClient.getGeofences()
        Log.sync.info("Fetched geofences from server", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        // Upsert each geofence
        for apiGeofence in geofences {
            try localStore.upsertGeofence(id: apiGeofence.id) { geofence in
                geofence.name = apiGeofence.name
                geofence.latitude = apiGeofence.latitude
                geofence.longitude = apiGeofence.longitude
                geofence.radius = apiGeofence.radius
                geofence.isActive = apiGeofence.isActive
                geofence.notifyOnEntry = apiGeofence.notifyOnEntry
                geofence.notifyOnExit = apiGeofence.notifyOnExit
                // Event type IDs are now String (UUIDv7), same as on server
                geofence.eventTypeEntryID = apiGeofence.eventTypeEntryId
                geofence.eventTypeExitID = apiGeofence.eventTypeExitId
            }
        }

        try context.save()
        Log.sync.info("Saved geofences locally", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        return geofences.count
    }

    /// Get the local geofence count
    func getLocalGeofenceCount() -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Geofence>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Queue a mutation for sync. The mutation will be flushed on the next sync.
    func queueMutation(
        entityType: MutationEntityType,
        operation: MutationOperation,
        entityId: String,
        payload: Data
    ) async throws {
        let context = ModelContext(modelContainer)

        let mutation = PendingMutation(
            entityType: entityType,
            operation: operation,
            entityId: entityId,
            payload: payload
        )

        context.insert(mutation)
        try context.save()

        await updatePendingCount()
        Log.sync.debug("Queued mutation", context: .with { ctx in
            ctx.add("entity_type", entityType.rawValue)
            ctx.add("operation", operation.rawValue)
            ctx.add("entity_id", entityId)
        })
    }

    /// Get the current pending mutation count
    func getPendingCount() async -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingMutation>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Clear all pending mutations from the queue.
    /// Use this to recover from a retry storm where mutations are continuously failing.
    /// WARNING: This will abandon any unsynced local changes - they will NOT be synced to the backend.
    /// - Parameter markEntitiesFailed: If true, mark the corresponding entities as failed. Default is true.
    /// - Returns: The number of mutations cleared
    @discardableResult
    func clearPendingMutations(markEntitiesFailed: Bool = true) async -> Int {
        let context = ModelContext(modelContainer)

        do {
            let descriptor = FetchDescriptor<PendingMutation>()
            let mutations = try context.fetch(descriptor)
            let count = mutations.count

            guard count > 0 else {
                Log.sync.info("No pending mutations to clear")
                return 0
            }

            Log.sync.warning("Clearing all pending mutations", context: .with { ctx in
                ctx.add("count", count)
                ctx.add("mark_entities_failed", markEntitiesFailed)
            })

            for mutation in mutations {
                if markEntitiesFailed {
                    try? markEntityFailed(mutation, context: context)
                }
                context.delete(mutation)
            }

            try context.save()
            await updatePendingCount()

            // Reset circuit breaker state
            consecutiveRateLimitErrors = 0
            rateLimitBackoffUntil = nil
            rateLimitBackoffMultiplier = 1.0

            Log.sync.info("Cleared pending mutations and reset circuit breaker", context: .with { ctx in
                ctx.add("cleared_count", count)
            })

            return count
        } catch {
            Log.sync.error("Failed to clear pending mutations", error: error)
            return 0
        }
    }

    /// Check if the circuit breaker is currently tripped (in backoff state)
    var isCircuitBreakerTripped: Bool {
        if let backoffUntil = rateLimitBackoffUntil {
            return Date() < backoffUntil
        }
        return false
    }

    /// Get remaining backoff time in seconds (0 if not in backoff)
    var circuitBreakerBackoffRemaining: TimeInterval {
        if let backoffUntil = rateLimitBackoffUntil {
            return max(0, backoffUntil.timeIntervalSinceNow)
        }
        return 0
    }

    // MARK: - Private: Health Check

    /// Performs a lightweight health check to verify actual internet connectivity.
    /// NWPathMonitor can report "satisfied" behind captive portals, so we verify
    /// with an actual HTTP request before attempting sync operations.
    ///
    /// Uses getEventTypes() because:
    /// - It always returns data (user always has at least default types)
    /// - Empty response would indicate a problem, not a valid state
    /// - Lightweight payload compared to full event list
    private func performHealthCheck() async -> Bool {
        let healthCheckStart = Date()
        Log.sync.info("TIMING performHealthCheck [T+0.000s] START - calling apiClient.getEventTypes()")
        do {
            let types = try await apiClient.getEventTypes()
            // If we get a response (even empty), connectivity is working
            Log.sync.debug("Health check passed", context: .with { ctx in
                ctx.add("event_types_count", types.count)
            })
            Log.sync.info("TIMING performHealthCheck [T+\(String(format: "%.3f", Date().timeIntervalSince(healthCheckStart)))s] SUCCESS")
            return true
        } catch {
            Log.sync.warning("Health check failed - likely captive portal or no connectivity", context: .with { ctx in
                ctx.add("error", error.localizedDescription)
            })
            Log.sync.info("TIMING performHealthCheck [T+\(String(format: "%.3f", Date().timeIntervalSince(healthCheckStart)))s] FAILED - \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private: Flush Pending Mutations

    private func flushPendingMutations() async throws {
        // Check circuit breaker - if we're in backoff, skip flushing
        if let backoffUntil = rateLimitBackoffUntil, Date() < backoffUntil {
            let remaining = backoffUntil.timeIntervalSinceNow
            Log.sync.warning("Circuit breaker tripped - skipping mutation flush", context: .with { ctx in
                ctx.add("backoff_remaining_seconds", Int(remaining))
            })
            return
        }

        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        let mutations = try localStore.fetchPendingMutations()
        guard !mutations.isEmpty else {
            Log.sync.debug("No pending mutations to flush")
            return
        }

        Log.sync.info("Flushing pending mutations", context: .with { ctx in
            ctx.add("count", mutations.count)
            ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
        })

        for mutation in mutations {
            // Check circuit breaker before each mutation
            if consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold {
                tripCircuitBreaker()
                Log.sync.warning("Circuit breaker tripped during flush - aborting remaining mutations", context: .with { ctx in
                    ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
                    ctx.add("backoff_seconds", Int(circuitBreakerBackoffRemaining))
                })
                break
            }

            Log.sync.debug("Processing mutation", context: .with { ctx in
                ctx.add("entity_type", mutation.entityType.rawValue)
                ctx.add("operation", mutation.operation.rawValue)
                ctx.add("entity_id", mutation.entityId)
                ctx.add("attempts_before", mutation.attempts)
            })

            do {
                try await flushMutation(mutation, localStore: localStore)
                Log.sync.info("Mutation flushed successfully", context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("entity_id", mutation.entityId)
                })
                context.delete(mutation)

                // Reset consecutive rate limit counter on success
                consecutiveRateLimitErrors = 0

            } catch let error as APIError where error.isDuplicateError {
                // Duplicate error - the entity already exists on the server
                // This can happen due to race conditions (e.g., HealthKit observer fires twice)
                // The "real" entity already synced, so delete this local duplicate
                Log.sync.warning("Duplicate detected, deleting local duplicate", context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("operation", mutation.operation.rawValue)
                    ctx.add("entity_id", mutation.entityId)
                    ctx.add("error", error.localizedDescription ?? "unknown")
                })
                // Delete the local duplicate entity - the "real" one already exists and synced
                try deleteLocalDuplicate(mutation, localStore: localStore)
                context.delete(mutation)

                // Reset rate limit counter - duplicates are not rate limit errors
                consecutiveRateLimitErrors = 0

            } catch let error as APIError where error.isRateLimitError {
                // Rate limit error - increment counter but DON'T count against mutation retry limit
                consecutiveRateLimitErrors += 1
                Log.sync.warning("Rate limit error during mutation flush", context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("entity_id", mutation.entityId)
                    ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
                })

                // Don't increment mutation.attempts for rate limits - it's a global issue, not a mutation issue
                // The mutation will be retried on the next sync cycle after backoff

            } catch let error as APIError {
                // Other API error (not duplicate, not rate limit)
                Log.sync.error("API error during mutation flush", error: error, context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("entity_id", mutation.entityId)
                    ctx.add("is_duplicate", error.isDuplicateError)
                    ctx.add("is_rate_limit", error.isRateLimitError)
                })
                mutation.recordFailure(error: error.localizedDescription ?? "Unknown API error")

                // Reset rate limit counter - this is a different kind of error
                consecutiveRateLimitErrors = 0

                if mutation.hasExceededRetryLimit {
                    Log.sync.error("Mutation exceeded retry limit (API error)", context: .with { ctx in
                        ctx.add("entity_type", mutation.entityType.rawValue)
                        ctx.add("attempts", mutation.attempts)
                    })
                    try markEntityFailed(mutation, context: context)
                    context.delete(mutation)
                } else {
                    Log.sync.info("Mutation will retry", context: .with { ctx in
                        ctx.add("attempts_after", mutation.attempts)
                    })
                }
            } catch {
                // Non-API error (decoding, encoding, etc.)
                Log.sync.error("Non-API error during mutation flush", error: error, context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("entity_id", mutation.entityId)
                    ctx.add("error_type", String(describing: type(of: error)))
                })
                mutation.recordFailure(error: error.localizedDescription)

                // Reset rate limit counter - this is a different kind of error
                consecutiveRateLimitErrors = 0

                if mutation.hasExceededRetryLimit {
                    Log.sync.error("Mutation exceeded retry limit (non-API error)", context: .with { ctx in
                        ctx.add("entity_type", mutation.entityType.rawValue)
                        ctx.add("operation", mutation.operation.rawValue)
                        ctx.add("attempts", mutation.attempts)
                    })
                    // Mark the entity as failed
                    try markEntityFailed(mutation, context: context)
                    context.delete(mutation)
                } else {
                    Log.sync.info("Mutation will retry", context: .with { ctx in
                        ctx.add("attempts_after", mutation.attempts)
                    })
                }
            }
        }

        try context.save()
        await updatePendingCount()
    }

    /// Trip the circuit breaker - enter backoff state
    private func tripCircuitBreaker() {
        let backoffDuration = min(rateLimitBaseBackoff * rateLimitBackoffMultiplier, rateLimitMaxBackoff)
        rateLimitBackoffUntil = Date().addingTimeInterval(backoffDuration)

        // Increase multiplier for next time (exponential backoff)
        rateLimitBackoffMultiplier = min(rateLimitBackoffMultiplier * 2.0, 10.0)

        Log.sync.warning("Circuit breaker tripped", context: .with { ctx in
            ctx.add("backoff_duration_seconds", Int(backoffDuration))
            ctx.add("backoff_multiplier", rateLimitBackoffMultiplier)
            ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
        })
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
            _ = try await apiClient.createEventWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            // With UUIDv7, no reconciliation needed - just mark as synced
            try localStore.markEventSynced(id: mutation.entityId)

        case .eventType:
            let request = try JSONDecoder().decode(CreateEventTypeRequest.self, from: mutation.payload)
            _ = try await apiClient.createEventTypeWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try localStore.markEventTypeSynced(id: mutation.entityId)

        case .geofence:
            let request = try JSONDecoder().decode(CreateGeofenceRequest.self, from: mutation.payload)
            _ = try await apiClient.createGeofenceWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try localStore.markGeofenceSynced(id: mutation.entityId)

        case .propertyDefinition:
            let request = try JSONDecoder().decode(CreatePropertyDefinitionRequest.self, from: mutation.payload)
            _ = try await apiClient.createPropertyDefinitionWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try localStore.markPropertyDefinitionSynced(id: mutation.entityId)
        }

        try localStore.save()
    }

    private func flushUpdate(_ mutation: PendingMutation) async throws {
        // For updates, entityId IS the server ID (since we use UUIDv7)
        let entityId = mutation.entityId

        switch mutation.entityType {
        case .event:
            let request = try JSONDecoder().decode(UpdateEventRequest.self, from: mutation.payload)
            _ = try await apiClient.updateEvent(id: entityId, request)

        case .eventType:
            let request = try JSONDecoder().decode(UpdateEventTypeRequest.self, from: mutation.payload)
            _ = try await apiClient.updateEventType(id: entityId, request)

        case .geofence:
            let request = try JSONDecoder().decode(UpdateGeofenceRequest.self, from: mutation.payload)
            _ = try await apiClient.updateGeofence(id: entityId, request)

        case .propertyDefinition:
            let request = try JSONDecoder().decode(UpdatePropertyDefinitionRequest.self, from: mutation.payload)
            _ = try await apiClient.updatePropertyDefinition(id: entityId, request)
        }
    }

    private func flushDelete(_ mutation: PendingMutation) async throws {
        // For deletes, entityId IS the server ID (since we use UUIDv7)
        let entityId = mutation.entityId

        switch mutation.entityType {
        case .event:
            try await apiClient.deleteEvent(id: entityId)
        case .eventType:
            try await apiClient.deleteEventType(id: entityId)
        case .geofence:
            try await apiClient.deleteGeofence(id: entityId)
        case .propertyDefinition:
            try await apiClient.deletePropertyDefinition(id: entityId)
        }
    }

    private func markEntityFailed(_ mutation: PendingMutation, context: ModelContext) throws {
        let entityId = mutation.entityId

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

    /// Handle duplicate error by marking the entity as synced.
    /// With UUIDv7, the server has the same ID, so we just mark synced.
    private func markEntitySynced(_ mutation: PendingMutation, localStore: LocalStore) throws {
        switch mutation.entityType {
        case .event:
            try localStore.markEventSynced(id: mutation.entityId)
        case .eventType:
            try localStore.markEventTypeSynced(id: mutation.entityId)
        case .geofence:
            try localStore.markGeofenceSynced(id: mutation.entityId)
        case .propertyDefinition:
            try localStore.markPropertyDefinitionSynced(id: mutation.entityId)
        }
    }

    /// Handle duplicate error by deleting the local duplicate entity.
    /// This happens when a race condition creates multiple local entities with different IDs
    /// but the same unique constraint fields (e.g., healthKitSampleId). The "real" entity
    /// already synced successfully, so this duplicate should be removed.
    private func deleteLocalDuplicate(_ mutation: PendingMutation, localStore: LocalStore) throws {
        Log.sync.info("Deleting local duplicate entity", context: .with { ctx in
            ctx.add("entity_type", mutation.entityType.rawValue)
            ctx.add("entity_id", mutation.entityId)
        })

        switch mutation.entityType {
        case .event:
            try localStore.deleteEvent(id: mutation.entityId)
        case .eventType:
            try localStore.deleteEventType(id: mutation.entityId)
        case .geofence:
            try localStore.deleteGeofence(id: mutation.entityId)
        case .propertyDefinition:
            try localStore.deletePropertyDefinition(id: mutation.entityId)
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
        // Skip resurrection if this entity has a pending DELETE mutation
        // This prevents the race condition where pullChanges recreates a deleted entity
        if pendingDeleteIds.contains(change.entityId) {
            Log.sync.debug("Skipping resurrection of pending-delete entity", context: .with { ctx in
                ctx.add("entity_id", change.entityId)
                ctx.add("entity_type", change.entityType)
            })
            return
        }

        guard let data = change.data else {
            Log.sync.warning("Missing data for upsert", context: .with { ctx in
                ctx.add("change_id", Int(change.id))
            })
            return
        }

        switch change.entityType {
        case "event":
            try localStore.upsertEvent(id: change.entityId) { event in
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
                // EventType ID - store for relationship recovery and establish relationship
                if let eventTypeId = data.eventTypeId {
                    event.eventTypeId = eventTypeId  // Always store for recovery
                    if let localEventType = try? localStore.findEventType(id: eventTypeId) {
                        event.eventType = localEventType
                    } else {
                        Log.sync.warning("Could not find EventType during changefeed processing", context: .with { ctx in
                            ctx.add("event_id", change.entityId)
                            ctx.add("event_type_id", eventTypeId)
                        })
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
                    event.geofenceId = geofenceId
                }
                if let lat = data.locationLatitude, let lon = data.locationLongitude {
                    event.locationLatitude = lat
                    event.locationLongitude = lon
                }
                if let locationName = data.locationName {
                    event.locationName = locationName
                }
                // Sync HealthKit fields from change feed (critical for deduplication)
                if let healthKitSampleId = data.healthKitSampleId {
                    event.healthKitSampleId = healthKitSampleId
                }
                if let healthKitCategory = data.healthKitCategory {
                    event.healthKitCategory = healthKitCategory
                }
                // Sync properties from change feed
                if let apiProperties = data.properties {
                    event.properties = Self.convertAPIProperties(apiProperties)
                }
            }

        case "event_type":
            try localStore.upsertEventType(id: change.entityId) { eventType in
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
            try localStore.upsertGeofence(id: change.entityId) { geofence in
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
                // Event type IDs are now String (UUIDv7)
                if let entryId = data.eventTypeEntryId {
                    geofence.eventTypeEntryID = entryId
                }
                if let exitId = data.eventTypeExitId {
                    geofence.eventTypeExitID = exitId
                }
            }

        case "property_definition":
            // PropertyDefinitions need eventTypeId
            if let eventTypeId = data.eventTypeId {
                try localStore.upsertPropertyDefinition(id: change.entityId, eventTypeId: eventTypeId) { propDef in
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
            try localStore.deleteEvent(id: change.entityId)
        case "event_type":
            try localStore.deleteEventType(id: change.entityId)
        case "geofence":
            try localStore.deleteGeofence(id: change.entityId)
        case "property_definition":
            try localStore.deletePropertyDefinition(id: change.entityId)
        default:
            Log.sync.warning("Unknown entity type for delete", context: .with { ctx in
                ctx.add("entity_type", change.entityType)
            })
        }
    }

    // MARK: - Private: Bootstrap Fetch (Initial Sync)

    /// Fetch all data from the backend when cursor is 0 (first sync).
    /// This handles the case where data existed before the change_log was implemented.
    private func bootstrapFetch() async throws {
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        // NUCLEAR CLEANUP: Delete ALL local data before repopulating from backend.
        // This ensures a completely clean slate and prevents any duplicate accumulation.
        // This is safe because bootstrap is only called when we want a fresh sync.
        Log.sync.info("Bootstrap: Starting nuclear cleanup of all local data")

        // Delete all Events first (they reference EventTypes)
        let allEventsDescriptor = FetchDescriptor<Event>()
        let allLocalEvents = try context.fetch(allEventsDescriptor)
        Log.sync.info("Bootstrap: Deleting all local events", context: .with { ctx in
            ctx.add("count", allLocalEvents.count)
        })
        for event in allLocalEvents {
            context.delete(event)
        }

        // Delete all Geofences
        let allGeofencesDescriptor = FetchDescriptor<Geofence>()
        let allLocalGeofences = try context.fetch(allGeofencesDescriptor)
        Log.sync.info("Bootstrap: Deleting all local geofences", context: .with { ctx in
            ctx.add("count", allLocalGeofences.count)
        })
        for geofence in allLocalGeofences {
            context.delete(geofence)
        }

        // Delete all PropertyDefinitions
        let allPropDefsDescriptor = FetchDescriptor<PropertyDefinition>()
        let allLocalPropDefs = try context.fetch(allPropDefsDescriptor)
        Log.sync.info("Bootstrap: Deleting all local property definitions", context: .with { ctx in
            ctx.add("count", allLocalPropDefs.count)
        })
        for propDef in allLocalPropDefs {
            context.delete(propDef)
        }

        // Delete all EventTypes last (other entities may reference them)
        let allEventTypesDescriptor = FetchDescriptor<EventType>()
        let allLocalEventTypes = try context.fetch(allEventTypesDescriptor)
        Log.sync.info("Bootstrap: Deleting all local event types", context: .with { ctx in
            ctx.add("count", allLocalEventTypes.count)
        })
        for eventType in allLocalEventTypes {
            context.delete(eventType)
        }

        // Save the deletions
        try context.save()
        Log.sync.info("Bootstrap: Nuclear cleanup completed - all local data deleted")

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
            try localStore.upsertEventType(id: apiEventType.id) { eventType in
                eventType.name = apiEventType.name
                eventType.colorHex = apiEventType.color
                eventType.iconName = apiEventType.icon
            }
        }

        // Save EventTypes immediately to ensure they're persisted before Geofences reference them
        try context.save()
        Log.sync.info("Bootstrap: Saved event types", context: .with { ctx in
            ctx.add("count", eventTypes.count)
        })

        // Step 2: Fetch and upsert all Geofences (Events may reference them)
        Log.sync.info("Bootstrap: fetching geofences")
        let geofences = try await apiClient.getGeofences()
        Log.sync.info("Bootstrap: received geofences", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        for apiGeofence in geofences {
            try localStore.upsertGeofence(id: apiGeofence.id) { geofence in
                geofence.name = apiGeofence.name
                geofence.latitude = apiGeofence.latitude
                geofence.longitude = apiGeofence.longitude
                geofence.radius = apiGeofence.radius
                geofence.isActive = apiGeofence.isActive
                geofence.notifyOnEntry = apiGeofence.notifyOnEntry
                geofence.notifyOnExit = apiGeofence.notifyOnExit
                // Event type IDs are now String (UUIDv7)
                geofence.eventTypeEntryID = apiGeofence.eventTypeEntryId
                geofence.eventTypeExitID = apiGeofence.eventTypeExitId
            }
        }

        // Save Geofences immediately to ensure they're persisted before Events reference them
        try context.save()
        Log.sync.info("Bootstrap: Saved geofences", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

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
            let event = try localStore.upsertEvent(id: apiEvent.id) { event in
                event.timestamp = apiEvent.timestamp
                event.notes = apiEvent.notes
                event.isAllDay = apiEvent.isAllDay
                event.endDate = apiEvent.endDate
                event.sourceType = EventSourceType(rawValue: apiEvent.sourceType) ?? .manual
                event.externalId = apiEvent.externalId
                event.originalTitle = apiEvent.originalTitle
                event.geofenceId = apiEvent.geofenceId
                event.locationLatitude = apiEvent.locationLatitude
                event.locationLongitude = apiEvent.locationLongitude
                event.locationName = apiEvent.locationName
                // Sync HealthKit fields from backend (critical for deduplication)
                event.healthKitSampleId = apiEvent.healthKitSampleId
                event.healthKitCategory = apiEvent.healthKitCategory
                // Sync properties from backend
                if let apiProperties = apiEvent.properties {
                    event.properties = Self.convertAPIProperties(apiProperties)
                }
                // Store eventTypeId for relationship recovery
                event.eventTypeId = apiEvent.eventTypeId
            }
            // Establish the SwiftData relationship to EventType
            if let localEventType = try? localStore.findEventType(id: apiEvent.eventTypeId) {
                event.eventType = localEventType
            } else {
                Log.sync.warning("Bootstrap: Could not find EventType for event", context: .with { ctx in
                    ctx.add("event_id", apiEvent.id)
                    ctx.add("event_type_id", apiEvent.eventTypeId)
                })
            }
        }

        // Save Events immediately to ensure they're persisted
        try context.save()
        Log.sync.info("Bootstrap: Saved events", context: .with { ctx in
            ctx.add("count", events.count)
        })

        // Step 4: Fetch property definitions for each event type
        Log.sync.info("Bootstrap: fetching property definitions")
        var allPropertyDefinitionIds: [String] = []
        for apiEventType in eventTypes {
            do {
                let propDefs = try await apiClient.getPropertyDefinitions(eventTypeId: apiEventType.id)
                for apiPropDef in propDefs {
                    try localStore.upsertPropertyDefinition(id: apiPropDef.id, eventTypeId: apiEventType.id) { propDef in
                        propDef.key = apiPropDef.key
                        propDef.label = apiPropDef.label
                        propDef.propertyType = PropertyType(rawValue: apiPropDef.propertyType) ?? .text
                        propDef.displayOrder = apiPropDef.displayOrder
                        propDef.options = apiPropDef.options ?? []
                    }
                    allPropertyDefinitionIds.append(apiPropDef.id)
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

        // Restore any broken Event→EventType relationships
        try restoreEventTypeRelationships(context: context, localStore: localStore)

        // Verification: count remaining records after cleanup
        let finalEventCount = try context.fetchCount(FetchDescriptor<Event>())
        let finalEventTypeCount = try context.fetchCount(FetchDescriptor<EventType>())
        let finalGeofenceCount = try context.fetchCount(FetchDescriptor<Geofence>())

        Log.sync.info("🔧 Bootstrap fetch completed", context: .with { ctx in
            ctx.add("backend_event_types", eventTypes.count)
            ctx.add("backend_geofences", geofences.count)
            ctx.add("backend_events", events.count)
            ctx.add("backend_property_definitions", allPropertyDefinitionIds.count)
            ctx.add("final_local_events", finalEventCount)
            ctx.add("final_local_event_types", finalEventTypeCount)
            ctx.add("final_local_geofences", finalGeofenceCount)
        })

        // DIAGNOSTIC: Additional verification after save
        Log.sync.info("🔧 Bootstrap verification after context.save()", context: .with { ctx in
            // Create a fresh context to verify persistence
            let verifyContext = ModelContext(modelContainer)
            let verifyEventCount = (try? verifyContext.fetchCount(FetchDescriptor<Event>())) ?? -1
            let verifyEventTypeCount = (try? verifyContext.fetchCount(FetchDescriptor<EventType>())) ?? -1
            ctx.add("verify_events_fresh_context", verifyEventCount)
            ctx.add("verify_event_types_fresh_context", verifyEventTypeCount)
        })
    }

    /// Restore Event→EventType relationships for events with missing eventType relationship.
    /// This can happen when events are loaded from backend but the SwiftData relationship wasn't
    /// properly established during sync. Uses the stored eventTypeId field for recovery.
    private func restoreEventTypeRelationships(context: ModelContext, localStore: LocalStore) throws {
        let allEvents = try context.fetch(FetchDescriptor<Event>())
        var restoredCount = 0
        var orphanedCount = 0

        for event in allEvents {
            // Check if event is missing the relationship
            guard event.eventType == nil else { continue }

            // Try to restore using the stored eventTypeId
            if let eventTypeId = event.eventTypeId {
                if let localEventType = try? localStore.findEventType(id: eventTypeId) {
                    event.eventType = localEventType
                    restoredCount += 1
                    Log.sync.info("Restored eventType relationship", context: .with { ctx in
                        ctx.add("event_id", event.id)
                        ctx.add("event_type_id", eventTypeId)
                        ctx.add("event_type_name", localEventType.name)
                    })
                } else {
                    orphanedCount += 1
                    Log.sync.warning("Event has eventTypeId but EventType not found locally", context: .with { ctx in
                        ctx.add("event_id", event.id)
                        ctx.add("event_type_id", eventTypeId)
                    })
                }
            } else {
                orphanedCount += 1
                Log.sync.warning("Event missing eventType relationship and has no eventTypeId for recovery", context: .with { ctx in
                    ctx.add("event_id", event.id)
                })
            }
        }

        if restoredCount > 0 || orphanedCount > 0 {
            try context.save()
            Log.sync.info("Event relationship restoration complete", context: .with { ctx in
                ctx.add("restored", restoredCount)
                ctx.add("orphaned", orphanedCount)
            })
        }
    }

    // MARK: - Private: State Updates

    @MainActor
    private func updateState(_ newState: SyncState) {
        state = newState
    }

    @MainActor
    private func updateLastSyncTime() {
        lastSyncTime = Date()
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
    case encodingFailed
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode mutation payload"
        case .unknown(let message):
            return message
        }
    }
}
