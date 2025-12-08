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
    private var calendarManager: CalendarManager?
    var syncWithCalendar = true

    // Backend integration
    private let apiClient: APIClient?
    private var syncEngine: SyncEngine?

    // MARK: - Sync State (delegated from SyncEngine)

    var syncState: SyncEngine.SyncState {
        syncEngine?.state ?? .idle
    }

    var syncProgress: SyncProgress {
        syncEngine?.progress ?? SyncProgress()
    }

    var isOnline: Bool {
        syncEngine?.isOnline ?? false
    }

    // MARK: - Initialization

    /// Initialize EventStore with APIClient
    /// - Parameter apiClient: API client for backend communication
    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    #if DEBUG
    /// Initialize EventStore for local-only mode (screenshot testing)
    /// No network calls, uses SwiftData directly
    init() {
        self.apiClient = nil
    }
    #endif

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

        // Initialize SyncEngine if we have an API client
        if let apiClient = apiClient {
            self.syncEngine = SyncEngine(apiClient: apiClient, modelContext: context)
        }
    }

    func setCalendarManager(_ manager: CalendarManager) {
        self.calendarManager = manager
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
            if let syncEngine = syncEngine, syncEngine.isOnline {
                try await syncEngine.performFullSync()
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
        guard let modelContext else { return }

        let eventDescriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let typeDescriptor = FetchDescriptor<EventType>(
            sortBy: [SortDescriptor(\.name)]
        )

        events = try modelContext.fetch(eventDescriptor)
        eventTypes = try modelContext.fetch(typeDescriptor)

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

        // Create event locally
        let newEvent = Event(
            timestamp: timestamp,
            eventType: type,
            notes: notes,
            sourceType: .manual,
            isAllDay: isAllDay,
            endDate: endDate,
            properties: properties
        )
        newEvent.calendarEventId = calendarEventId
        modelContext.insert(newEvent)

        do {
            try modelContext.save()
            reloadWidgets()

            // Refresh data (will sync to backend if online)
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

        // Delete locally
        modelContext.delete(event)

        do {
            try modelContext.save()
            reloadWidgets()
            await fetchData()
        } catch {
            errorMessage = EventError.deleteFailed.localizedDescription
        }
    }

    // MARK: - EventType CRUD

    func createEventType(name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        modelContext.insert(newType)

        do {
            try modelContext.save()
            reloadWidgets()
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
            await fetchData()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
        }
    }

    func deleteEventType(_ eventType: EventType) async {
        guard let modelContext else { return }

        modelContext.delete(eventType)

        do {
            try modelContext.save()
            reloadWidgets()
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

        modelContext.insert(geofence)

        do {
            try modelContext.save()
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
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
        }
    }

    func deleteGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        modelContext.delete(geofence)

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to delete geofence: \(error.localizedDescription)"
        }
    }

    // MARK: - Geofence Reconciliation

    /// Look up local Geofence UUID from a region identifier (which is the backendId or local UUID)
    func lookupLocalGeofenceId(from identifier: String) -> UUID? {
        guard let modelContext else {
            return UUID(uuidString: identifier)
        }

        // First, try to find a geofence with matching backendId
        let targetBackendId = identifier
        let backendIdDescriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.backendId == targetBackendId }
        )
        if let geofence = try? modelContext.fetch(backendIdDescriptor).first {
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
        guard let modelContext else { return [] }

        // If offline, return local definitions
        guard let syncEngine = syncEngine, syncEngine.isOnline else {
            return getLocalGeofenceDefinitions()
        }

        // Sync first to ensure we have latest data
        if forceRefresh {
            try? await syncEngine.performFullSync()
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

        // Use backendId field directly - no mapping needed
        return limited.map { geofence -> GeofenceDefinition in
            if let backendId = geofence.backendId {
                return GeofenceDefinition(from: geofence, backendId: backendId)
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
}
