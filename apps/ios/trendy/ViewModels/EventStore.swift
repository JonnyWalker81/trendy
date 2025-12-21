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

        Log.sync.info("fetchFromLocal: loaded data", context: .with { ctx in
            ctx.add("events_count", events.count)
            ctx.add("event_types_count", eventTypes.count)
            // Log first few items
            for (index, et) in eventTypes.prefix(3).enumerated() {
                ctx.add("type_\(index)", "\(et.name) (serverId: \(et.serverId ?? "nil"))")
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

        // Create event locally with pending status
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
        newEvent.eventTypeServerId = type.serverId
        modelContext.insert(newEvent)

        do {
            try modelContext.save()
            reloadWidgets()

            // Queue mutation for sync if we have a sync engine
            if let syncEngine = syncEngine, let eventTypeServerId = type.serverId {
                let request = CreateEventRequest(
                    eventTypeId: eventTypeServerId,
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
                    properties: convertLocalPropertiesToAPI(properties)
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .create,
                    localEntityId: newEvent.id,
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

            // Queue mutation for sync if we have a sync engine and server ID
            if let syncEngine = syncEngine, let serverId = event.serverId {
                let request = UpdateEventRequest(
                    eventTypeId: event.eventType?.serverId,
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
                    properties: convertLocalPropertiesToAPI(event.properties)
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .update,
                    localEntityId: event.id,
                    serverEntityId: serverId,
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
        if let syncEngine = syncEngine, let serverId = event.serverId {
            do {
                let payload = Data() // No payload needed for delete
                try await syncEngine.queueMutation(
                    entityType: .event,
                    operation: .delete,
                    localEntityId: event.id,
                    serverEntityId: serverId,
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

        let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        newType.syncStatus = .pending
        modelContext.insert(newType)

        do {
            try modelContext.save()
            reloadWidgets()

            // Queue mutation for sync
            if let syncEngine = syncEngine {
                let request = CreateEventTypeRequest(name: name, color: colorHex, icon: iconName)
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .create,
                    localEntityId: newType.id,
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

            // Queue mutation for sync if we have server ID
            if let syncEngine = syncEngine, let serverId = eventType.serverId {
                let request = UpdateEventTypeRequest(name: name, color: colorHex, icon: iconName)
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .update,
                    localEntityId: eventType.id,
                    serverEntityId: serverId,
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
        if let syncEngine = syncEngine, let serverId = eventType.serverId {
            do {
                let payload = Data()
                try await syncEngine.queueMutation(
                    entityType: .eventType,
                    operation: .delete,
                    localEntityId: eventType.id,
                    serverEntityId: serverId,
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
                    name: geofence.name,
                    latitude: geofence.latitude,
                    longitude: geofence.longitude,
                    radius: geofence.radius,
                    eventTypeEntryId: nil, // TODO: lookup server IDs
                    eventTypeExitId: nil,
                    isActive: geofence.isActive,
                    notifyOnEntry: geofence.notifyOnEntry,
                    notifyOnExit: geofence.notifyOnExit
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .geofence,
                    operation: .create,
                    localEntityId: geofence.id,
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

            // Queue mutation for sync if we have server ID
            if let syncEngine = syncEngine, let serverId = geofence.serverId {
                let request = UpdateGeofenceRequest(
                    name: geofence.name,
                    latitude: geofence.latitude,
                    longitude: geofence.longitude,
                    radius: geofence.radius,
                    eventTypeEntryId: nil, // TODO: lookup server IDs
                    eventTypeExitId: nil,
                    isActive: geofence.isActive,
                    notifyOnEntry: geofence.notifyOnEntry,
                    notifyOnExit: geofence.notifyOnExit,
                    iosRegionIdentifier: geofence.regionIdentifier
                )
                let payload = try JSONEncoder().encode(request)
                try await syncEngine.queueMutation(
                    entityType: .geofence,
                    operation: .update,
                    localEntityId: geofence.id,
                    serverEntityId: serverId,
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
        if let syncEngine = syncEngine, let serverId = geofence.serverId {
            do {
                let payload = Data()
                try await syncEngine.queueMutation(
                    entityType: .geofence,
                    operation: .delete,
                    localEntityId: geofence.id,
                    serverEntityId: serverId,
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

    /// Look up local Geofence UUID from a region identifier (which is the serverId or local UUID)
    func lookupLocalGeofenceId(from identifier: String) -> UUID? {
        guard let modelContext else {
            return UUID(uuidString: identifier)
        }

        // First, try to find a geofence with matching serverId
        let targetServerId = identifier
        let serverIdDescriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.serverId == targetServerId }
        )
        if let geofence = try? modelContext.fetch(serverIdDescriptor).first {
            return geofence.id
        }

        // Fallback: try to parse as UUID (for offline-created geofences)
        if let uuid = UUID(uuidString: identifier) {
            let uuidDescriptor = FetchDescriptor<Geofence>(
                predicate: #Predicate { $0.id == uuid }
            )
            if let geofence = try? modelContext.fetch(uuidDescriptor).first {
                return geofence.id
            }
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

        // Use serverId field directly - no mapping needed
        return limited.map { geofence -> GeofenceDefinition in
            if let serverId = geofence.serverId {
                return GeofenceDefinition(from: geofence, backendId: serverId)
            } else {
                return GeofenceDefinition(fromLocal: geofence)
            }
        }
    }

    // MARK: - Sync Helpers for External Services

    /// Sync an existing event to the backend (used by GeofenceManager)
    func syncEventToBackend(_ event: Event) async {
        // Just save locally - SyncEngine will upload on next sync
        guard let modelContext else { return }
        try? modelContext.save()
    }

    /// Sync an auto-created EventType to the backend (used by HealthKitService)
    func syncEventTypeToBackend(_ eventType: EventType) async {
        // Just save locally - SyncEngine will upload on next sync
        guard let modelContext else { return }
        try? modelContext.save()
    }

    /// Sync a geofence to the backend
    func syncGeofenceToBackend(_ geofence: Geofence) async {
        // Just save locally - SyncEngine will upload on next sync
        guard let modelContext else { return }
        try? modelContext.save()
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
