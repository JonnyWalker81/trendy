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
    private(set) var events: [Event] = []
    private(set) var eventTypes: [EventType] = []
    var isLoading = false
    var errorMessage: String?

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
            Task { @MainActor in
                let wasOffline = !(self?.isOnline ?? false)
                self?.isOnline = (path.status == .satisfied)

                // Auto-sync when coming back online
                if wasOffline && (self?.isOnline ?? false) {
                    await self?.handleNetworkRestored()
                }
            }
        }
        let queue = DispatchQueue(label: "com.trendy.eventstore-network-monitor")
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func handleNetworkRestored() async {
        Log.sync.info("Network restored - starting sync")
        await performSync()
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

            Log.sync.info("Found widget-created events needing mutation queue", context: .with { ctx in
                ctx.add("count", eventsNeedingMutation.count)
            })

            // Queue mutations for each unsynced event
            for event in eventsNeedingMutation {
                guard let eventType = event.eventType else {
                    Log.sync.warning("queueMutationsForUnsyncedEvents: event has no eventType", context: .with { ctx in
                        ctx.add("event_id", event.id)
                    })
                    continue
                }

                let request = CreateEventRequest(
                    id: event.id,
                    eventTypeId: eventType.id,
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
                    Log.sync.info("Queued mutation for widget-created event", context: .with { ctx in
                        ctx.add("event_id", event.id)
                        ctx.add("event_type", eventType.name)
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

        } catch {
            Log.sync.error("queueMutationsForUnsyncedEvents failed", error: error)
        }
    }

    // MARK: - Setup

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.modelContainer = context.container

        // Initialize SyncEngine if we have an API client
        if let apiClient = apiClient {
            self.syncEngine = SyncEngine(apiClient: apiClient, modelContainer: context.container)
        }
    }

    func setCalendarManager(_ manager: CalendarManager) {
        self.calendarManager = manager
    }

    // MARK: - Sync

    /// Trigger a sync with the backend
    func performSync() async {
        guard let syncEngine = syncEngine else { return }
        // Queue mutations for any widget-created events that may have been missed
        await queueMutationsForUnsyncedEvents()
        await syncEngine.performSync()
        // Refresh local data after sync
        try? await fetchFromLocal()
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
        await syncEngine.forceFullResync()
        try? await fetchFromLocal()
        isLoading = false
        Log.sync.info("Force full resync completed")
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
            Log.sync.info("fetchData: checking sync conditions", context: .with { ctx in
                ctx.add("has_sync_engine", syncEngine != nil)
                ctx.add("is_online", isOnline)
            })
            if let syncEngine = syncEngine, isOnline {
                Log.sync.info("fetchData: calling performSync")
                await syncEngine.performSync()
            } else {
                Log.sync.warning("fetchData: skipping sync - syncEngine=\(syncEngine != nil), isOnline=\(isOnline)")
            }

            // Always load from local cache after sync
            try await fetchFromLocal()

        } catch {
            Log.data.error("Fetch error", error: error)
            errorMessage = "Failed to sync. Showing cached data."
            // Still show cached data on error
            try? await fetchFromLocal()
        }

        lastFetchTime = Date()
        isLoading = false
    }

    private func fetchFromLocal() async throws {
        guard let modelContainer else { return }

        // Create a fresh context to ensure we see the latest persisted data
        // This is necessary because SyncEngine uses its own context for sync operations
        let freshContext = ModelContext(modelContainer)

        let eventDescriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let typeDescriptor = FetchDescriptor<EventType>(
            sortBy: [SortDescriptor(\.name)]
        )

        events = try freshContext.fetch(eventDescriptor)
        eventTypes = try freshContext.fetch(typeDescriptor)

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

        do {
            try modelContext.save()
            reloadWidgets()

            // Queue mutation for sync if we have a sync engine
            // With UUIDv7, we can sync immediately - the ID is already known
            if let syncEngine = syncEngine {
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

                // Trigger sync if online
                if isOnline {
                    await syncEngine.performSync()
                }
            }

            await fetchData()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
        }
    }

    func updateEvent(_ event: Event) async {
        guard let modelContext else { return }

        // Update system calendar if synced
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

        do {
            try modelContext.save()
            reloadWidgets()

            // Queue mutation for sync - with UUIDv7, the ID is always the server ID
            if let syncEngine = syncEngine {
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

                // Trigger sync if online
                if isOnline {
                    await syncEngine.performSync()
                }
            }

            await fetchData()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
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

        // Queue deletion mutation before deleting locally
        // With UUIDv7, we always have the ID we need
        if let syncEngine = syncEngine {
            do {
                let payload = Data() // No payload needed for delete
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .delete,
                    entityId: event.id,
                    payload: payload
                )
            } catch {
                Log.sync.error("Failed to queue delete mutation", error: error)
            }
        }

        // Delete locally
        modelContext.delete(event)

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

    // MARK: - EventType CRUD

    func createEventType(name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        // Create with UUIDv7 - ID is immediately known
        let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        newType.syncStatus = .pending
        modelContext.insert(newType)

        do {
            try modelContext.save()
            reloadWidgets()

            // Queue mutation for sync
            if let syncEngine = syncEngine {
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

                // Trigger sync if online
                if isOnline {
                    await syncEngine.performSync()
                }
            }

            await fetchData()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
        }
    }

    func updateEventType(_ eventType: EventType, name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        eventType.name = name
        eventType.colorHex = colorHex
        eventType.iconName = iconName

        do {
            try modelContext.save()
            reloadWidgets()

            // Queue mutation for sync - ID is always the canonical ID
            if let syncEngine = syncEngine {
                let request = UpdateEventTypeRequest(name: name, color: colorHex, icon: iconName)
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .update,
                    entityId: eventType.id,
                    payload: payload
                )

                // Trigger sync if online
                if isOnline {
                    await syncEngine.performSync()
                }
            }

            await fetchData()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
        }
    }

    func deleteEventType(_ eventType: EventType) async {
        guard let modelContext else { return }

        // Queue deletion mutation before deleting locally
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

    func events(on date: Date) -> [Event] {
        let calendar = Calendar.current
        return events.filter { event in
            if event.isAllDay {
                if let endDate = event.endDate {
                    return date >= calendar.startOfDay(for: event.timestamp) &&
                           date <= calendar.startOfDay(for: endDate)
                } else {
                    return calendar.isDate(event.timestamp, inSameDayAs: date)
                }
            } else {
                return calendar.isDate(event.timestamp, inSameDayAs: date)
            }
        }.sorted { first, second in
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }
            return first.timestamp < second.timestamp
        }
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

        do {
            try modelContext.save()

            // Queue mutation for sync
            if let syncEngine = syncEngine {
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

                // Trigger sync if online
                if isOnline {
                    await syncEngine.performSync()
                }
            }

            return true
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
            return false
        }
    }

    func updateGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        do {
            try modelContext.save()

            // Queue mutation for sync
            if let syncEngine = syncEngine {
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

                // Trigger sync if online
                if isOnline {
                    await syncEngine.performSync()
                }
            }
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
        }
    }

    func deleteGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        // Queue deletion mutation before deleting locally
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

            // Log the values being synced for debugging
            Log.sync.debug("syncEventToBackend: building request", context: .with { ctx in
                ctx.add("event_id", eventId)
                ctx.add("geofence_id", freshEvent.geofenceId ?? "nil")
                ctx.add("location_name", freshEvent.locationName ?? "nil")
                ctx.add("source_type", freshEvent.sourceType.rawValue)
            })

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
            let payload = try JSONEncoder().encode(request)
            try await syncEngine.queueMutation(
                entityType: .event,
                operation: .create,
                entityId: event.id,
                payload: payload
            )

            Log.sync.info("Queued event for sync", context: .with { ctx in
                ctx.add("event_id", event.id)
                ctx.add("source_type", event.sourceType.rawValue)
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
}
