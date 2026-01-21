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

/// Notification posted after bootstrap fetch completes.
/// HealthKitService listens for this to reload processedSampleIds from the database.
extension Notification.Name {
    static let syncEngineBootstrapCompleted = Notification.Name("syncEngineBootstrapCompleted")
}

/// Observable state for the sync engine
enum SyncState: Equatable {
    case idle
    /// Pushing local changes with progress: synced count and total count
    case syncing(synced: Int, total: Int)
    /// Pulling remote changes (after push completes)
    case pulling
    case rateLimited(retryAfter: TimeInterval, pending: Int)
    case error(String)

    /// Convenience for checking if syncing (regardless of progress)
    var isSyncing: Bool {
        switch self {
        case .syncing, .pulling:
            return true
        default:
            return false
        }
    }
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
    private let syncHistoryStore: SyncHistoryStore?

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

    /// UserDefaults key for pending delete IDs (environment-specific)
    private var pendingDeleteIdsKey: String {
        "sync_engine_pending_delete_ids_\(AppEnvironment.current.rawValue)"
    }

    private let changeFeedLimit = 100

    // MARK: - Initialization

    /// Flag to track if initial state has been loaded
    private var initialStateLoaded = false

    init(apiClient: APIClient, modelContainer: ModelContainer, syncHistoryStore: SyncHistoryStore? = nil) {
        self.apiClient = apiClient
        self.modelContainer = modelContainer
        self.syncHistoryStore = syncHistoryStore
        // Use computed cursorKey which includes environment
        let cursorKeyValue = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        self.lastSyncCursor = Int64(UserDefaults.standard.integer(forKey: cursorKeyValue))

        // DIAGNOSTIC: Log cursor state on init
        Log.sync.info("SyncEngine init", context: .with { ctx in
            ctx.add("cursor_key", cursorKeyValue)
            ctx.add("loaded_cursor", Int(self.lastSyncCursor))
            ctx.add("environment", AppEnvironment.current.rawValue)
            ctx.add("last_sync_time", "nil (fresh init)")
            ctx.add("has_history_store", syncHistoryStore != nil)
        })
    }

    /// Load initial state from persistent storage (SwiftData and UserDefaults).
    /// Call this after SyncEngine is created to populate pendingCount and pendingDeleteIds.
    /// This ensures the UI shows correct pending count immediately after app launch.
    func loadInitialState() async {
        guard !initialStateLoaded else {
            Log.sync.debug("Initial state already loaded, skipping")
            return
        }
        initialStateLoaded = true

        // Load pending count from SwiftData
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingMutation>()
        let count = (try? context.fetchCount(descriptor)) ?? 0

        await MainActor.run {
            pendingCount = count
        }

        // Load pending delete IDs from UserDefaults
        if let savedIds = UserDefaults.standard.array(forKey: pendingDeleteIdsKey) as? [String] {
            pendingDeleteIds = Set(savedIds)
            Log.sync.info("Loaded pendingDeleteIds from UserDefaults", context: .with { ctx in
                ctx.add("count", savedIds.count)
            })
        }

        Log.sync.info("Loaded initial state", context: .with { ctx in
            ctx.add("pending_count", count)
            ctx.add("pending_delete_ids_count", pendingDeleteIds.count)
        })
    }

