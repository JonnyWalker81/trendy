//
//  EventStore.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import SwiftData
import SwiftUI
import Network
import WidgetKit

@Observable
@MainActor
class EventStore {
    private(set) var events: [Event] = [] {
        didSet {
            rebuildEventsByDateCache()
        }
    }
    private(set) var eventTypes: [EventType] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Events by Date Cache (Performance Optimization)

    /// Cached dictionary for O(1) date lookups instead of O(N) filtering.
    /// Key: Start of day (midnight) for the date
    /// Value: Array of events on that date (including multi-day events)
    private var eventsByDateCache: [Date: [Event]] = [:]

    /// Calendar instance cached for performance (avoid repeated Calendar.current calls)
    private let cachedCalendar = Calendar.current

    /// Indicates whether data has been loaded at least once (for distinguishing initial load vs refresh)
    private(set) var hasLoadedOnce = false

    /// Timestamp of last successful fetch (for debouncing)
    private var lastFetchTime: Date?

    /// Minimum interval between fetches (5 seconds) to prevent redundant API calls on tab switches
    private let fetchDebounceInterval: TimeInterval = 5.0

    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?
    private var calendarManager: CalendarManager?
    var syncWithCalendar = true

    // Backend integration
    private let apiClient: APIClient?
    private var syncEngine: SyncEngine?
    private var syncHistoryStore: SyncHistoryStore?

    // Network monitoring
    private let monitor = NWPathMonitor()
    private(set) var isOnline = false

    // MARK: - Sync State (delegated from SyncEngine)

    var syncState: SyncState {
        get async {
            await syncEngine?.state ?? .idle
        }
    }

    var pendingCount: Int {
        get async {
            await syncEngine?.pendingCount ?? 0
        }
    }

    // Cached sync state for UI binding (updated periodically)
    private(set) var currentSyncState: SyncState = .idle
    private(set) var currentPendingCount: Int = 0
    private(set) var currentLastSyncTime: Date?

    // MARK: - Initialization

    /// Initialize EventStore with APIClient
    /// - Parameter apiClient: API client for backend communication
    init(apiClient: APIClient) {
        self.apiClient = apiClient
        setupNetworkMonitor()
    }

    #if DEBUG
    /// Initialize EventStore for local-only mode (screenshot testing)
    /// No network calls, uses SwiftData directly
    init() {
        self.apiClient = nil
        setupNetworkMonitor()
    }
    #endif

    private func setupNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Update state on MainActor without blocking
            // Use Task.detached to avoid inheriting actor context from callback queue
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasOffline = !self.isOnline
                let nowOnline = (path.status == .satisfied)
                self.isOnline = nowOnline

                Log.sync.debug("Network state changed", context: .with { ctx in
                    ctx.add("was_offline", wasOffline)
                    ctx.add("now_online", nowOnline)
                })

