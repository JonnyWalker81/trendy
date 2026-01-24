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

    private let networkClient: any NetworkClientProtocol
    private let dataStoreFactory: any DataStoreFactory
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

    init(networkClient: any NetworkClientProtocol, dataStoreFactory: any DataStoreFactory, syncHistoryStore: SyncHistoryStore? = nil) {
        self.networkClient = networkClient
        self.dataStoreFactory = dataStoreFactory
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
        let dataStore = dataStoreFactory.makeDataStore()
        let count = (try? dataStore.fetchPendingMutations().count) ?? 0

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

        // Start metrics interval for full sync
        let syncMetricsId = SyncMetrics.beginFullSync()

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

            // Create a single dataStore for pre-sync operations to avoid SQLite file locking issues.
            // Multiple concurrent ModelContexts can cause "default.store couldn't be opened" errors.
            let preSyncDataStore = dataStoreFactory.makeDataStore()

            // Count pending mutations before sync for history tracking
            let allMutations = try preSyncDataStore.fetchPendingMutations()
            let initialPendingCount = allMutations.count

            // Capture IDs with pending DELETE mutations BEFORE flush
            // These should not be resurrected by pullChanges even if change_log has CREATE entries
            let pendingDeletes = allMutations
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
                    let latestCursor = try await networkClient.getLatestCursor()
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
            let finalPendingCount = (try? preSyncDataStore.fetchPendingMutations().count) ?? 0
            let syncedCount = max(0, initialPendingCount - finalPendingCount)

            Log.sync.info("Sync completed successfully", context: .with { ctx in
                ctx.add("new_cursor", Int(lastSyncCursor))
                ctx.add("duration_ms", syncDurationMs)
                ctx.add("items_synced", syncedCount)
            })

            // Record success metrics
            SyncMetrics.recordSyncSuccess()
            SyncMetrics.endFullSync(syncMetricsId)

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

            // Record failure metrics
            SyncMetrics.recordSyncFailure()
            SyncMetrics.endFullSync(syncMetricsId)

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
        let dataStore = dataStoreFactory.makeDataStore()
        let pendingMutations = try dataStore.fetchPendingMutations()
        let pendingCount = pendingMutations.count

        // Get the latest cursor from the backend
        let previousCursor = lastSyncCursor
        let latestCursor = try await networkClient.getLatestCursor()

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
        let dataStore = dataStoreFactory.makeDataStore()

        do {
            try restoreEventTypeRelationships(dataStore: dataStore)
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

        let dataStore = dataStoreFactory.makeDataStore()

        // Fetch geofences from API
        let geofences = try await networkClient.getGeofences(activeOnly: false)
        Log.sync.info("Fetched geofences from server", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        // Upsert each geofence
        for apiGeofence in geofences {
            try dataStore.upsertGeofence(id: apiGeofence.id) { geofence in
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

        try dataStore.save()
        Log.sync.info("Saved geofences locally", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        return geofences.count
    }

    /// Get the local geofence count
    func getLocalGeofenceCount() -> Int {
        let dataStore = dataStoreFactory.makeDataStore()
        return (try? dataStore.fetchAllGeofences().count) ?? 0
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
        let dataStore = dataStoreFactory.makeDataStore()

        // DEDUPLICATION: Check if a pending mutation already exists for this entity
        // This prevents duplicate mutations from being queued when multiple code paths
        // (e.g., syncEventToBackend, queueMutationsForUnsyncedEvents, resyncHealthKitEvents)
        // try to sync the same event.
        let hasDuplicate = try dataStore.hasPendingMutation(entityId: entityId, entityType: entityType, operation: operation)
        if hasDuplicate {
            Log.sync.debug("Skipping duplicate mutation (already pending)", context: .with { ctx in
                ctx.add("entity_type", entityType.rawValue)
                ctx.add("operation", operation.rawValue)
                ctx.add("entity_id", entityId)
            })
            return
        }

        let mutation = PendingMutation(
            entityType: entityType,
            operation: operation,
            entityId: entityId,
            payload: payload
        )

        try dataStore.insertPendingMutation(mutation)
        try dataStore.save()

        await updatePendingCount()
        Log.sync.debug("Queued mutation", context: .with { ctx in
            ctx.add("entity_type", entityType.rawValue)
            ctx.add("operation", operation.rawValue)
            ctx.add("entity_id", entityId)
        })
    }

    /// Get the current pending mutation count
    func getPendingCount() async -> Int {
        let dataStore = dataStoreFactory.makeDataStore()
        return getPendingCountFromDataStore(dataStore)
    }

    /// Get the current pending mutation count using an existing dataStore.
    /// This avoids creating multiple ModelContexts which can cause SQLite file locking issues.
    private func getPendingCountFromDataStore(_ dataStore: any DataStoreProtocol) -> Int {
        return (try? dataStore.fetchPendingMutations().count) ?? 0
    }

    /// Clear all pending mutations from the queue.
    /// Use this to recover from a retry storm where mutations are continuously failing.
    /// WARNING: This will abandon any unsynced local changes - they will NOT be synced to the backend.
    /// - Parameter markEntitiesFailed: If true, mark the corresponding entities as failed. Default is true.
    /// - Returns: The number of mutations cleared
    @discardableResult
    func clearPendingMutations(markEntitiesFailed: Bool = true) async -> Int {
        let dataStore = dataStoreFactory.makeDataStore()

        do {
            let mutations = try dataStore.fetchPendingMutations()
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
                    try? markEntityFailed(mutation, dataStore: dataStore)
                }
                try dataStore.deletePendingMutation(mutation)
            }

            try dataStore.save()
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
        let healthCheckMetricsId = SyncMetrics.beginHealthCheck()
        defer { SyncMetrics.endHealthCheck(healthCheckMetricsId) }

        do {
            let types = try await networkClient.getEventTypes()
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
        let flushMetricsId = SyncMetrics.beginFlushMutations()
        defer { SyncMetrics.endFlushMutations(flushMetricsId) }

        let dataStore = dataStoreFactory.makeDataStore()

        let mutations = try dataStore.fetchPendingMutations()
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
        syncedCount = try await syncEventCreateBatches(
            eventCreateMutations,
            dataStore: dataStore,
            totalPending: totalPending
        )

        // Check if circuit breaker tripped during batch processing - early exit if so
        if isCircuitBreakerTripped {
            try dataStore.save()
            await updatePendingCount()
            return
        }

        // Step 2: Process other mutations one by one (updates, deletes, non-events)
        syncedCount = try await syncOtherMutations(
            otherMutations,
            dataStore: dataStore,
            startingSyncedCount: syncedCount,
            totalPending: totalPending
        )

        try dataStore.save()
        await updatePendingCount()
    }

    /// Process event CREATE mutations in batches of 50.
    /// - Parameters:
    ///   - mutations: Event CREATE mutations to process
    ///   - dataStore: Data store for persistence operations
    ///   - totalPending: Total pending mutations (for progress updates)
    /// - Returns: Number of successfully synced events
    /// - Throws: Propagates network errors (rate limits handled internally)
    private func syncEventCreateBatches(
        _ mutations: [PendingMutation],
        dataStore: any DataStoreProtocol,
        totalPending: Int
    ) async throws -> Int {
        guard !mutations.isEmpty else { return 0 }

        Log.sync.info("Batch processing event creates", context: .with { ctx in
            ctx.add("event_creates", mutations.count)
            ctx.add("batch_size", batchSize)
            ctx.add("num_batches", (mutations.count + batchSize - 1) / batchSize)
        })

        var syncedCount = 0

        // Process in batches of batchSize
        for batchStart in stride(from: 0, to: mutations.count, by: batchSize) {
            // Check circuit breaker before each batch
            if consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold {
                tripCircuitBreaker()
                let remaining = circuitBreakerBackoffRemaining
                // Use existing dataStore to get pending count - avoids creating concurrent contexts
                let pendingNow = getPendingCountFromDataStore(dataStore)
                Log.sync.warning("Circuit breaker tripped during batch flush", context: .with { ctx in
                    ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
                    ctx.add("backoff_seconds", Int(remaining))
                    ctx.add("pending_remaining", pendingNow)
                })
                await updateState(.rateLimited(retryAfter: remaining, pending: pendingNow))
                try dataStore.save()
                await updatePendingCount()
                return syncedCount
            }

            let batchEnd = min(batchStart + batchSize, mutations.count)
            let batchMutations = Array(mutations[batchStart..<batchEnd])

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
                    dataStore: dataStore
                )
                syncedCount += batchSyncedCount
                await updateState(.syncing(synced: syncedCount, total: totalPending))

                // Reset consecutive rate limit counter on success
                consecutiveRateLimitErrors = 0

            } catch let error as APIError where error.isRateLimitError {
                // Rate limit error - increment counter
                consecutiveRateLimitErrors += 1
                SyncMetrics.recordRateLimitHit()
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
                        try? markEntityFailed(mutation, dataStore: dataStore)
                        try? dataStore.deletePendingMutation(mutation)
                    }
                }
            }
        }

        return syncedCount
    }

    /// Process non-event-CREATE mutations one by one.
    /// - Parameters:
    ///   - mutations: Mutations to process (updates, deletes, non-events)
    ///   - dataStore: Data store for persistence operations
    ///   - startingSyncedCount: Count of already synced mutations
    ///   - totalPending: Total pending mutations (for progress updates)
    /// - Returns: Final synced count after processing
    /// - Throws: Propagates unexpected errors (rate limits handled internally)
    private func syncOtherMutations(
        _ mutations: [PendingMutation],
        dataStore: any DataStoreProtocol,
        startingSyncedCount: Int,
        totalPending: Int
    ) async throws -> Int {
        var syncedCount = startingSyncedCount

        for mutation in mutations {
            // Check circuit breaker before each mutation
            if consecutiveRateLimitErrors >= rateLimitCircuitBreakerThreshold {
                tripCircuitBreaker()
                let remaining = circuitBreakerBackoffRemaining
                // Use existing dataStore to get pending count - avoids creating concurrent contexts
                let pendingNow = getPendingCountFromDataStore(dataStore)
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
                try await flushMutation(mutation, dataStore: dataStore)
                Log.sync.info("Mutation flushed successfully", context: .with { ctx in
                    ctx.add("entity_type", mutation.entityType.rawValue)
                    ctx.add("entity_id", mutation.entityId)
                })
                try dataStore.deletePendingMutation(mutation)
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
                try deleteLocalDuplicate(mutation, dataStore: dataStore)
                try dataStore.deletePendingMutation(mutation)
                syncedCount += 1
                await updateState(.syncing(synced: syncedCount, total: totalPending))

                // Reset rate limit counter - duplicates are not rate limit errors
                consecutiveRateLimitErrors = 0

            } catch let error as APIError where error.isRateLimitError {
                // Rate limit error - increment counter but DON'T count against mutation retry limit
                consecutiveRateLimitErrors += 1
                SyncMetrics.recordRateLimitHit()
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
                    try markEntityFailed(mutation, dataStore: dataStore)
                    try dataStore.deletePendingMutation(mutation)
                    syncedCount += 1
                    await updateState(.syncing(synced: syncedCount, total: totalPending))
                } else {
                    SyncMetrics.recordRetry()
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
                    try markEntityFailed(mutation, dataStore: dataStore)
                    try dataStore.deletePendingMutation(mutation)
                    syncedCount += 1
                    await updateState(.syncing(synced: syncedCount, total: totalPending))
                } else {
                    SyncMetrics.recordRetry()
                    Log.sync.info("Mutation will retry", context: .with { ctx in
                        ctx.add("attempts_after", mutation.attempts)
                    })
                }
            }
        }

        return syncedCount
    }

    /// Flush a batch of event CREATE mutations using the batch API.
    /// Returns the number of successfully synced events.
    private func flushEventCreateBatch(
        _ mutations: [PendingMutation],
        dataStore: any DataStoreProtocol
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
                    try? markEntityFailed(mutation, dataStore: dataStore)
                    try? dataStore.deletePendingMutation(mutation)
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
        let response = try await networkClient.createEventsBatch(requests)

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
                        try dataStore.markEventSynced(id: createdEvent.id)
                        try dataStore.deletePendingMutation(mutation)
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
                        try? dataStore.deletePendingMutation(mutation)
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
                    try dataStore.deleteEvent(id: mutation.entityId)
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

                try? dataStore.deletePendingMutation(mutation)
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
                    try? deleteLocalDuplicate(mutation, dataStore: dataStore)
                    try? dataStore.deletePendingMutation(mutation)
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
                        try? markEntityFailed(mutation, dataStore: dataStore)
                        try? dataStore.deletePendingMutation(mutation)
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

        // Record circuit breaker trip in metrics
        SyncMetrics.recordCircuitBreakerTrip()

        Log.sync.warning("Circuit breaker tripped", context: .with { ctx in
            ctx.add("backoff_duration_seconds", Int(backoffDuration))
            ctx.add("backoff_multiplier", rateLimitBackoffMultiplier)
            ctx.add("consecutive_rate_limits", consecutiveRateLimitErrors)
        })
    }

    private func flushMutation(_ mutation: PendingMutation, dataStore: any DataStoreProtocol) async throws {
        switch mutation.operation {
        case .create:
            try await flushCreate(mutation, dataStore: dataStore)
        case .update:
            try await flushUpdate(mutation)
        case .delete:
            try await flushDelete(mutation)
        }
    }

    private func flushCreate(_ mutation: PendingMutation, dataStore: any DataStoreProtocol) async throws {
        switch mutation.entityType {
        case .event:
            let request = try JSONDecoder().decode(CreateEventRequest.self, from: mutation.payload)
            _ = try await networkClient.createEventWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            // With UUIDv7, no reconciliation needed - just mark as synced
            try dataStore.markEventSynced(id: mutation.entityId)

        case .eventType:
            let request = try JSONDecoder().decode(CreateEventTypeRequest.self, from: mutation.payload)
            _ = try await networkClient.createEventTypeWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try dataStore.markEventTypeSynced(id: mutation.entityId)

        case .geofence:
            let request = try JSONDecoder().decode(CreateGeofenceRequest.self, from: mutation.payload)
            _ = try await networkClient.createGeofenceWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try dataStore.markGeofenceSynced(id: mutation.entityId)

        case .propertyDefinition:
            let request = try JSONDecoder().decode(CreatePropertyDefinitionRequest.self, from: mutation.payload)
            _ = try await networkClient.createPropertyDefinitionWithIdempotency(
                request,
                idempotencyKey: mutation.clientRequestId
            )
            try dataStore.markPropertyDefinitionSynced(id: mutation.entityId)
        }

        try dataStore.save()
    }

    private func flushUpdate(_ mutation: PendingMutation) async throws {
        // For updates, entityId IS the server ID (since we use UUIDv7)
        let entityId = mutation.entityId

        switch mutation.entityType {
        case .event:
            let request = try JSONDecoder().decode(UpdateEventRequest.self, from: mutation.payload)
            _ = try await networkClient.updateEvent(id: entityId, request)

        case .eventType:
            let request = try JSONDecoder().decode(UpdateEventTypeRequest.self, from: mutation.payload)
            _ = try await networkClient.updateEventType(id: entityId, request)

        case .geofence:
            let request = try JSONDecoder().decode(UpdateGeofenceRequest.self, from: mutation.payload)
            _ = try await networkClient.updateGeofence(id: entityId, request)

        case .propertyDefinition:
            let request = try JSONDecoder().decode(UpdatePropertyDefinitionRequest.self, from: mutation.payload)
            _ = try await networkClient.updatePropertyDefinition(id: entityId, request)
        }
    }

    private func flushDelete(_ mutation: PendingMutation) async throws {
        // For deletes, entityId IS the server ID (since we use UUIDv7)
        let entityId = mutation.entityId

        switch mutation.entityType {
        case .event:
            try await networkClient.deleteEvent(id: entityId)
        case .eventType:
            try await networkClient.deleteEventType(id: entityId)
        case .geofence:
            try await networkClient.deleteGeofence(id: entityId)
        case .propertyDefinition:
            try await networkClient.deletePropertyDefinition(id: entityId)
        }
    }

    private func markEntityFailed(_ mutation: PendingMutation, dataStore: any DataStoreProtocol) throws {
        let entityId = mutation.entityId

        switch mutation.entityType {
        case .event:
            if let event = try dataStore.findEvent(id: entityId) {
                event.syncStatus = .failed
            }

        case .eventType:
            if let eventType = try dataStore.findEventType(id: entityId) {
                eventType.syncStatus = .failed
            }

        case .geofence:
            if let geofence = try dataStore.findGeofence(id: entityId) {
                geofence.syncStatus = .failed
            }

        case .propertyDefinition:
            if let propDef = try dataStore.findPropertyDefinition(id: entityId) {
                propDef.syncStatus = .failed
            }
        }
    }

    /// Handle duplicate error by marking the entity as synced.
    /// With UUIDv7, the server has the same ID, so we just mark synced.
    private func markEntitySynced(_ mutation: PendingMutation, dataStore: any DataStoreProtocol) throws {
        switch mutation.entityType {
        case .event:
            try dataStore.markEventSynced(id: mutation.entityId)
        case .eventType:
            try dataStore.markEventTypeSynced(id: mutation.entityId)
        case .geofence:
            try dataStore.markGeofenceSynced(id: mutation.entityId)
        case .propertyDefinition:
            try dataStore.markPropertyDefinitionSynced(id: mutation.entityId)
        }
    }

    /// Handle duplicate error by deleting the local duplicate entity.
    /// This happens when a race condition creates multiple local entities with different IDs
    /// but the same unique constraint fields (e.g., healthKitSampleId). The "real" entity
    /// already synced successfully, so this duplicate should be removed.
    private func deleteLocalDuplicate(_ mutation: PendingMutation, dataStore: any DataStoreProtocol) throws {
        Log.sync.info("Deleting local duplicate entity", context: .with { ctx in
            ctx.add("entity_type", mutation.entityType.rawValue)
            ctx.add("entity_id", mutation.entityId)
        })

        switch mutation.entityType {
        case .event:
            try dataStore.deleteEvent(id: mutation.entityId)
        case .eventType:
            try dataStore.deleteEventType(id: mutation.entityId)
        case .geofence:
            try dataStore.deleteGeofence(id: mutation.entityId)
        case .propertyDefinition:
            try dataStore.deletePropertyDefinition(id: mutation.entityId)
        }
    }

    // MARK: - Private: Pull Changes

    private func pullChanges() async throws {
        let pullMetricsId = SyncMetrics.beginPullChanges()
        defer { SyncMetrics.endPullChanges(pullMetricsId) }

        var hasMore = true

        while hasMore {
            let response = try await networkClient.getChanges(
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
        let dataStore = dataStoreFactory.makeDataStore()

        for change in changes {
            do {
                try applyChange(change, dataStore: dataStore)
            } catch {
                Log.sync.error("Failed to apply change", error: error, context: .with { ctx in
                    ctx.add("change_id", Int(change.id))
                    ctx.add("entity_type", change.entityType)
                    ctx.add("operation", change.operation)
                })
                // Continue with other changes even if one fails
            }
        }

        try dataStore.save()
    }

    private func applyChange(_ change: ChangeEntry, dataStore: any DataStoreProtocol) throws {
        switch change.operation {
        case "create", "update":
            try applyUpsert(change, dataStore: dataStore)
        case "delete":
            try applyDelete(change, dataStore: dataStore)
        default:
            Log.sync.warning("Unknown operation", context: .with { ctx in
                ctx.add("operation", change.operation)
            })
        }
    }

    private func applyUpsert(_ change: ChangeEntry, dataStore: any DataStoreProtocol) throws {
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
        if hasPendingDeleteInSwiftData(entityId: change.entityId, dataStore: dataStore) {
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
            try dataStore.upsertEvent(id: change.entityId) { event in
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
                    if let localEventType = try? dataStore.findEventType(id: eventTypeId) {
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
            try dataStore.upsertEventType(id: change.entityId) { eventType in
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
            try dataStore.upsertGeofence(id: change.entityId) { geofence in
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
                try dataStore.upsertPropertyDefinition(id: change.entityId, eventTypeId: eventTypeId) { propDef in
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
    private func hasPendingDeleteInSwiftData(entityId: String, dataStore: any DataStoreProtocol) -> Bool {
        do {
            let mutations = try dataStore.fetchPendingMutations()
            return mutations.contains { $0.entityId == entityId && $0.operation == .delete }
        } catch {
            Log.sync.warning("Failed to check pending delete in SwiftData", context: .with { ctx in
                ctx.add("entity_id", entityId)
                ctx.add("error", error.localizedDescription)
            })
            return false
        }
    }

    private func applyDelete(_ change: ChangeEntry, dataStore: any DataStoreProtocol) throws {
        switch change.entityType {
        case "event":
            try dataStore.deleteEvent(id: change.entityId)
        case "event_type":
            try dataStore.deleteEventType(id: change.entityId)
        case "geofence":
            try dataStore.deleteGeofence(id: change.entityId)
        case "property_definition":
            try dataStore.deletePropertyDefinition(id: change.entityId)
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
        let bootstrapMetricsId = SyncMetrics.beginBootstrapFetch()
        defer { SyncMetrics.endBootstrapFetch(bootstrapMetricsId) }

        let dataStore = dataStoreFactory.makeDataStore()

        // Step 0: Nuclear cleanup - ensure clean slate before populating from backend
        try performNuclearCleanup(dataStore: dataStore)

        // Step 1: Fetch EventTypes first (Events reference them)
        let eventTypes = try await fetchEventTypesForBootstrap(dataStore: dataStore)

        // Step 2: Fetch Geofences (Events may reference them)
        try await fetchGeofencesForBootstrap(dataStore: dataStore)

        // Step 3: Fetch Events
        let eventCount = try await fetchEventsForBootstrap(dataStore: dataStore)

        // Step 4: Fetch PropertyDefinitions for each EventType
        let propDefCount = try await fetchPropertyDefinitionsForBootstrap(
            eventTypes: eventTypes,
            dataStore: dataStore
        )

        // Restore any broken Event->EventType relationships
        try restoreEventTypeRelationships(dataStore: dataStore)

        // Verification: count remaining records after bootstrap
        let finalEventCount = try dataStore.fetchAllEvents().count
        let finalEventTypeCount = try dataStore.fetchAllEventTypes().count
        let finalGeofenceCount = try dataStore.fetchAllGeofences().count

        Log.sync.info("Bootstrap fetch completed", context: .with { ctx in
            ctx.add("backend_event_types", eventTypes.count)
            ctx.add("backend_geofences", finalGeofenceCount)
            ctx.add("backend_events", eventCount)
            ctx.add("backend_property_definitions", propDefCount)
            ctx.add("final_local_events", finalEventCount)
            ctx.add("final_local_event_types", finalEventTypeCount)
            ctx.add("final_local_geofences", finalGeofenceCount)
        })

        // DIAGNOSTIC: Additional verification after save (using fresh dataStore)
        let verifyDataStore = dataStoreFactory.makeDataStore()
        let verifyEventCount = (try? verifyDataStore.fetchAllEvents().count) ?? -1
        let verifyEventTypeCount = (try? verifyDataStore.fetchAllEventTypes().count) ?? -1
        Log.sync.info("Bootstrap verification after save", context: .with { ctx in
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

    /// Fetch and upsert all EventTypes from backend.
    /// - Parameter dataStore: Data store for persistence operations
    /// - Returns: Array of fetched API event types (needed for property definition fetch)
    /// - Throws: Network or persistence errors
    private func fetchEventTypesForBootstrap(
        dataStore: any DataStoreProtocol
    ) async throws -> [APIEventType] {
        Log.sync.info("Bootstrap: fetching event types")
        let eventTypes = try await networkClient.getEventTypes()
        Log.sync.info("Bootstrap: received event types", context: .with { ctx in
            ctx.add("count", eventTypes.count)
            for (index, et) in eventTypes.prefix(5).enumerated() {
                ctx.add("event_type_\(index)", "\(et.id): \(et.name)")
            }
        })

        for apiEventType in eventTypes {
            try dataStore.upsertEventType(id: apiEventType.id) { eventType in
                eventType.name = apiEventType.name
                eventType.colorHex = apiEventType.color
                eventType.iconName = apiEventType.icon
            }
        }

        // Save EventTypes immediately to ensure they're persisted before Geofences reference them
        try dataStore.save()
        Log.sync.info("Bootstrap: Saved event types", context: .with { ctx in
            ctx.add("count", eventTypes.count)
        })

        return eventTypes
    }

    /// Fetch and upsert all Geofences from backend.
    /// - Parameter dataStore: Data store for persistence operations
    /// - Throws: Network or persistence errors
    private func fetchGeofencesForBootstrap(
        dataStore: any DataStoreProtocol
    ) async throws {
        Log.sync.info("Bootstrap: fetching geofences")
        let geofences = try await networkClient.getGeofences(activeOnly: false)
        Log.sync.info("Bootstrap: received geofences", context: .with { ctx in
            ctx.add("count", geofences.count)
        })

        for apiGeofence in geofences {
            try dataStore.upsertGeofence(id: apiGeofence.id) { geofence in
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
        try dataStore.save()
        Log.sync.info("Bootstrap: Saved geofences", context: .with { ctx in
            ctx.add("count", geofences.count)
        })
    }

    /// Fetch and upsert all Events from backend.
    /// - Parameter dataStore: Data store for persistence operations
    /// - Returns: Count of fetched events (for logging)
    /// - Throws: Network or persistence errors
    private func fetchEventsForBootstrap(
        dataStore: any DataStoreProtocol
    ) async throws -> Int {
        Log.sync.info("Bootstrap: fetching events")
        let events = try await networkClient.getAllEvents(batchSize: 50)
        Log.sync.info("Bootstrap: received events", context: .with { ctx in
            ctx.add("count", events.count)
            for (index, ev) in events.prefix(5).enumerated() {
                ctx.add("event_\(index)", "\(ev.id): \(ev.eventTypeId) @ \(ev.timestamp)")
            }
        })

        for apiEvent in events {
            let event = try dataStore.upsertEvent(id: apiEvent.id) { event in
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
            if let localEventType = try? dataStore.findEventType(id: apiEvent.eventTypeId) {
                event.eventType = localEventType
            } else {
                Log.sync.warning("Bootstrap: Could not find EventType for event", context: .with { ctx in
                    ctx.add("event_id", apiEvent.id)
                    ctx.add("event_type_id", apiEvent.eventTypeId)
                })
            }
        }

        // Save Events immediately to ensure they're persisted
        try dataStore.save()
        Log.sync.info("Bootstrap: Saved events", context: .with { ctx in
            ctx.add("count", events.count)
        })

        return events.count
    }

    /// Fetch property definitions for all event types.
    /// - Parameters:
    ///   - eventTypes: Event types to fetch definitions for
    ///   - dataStore: Data store for persistence operations
    /// - Returns: Count of fetched property definitions (for logging)
    /// - Throws: Persistence errors (network errors per-type are logged and continue)
    private func fetchPropertyDefinitionsForBootstrap(
        eventTypes: [APIEventType],
        dataStore: any DataStoreProtocol
    ) async throws -> Int {
        Log.sync.info("Bootstrap: fetching property definitions")
        var allPropertyDefinitionIds: [String] = []

        for apiEventType in eventTypes {
            do {
                let propDefs = try await networkClient.getPropertyDefinitions(eventTypeId: apiEventType.id)
                for apiPropDef in propDefs {
                    try dataStore.upsertPropertyDefinition(id: apiPropDef.id, eventTypeId: apiEventType.id) { propDef in
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
        try dataStore.save()

        return allPropertyDefinitionIds.count
    }

    /// Delete all local data before repopulating from backend.
    /// Called during bootstrap to ensure a clean slate.
    /// - Parameter dataStore: Data store for persistence operations
    /// - Throws: If deletion or save fails
    private func performNuclearCleanup(dataStore: any DataStoreProtocol) throws {
        Log.sync.info("Bootstrap: Starting nuclear cleanup of all local data")

        // Delete all Events first (they reference EventTypes)
        let allLocalEvents = try dataStore.fetchAllEvents()
        Log.sync.info("Bootstrap: Deleting all local events", context: .with { ctx in
            ctx.add("count", allLocalEvents.count)
        })
        try dataStore.deleteAllEvents()

        // Delete all Geofences
        let allLocalGeofences = try dataStore.fetchAllGeofences()
        Log.sync.info("Bootstrap: Deleting all local geofences", context: .with { ctx in
            ctx.add("count", allLocalGeofences.count)
        })
        try dataStore.deleteAllGeofences()

        // Delete all PropertyDefinitions
        let allLocalPropDefs = try dataStore.fetchAllPropertyDefinitions()
        Log.sync.info("Bootstrap: Deleting all local property definitions", context: .with { ctx in
            ctx.add("count", allLocalPropDefs.count)
        })
        try dataStore.deleteAllPropertyDefinitions()

        // Delete all EventTypes last (other entities may reference them)
        let allLocalEventTypes = try dataStore.fetchAllEventTypes()
        Log.sync.info("Bootstrap: Deleting all local event types", context: .with { ctx in
            ctx.add("count", allLocalEventTypes.count)
        })
        try dataStore.deleteAllEventTypes()

        // Save the deletions
        try dataStore.save()
        Log.sync.info("Bootstrap: Nuclear cleanup completed - all local data deleted")
    }

    /// Restore Event→EventType relationships for events with missing eventType relationship.
    /// This can happen when events are loaded from backend but the SwiftData relationship wasn't
    /// properly established during sync. Uses the stored eventTypeId field for recovery.
    private func restoreEventTypeRelationships(dataStore: any DataStoreProtocol) throws {
        let allEvents = try dataStore.fetchAllEvents()
        var restoredCount = 0
        var orphanedCount = 0

        for event in allEvents {
            // Check if event is missing the relationship
            guard event.eventType == nil else { continue }

            // Try to restore using the stored eventTypeId
            if let eventTypeId = event.eventTypeId {
                if let localEventType = try? dataStore.findEventType(id: eventTypeId) {
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
            try dataStore.save()
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