    /// Persist pendingDeleteIds to UserDefaults for resurrection prevention across restarts
    private func savePendingDeleteIds() {
        UserDefaults.standard.set(Array(pendingDeleteIds), forKey: pendingDeleteIdsKey)
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

        // Verify actual connectivity before starting sync
        // This catches captive portal situations where NWPathMonitor reports "satisfied"
        guard await performHealthCheck() else {
            Log.sync.info("Skipping sync - health check failed (likely captive portal)")
            return
        }

        isSyncing = true
        await updateState(.syncing(synced: 0, total: 0))

        // Track sync timing for history
        let syncStartTime = Date()

        defer {
            isSyncing = false
        }

        do {
            Log.sync.info("Starting sync", context: .with { ctx in
                ctx.add("cursor", Int(lastSyncCursor))
                ctx.add("is_first_sync", lastSyncCursor == 0)
            })

            // Create a single context for pre-sync operations to avoid SQLite file locking issues.
            // Multiple concurrent ModelContexts can cause "default.store couldn't be opened" errors.
            let preSyncContext = ModelContext(modelContainer)

            // Count pending mutations before sync for history tracking
            let pendingDescriptor = FetchDescriptor<PendingMutation>()
            let initialPendingCount = (try? preSyncContext.fetchCount(pendingDescriptor)) ?? 0

            // Capture IDs with pending DELETE mutations BEFORE flush
            // These should not be resurrected by pullChanges even if change_log has CREATE entries
            let localStore = LocalStore(modelContext: preSyncContext)
            let pendingDeletes = try localStore.fetchPendingMutations()
                .filter { $0.operation == .delete }
                .map { $0.entityId }
            pendingDeleteIds = Set(pendingDeletes)
            savePendingDeleteIds()  // Persist for resurrection prevention across restarts
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
                // Update state to show we're pulling (bootstrap downloads all data)
                await updateState(.pulling)
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
                    let previousCursor = lastSyncCursor
                    let latestCursor = try await apiClient.getLatestCursor()
                    lastSyncCursor = latestCursor
                    UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                    UserDefaults.standard.synchronize() // Force immediate persistence
                    Log.sync.info("Cursor saved after bootstrap", context: .with { ctx in
                        ctx.add("before", Int(previousCursor))
                        ctx.add("after", Int(latestCursor))
                        ctx.add("cursor_key", cursorKey)
                        ctx.add("was_forced", wasForceBootstrap)
                        // Verify it was saved
                        let verifyValue = UserDefaults.standard.integer(forKey: cursorKey)
                        ctx.add("verify_read_back", verifyValue)
                    })
                } catch {
                    // Fallback: if we can't get the latest cursor, use a high value
                    // Use Int64.max / 2 to avoid any theoretical overflow concerns
                    // This value (~4.6 quintillion) is far enough in the future
                    let previousCursor = lastSyncCursor
                    lastSyncCursor = Int64.max / 2
                    UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                    UserDefaults.standard.synchronize() // Force immediate persistence
                    Log.sync.warning("Could not get latest cursor, using fallback", context: .with { ctx in
                        ctx.add("before", Int(previousCursor))
                        ctx.add("after", Int(lastSyncCursor))
                        ctx.add("error", error.localizedDescription)
                    })
                }
            } else {
                // Update state to show we're pulling changes (not stuck at last push progress)
                await updateState(.pulling)
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

            // Calculate sync duration and record to history
            let syncDurationMs = Int(Date().timeIntervalSince(syncStartTime) * 1000)
            let finalPendingCount = (try? preSyncContext.fetchCount(pendingDescriptor)) ?? 0
            let syncedCount = max(0, initialPendingCount - finalPendingCount)

            Log.sync.info("Sync completed successfully", context: .with { ctx in
                ctx.add("new_cursor", Int(lastSyncCursor))
                ctx.add("duration_ms", syncDurationMs)
                ctx.add("items_synced", syncedCount)
            })

            // Record success to sync history
            await recordSyncHistory(
                eventsCount: syncedCount,
                eventTypesCount: 0,
                durationMs: syncDurationMs,
                error: nil
            )

            pendingDeleteIds.removeAll()  // Clear tracking after successful sync
            savePendingDeleteIds()
        } catch {
            // Calculate duration even on failure
            let syncDurationMs = Int(Date().timeIntervalSince(syncStartTime) * 1000)

            Log.sync.error("Sync failed", error: error)
            await updateState(.error(error.localizedDescription))

            // Record failure to sync history
            await recordSyncHistory(
                eventsCount: 0,
                eventTypesCount: 0,
                durationMs: syncDurationMs,
                error: error.localizedDescription
            )

            pendingDeleteIds.removeAll()  // Clear tracking even on failure
            savePendingDeleteIds()
        }
    }

    /// Record sync result to history store (if available)
    private func recordSyncHistory(eventsCount: Int, eventTypesCount: Int, durationMs: Int, error: String?) async {
        guard let syncHistoryStore = syncHistoryStore else { return }

        await MainActor.run {
            if let errorMessage = error {
                syncHistoryStore.recordFailure(errorMessage: errorMessage, durationMs: durationMs)
            } else {
                syncHistoryStore.recordSuccess(events: eventsCount, eventTypes: eventTypesCount, durationMs: durationMs)
            }
        }
    }

    /// Force a full resync by resetting the cursor
    func forceFullResync() async {
        Log.sync.info("Force full resync requested")

        // Wait for any in-progress sync with timeout
        do {
            try await waitForSyncCompletion(timeout: .seconds(30))
        } catch {
            Log.sync.warning("Timeout waiting for sync, proceeding anyway", context: .with { ctx in
                ctx.add(error: error)
            })
        }

        // Reset cursor and set flag to force bootstrap
        let previousCursor = lastSyncCursor
        lastSyncCursor = 0
        UserDefaults.standard.set(0, forKey: cursorKey)
        forceBootstrapOnNextSync = true

        Log.sync.info("Cursor reset for forced resync", context: .with { ctx in
            ctx.add("before", Int(previousCursor))
            ctx.add("after", 0)
        })
        await performSync()
    }

    /// Wait for any in-progress sync to complete, with timeout.
    /// Uses task group pattern instead of busy-wait polling for proper cancellation support.
    private func waitForSyncCompletion(timeout: Duration = .seconds(30)) async throws {
        guard isSyncing else { return }

        Log.sync.debug("Waiting for in-progress sync to complete", context: .with { ctx in
            ctx.add("timeout_seconds", 30)
        })

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Task 1: Poll for sync completion with cancellation support
            group.addTask { [self] in
                while await self.isSyncing {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(50))
                }
            }

            // Task 2: Timeout after specified duration
            group.addTask {
                try await Task.sleep(until: .now + timeout, clock: .continuous)
                throw SyncError.waitTimeout
            }

            // Wait for first task to complete, cancel the other
            defer { group.cancelAll() }
            try await group.next()
        }

        Log.sync.debug("In-progress sync completed, proceeding")
    }

    /// Skip all pending change_log entries and jump cursor to latest.
    /// Use when change_log backlog is too large and causing rate limit errors.
    ///
    /// This is SAFE to use even with pending mutations because:
    /// 1. Pending mutations are pushed BEFORE pullChanges runs
    /// 2. The cursor only affects which change_log entries to PULL
    /// 3. Skipping cursor doesn't affect the push phase at all
    /// 4. The push phase will still push all pending mutations on next sync
    ///
    /// - Returns: The new cursor value
    /// - Throws: Error if API call fails
    func skipToLatestCursor() async throws -> Int64 {
        // Log pending mutation count for informational purposes
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)
        let pendingMutations = try localStore.fetchPendingMutations()
        let pendingCount = pendingMutations.count

        // Get the latest cursor from the backend
        let previousCursor = lastSyncCursor
        let latestCursor = try await apiClient.getLatestCursor()

        // Update local cursor
        lastSyncCursor = latestCursor
        UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
        UserDefaults.standard.synchronize()

        Log.sync.info("Skipped to latest cursor", context: .with { ctx in
            ctx.add("before", Int(previousCursor))
            ctx.add("after", Int(latestCursor))
            ctx.add("pending_mutations", pendingCount)
        })

        return latestCursor
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
    /// Deduplicates by entityId - if a pending mutation already exists for the same
    /// entity with the same operation, the new mutation is skipped.
    func queueMutation(
        entityType: MutationEntityType,
        operation: MutationOperation,
        entityId: String,
        payload: Data
    ) async throws {
        let context = ModelContext(modelContainer)

        // DEDUPLICATION: Check if a pending mutation already exists for this entity
        // This prevents duplicate mutations from being queued when multiple code paths
        // (e.g., syncEventToBackend, queueMutationsForUnsyncedEvents, resyncHealthKitEvents)
        // try to sync the same event.
        let entityTypeRaw = entityType.rawValue
        let operationRaw = operation.rawValue
        let existingDescriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate {
                $0.entityId == entityId &&
                $0.entityTypeRaw == entityTypeRaw &&
                $0.operationRaw == operationRaw
            }
        )

        let existingCount = (try? context.fetchCount(existingDescriptor)) ?? 0
        if existingCount > 0 {
            Log.sync.debug("Skipping duplicate mutation (already pending)", context: .with { ctx in
                ctx.add("entity_type", entityType.rawValue)
                ctx.add("operation", operation.rawValue)
                ctx.add("entity_id", entityId)
                ctx.add("existing_count", existingCount)
            })
            return
        }

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
        return getPendingCountFromContext(context)
    }

    /// Get the current pending mutation count using an existing context.
    /// This avoids creating multiple ModelContexts which can cause SQLite file locking issues.
    private func getPendingCountFromContext(_ context: ModelContext) -> Int {
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

    /// Reset the circuit breaker to allow immediate retry.
    /// Call this when the user explicitly requests a retry, bypassing the backoff period.
    func resetCircuitBreaker() async {
        Log.sync.info("Circuit breaker manually reset by user")
        consecutiveRateLimitErrors = 0
        rateLimitBackoffUntil = nil
        rateLimitBackoffMultiplier = 1.0
        await updateState(.idle)
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
        do {
            let types = try await apiClient.getEventTypes()
            // If we get a response (even empty), connectivity is working
            Log.sync.debug("Health check passed", context: .with { ctx in
                ctx.add("event_types_count", types.count)
            })
            return true
        } catch {
            Log.sync.warning("Health check failed - likely captive portal or no connectivity", context: .with { ctx in
                ctx.add("error", error.localizedDescription)
            })
            return false
        }
    }

    // MARK: - Private: Flush Pending Mutations

    /// Maximum number of events per batch request.
    /// Reduced from 500 to 50 because Cloud Run cannot process large batches
    /// within the iOS 15-second timeout (APIClient.swift line 44).
    /// With 500 events, every batch times out with NSURLErrorDomain -1001.
    /// 50 events completes in ~5-8 seconds, leaving headroom for cold starts.
    private let batchSize = 50

    private func flushPendingMutations() async throws {
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)

        let mutations = try localStore.fetchPendingMutations()
        let totalPending = mutations.count

        // Check circuit breaker - if we're in backoff, skip flushing but update state
        if let backoffUntil = rateLimitBackoffUntil, Date() < backoffUntil {
            let remaining = backoffUntil.timeIntervalSinceNow
            Log.sync.warning("Circuit breaker tripped - skipping mutation flush", context: .with { ctx in
                ctx.add("backoff_remaining_seconds", Int(remaining))
                ctx.add("pending_count", totalPending)
            })
            // Update state to show rate limit status to user
            await updateState(.rateLimited(retryAfter: remaining, pending: totalPending))
            return
        }

        guard !mutations.isEmpty else {
            Log.sync.debug("No pending mutations to flush")
            return
        }

        Log.sync.info("Flushing pending mutations", context: .with { ctx in
            ctx.add("count", mutations.count)
            ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
        })

        // Separate mutations by type for batch processing
        let eventCreateMutations = mutations.filter { $0.entityType == .event && $0.operation == .create }
        let otherMutations = mutations.filter { !($0.entityType == .event && $0.operation == .create) }

        var syncedCount = 0
        await updateState(.syncing(synced: 0, total: totalPending))

        // Step 1: Batch process event CREATE mutations
        if !eventCreateMutations.isEmpty {
            Log.sync.info("Batch processing event creates", context: .with { ctx in
                ctx.add("event_creates", eventCreateMutations.count)
                ctx.add("batch_size", batchSize)
                ctx.add("num_batches", (eventCreateMutations.count + batchSize - 1) / batchSize)
            })

            // Process in batches of batchSize
            for batchStart in stride(from: 0, to: eventCreateMutations.count, by: batchSize) {
                // Check circuit breaker before each batch
                if consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold {
                    tripCircuitBreaker()
                    let remaining = circuitBreakerBackoffRemaining
                    // Use existing context to get pending count - avoids creating concurrent ModelContext
                    let pendingNow = getPendingCountFromContext(context)
                    Log.sync.warning("Circuit breaker tripped during batch flush", context: .with { ctx in
                        ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
                        ctx.add("backoff_seconds", Int(remaining))
                        ctx.add("pending_remaining", pendingNow)
                    })
                    await updateState(.rateLimited(retryAfter: remaining, pending: pendingNow))
                    try context.save()
                    await updatePendingCount()
                    return
                }

                let batchEnd = min(batchStart + batchSize, eventCreateMutations.count)
                let batchMutations = Array(eventCreateMutations[batchStart..<batchEnd])

                // Update progress before attempting batch (so UI shows progress even if batch fails)
                let attemptedCount = batchStart
                await updateState(.syncing(synced: attemptedCount, total: totalPending))

                Log.sync.debug("Processing event batch", context: .with { ctx in
                    ctx.add("batch_start", batchStart)
                    ctx.add("batch_size", batchMutations.count)
                })

                do {
                    let batchSyncedCount = try await flushEventCreateBatch(
                        batchMutations,
                        localStore: localStore,
                        context: context
                    )
                    syncedCount += batchSyncedCount
                    await updateState(.syncing(synced: syncedCount, total: totalPending))

                    // Reset consecutive rate limit counter on success
                    consecutiveRateLimitErrors = 0

                } catch let error as APIError where error.isRateLimitError {
                    // Rate limit error - increment counter
                    consecutiveRateLimitErrors += 1
                    Log.sync.warning("Rate limit error during batch flush", context: .with { ctx in
                        ctx.add("batch_size", batchMutations.count)
                        ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
                    })
                    // Don't fail the batch - will retry on next sync cycle

                } catch {
                    // Other error (timeout, network, etc.) - record failure on each mutation
                    Log.sync.error("Error during batch flush", error: error, context: .with { ctx in
                        ctx.add("batch_size", batchMutations.count)
                        ctx.add("error_type", String(describing: type(of: error)))
                    })

                    // Record failure for each mutation in the batch so they're retried with backoff
                    for mutation in batchMutations {
                        mutation.recordFailure(error: "Batch operation failed: \(error.localizedDescription)")
                        if mutation.hasExceededRetryLimit {
                            Log.sync.warning("Mutation exceeded retry limit, marking entity as failed", context: .with { ctx in
                                ctx.add("entity_id", mutation.entityId)
                                ctx.add("attempt_count", mutation.attempts)
                            })
                            try? markEntityFailed(mutation, context: context)
                            context.delete(mutation)
                        }
                    }
                }
            }
        }

        // Step 2: Process other mutations one by one (updates, deletes, non-events)
        for mutation in otherMutations {
            // Check circuit breaker before each mutation
            if consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold {
                tripCircuitBreaker()
                let remaining = circuitBreakerBackoffRemaining
                // Use existing context to get pending count - avoids creating concurrent ModelContext
                let pendingNow = getPendingCountFromContext(context)
                Log.sync.warning("Circuit breaker tripped during flush - aborting remaining mutations", context: .with { ctx in
                    ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
                    ctx.add("backoff_seconds", Int(remaining))
                    ctx.add("pending_remaining", pendingNow)
                })
                // Update state to show rate limit status to user
                await updateState(.rateLimited(retryAfter: remaining, pending: pendingNow))
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
                syncedCount += 1
                await updateState(.syncing(synced: syncedCount, total: totalPending))

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
                syncedCount += 1
                await updateState(.syncing(synced: syncedCount, total: totalPending))

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
                    syncedCount += 1
                    await updateState(.syncing(synced: syncedCount, total: totalPending))
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
                    syncedCount += 1
                    await updateState(.syncing(synced: syncedCount, total: totalPending))
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

    /// Flush a batch of event CREATE mutations using the batch API.
    /// Returns the number of successfully synced events.
    private func flushEventCreateBatch(
        _ mutations: [PendingMutation],
        localStore: LocalStore,
        context: ModelContext
    ) async throws -> Int {
        // Build batch request from mutation payloads
        // Also build a secondary lookup by healthKitSampleId for upsert matching
        var requests: [CreateEventRequest] = []
        var mutationsByIndex: [Int: PendingMutation] = [:]
        var mutationsBySampleId: [String: (index: Int, mutation: PendingMutation)] = [:]

        for (index, mutation) in mutations.enumerated() {
            do {
                let request = try JSONDecoder().decode(CreateEventRequest.self, from: mutation.payload)
                requests.append(request)
                let requestIndex = requests.count - 1
                mutationsByIndex[requestIndex] = mutation

                // Build secondary lookup for HealthKit events by sample ID
                // This handles the case where backend upserts return a different ID
                if let sampleId = request.healthKitSampleId, !sampleId.isEmpty {
                    mutationsBySampleId[sampleId] = (index: requestIndex, mutation: mutation)
                }
            } catch {
                Log.sync.error("Failed to decode mutation payload for batch", error: error, context: .with { ctx in
                    ctx.add("entity_id", mutation.entityId)
                })
                // Mark mutation as failed
                mutation.recordFailure(error: "Failed to decode payload: \(error.localizedDescription)")
                if mutation.hasExceededRetryLimit {
                    try? markEntityFailed(mutation, context: context)
                    context.delete(mutation)
                }
            }
        }

        guard !requests.isEmpty else {
            return 0
        }

        Log.sync.info("Sending batch create request", context: .with { ctx in
            ctx.add("batch_size", requests.count)
            ctx.add("healthkit_events", mutationsBySampleId.count)
        })

        // Call batch API
        let response = try await apiClient.createEventsBatch(requests)

        Log.sync.info("Batch create response received", context: .with { ctx in
            ctx.add("total", response.total)
            ctx.add("success", response.success)
            ctx.add("failed", response.failed)
        })

        var syncedCount = 0

        // Mark successfully created events as synced
        for createdEvent in response.created {
            var matched = false

            // First try: Match by ID (works for new events with client-generated IDs)
            for (index, mutation) in mutationsByIndex {
                if mutation.entityId == createdEvent.id {
                    do {
                        try localStore.markEventSynced(id: createdEvent.id)
                        context.delete(mutation)
                        syncedCount += 1
                        matched = true
                        // Only remove from tracking AFTER successful processing
                        mutationsByIndex.removeValue(forKey: index)
                        // Also remove from sampleId lookup if present
                        if let sampleId = createdEvent.healthKitSampleId {
                            mutationsBySampleId.removeValue(forKey: sampleId)
                        }
                    } catch {
                        Log.sync.warning("Failed to mark event synced", context: .with { ctx in
                            ctx.add("event_id", createdEvent.id)
                            ctx.add("error", error.localizedDescription)
                        })
                        // Event was created on server, so delete the mutation anyway
                        // The local event will be updated via pullChanges on next sync
                        context.delete(mutation)
                        syncedCount += 1
                        matched = true
                        mutationsByIndex.removeValue(forKey: index)
                        if let sampleId = createdEvent.healthKitSampleId {
                            mutationsBySampleId.removeValue(forKey: sampleId)
                        }
                    }
                    break
                }
            }

            // Second try: Match by healthKitSampleId (handles HealthKit upserts)
            // When backend upserts an existing HealthKit event, it returns the EXISTING
            // event's ID, not the client-provided ID. We match by sample ID instead.
            if !matched, let sampleId = createdEvent.healthKitSampleId,
               let matchInfo = mutationsBySampleId[sampleId] {
                let mutation = matchInfo.mutation
                Log.sync.info("Matched HealthKit event by sample ID (upsert case)", context: .with { ctx in
                    ctx.add("sample_id", sampleId)
                    ctx.add("client_id", mutation.entityId)
                    ctx.add("server_id", createdEvent.id)
                })

                // Delete the LOCAL duplicate event (the one with client-generated ID)
                // The "real" event now has the server's ID
                do {
                    try localStore.deleteEvent(id: mutation.entityId)
                    Log.sync.debug("Deleted local duplicate event", context: .with { ctx in
                        ctx.add("local_id", mutation.entityId)
                        ctx.add("server_id", createdEvent.id)
                    })
                } catch {
                    // Event might not exist locally (already deleted or never saved)
                    Log.sync.debug("Could not delete local event (may not exist)", context: .with { ctx in
                        ctx.add("local_id", mutation.entityId)
                        ctx.add("error", error.localizedDescription)
                    })
                }

                context.delete(mutation)
                syncedCount += 1
                mutationsByIndex.removeValue(forKey: matchInfo.index)
                mutationsBySampleId.removeValue(forKey: sampleId)
            }
        }

        // Handle errors for specific events
        if let errors = response.errors {
            for batchError in errors {
                guard let mutation = mutationsByIndex[batchError.index] else { continue }

                // Check if it's a duplicate error (should be treated as success)
                if batchError.message.lowercased().contains("duplicate") ||
                   batchError.message.lowercased().contains("unique") {
                    Log.sync.warning("Batch item duplicate detected", context: .with { ctx in
                        ctx.add("index", batchError.index)
                        ctx.add("entity_id", mutation.entityId)
                        ctx.add("message", batchError.message)
                    })
                    // Delete local duplicate and mark as synced
                    try? deleteLocalDuplicate(mutation, localStore: localStore)
                    context.delete(mutation)
                    syncedCount += 1
                } else {
                    // Other error - record failure
                    Log.sync.error("Batch item failed", context: .with { ctx in
                        ctx.add("index", batchError.index)
                        ctx.add("entity_id", mutation.entityId)
                        ctx.add("message", batchError.message)
                    })
                    mutation.recordFailure(error: batchError.message)
                    if mutation.hasExceededRetryLimit {
                        try? markEntityFailed(mutation, context: context)
                        context.delete(mutation)
                        syncedCount += 1
                    }
                }
            }
        }

        return syncedCount
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
                let previousCursor = lastSyncCursor
                lastSyncCursor = response.nextCursor
                UserDefaults.standard.set(Int(lastSyncCursor), forKey: cursorKey)
                Log.sync.debug("Cursor advanced", context: .with { ctx in
                    ctx.add("before", Int(previousCursor))
                    ctx.add("after", Int(lastSyncCursor))
                })
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
        // Check both in-memory set AND SwiftData for belt-and-suspenders approach
        if pendingDeleteIds.contains(change.entityId) {
            Log.sync.debug("Skipping resurrection of pending-delete entity (from memory)", context: .with { ctx in
                ctx.add("entity_id", change.entityId)
                ctx.add("entity_type", change.entityType)
            })
            return
        }

        // Fallback check: query PendingMutation table directly for pending deletes
        // This handles the case where pendingDeleteIds wasn't populated (e.g., crash before persist)
        if hasPendingDeleteInSwiftData(entityId: change.entityId, localStore: localStore) {
            Log.sync.debug("Skipping resurrection of pending-delete entity (from SwiftData)", context: .with { ctx in
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
                        if let parsedType = PropertyType(rawValue: propertyType) {
                            propDef.propertyType = parsedType
                        } else {
                            Log.sync.warning("Unknown property type, using fallback", context: .with { ctx in
                                ctx.add("raw_value", propertyType)
                                ctx.add("fallback", PropertyType.text.rawValue)
                                ctx.add("property_key", propDef.key)
                            })
                            #if DEBUG
                            // Developer indicator for silent failures
                            assertionFailure("Unknown PropertyType: \(propertyType)")
                            #endif
                            propDef.propertyType = .text
                        }
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

    /// Check if there's a pending DELETE mutation for this entity in SwiftData.
    /// This is a fallback check for resurrection prevention when pendingDeleteIds
    /// may not have been populated (e.g., after app crash or restart).
    private func hasPendingDeleteInSwiftData(entityId: String, localStore: LocalStore) -> Bool {
        do {
            let mutations = try localStore.fetchPendingMutations()
            return mutations.contains { $0.entityId == entityId && $0.operation == .delete }
        } catch {
            Log.sync.warning("Failed to check pending delete in SwiftData", context: .with { ctx in
                ctx.add("entity_id", entityId)
                ctx.add("error", error.localizedDescription)
            })
            return false
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
                        if let parsedType = PropertyType(rawValue: apiPropDef.propertyType) {
                            propDef.propertyType = parsedType
                        } else {
                            Log.sync.warning("Unknown property type, using fallback", context: .with { ctx in
                                ctx.add("raw_value", apiPropDef.propertyType)
                                ctx.add("fallback", PropertyType.text.rawValue)
                                ctx.add("property_key", propDef.key)
                            })
                            #if DEBUG
                            // Developer indicator for silent failures
                            assertionFailure("Unknown PropertyType: \(apiPropDef.propertyType)")
                            #endif
                            propDef.propertyType = .text
                        }
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

        // Notify HealthKitService to reload processedSampleIds from the database.
        // This prevents duplicate event creation when HealthKit observer queries fire after bootstrap.
        // The bootstrap downloaded events with healthKitSampleIds, but HealthKitService's in-memory
        // processedSampleIds set doesn't include them yet.
        Log.sync.info("Posting bootstrap completed notification for HealthKit")
        await MainActor.run {
            NotificationCenter.default.post(name: .syncEngineBootstrapCompleted, object: nil)
        }
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
            let propertyType: PropertyType
            if let parsedType = PropertyType(rawValue: apiValue.type) {
                propertyType = parsedType
            } else {
                Log.sync.warning("Unknown property type, using fallback", context: .with { ctx in
                    ctx.add("raw_value", apiValue.type)
                    ctx.add("fallback", PropertyType.text.rawValue)
                    ctx.add("property_key", key)
                })
                #if DEBUG
                // Developer indicator for silent failures
                assertionFailure("Unknown PropertyType: \(apiValue.type)")
                #endif
                propertyType = .text
            }
            localProperties[key] = PropertyValue(type: propertyType, value: apiValue.value.value)
        }
        return localProperties
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case encodingFailed
    case waitTimeout
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode mutation payload"
        case .waitTimeout:
            return "Timed out waiting for sync to complete"
        case .unknown(let message):
            return message
        }
    }
}