                // Auto-sync when coming back online (fire-and-forget to avoid blocking)
                if wasOffline && nowOnline {
                    // Spawn a separate task for sync to avoid blocking the monitor callback
                    Task { @MainActor [weak self] in
                        await self?.handleNetworkRestored()
                    }
                }
            }
        }
        let queue = DispatchQueue(label: "com.trendy.eventstore-network-monitor")
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Synchronously check the current network path status.
    /// This is more reliable than the cached `isOnline` value when the app returns from background,
    /// because NWPathMonitor callbacks may not have fired yet.
    /// - Returns: true if network is currently available, false otherwise
    func checkNetworkPathSynchronously() -> Bool {
        let path = monitor.currentPath
        let isConnected = path.status == .satisfied

        // Update cached value to match current state
        if isOnline != isConnected {
            Log.sync.debug("Network state updated from synchronous check", context: .with { ctx in
                ctx.add("cached_was", isOnline)
                ctx.add("actual_is", isConnected)
            })
            isOnline = isConnected
        }

        return isConnected
    }

    private func handleNetworkRestored() async {
        // Guard against rapid repeated calls
        guard !isLoading else {
            Log.sync.debug("Network restored but already loading, skipping sync")
            return
        }

        Log.sync.info("Network restored - starting sync")

        // Reset DataStore before sync in case the app was backgrounded when connectivity dropped.
        // The cached ModelContext may have stale file handles after iOS reclaimed resources.
        await syncEngine?.resetDataStore()

        await performSync()
        await refreshSyncStateForUI()
    }

    // MARK: - Widget Integration

    /// Reloads all widget timelines to reflect data changes
    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sets up Darwin notification observer to receive updates from widgets
    /// Call this from the main app view (e.g., MainTabView) on appear
    func setupWidgetNotificationObserver() {
        let notificationName = "com.memento.trendy.widgetDataChanged" as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let eventStore = Unmanaged<EventStore>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    // Queue mutations for any widget-created events before fetching
                    await eventStore.queueMutationsForUnsyncedEvents()
                    await eventStore.fetchData()
                }
            },
            notificationName,
            nil,
            .deliverImmediately
        )
    }

    /// Removes Darwin notification observer
    func removeWidgetNotificationObserver() {
        let notificationName = "com.memento.trendy.widgetDataChanged" as CFString
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(notificationName),
            nil
        )
    }

    /// Finds events created by widgets (pending sync but no mutation queued) and queues mutations for them.
    /// This is called when the main app receives a Darwin notification from the widget extension.
    func queueMutationsForUnsyncedEvents() async {
        guard let modelContext = modelContext,
              let syncEngine = syncEngine else {
            Log.sync.debug("queueMutationsForUnsyncedEvents: skipping - no context or syncEngine")
            return
        }

        do {
            // Fetch all events with syncStatus = pending
            let pendingStatus = SyncStatus.pending.rawValue
            let pendingEventsDescriptor = FetchDescriptor<Event>(
                predicate: #Predicate { $0.syncStatusRaw == pendingStatus }
            )
            let pendingEvents = try modelContext.fetch(pendingEventsDescriptor)

            guard !pendingEvents.isEmpty else {
                Log.sync.debug("queueMutationsForUnsyncedEvents: no pending events found")
                return
            }

            // Fetch all existing PendingMutation entries for events (create operations)
            let eventEntityType = MutationEntityType.event.rawValue
            let createOperation = MutationOperation.create.rawValue
            let mutationDescriptor = FetchDescriptor<PendingMutation>(
                predicate: #Predicate {
                    $0.entityTypeRaw == eventEntityType && $0.operationRaw == createOperation
                }
            )
            let existingMutations = try modelContext.fetch(mutationDescriptor)
            let mutatedEventIds = Set(existingMutations.map { $0.entityId })

            // Find pending events that don't have a mutation queued
            let eventsNeedingMutation = pendingEvents.filter { !mutatedEventIds.contains($0.id) }

            if eventsNeedingMutation.isEmpty {
                Log.sync.debug("queueMutationsForUnsyncedEvents: all pending events have mutations")
                return
            }

            Log.sync.info("Found pending events needing mutation queue", context: .with { ctx in
                ctx.add("count", eventsNeedingMutation.count)
            })

            // Queue mutations for each unsynced event
            for event in eventsNeedingMutation {
                // Try to get eventTypeId from multiple sources (handles HealthKit events with broken relationships)
                var eventTypeId: String?

                if let existingEventType = event.eventType {
                    eventTypeId = existingEventType.id
                } else if let storedEventTypeId = event.eventTypeId {
                    // Backup field for when SwiftData relationship is broken
                    eventTypeId = storedEventTypeId
                } else if let categoryRaw = event.healthKitCategory,
                          let category = HealthDataCategory(rawValue: categoryRaw) {
                    // Look up EventType by HealthKit category default name
                    let defaultName = category.defaultEventTypeName
                    let eventTypeDescriptor = FetchDescriptor<EventType>(
                        predicate: #Predicate { et in et.name == defaultName }
                    )
                    if let foundEventType = try? modelContext.fetch(eventTypeDescriptor).first {
                        eventTypeId = foundEventType.id
                        // Restore the relationship and backup field for future use
                        event.eventType = foundEventType
                        event.eventTypeId = foundEventType.id
                    }
                }

                guard let finalEventTypeId = eventTypeId else {
                    Log.sync.warning("queueMutationsForUnsyncedEvents: event has no eventType", context: .with { ctx in
                        ctx.add("event_id", event.id)
                        ctx.add("healthKitCategory", event.healthKitCategory ?? "nil")
                    })
                    continue
                }

                let request = CreateEventRequest(
                    id: event.id,
                    eventTypeId: finalEventTypeId,
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
                    healthKitSampleId: event.healthKitSampleId,
                    healthKitCategory: event.healthKitCategory,
                    properties: convertLocalPropertiesToAPI(event.properties)
                )

                do {
                    let payload = try JSONEncoder().encode(request)
                    try await syncEngine.queueMutation(
                        entityType: .event,
                        operation: .create,
                        entityId: event.id,
                        payload: payload
                    )
                    Log.sync.info("Queued mutation for pending event", context: .with { ctx in
                        ctx.add("event_id", event.id)
                        ctx.add("event_type_id", finalEventTypeId)
                        ctx.add("source", event.sourceType.rawValue)
                    })
                } catch {
                    Log.sync.error("Failed to queue mutation for widget event", error: error, context: .with { ctx in
                        ctx.add("event_id", event.id)
                    })
                }
            }

            // Trigger sync if online
            if isOnline {
                await syncEngine.performSync()
            }

            await refreshSyncStateForUI()

        } catch {
            Log.sync.error("queueMutationsForUnsyncedEvents failed", error: error)
        }
    }

    // MARK: - Setup

    func setModelContext(_ context: ModelContext, syncHistoryStore: SyncHistoryStore? = nil) {
        self.modelContext = context
        self.modelContainer = context.container
        self.syncHistoryStore = syncHistoryStore

        // Initialize SyncEngine if we have an API client
        if let apiClient = apiClient {
            let dataStoreFactory = DefaultDataStoreFactory(modelContainer: context.container)
            self.syncEngine = SyncEngine(
                networkClient: apiClient,
                dataStoreFactory: dataStoreFactory,
                syncHistoryStore: syncHistoryStore
            )
        }

        // Load initial state (pending count, pending delete IDs) and refresh cached sync state
        if let syncEngine = syncEngine {
            Task {
                // Load initial state from SwiftData/UserDefaults BEFORE refreshSyncStateForUI
                // This ensures pendingCount reflects actual PendingMutation count on app launch
                await syncEngine.loadInitialState()

                // Queue mutations for any pending events (e.g., HealthKit bulk imports that were
                // stored locally but never synced). This runs on every app launch to catch any
                // orphaned events and ensures they eventually sync to the backend.
                await queueMutationsForUnsyncedEvents()

                await refreshSyncStateForUI()
            }
        }
    }

    func setCalendarManager(_ manager: CalendarManager) {
        self.calendarManager = manager
    }

    // MARK: - Sync

    /// Reset the SyncEngine's cached DataStore after returning from background.
    ///
    /// When iOS suspends the app for extended periods (1+ hours), it may invalidate
    /// file descriptors for the SQLite database. The SyncEngine caches a ModelContext
    /// which holds these file handles. Without resetting, the first sync after returning
    /// from background fails with "The file 'default.store' couldn't be opened".
    ///
    /// Call this when the scene phase transitions to `.active` BEFORE triggering any sync.
    func resetSyncEngineDataStore() async {
        await syncEngine?.resetDataStore()
    }

    /// Trigger a sync with the backend
    func performSync() async {
        guard let syncEngine = syncEngine else { return }

        // Skip sync entirely if offline - avoids waiting for network timeouts
        guard isOnline else {
            Log.sync.debug("Skipping sync - device is offline")
            await refreshSyncStateForUI()
            return
        }

        // Queue mutations for any widget-created events that may have been missed
        await queueMutationsForUnsyncedEvents()

        // Start a background task to poll sync state and update UI in real-time
        // This ensures LoadingView shows progress during sync, not just "Loading..."
        let pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshSyncStateForUI()
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms polling interval
            }
        }

        await syncEngine.performSync()

        // Stop polling now that sync is complete
        pollingTask.cancel()

        // Refresh local data after sync
        try? await fetchFromLocal()
        await refreshSyncStateForUI()
    }

    /// Force a full resync by resetting the cursor and re-fetching all data from the backend.
    /// This will remove any stale local data that doesn't exist on the backend.
    func forceFullResync() async {
        guard let syncEngine = syncEngine else {
            Log.sync.warning("forceFullResync: no syncEngine available")
            return
        }
        isLoading = true
        Log.sync.info("Starting force full resync")

        // Start a background task to poll sync state and update UI in real-time
        let pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshSyncStateForUI()
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms polling interval
            }
        }

        await syncEngine.forceFullResync()

        // Stop polling now that sync is complete
        pollingTask.cancel()

        try? await fetchFromLocal()
        isLoading = false
        Log.sync.info("Force full resync completed")
        await refreshSyncStateForUI()
    }

    /// Restore broken Event→EventType relationships.
    /// Use this when events show "Unknown" instead of their proper event type name.
    func restoreEventRelationships() async {
        guard let syncEngine = syncEngine else {
            Log.sync.warning("restoreEventRelationships: no syncEngine available")
            return
        }
        Log.sync.info("Starting event relationship restoration")
        await syncEngine.restoreEventRelationships()
        try? await fetchFromLocal()
        Log.sync.info("Event relationship restoration completed")
    }

    /// Clear all pending mutations from the sync queue.
    /// Use this to recover from a retry storm where mutations are continuously failing.
    /// WARNING: This will abandon any unsynced local changes - they will NOT be synced to the backend.
    /// - Returns: The number of mutations cleared
    @discardableResult
    func clearPendingMutations() async -> Int {
        guard let syncEngine = syncEngine else {
            Log.sync.warning("clearPendingMutations: no syncEngine available")
            return 0
        }
        Log.sync.warning("User requested clearing pending mutations")
        let count = await syncEngine.clearPendingMutations(markEntitiesFailed: true)
        try? await fetchFromLocal()
        return count
    }

    /// Check if the sync engine's circuit breaker is currently tripped
    var isCircuitBreakerTripped: Bool {
        get async {
            await syncEngine?.isCircuitBreakerTripped ?? false
        }
    }

    /// Get remaining circuit breaker backoff time in seconds
    var circuitBreakerBackoffRemaining: TimeInterval {
        get async {
            await syncEngine?.circuitBreakerBackoffRemaining ?? 0
        }
    }

    /// Reset the circuit breaker and retry sync immediately.
    /// Use this when the user explicitly wants to bypass the rate limit backoff.
    func resetCircuitBreakerAndSync() async {
        guard let syncEngine = syncEngine else {
            Log.sync.warning("resetCircuitBreakerAndSync: no syncEngine available")
            return
        }
        await syncEngine.resetCircuitBreaker()
        await performSync()
    }

    /// Refresh cached sync state from SyncEngine for UI binding
    func refreshSyncStateForUI() async {
        guard let syncEngine = syncEngine else { return }
        currentSyncState = await syncEngine.state
        currentPendingCount = await syncEngine.pendingCount
        currentLastSyncTime = await syncEngine.lastSyncTime
    }

    /// Restore broken Event→EventType relationships directly on fetched objects.
    /// This handles SwiftData relationship detachment that occurs when fetching
    /// from a fresh ModelContext, without needing the full SyncEngine machinery.
    private func restoreBrokenRelationshipsInPlace(events: [Event], eventTypes: [EventType]) {
        // Create lookup dictionary for fast EventType access
        let eventTypeById = Dictionary(uniqueKeysWithValues: eventTypes.map { ($0.id, $0) })

        var restoredCount = 0
        for event in events {
            // Skip if relationship is intact
            guard event.eventType == nil else { continue }

            // Try to restore from backup eventTypeId
            if let eventTypeId = event.eventTypeId,
               let eventType = eventTypeById[eventTypeId] {
                event.eventType = eventType
                restoredCount += 1
            }
        }

        if restoredCount > 0 {
            Log.sync.info("Restored broken Event→EventType relationships in-place", context: .with { ctx in
                ctx.add("restored_count", restoredCount)
            })
        }
    }

    // MARK: - Data Fetching

    /// Fetch data - performs sync if online, otherwise loads from local cache
    /// - Parameter force: If true, bypasses debouncing and forces a fresh fetch
    func fetchData(force: Bool = false) async {
        guard modelContext != nil else { return }

        // Debounce: skip if recently fetched (unless forced)
        if !force, let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < fetchDebounceInterval {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Sync with backend if we have a SyncEngine and are online
            // Use synchronous network check to avoid stale isOnline value when returning from background
            // This prevents 60-second Supabase SDK timeout when network state changed while app was backgrounded
            let actuallyOnline = checkNetworkPathSynchronously()
            if let syncEngine = syncEngine, actuallyOnline {
                // Start a background task to poll sync state and update UI in real-time
                // This ensures LoadingView shows progress during sync, not just "Loading..."
                let pollingTask = Task { @MainActor in
                    while !Task.isCancelled {
                        await refreshSyncStateForUI()
                        try? await Task.sleep(nanoseconds: 250_000_000) // 250ms polling interval
                    }
                }

                await syncEngine.performSync()

                // Stop polling now that sync is complete
                pollingTask.cancel()
            } else {
                Log.sync.debug("fetchData: skipping sync - syncEngine=\(syncEngine != nil), actuallyOnline=\(actuallyOnline)")
            }

            // Always load from local cache after sync
            try await fetchFromLocal()
            await refreshSyncStateForUI()

        } catch {
            Log.data.error("Fetch error", error: error)
            errorMessage = "Failed to sync. Showing cached data."
            // Still show cached data on error
            try? await fetchFromLocal()
            await refreshSyncStateForUI()
        }

        lastFetchTime = Date()
        isLoading = false
    }

    /// Loads data from local SwiftData cache only - does NOT trigger sync.
    /// Use this for instant UI display during app launch, then call performSync() separately.
    func fetchFromLocalOnly() async {
        guard modelContext != nil else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await fetchFromLocal()
            await refreshSyncStateForUI()
        } catch {
            Log.data.error("Local fetch error", error: error)
            errorMessage = "Failed to load cached data."
        }

        isLoading = false
    }

    private func fetchFromLocal() async throws {
        guard let modelContainer else { return }

        // Use mainContext instead of creating a fresh ModelContext to avoid SQLite file locking issues.
        // Creating multiple ModelContext(modelContainer) instances can cause "default.store couldn't be opened"
        // errors when concurrent contexts try to access the same SQLite file.
        // Since EventStore is @MainActor, using mainContext is the correct pattern.
        let context = modelContainer.mainContext

        let eventDescriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let typeDescriptor = FetchDescriptor<EventType>(
            sortBy: [SortDescriptor(\.name)]
        )

        events = try context.fetch(eventDescriptor)
        eventTypes = try context.fetch(typeDescriptor)

        // Restore broken Event→EventType relationships that can occur
        // when fetching from a fresh ModelContext (SwiftData relationship detachment)
        restoreBrokenRelationshipsInPlace(events: events, eventTypes: eventTypes)

        Log.sync.info("🔧 fetchFromLocal: loaded data", context: .with { ctx in
            ctx.add("events_count", events.count)
            ctx.add("event_types_count", eventTypes.count)
            // Log first few items
            for (index, et) in eventTypes.prefix(3).enumerated() {
                ctx.add("type_\(index)", "\(et.name) (id: \(et.id))")
            }
            // Log first few events
            for (index, ev) in events.prefix(5).enumerated() {
                ctx.add("event_\(index)", "\(ev.eventType?.name ?? "nil") @ \(ev.timestamp)")
            }
        })

        hasLoadedOnce = true
    }

    // MARK: - Event CRUD

    func recordEvent(type: EventType, timestamp: Date = Date(), isAllDay: Bool = false, endDate: Date? = nil, notes: String? = nil, properties: [String: PropertyValue] = [:]) async {
        guard let modelContext else { return }

        // Sync with system calendar if enabled (iOS-only feature)
        var calendarEventId: String?
        if syncWithCalendar, let calendarManager = calendarManager, calendarManager.isAuthorized {
            do {
                calendarEventId = try await calendarManager.addEventToCalendar(
                    title: type.name,
                    startDate: timestamp,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    notes: notes
                )
            } catch {
                Log.calendar.error("Failed to add event to calendar", error: error)
            }
        }

        // Create event locally with UUIDv7 - the ID is immediately known
        let newEvent = Event(
            timestamp: timestamp,
            eventType: type,
            notes: notes,
            sourceType: .manual,
            isAllDay: isAllDay,
            endDate: endDate,
            properties: properties,
            syncStatus: .pending
        )
        newEvent.calendarEventId = calendarEventId
        modelContext.insert(newEvent)

        // Step 1: Queue mutation BEFORE save to ensure atomicity
        // If app force quits after save but before queueMutation, the mutation would be lost.
        // By queueing first, PendingMutation is persisted even if subsequent save is interrupted.
        if let syncEngine = syncEngine {
            do {
                let request = CreateEventRequest(
                    id: newEvent.id,  // Send client-generated UUIDv7
                    eventTypeId: type.id,
                    timestamp: timestamp,
                    notes: notes,
                    isAllDay: isAllDay,
                    endDate: endDate,
                    sourceType: "manual",
                    externalId: nil,
                    originalTitle: nil,
                    geofenceId: nil,
                    locationLatitude: nil,
                    locationLongitude: nil,
                    locationName: nil,
                    healthKitSampleId: nil,
                    healthKitCategory: nil,
                    properties: convertLocalPropertiesToAPI(properties)
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .create,
                    entityId: newEvent.id,
                    payload: payload
                )

                Log.sync.info("Mutation queued for event", context: .with { ctx in
                    ctx.add("event_id", newEvent.id)
                })
            } catch {
                // Log error but don't block - we still want to save the event locally
                Log.sync.error("Failed to queue mutation for event", error: error, context: .with { ctx in
                    ctx.add("event_id", newEvent.id)
                })
            }
        }

        // Step 2: Save event locally (after mutation is queued)
        do {
            try modelContext.save()
            reloadWidgets()

            // Optimistic update: immediately add event to UI array
            // This ensures the event appears instantly, before any sync operations
            events.insert(newEvent, at: 0)

            Log.sync.info("Event saved locally", context: .with { ctx in
                ctx.add("event_id", newEvent.id)
                ctx.add("is_online", isOnline)
            })
        } catch {
            Log.data.error("Failed to save event locally", error: error)
            errorMessage = EventError.saveFailed.localizedDescription
            return  // Can't continue if save failed
        }

        // Step 3: Trigger sync if online
        if let syncEngine = syncEngine {
            // Always refresh sync state after queueing (shows pending count)
            await refreshSyncStateForUI()

            // Trigger sync if online, then refresh data
            if isOnline {
                await syncEngine.performSync()
                // Fetch fresh data after sync completes
                await fetchData()
            }
            // When offline, skip fetchData() - optimistic update already added the event
            // fetchData() would create a fresh context that might not see the just-saved event
        } else {
            // No sync engine (pre-auth) - still refresh sync state
            await refreshSyncStateForUI()
        }
    }

    func updateEvent(_ event: Event) async {
        guard let modelContext else { return }

        // Update system calendar if synced (external system, order doesn't matter for data safety)
        if syncWithCalendar,
           let calendarManager = calendarManager,
           calendarManager.isAuthorized,
           let calendarEventId = event.calendarEventId {
            do {
                try await calendarManager.updateCalendarEvent(
                    identifier: calendarEventId,
                    title: event.eventType?.name,
                    startDate: event.timestamp,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    notes: event.notes
                )
            } catch {
                Log.calendar.error("Failed to update calendar event", error: error)
            }
        }

        // Step 1: Queue mutation BEFORE save to ensure atomicity
        // If app force quits after save but before queueMutation, the mutation would be lost.
        // By queueing first, PendingMutation is persisted even if subsequent save is interrupted.
        if let syncEngine = syncEngine {
            do {
                let request = UpdateEventRequest(
                    eventTypeId: event.eventType?.id,
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
                    healthKitSampleId: event.healthKitSampleId,
                    healthKitCategory: event.healthKitCategory,
                    properties: convertLocalPropertiesToAPI(event.properties)
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .update,
                    entityId: event.id,
                    payload: payload
                )

                Log.sync.info("Update mutation queued", context: .with { ctx in
                    ctx.add("event_id", event.id)
                })
            } catch {
                // Log error but don't block - we still want to save the event locally
                Log.sync.error("Failed to queue update mutation", error: error, context: .with { ctx in
                    ctx.add("event_id", event.id)
                })
            }
        }

        // Step 2: Save update locally (after mutation is queued)
        do {
            try modelContext.save()
            reloadWidgets()

            Log.sync.info("Event updated locally", context: .with { ctx in
                ctx.add("event_id", event.id)
                ctx.add("is_online", isOnline)
            })
        } catch {
            Log.data.error("Failed to save event update locally", error: error)
            errorMessage = EventError.saveFailed.localizedDescription
            return  // Can't continue if save failed
        }

        // Step 3: Trigger sync if online
        if let syncEngine = syncEngine {
            // Always refresh sync state after queueing (shows pending count)
            await refreshSyncStateForUI()

            // Trigger sync if online, then refresh data
            if isOnline {
                await syncEngine.performSync()
                await fetchData()
            }
            // When offline, skip fetchData() - update is already visible in UI
        } else {
            await refreshSyncStateForUI()
        }
    }

    func deleteEvent(_ event: Event) async {
        guard let modelContext else { return }

        // Delete from system calendar if synced
        if syncWithCalendar,
           let calendarManager = calendarManager,
           calendarManager.isAuthorized,
           let calendarEventId = event.calendarEventId {
            do {
                try await calendarManager.deleteCalendarEvent(identifier: calendarEventId)
            } catch {
                Log.calendar.error("Failed to delete calendar event", error: error)
            }
        }

        let eventId = event.id

        // Step 1: Queue deletion mutation BEFORE deleting locally
        // This ordering is intentional for deletes: we need the entity to still exist when queueing
        // the mutation (to capture any needed data). The mutation is queued first to ensure it
        // persists even if a force quit occurs after queueMutation but before the entity is deleted.
        if let syncEngine = syncEngine {
            do {
                let payload = Data() // No payload needed for delete
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .delete,
                    entityId: eventId,
                    payload: payload
                )

                Log.sync.info("Delete mutation queued", context: .with { ctx in
                    ctx.add("event_id", eventId)
                })
            } catch {
                Log.sync.error("Failed to queue delete mutation", error: error, context: .with { ctx in
                    ctx.add("event_id", eventId)
                })
            }

            // Refresh sync state after queueing
            await refreshSyncStateForUI()
        }

        // Step 2: Delete locally and optimistically remove from UI
        modelContext.delete(event)
        events.removeAll { $0.id == eventId }

        do {
            try modelContext.save()
            reloadWidgets()

            Log.sync.info("Event deleted locally", context: .with { ctx in
                ctx.add("event_id", eventId)
                ctx.add("is_online", isOnline)
            })
        } catch {
            Log.data.error("Failed to delete event locally", error: error)
            errorMessage = EventError.deleteFailed.localizedDescription
            return
        }

        // Step 3: Trigger sync if online, then refresh data
        if let syncEngine = syncEngine, isOnline {
            await syncEngine.performSync()
            await fetchData()
        }
        // When offline, skip fetchData() - optimistic delete already removed the event
    }

    // MARK: - EventType CRUD

    func createEventType(name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        // Create with UUIDv7 - ID is immediately known
        let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        newType.syncStatus = .pending
        modelContext.insert(newType)

        // Step 1: Queue mutation BEFORE save to ensure atomicity
        // If app force quits after save but before queueMutation, the mutation would be lost.
        // By queueing first, PendingMutation is persisted even if subsequent save is interrupted.
        if let syncEngine = syncEngine {
            do {
                let request = CreateEventTypeRequest(
                    id: newType.id,  // Send client-generated UUIDv7
                    name: name,
                    color: colorHex,
                    icon: iconName
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .create,
                    entityId: newType.id,
                    payload: payload
                )
            } catch {
                // Log error but don't block - we still want to save the event type locally
                Log.sync.error("Failed to queue create mutation for event type", error: error, context: .with { ctx in
                    ctx.add("event_type_id", newType.id)
                })
            }
        }

        // Step 2: Save event type locally (after mutation is queued)
        do {
            try modelContext.save()
            reloadWidgets()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
            return
        }

        // Step 3: Trigger sync if online
        if let syncEngine = syncEngine, isOnline {
            await syncEngine.performSync()
        }

        await fetchData()
    }

    func updateEventType(_ eventType: EventType, name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        eventType.name = name
        eventType.colorHex = colorHex
        eventType.iconName = iconName

        // Step 1: Queue mutation BEFORE save to ensure atomicity
        // If app force quits after save but before queueMutation, the mutation would be lost.
        // By queueing first, PendingMutation is persisted even if subsequent save is interrupted.
        if let syncEngine = syncEngine {
            do {
                let request = UpdateEventTypeRequest(name: name, color: colorHex, icon: iconName)
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .update,
                    entityId: eventType.id,
                    payload: payload
                )
            } catch {
                // Log error but don't block - we still want to save the event type locally
                Log.sync.error("Failed to queue update mutation for event type", error: error, context: .with { ctx in
                    ctx.add("event_type_id", eventType.id)
                })
            }
        }

        // Step 2: Save event type locally (after mutation is queued)
        do {
            try modelContext.save()
            reloadWidgets()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
            return
        }

        // Step 3: Trigger sync if online
        if let syncEngine = syncEngine, isOnline {
            await syncEngine.performSync()
        }

        await fetchData()
    }

    func deleteEventType(_ eventType: EventType) async {
        guard let modelContext else { return }

        // Step 1: Queue deletion mutation BEFORE deleting locally
        // This ordering is intentional for deletes: we need the entity to still exist when queueing
        // the mutation (to capture any needed data). The mutation is queued first to ensure it
        // persists even if a force quit occurs after queueMutation but before the entity is deleted.
        if let syncEngine = syncEngine {
            do {
                let payload = Data()
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .delete,
                    entityId: eventType.id,
                    payload: payload
                )
            } catch {
                Log.sync.error("Failed to queue delete mutation", error: error)
            }
        }

        modelContext.delete(eventType)

        do {
            try modelContext.save()
            reloadWidgets()

            // Trigger sync if online
            if let syncEngine = syncEngine, isOnline {
                await syncEngine.performSync()
            }

            await fetchData()
        } catch {
            errorMessage = EventError.deleteFailed.localizedDescription
        }
    }

    // MARK: - Query Helpers

    func events(for eventType: EventType) -> [Event] {
        events.filter { $0.eventType?.id == eventType.id }
    }

    /// Returns events on a specific date using O(1) dictionary lookup.
    /// Results are sorted with all-day events first, then by timestamp.
    func events(on date: Date) -> [Event] {
        let dayStart = cachedCalendar.startOfDay(for: date)

        // O(1) lookup from cache
        guard let cachedEvents = eventsByDateCache[dayStart] else {
            return []
        }

        // Sort: all-day events first, then by timestamp
        return cachedEvents.sorted { first, second in
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }
            return first.timestamp < second.timestamp
        }
    }

    /// Rebuilds the eventsByDateCache dictionary from the events array.
    /// This is called automatically when the events array changes.
    /// Handles multi-day all-day events by adding them to each day in the range.
    private func rebuildEventsByDateCache() {
        var newCache: [Date: [Event]] = [:]

        for event in events {
            if event.isAllDay, let endDate = event.endDate {
                // Multi-day all-day event: add to each day in the range
                let startDay = cachedCalendar.startOfDay(for: event.timestamp)
                let endDay = cachedCalendar.startOfDay(for: endDate)

                var currentDay = startDay
                while currentDay <= endDay {
                    newCache[currentDay, default: []].append(event)
                    guard let nextDay = cachedCalendar.date(byAdding: .day, value: 1, to: currentDay) else {
                        break
                    }
                    currentDay = nextDay
                }
            } else {
                // Single-day event: add to its day only
                let dayStart = cachedCalendar.startOfDay(for: event.timestamp)
                newCache[dayStart, default: []].append(event)
            }
        }

        eventsByDateCache = newCache
    }

    // MARK: - Geofence CRUD

    @discardableResult
    func createGeofence(_ geofence: Geofence) async -> Bool {
        guard let modelContext else {
            Log.geofence.error("createGeofence failed: modelContext is nil")
            return false
        }

        geofence.syncStatus = .pending
        modelContext.insert(geofence)

        // Step 1: Queue mutation BEFORE save to ensure atomicity
        // If app force quits after save but before queueMutation, the mutation would be lost.
        // By queueing first, PendingMutation is persisted even if subsequent save is interrupted.
        if let syncEngine = syncEngine {
            do {
                let request = CreateGeofenceRequest(
                    id: geofence.id,  // Send client-generated UUIDv7
                    name: geofence.name,
                    latitude: geofence.latitude,
                    longitude: geofence.longitude,
                    radius: geofence.radius,
                    eventTypeEntryId: geofence.eventTypeEntryID,
                    eventTypeExitId: geofence.eventTypeExitID,
                    isActive: geofence.isActive,
                    notifyOnEntry: geofence.notifyOnEntry,
                    notifyOnExit: geofence.notifyOnExit
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .geofence,
                    operation: .create,
                    entityId: geofence.id,
                    payload: payload
                )
            } catch {
                // Log error but don't block - we still want to save the geofence locally
                Log.sync.error("Failed to queue create mutation for geofence", error: error, context: .with { ctx in
                    ctx.add("geofence_id", geofence.id)
                })
            }
        }

        // Step 2: Save geofence locally (after mutation is queued)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
            return false
        }

        // Step 3: Trigger sync if online
        if let syncEngine = syncEngine, isOnline {
            await syncEngine.performSync()
        }

        return true
    }

    func updateGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        // Step 1: Queue mutation BEFORE save to ensure atomicity
        // If app force quits after save but before queueMutation, the mutation would be lost.
        // By queueing first, PendingMutation is persisted even if subsequent save is interrupted.
        if let syncEngine = syncEngine {
            do {
                let request = UpdateGeofenceRequest(
                    name: geofence.name,
                    latitude: geofence.latitude,
                    longitude: geofence.longitude,
                    radius: geofence.radius,
                    eventTypeEntryId: geofence.eventTypeEntryID,
                    eventTypeExitId: geofence.eventTypeExitID,
                    isActive: geofence.isActive,
                    notifyOnEntry: geofence.notifyOnEntry,
                    notifyOnExit: geofence.notifyOnExit,
                    iosRegionIdentifier: geofence.regionIdentifier
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .geofence,
                    operation: .update,
                    entityId: geofence.id,
                    payload: payload
                )
            } catch {
                // Log error but don't block - we still want to save the geofence locally
                Log.sync.error("Failed to queue update mutation for geofence", error: error, context: .with { ctx in
                    ctx.add("geofence_id", geofence.id)
                })
            }
        }

        // Step 2: Save geofence locally (after mutation is queued)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
            return
        }

        // Step 3: Trigger sync if online
        if let syncEngine = syncEngine, isOnline {
            await syncEngine.performSync()
        }
    }

    func deleteGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        // Step 1: Queue deletion mutation BEFORE deleting locally
        // This ordering is intentional for deletes: we need the entity to still exist when queueing
        // the mutation (to capture any needed data). The mutation is queued first to ensure it
        // persists even if a force quit occurs after queueMutation but before the entity is deleted.
        if let syncEngine = syncEngine {
            do {
                let payload = Data()
                try await syncEngine.queueMutation(
                    entityType: .geofence,
                    operation: .delete,
                    entityId: geofence.id,
                    payload: payload
                )
            } catch {
                Log.sync.error("Failed to queue delete mutation", error: error)
            }
        }

        modelContext.delete(geofence)

        do {
            try modelContext.save()

            // Trigger sync if online
            if let syncEngine = syncEngine, isOnline {
                await syncEngine.performSync()
            }
        } catch {
            errorMessage = "Failed to delete geofence: \(error.localizedDescription)"
        }
    }

    // MARK: - Geofence Reconciliation

    /// Look up local Geofence ID from a region identifier (which is the UUIDv7 id)
    func lookupLocalGeofenceId(from identifier: String) -> String? {
        guard let modelContext else {
            return identifier
        }

        // With UUIDv7, the region identifier IS the canonical ID
        let targetId = identifier
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.id == targetId }
        )
        if let geofence = try? modelContext.fetch(descriptor).first {
            return geofence.id
        }

        return nil
    }

    /// Reconciles local geofences with backend state.
    /// Returns definitions for CLLocationManager to monitor.
    func reconcileGeofencesWithBackend(forceRefresh: Bool = false) async -> [GeofenceDefinition] {
        guard modelContext != nil else { return [] }

        // If offline, return local definitions
        guard let syncEngine = syncEngine, isOnline else {
            return getLocalGeofenceDefinitions()
        }

        // Sync first to ensure we have latest data
        if forceRefresh {
            await syncEngine.performSync()
        }

        return getLocalGeofenceDefinitions()
    }

    /// Skip to latest cursor (for recovery from change_log backlog)
    func skipToLatestCursor() async throws -> Int64 {
        guard let syncEngine = syncEngine else {
            throw NSError(domain: "EventStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync engine not available"])
        }
        return try await syncEngine.skipToLatestCursor()
    }

    /// Get latest cursor from backend
    func getLatestCursor() async throws -> Int64 {
        guard let apiClient = apiClient else {
            throw NSError(domain: "EventStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "API client not available"])
        }
        return try await apiClient.getLatestCursor()
    }

    /// Sync geofences from the server without doing a full resync.
    /// This is useful when geofences exist on the server but weren't pulled during incremental sync.
    /// Returns the number of geofences synced.
    func syncGeofencesFromServer() async throws -> Int {
        guard let syncEngine = syncEngine else {
            Log.sync.warning("syncGeofencesFromServer: no syncEngine available")
            return 0
        }

        guard isOnline else {
            Log.sync.warning("syncGeofencesFromServer: offline, cannot sync")
            return 0
        }

        let count = try await syncEngine.syncGeofences()

        // Note: We don't call fetchFromLocal() here because:
        // 1. Geofence sync doesn't change events or eventTypes
        // 2. Calling it can cause UICollectionView inconsistency crashes
        //    if another UI update is in progress

        return count
    }

    /// Get current geofence definitions from local cache
    func getLocalGeofenceDefinitions() -> [GeofenceDefinition] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let geofences = try? modelContext.fetch(descriptor) else {
            return []
        }

        let limited = Array(geofences.prefix(20))

        // With UUIDv7, the id IS the canonical identifier - no mapping needed
        return limited.map { geofence in
            GeofenceDefinition(from: geofence)
        }
    }

    // MARK: - Sync Helpers for External Services

    /// Sync an existing event to the backend (used by GeofenceManager, HealthKitService)
    func syncEventToBackend(_ event: Event) async {
        guard let modelContext else {
            Log.sync.error("syncEventToBackend: modelContext is nil - event will NOT sync!", context: .with { ctx in
                ctx.add("event_id", event.id)
                ctx.add("source_type", event.sourceType.rawValue)
            })
            return
        }
        guard let syncEngine = syncEngine else {
            Log.sync.warning("syncEventToBackend: no syncEngine available")
            return
        }

        // Capture the event ID immediately - event object may have stale properties across Task boundaries
        let eventId = event.id

        do {
            try modelContext.save()

            // Fetch the event fresh from the context to ensure we have persisted values
            // This fixes issues where SwiftData model properties may be stale when accessed across async boundaries
            let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == eventId })
            guard let freshEvent = try modelContext.fetch(descriptor).first else {
                Log.sync.error("syncEventToBackend: could not fetch event after save", context: .with { ctx in
                    ctx.add("event_id", eventId)
                })
                return
            }

            // With UUIDv7, we always have the ID we need
            guard let eventType = freshEvent.eventType else {
                Log.sync.warning("syncEventToBackend: event has no eventType", context: .with { ctx in
                    ctx.add("event_id", eventId)
                })
                return
            }

            // Determine if this is an update (event already synced) or create (new event)
            let isUpdate = freshEvent.syncStatus == .synced

            // Log the values being synced for debugging
            Log.sync.debug("syncEventToBackend: building request", context: .with { ctx in
                ctx.add("event_id", eventId)
                ctx.add("geofence_id", freshEvent.geofenceId ?? "nil")
                ctx.add("location_name", freshEvent.locationName ?? "nil")
                ctx.add("source_type", freshEvent.sourceType.rawValue)
                ctx.add("sync_status", freshEvent.syncStatus.rawValue)
                ctx.add("is_update", isUpdate)
                ctx.add("end_date", freshEvent.endDate?.description ?? "nil")
            })

            let payload: Data
            let operation: MutationOperation

            if isUpdate {
                // Event already exists on backend - send UPDATE
                let request = UpdateEventRequest(
                    eventTypeId: eventType.id,
                    timestamp: freshEvent.timestamp,
                    notes: freshEvent.notes,
                    isAllDay: freshEvent.isAllDay,
                    endDate: freshEvent.endDate,
                    sourceType: freshEvent.sourceType.rawValue,
                    externalId: freshEvent.externalId,
                    originalTitle: freshEvent.originalTitle,
                    geofenceId: freshEvent.geofenceId,
                    locationLatitude: freshEvent.locationLatitude,
                    locationLongitude: freshEvent.locationLongitude,
                    locationName: freshEvent.locationName,
                    healthKitSampleId: freshEvent.healthKitSampleId,
                    healthKitCategory: freshEvent.healthKitCategory,
                    properties: convertLocalPropertiesToAPI(freshEvent.properties)
                )
                payload = try JSONEncoder().encode(request)
                operation = .update
            } else {
                // Event not yet on backend - send CREATE
                let request = CreateEventRequest(
                    id: freshEvent.id,  // Client-generated UUIDv7
                    eventTypeId: eventType.id,
                    timestamp: freshEvent.timestamp,
                    notes: freshEvent.notes,
                    isAllDay: freshEvent.isAllDay,
                    endDate: freshEvent.endDate,
                    sourceType: freshEvent.sourceType.rawValue,
                    externalId: freshEvent.externalId,
                    originalTitle: freshEvent.originalTitle,
                    geofenceId: freshEvent.geofenceId,
                    locationLatitude: freshEvent.locationLatitude,
                    locationLongitude: freshEvent.locationLongitude,
                    locationName: freshEvent.locationName,
                    healthKitSampleId: freshEvent.healthKitSampleId,
                    healthKitCategory: freshEvent.healthKitCategory,
                    properties: convertLocalPropertiesToAPI(freshEvent.properties)
                )
                payload = try JSONEncoder().encode(request)
                operation = .create
            }

            try await syncEngine.queueMutation(
                entityType: .event,
                operation: operation,
                entityId: eventId,
                payload: payload
            )

            Log.sync.info("Queued event for sync", context: .with { ctx in
                ctx.add("event_id", eventId)
                ctx.add("source_type", freshEvent.sourceType.rawValue)
                ctx.add("operation", operation.rawValue)
            })

            // Trigger sync if online
            if isOnline {
                await syncEngine.performSync()
            }
        } catch {
            Log.sync.error("Failed to queue event for sync", error: error)
        }
    }

    /// Sync an existing HealthKit event update to the backend
    /// This sends an UPDATE mutation instead of CREATE, ensuring the backend receives the new values
    func syncHealthKitEventUpdate(_ event: Event) async {
        guard let modelContext else {
            Log.sync.error("syncHealthKitEventUpdate: modelContext is nil", context: .with { ctx in
                ctx.add("event_id", event.id)
            })
            return
        }
        guard let syncEngine = syncEngine else {
            Log.sync.warning("syncHealthKitEventUpdate: no syncEngine available")
            return
        }

        // Capture the event ID immediately
        let eventId = event.id

        do {
            try modelContext.save()

            // Fetch the event fresh from the context to ensure we have persisted values
            let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == eventId })
            guard let freshEvent = try modelContext.fetch(descriptor).first else {
                Log.sync.error("syncHealthKitEventUpdate: could not fetch event after save", context: .with { ctx in
                    ctx.add("event_id", eventId)
                })
                return
            }

            // Build UpdateEventRequest with only the fields we want to update
            let request = UpdateEventRequest(
                eventTypeId: freshEvent.eventType?.id,
                timestamp: freshEvent.timestamp,
                notes: freshEvent.notes,
                isAllDay: freshEvent.isAllDay,
                endDate: freshEvent.endDate,
                sourceType: freshEvent.sourceType.rawValue,
                externalId: freshEvent.externalId,
                originalTitle: freshEvent.originalTitle,
                geofenceId: freshEvent.geofenceId,
                locationLatitude: freshEvent.locationLatitude,
                locationLongitude: freshEvent.locationLongitude,
                locationName: freshEvent.locationName,
                healthKitSampleId: freshEvent.healthKitSampleId,
                healthKitCategory: freshEvent.healthKitCategory,
                properties: convertLocalPropertiesToAPI(freshEvent.properties)
            )
            let payload = try JSONEncoder().encode(request)
            try await syncEngine.queueMutation(
                entityType: .event,
                operation: .update,  // UPDATE, not CREATE
                entityId: eventId,
                payload: payload
            )

            Log.sync.info("Queued HealthKit event UPDATE for sync", context: .with { ctx in
                ctx.add("event_id", eventId)
                ctx.add("healthkit_sample_id", freshEvent.healthKitSampleId ?? "none")
                ctx.add("healthkit_category", freshEvent.healthKitCategory ?? "none")
            })

            // Trigger sync if online
            if isOnline {
                await syncEngine.performSync()
            }
        } catch {
            Log.sync.error("Failed to queue HealthKit event update for sync", error: error)
        }
    }

    /// Sync an auto-created EventType to the backend (used by HealthKitService)
    func syncEventTypeToBackend(_ eventType: EventType) async {
        guard let modelContext else {
            Log.sync.error("syncEventTypeToBackend: modelContext is nil - eventType will NOT sync!", context: .with { ctx in
                ctx.add("event_type_id", eventType.id)
                ctx.add("name", eventType.name)
            })
            return
        }
        guard let syncEngine = syncEngine else {
            Log.sync.warning("syncEventTypeToBackend: no syncEngine available")
            return
        }

        do {
            try modelContext.save()

            let request = CreateEventTypeRequest(
                id: eventType.id,  // Client-generated UUIDv7
                name: eventType.name,
                color: eventType.colorHex,
                icon: eventType.iconName
            )
            let payload = try JSONEncoder().encode(request)
            try await syncEngine.queueMutation(
                entityType: .eventType,
                operation: .create,
                entityId: eventType.id,
                payload: payload
            )

            Log.sync.info("Queued event type for sync", context: .with { ctx in
                ctx.add("event_type_id", eventType.id)
                ctx.add("name", eventType.name)
            })

            // Trigger sync if online
            if isOnline {
                await syncEngine.performSync()
            }
        } catch {
            Log.sync.error("Failed to queue event type for sync", error: error)
        }
    }

    /// Sync a geofence to the backend
    func syncGeofenceToBackend(_ geofence: Geofence) async {
        guard let modelContext else { return }
        guard let syncEngine = syncEngine else {
            Log.sync.warning("syncGeofenceToBackend: no syncEngine available")
            return
        }

        do {
            try modelContext.save()

            let request = CreateGeofenceRequest(
                id: geofence.id,  // Client-generated UUIDv7
                name: geofence.name,
                latitude: geofence.latitude,
                longitude: geofence.longitude,
                radius: geofence.radius,
                eventTypeEntryId: geofence.eventTypeEntryID,
                eventTypeExitId: geofence.eventTypeExitID,
                isActive: geofence.isActive,
                notifyOnEntry: geofence.notifyOnEntry,
                notifyOnExit: geofence.notifyOnExit
            )
            let payload = try JSONEncoder().encode(request)
            try await syncEngine.queueMutation(
                entityType: .geofence,
                operation: .create,
                entityId: geofence.id,
                payload: payload
            )

            Log.sync.info("Queued geofence for sync", context: .with { ctx in
                ctx.add("geofence_id", geofence.id)
                ctx.add("name", geofence.name)
            })

            // Trigger sync if online
            if isOnline {
                await syncEngine.performSync()
            }
        } catch {
            Log.sync.error("Failed to queue geofence for sync", error: error)
        }
    }

    /// Re-sync all local HealthKit events to the backend
    /// Use this to recover orphaned events that were created locally but never synced
    func resyncHealthKitEvents() async {
        guard let modelContext else {
            Log.sync.error("resyncHealthKitEvents: modelContext is nil")
            return
        }
        guard let syncEngine = syncEngine else {
            Log.sync.warning("resyncHealthKitEvents: no syncEngine available")
            return
        }

        Log.sync.info("Starting resync of HealthKit events")

        // Find all HealthKit events (use sourceTypeRaw for SwiftData predicate)
        let healthKitRawValue = EventSourceType.healthKit.rawValue
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.sourceTypeRaw == healthKitRawValue
            }
        )

        do {
            let healthKitEvents = try modelContext.fetch(descriptor)
            Log.sync.info("Found \(healthKitEvents.count) HealthKit events to resync")

            var syncedCount = 0
            var skippedCount = 0
            for event in healthKitEvents {
                // Try to get eventTypeId from multiple sources:
                // 1. The relationship (if it exists)
                // 2. The stored eventTypeId backup field
                // 3. Look up by HealthKit category name (for events created before eventTypeId was added)
                var eventTypeId: String?

                if let existingEventType = event.eventType {
                    eventTypeId = existingEventType.id
                } else if let storedEventTypeId = event.eventTypeId {
                    eventTypeId = storedEventTypeId
                } else if let categoryRaw = event.healthKitCategory,
                          let category = HealthDataCategory(rawValue: categoryRaw) {
                    // Look up EventType by the default name for this category
                    let defaultName = category.defaultEventTypeName
                    let eventTypeDescriptor = FetchDescriptor<EventType>(
                        predicate: #Predicate { et in et.name == defaultName }
                    )
                    if let foundEventType = try? modelContext.fetch(eventTypeDescriptor).first {
                        eventTypeId = foundEventType.id
                        // Also restore the relationship and backup field for future use
                        event.eventType = foundEventType
                        event.eventTypeId = foundEventType.id
                    }
                }

                guard let finalEventTypeId = eventTypeId else {
                    Log.sync.warning("resyncHealthKitEvents: skipping event - no eventTypeId", context: .with { ctx in
                        ctx.add("event_id", event.id)
                        ctx.add("category", event.healthKitCategory ?? "nil")
                    })
                    skippedCount += 1
                    continue
                }

                // Queue the event for sync (idempotent - backend handles duplicates)
                let request = CreateEventRequest(
                    id: event.id,
                    eventTypeId: finalEventTypeId,
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
                    healthKitSampleId: event.healthKitSampleId,
                    healthKitCategory: event.healthKitCategory,
                    properties: convertLocalPropertiesToAPI(event.properties)
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .create,
                    entityId: event.id,
                    payload: payload
                )
                syncedCount += 1
            }

            // Save any relationship restorations
            try modelContext.save()

            Log.sync.info("Queued HealthKit events for sync", context: .with { ctx in
                ctx.add("synced_count", syncedCount)
                ctx.add("skipped_count", skippedCount)
            })

            // Trigger sync if online
            if isOnline {
                await syncEngine.performSync()
            }
        } catch {
            Log.sync.error("Failed to resync HealthKit events", error: error)
        }
    }

    // MARK: - Property Conversion Helpers

    private func convertLocalPropertiesToAPI(_ properties: [String: PropertyValue]) -> [String: APIPropertyValue] {
        return properties.mapValues { propValue in
            APIPropertyValue(
                type: propValue.type.rawValue,
                value: propValue.value
            )
        }
    }

    // MARK: - Debug Methods

    /// Test method to directly fetch geofences from the API (for debugging)
    func testFetchGeofences() async throws -> [APIGeofence] {
        guard let apiClient else {
            throw NSError(domain: "EventStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "API client not available"])
        }
        return try await apiClient.getGeofences()
    }

    // MARK: - Deduplication

    /// Result of a deduplication operation
    struct DeduplicationResult {
        let duplicatesFound: Int
        let duplicatesRemoved: Int
        let groupsProcessed: Int
        let details: [String]
    }

    /// Find and remove duplicate events based on healthKitSampleId.
    /// For each group of duplicates:
    /// - Keep the one that's synced to the server (if any)
    /// - Otherwise keep the oldest one (by id, which is UUIDv7 time-ordered)
    /// - Delete the rest locally (and queue delete mutations if they're synced)
    ///
    /// - Returns: DeduplicationResult with stats about what was removed
    func deduplicateHealthKitEvents() async -> DeduplicationResult {
        guard let modelContainer else {
            Log.sync.error("deduplicateHealthKitEvents: modelContainer is nil")
            return DeduplicationResult(duplicatesFound: 0, duplicatesRemoved: 0, groupsProcessed: 0, details: ["Error: modelContainer is nil"])
        }

        // Use mainContext to avoid SQLite file locking issues with concurrent ModelContext instances
        let context = modelContainer.mainContext
        var details: [String] = []
        var totalDuplicatesFound = 0
        var totalDuplicatesRemoved = 0
        var groupsProcessed = 0

        do {
            // Fetch all events with a healthKitSampleId
            let descriptor = FetchDescriptor<Event>(
                predicate: #Predicate { $0.healthKitSampleId != nil }
            )
            let allHealthKitEvents = try context.fetch(descriptor)

            Log.sync.info("Deduplication: scanning HealthKit events", context: .with { ctx in
                ctx.add("total_healthkit_events", allHealthKitEvents.count)
            })

            // Group by healthKitSampleId
            let groupedBySampleId = Dictionary(grouping: allHealthKitEvents) { $0.healthKitSampleId! }

            // Find groups with duplicates
            let duplicateGroups = groupedBySampleId.filter { $0.value.count > 1 }

            if duplicateGroups.isEmpty {
                Log.sync.info("Deduplication: no duplicates found")
                return DeduplicationResult(
                    duplicatesFound: 0,
                    duplicatesRemoved: 0,
                    groupsProcessed: 0,
                    details: ["No duplicate HealthKit events found"]
                )
            }

            Log.sync.info("Deduplication: found duplicate groups", context: .with { ctx in
                ctx.add("duplicate_groups", duplicateGroups.count)
            })

            for (sampleId, events) in duplicateGroups {
                groupsProcessed += 1
                let duplicateCount = events.count - 1
                totalDuplicatesFound += duplicateCount

                // Determine which one to keep:
                // 1. Prefer synced events (they exist on the server)
                // 2. If multiple synced or none synced, keep the oldest (smallest UUIDv7)
                let syncedStatus = SyncStatus.synced.rawValue
                let sortedEvents = events.sorted { $0.id < $1.id }  // UUIDv7 is time-ordered

                let eventToKeep: Event
                if let syncedEvent = sortedEvents.first(where: { $0.syncStatusRaw == syncedStatus }) {
                    eventToKeep = syncedEvent
                } else {
                    eventToKeep = sortedEvents.first!  // Oldest by UUIDv7
                }

                let eventsToDelete = sortedEvents.filter { $0.id != eventToKeep.id }

                let shortSampleId = String(sampleId.prefix(8))
                let typeName = eventToKeep.eventType?.name ?? eventToKeep.healthKitCategory ?? "Unknown"
                details.append("• \(typeName) (\(shortSampleId)...): kept 1, removing \(eventsToDelete.count)")

                // Delete duplicates
                for event in eventsToDelete {
                    // If the event was synced, queue a delete mutation
                    if event.syncStatus == .synced, let syncEngine = syncEngine {
                        do {
                            try await syncEngine.queueMutation(
                                entityType: .event,
                                operation: .delete,
                                entityId: event.id,
                                payload: Data()
                            )
                            Log.sync.debug("Queued delete mutation for duplicate", context: .with { ctx in
                                ctx.add("event_id", event.id)
                                ctx.add("healthkit_sample_id", sampleId)
                            })
                        } catch {
                            Log.sync.error("Failed to queue delete mutation for duplicate", error: error)
                        }
                    }

                    context.delete(event)
                    totalDuplicatesRemoved += 1
                }
            }

            // Save all deletions
            try context.save()

            Log.sync.info("Deduplication complete", context: .with { ctx in
                ctx.add("groups_processed", groupsProcessed)
                ctx.add("duplicates_found", totalDuplicatesFound)
                ctx.add("duplicates_removed", totalDuplicatesRemoved)
            })

            // Trigger sync if online to push delete mutations
            if isOnline, let syncEngine = syncEngine {
                await syncEngine.performSync()
            }

            // Refresh local data
            try? await fetchFromLocal()

        } catch {
            Log.sync.error("Deduplication failed", error: error)
            details.append("Error: \(error.localizedDescription)")
        }

        return DeduplicationResult(
            duplicatesFound: totalDuplicatesFound,
            duplicatesRemoved: totalDuplicatesRemoved,
            groupsProcessed: groupsProcessed,
            details: details
        )
    }

    /// Analyze duplicate events without removing them.
    /// Returns information about duplicate groups found.
    func analyzeDuplicates() async -> DeduplicationResult {
        guard let modelContainer else {
            return DeduplicationResult(duplicatesFound: 0, duplicatesRemoved: 0, groupsProcessed: 0, details: ["Error: modelContainer is nil"])
        }

        // Use mainContext to avoid SQLite file locking issues with concurrent ModelContext instances
        let context = modelContainer.mainContext
        var details: [String] = []
        var totalDuplicates = 0

        do {
            // Fetch all events with a healthKitSampleId
            let descriptor = FetchDescriptor<Event>(
                predicate: #Predicate { $0.healthKitSampleId != nil }
            )
            let allHealthKitEvents = try context.fetch(descriptor)

            // Group by healthKitSampleId
            let groupedBySampleId = Dictionary(grouping: allHealthKitEvents) { $0.healthKitSampleId! }

            // Find groups with duplicates
            let duplicateGroups = groupedBySampleId.filter { $0.value.count > 1 }

            if duplicateGroups.isEmpty {
                return DeduplicationResult(
                    duplicatesFound: 0,
                    duplicatesRemoved: 0,
                    groupsProcessed: 0,
                    details: ["No duplicate HealthKit events found"]
                )
            }

            for (sampleId, events) in duplicateGroups.prefix(10) {  // Limit details to first 10 groups
                let duplicateCount = events.count - 1
                totalDuplicates += duplicateCount

                let shortSampleId = String(sampleId.prefix(8))
                let typeName = events.first?.eventType?.name ?? events.first?.healthKitCategory ?? "Unknown"
                let syncedCount = events.filter { $0.syncStatus == .synced }.count
                let dateStr = events.first?.timestamp.formatted(date: .abbreviated, time: .shortened) ?? "?"
                details.append("• \(typeName) @ \(dateStr): \(events.count) copies (\(syncedCount) synced)")
            }

            // Add remaining count if more than 10 groups
            let remainingGroups = duplicateGroups.count - 10
            if remainingGroups > 0 {
                let remainingDuplicates = duplicateGroups.dropFirst(10).reduce(0) { $0 + $1.value.count - 1 }
                totalDuplicates += remainingDuplicates
                details.append("... and \(remainingGroups) more groups with \(remainingDuplicates) duplicates")
            }

            return DeduplicationResult(
                duplicatesFound: totalDuplicates,
                duplicatesRemoved: 0,
                groupsProcessed: duplicateGroups.count,
                details: details
            )

        } catch {
            return DeduplicationResult(
                duplicatesFound: 0,
                duplicatesRemoved: 0,
                groupsProcessed: 0,
                details: ["Error analyzing: \(error.localizedDescription)"]
            )
        }
    }
}
