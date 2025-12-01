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

    private var modelContext: ModelContext?
    private var calendarManager: CalendarManager?
    private var syncQueue: SyncQueue?
    var syncWithCalendar = true

    // Backend integration (injected)
    private let apiClient: APIClient?

    // UserDefaults-backed properties (can't use @AppStorage with @Observable)
    @ObservationIgnored var useBackend: Bool {
        get { UserDefaults.standard.bool(forKey: "use_backend") }
        set { UserDefaults.standard.set(newValue, forKey: "use_backend") }
    }

    @ObservationIgnored private var migrationCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "migration_completed") }
        set { UserDefaults.standard.set(newValue, forKey: "migration_completed") }
    }

    // Network monitoring
    private let monitor = NWPathMonitor()
    @ObservationIgnored private var isOnline = false

    // Backend ID mapping (iOS UUID → Backend UUID string)
    // Persisted to UserDefaults to survive app restarts
    private var eventTypeBackendIds: [UUID: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "eventTypeBackendIds"),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            // Convert String keys back to UUID
            var result: [UUID: String] = [:]
            for (key, value) in dict {
                if let uuid = UUID(uuidString: key) {
                    result[uuid] = value
                }
            }
            return result
        }
        set {
            // Convert UUID keys to String for JSON encoding
            let stringDict = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            if let data = try? JSONEncoder().encode(stringDict) {
                UserDefaults.standard.set(data, forKey: "eventTypeBackendIds")
            }
        }
    }
    
    private var eventBackendIds: [UUID: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "eventBackendIds"),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            var result: [UUID: String] = [:]
            for (key, value) in dict {
                if let uuid = UUID(uuidString: key) {
                    result[uuid] = value
                }
            }
            return result
        }
        set {
            let stringDict = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            if let data = try? JSONEncoder().encode(stringDict) {
                UserDefaults.standard.set(data, forKey: "eventBackendIds")
            }
        }
    }

    private var geofenceBackendIds: [UUID: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "geofenceBackendIds"),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            var result: [UUID: String] = [:]
            for (key, value) in dict {
                if let uuid = UUID(uuidString: key) {
                    result[uuid] = value
                }
            }
            return result
        }
        set {
            let stringDict = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            if let data = try? JSONEncoder().encode(stringDict) {
                UserDefaults.standard.set(data, forKey: "geofenceBackendIds")
            }
        }
    }

    /// Initialize EventStore with APIClient
    /// - Parameter apiClient: API client for backend communication
    init(apiClient: APIClient) {
        self.apiClient = apiClient

        // Monitor network status
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        let queue = DispatchQueue(label: "com.trendy.network-monitor")
        monitor.start(queue: queue)
    }

    #if DEBUG
    /// Initialize EventStore for local-only mode (screenshot testing)
    /// No network calls, uses SwiftData directly
    init() {
        self.apiClient = nil
        self.useBackend = false
        // Don't start network monitor in local-only mode
    }
    #endif

    deinit {
        monitor.cancel()
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
                // Fetch data to sync any widget-created events to backend
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

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        // Only set up sync queue if we have an API client
        if let apiClient = apiClient {
            self.syncQueue = SyncQueue(modelContext: context, apiClient: apiClient)
        }

        // Enable backend mode after migration
        if migrationCompleted {
            useBackend = true
        }
        // Note: fetchData() is called by MainTabView, not here
    }

    func setCalendarManager(_ manager: CalendarManager) {
        self.calendarManager = manager
    }
    
    func fetchData() async {
        guard modelContext != nil else { return }

        isLoading = true
        errorMessage = nil

        do {
            if useBackend && isOnline {
                // Fetch from backend and cache locally
                try await fetchFromBackend()
            } else {
                // Fetch from local cache
                try await fetchFromLocal()
            }
        } catch {
            // On error, fall back to local cache
            #if DEBUG
            print("Fetch error: \(error.localizedDescription)")
            #endif
            errorMessage = "Failed to sync. Showing cached data."
            try? await fetchFromLocal()
        }

        isLoading = false
    }

    private func fetchFromBackend() async throws {
        guard let modelContext else { return }
        guard let apiClient = apiClient else {
            // No API client, fall back to local
            try await fetchFromLocal()
            return
        }

        // Fetch from API
        let apiEventTypes = try await apiClient.getEventTypes()
        let apiEvents = try await apiClient.getAllEvents() // Uses pagination to fetch ALL events

        // CRITICAL: Clear in-memory arrays FIRST to prevent SwiftUI from
        // accessing invalidated objects while we process
        events = []
        eventTypes = []

        // Fetch existing local data
        let localTypeDescriptor = FetchDescriptor<EventType>()
        let localEventDescriptor = FetchDescriptor<Event>()
        
        var existingTypes = try modelContext.fetch(localTypeDescriptor)
        let existingEvents = try modelContext.fetch(localEventDescriptor)

        // Build reverse mapping: backend ID -> local EventType
        var backendIdToLocalType: [String: EventType] = [:]
        let currentMappings = eventTypeBackendIds // Get current persisted mappings
        for (localId, backendId) in currentMappings {
            if let localType = existingTypes.first(where: { $0.id == localId }) {
                backendIdToLocalType[backendId] = localType
            }
        }

        // UPSERT EventTypes - update existing or create new, but preserve local IDs
        var processedBackendTypeIds = Set<String>()
        var updatedMappings = currentMappings
        
        for apiType in apiEventTypes {
            processedBackendTypeIds.insert(apiType.id)
            
            if let existingType = backendIdToLocalType[apiType.id] {
                // UPDATE existing - preserve the local ID!
                existingType.name = apiType.name
                existingType.colorHex = apiType.color
                existingType.iconName = apiType.icon
                #if DEBUG
                print("📝 Updated existing EventType: \(apiType.name) (local ID: \(existingType.id))")
                #endif
            } else {
                // Check if there's already a local type with the same name (unmapped)
                if let existingByName = existingTypes.first(where: {
                    $0.name == apiType.name && !currentMappings.keys.contains($0.id)
                }) {
                    // Map existing local type to backend ID
                    existingByName.colorHex = apiType.color
                    existingByName.iconName = apiType.icon
                    updatedMappings[existingByName.id] = apiType.id
                    backendIdToLocalType[apiType.id] = existingByName
                    #if DEBUG
                    print("🔗 Linked existing EventType by name: \(apiType.name) (local ID: \(existingByName.id))")
                    #endif
                } else {
                    // CREATE new
                    let newType = EventType(
                        name: apiType.name,
                        colorHex: apiType.color,
                        iconName: apiType.icon
                    )
                    modelContext.insert(newType)
                    updatedMappings[newType.id] = apiType.id
                    backendIdToLocalType[apiType.id] = newType
                    #if DEBUG
                    print("➕ Created new EventType: \(apiType.name) (local ID: \(newType.id))")
                    #endif
                }
            }
        }
        
        // Save the updated mappings
        eventTypeBackendIds = updatedMappings

        // Delete EventTypes that no longer exist on backend (optional - be careful with this)
        // For now, we'll keep orphaned types to avoid breaking geofences
        // for type in existingTypes {
        //     if let backendId = eventTypeBackendIds[type.id], !processedBackendTypeIds.contains(backendId) {
        //         modelContext.delete(type)
        //     }
        // }

        try modelContext.save()
        
        // Refresh the types list
        existingTypes = try modelContext.fetch(localTypeDescriptor)

        // UPSERT Events - similar approach
        var backendIdToLocalEvent: [String: Event] = [:]
        let currentEventMappings = eventBackendIds
        for (localId, backendId) in currentEventMappings {
            if let localEvent = existingEvents.first(where: { $0.id == localId }) {
                backendIdToLocalEvent[backendId] = localEvent
            }
        }

        var processedBackendEventIds = Set<String>()
        var updatedEventMappings = currentEventMappings
        
        for apiEvent in apiEvents {
            processedBackendEventIds.insert(apiEvent.id)
            
            // Find matching local event type by backend ID
            guard let localType = backendIdToLocalType[apiEvent.eventTypeId] else {
                #if DEBUG
                print("⚠️ Skipping event - no matching EventType for backend ID: \(apiEvent.eventTypeId)")
                #endif
                continue
            }

            // Convert API properties to local PropertyValue format
            let localProperties = convertAPIPropertiesToLocal(apiEvent.properties)

            #if DEBUG
            if let apiProps = apiEvent.properties {
                print("📥 Event \(apiEvent.id) has \(apiProps.count) properties from API: \(apiProps.keys.joined(separator: ", "))")
            }
            print("📥 Converted to \(localProperties.count) local properties: \(localProperties.keys.joined(separator: ", "))")
            #endif

            if let existingEvent = backendIdToLocalEvent[apiEvent.id] {
                // UPDATE existing event
                existingEvent.timestamp = apiEvent.timestamp
                existingEvent.eventType = localType
                existingEvent.notes = apiEvent.notes
                existingEvent.isAllDay = apiEvent.isAllDay
                existingEvent.endDate = apiEvent.endDate
                existingEvent.properties = localProperties
            } else {
                // Check for duplicate by timestamp and event type (unmapped events)
                let isDuplicate = existingEvents.contains { event in
                    event.eventType?.id == localType.id &&
                    abs(event.timestamp.timeIntervalSince(apiEvent.timestamp)) < 1.0 &&
                    !currentEventMappings.keys.contains(event.id)
                }
                
                if let existingByMatch = existingEvents.first(where: { event in
                    event.eventType?.id == localType.id &&
                    abs(event.timestamp.timeIntervalSince(apiEvent.timestamp)) < 1.0 &&
                    !currentEventMappings.keys.contains(event.id)
                }) {
                    // Link existing event to backend and sync properties
                    updatedEventMappings[existingByMatch.id] = apiEvent.id
                    backendIdToLocalEvent[apiEvent.id] = existingByMatch
                    existingByMatch.properties = localProperties
                    #if DEBUG
                    print("🔗 Linked existing Event by match (local ID: \(existingByMatch.id))")
                    #endif
                } else {
                    // CREATE new event
                    let newEvent = Event(
                        timestamp: apiEvent.timestamp,
                        eventType: localType,
                        notes: apiEvent.notes,
                        sourceType: apiEvent.sourceType == "manual" ? .manual : .imported,
                        externalId: apiEvent.externalId,
                        originalTitle: apiEvent.originalTitle,
                        isAllDay: apiEvent.isAllDay,
                        endDate: apiEvent.endDate,
                        properties: localProperties
                    )
                    modelContext.insert(newEvent)
                    updatedEventMappings[newEvent.id] = apiEvent.id
                }
            }
        }
        
        // Save updated event mappings
        eventBackendIds = updatedEventMappings

        // Delete events that no longer exist on backend
        for event in existingEvents {
            if let backendId = eventBackendIds[event.id], !processedBackendEventIds.contains(backendId) {
                modelContext.delete(event)
                eventBackendIds.removeValue(forKey: event.id)
            }
        }

        // SYNC GEOFENCES
        // Build reverse mapping: backend EventType ID -> local EventType UUID
        var backendTypeIdToLocalId: [String: UUID] = [:]
        for (localId, backendId) in updatedMappings {
            backendTypeIdToLocalId[backendId] = localId
        }

        do {
            let apiGeofences = try await apiClient.getGeofences()

            // Fetch existing local geofences
            let localGeofenceDescriptor = FetchDescriptor<Geofence>()
            let existingGeofences = try modelContext.fetch(localGeofenceDescriptor)

            // Build reverse mapping: backend ID -> local Geofence
            var backendIdToLocalGeofence: [String: Geofence] = [:]
            let currentGeofenceMappings = geofenceBackendIds
            for (localId, backendId) in currentGeofenceMappings {
                if let localGeofence = existingGeofences.first(where: { $0.id == localId }) {
                    backendIdToLocalGeofence[backendId] = localGeofence
                }
            }

            var processedBackendGeofenceIds = Set<String>()
            var updatedGeofenceMappings = currentGeofenceMappings

            for apiGeofence in apiGeofences {
                processedBackendGeofenceIds.insert(apiGeofence.id)

                // Resolve backend EventType IDs to local UUIDs
                let localEntryTypeId: UUID? = apiGeofence.eventTypeEntryId.flatMap { backendTypeIdToLocalId[$0] }
                let localExitTypeId: UUID? = apiGeofence.eventTypeExitId.flatMap { backendTypeIdToLocalId[$0] }

                if let existingGeofence = backendIdToLocalGeofence[apiGeofence.id] {
                    // UPDATE existing geofence
                    existingGeofence.name = apiGeofence.name
                    existingGeofence.latitude = apiGeofence.latitude
                    existingGeofence.longitude = apiGeofence.longitude
                    existingGeofence.radius = apiGeofence.radius
                    existingGeofence.eventTypeEntryID = localEntryTypeId
                    existingGeofence.eventTypeExitID = localExitTypeId
                    existingGeofence.isActive = apiGeofence.isActive
                    existingGeofence.notifyOnEntry = apiGeofence.notifyOnEntry
                    existingGeofence.notifyOnExit = apiGeofence.notifyOnExit
                    #if DEBUG
                    print("📝 Updated existing Geofence: \(apiGeofence.name) (local ID: \(existingGeofence.id))")
                    #endif
                } else {
                    // Check if there's already a local geofence with same name and location (unmapped)
                    let targetName = apiGeofence.name
                    let targetLat = apiGeofence.latitude
                    let targetLon = apiGeofence.longitude
                    let mappedIds = Set(currentGeofenceMappings.keys)

                    let existingByMatch = existingGeofences.first { geofence in
                        let nameMatches = geofence.name == targetName
                        let latMatches = abs(geofence.latitude - targetLat) < 0.0001
                        let lonMatches = abs(geofence.longitude - targetLon) < 0.0001
                        let notMapped = !mappedIds.contains(geofence.id)
                        return nameMatches && latMatches && lonMatches && notMapped
                    }

                    if let existingByMatch = existingByMatch {
                        // Link existing local geofence to backend
                        existingByMatch.radius = apiGeofence.radius
                        existingByMatch.eventTypeEntryID = localEntryTypeId
                        existingByMatch.eventTypeExitID = localExitTypeId
                        existingByMatch.isActive = apiGeofence.isActive
                        existingByMatch.notifyOnEntry = apiGeofence.notifyOnEntry
                        existingByMatch.notifyOnExit = apiGeofence.notifyOnExit
                        updatedGeofenceMappings[existingByMatch.id] = apiGeofence.id
                        backendIdToLocalGeofence[apiGeofence.id] = existingByMatch
                        #if DEBUG
                        print("🔗 Linked existing Geofence by match: \(apiGeofence.name) (local ID: \(existingByMatch.id))")
                        #endif
                    } else {
                        // CREATE new geofence
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
                        modelContext.insert(newGeofence)
                        updatedGeofenceMappings[newGeofence.id] = apiGeofence.id
                        #if DEBUG
                        print("➕ Created new Geofence: \(apiGeofence.name) (local ID: \(newGeofence.id))")
                        #endif
                    }
                }
            }

            // Save updated geofence mappings
            geofenceBackendIds = updatedGeofenceMappings

            // Delete geofences that no longer exist on backend
            for geofence in existingGeofences {
                if let backendId = geofenceBackendIds[geofence.id], !processedBackendGeofenceIds.contains(backendId) {
                    modelContext.delete(geofence)
                    geofenceBackendIds.removeValue(forKey: geofence.id)
                    #if DEBUG
                    print("🗑️ Deleted Geofence no longer on backend: \(geofence.name)")
                    #endif
                }
            }

            #if DEBUG
            print("✅ Geofence sync complete - synced \(apiGeofences.count) geofences")
            #endif
        } catch {
            // Geofence sync is non-critical, log but continue
            #if DEBUG
            print("⚠️ Geofence sync failed: \(error.localizedDescription)")
            #endif
        }

        try modelContext.save()

        // Update in-memory arrays with fresh data
        try await fetchFromLocal()

        #if DEBUG
        print("✅ Backend sync complete - EventTypes: \(eventTypes.count), Events: \(events.count)")
        #endif
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
    }
    
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
                #if DEBUG
                print("Failed to add event to calendar: \(error)")
                #endif
                // Continue even if calendar sync fails
            }
        }

        if useBackend {
            // Backend mode: create on backend, cache locally
            do {
                guard let backendTypeId = eventTypeBackendIds[type.id] else {
                    throw EventError.saveFailed
                }

                // Convert properties to API format
                let apiProperties: [String: APIPropertyValue]? = properties.isEmpty ? nil : properties.mapValues { propValue in
                    APIPropertyValue(
                        type: propValue.type.rawValue,
                        value: propValue.value
                    )
                }

                #if DEBUG
                print("📝 Creating event with \(properties.count) properties: \(properties.keys.joined(separator: ", "))")
                #endif

                let request = CreateEventRequest(
                    eventTypeId: backendTypeId,
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
                    properties: apiProperties
                )

                if isOnline {
                    // Online: create on backend
                    let apiEvent = try await apiClient!.createEvent(request)

                    // Cache locally
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
                    eventBackendIds[newEvent.id] = apiEvent.id

                    try modelContext.save()
                    reloadWidgets()
                } else {
                    // Offline: create locally and queue for sync
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
                    try modelContext.save()
                    reloadWidgets()

                    // Queue for backend sync
                    try? syncQueue?.enqueue(type: .createEvent, entityId: newEvent.id, payload: request)
                }

                await fetchData()
            } catch {
                errorMessage = "Failed to create event: \(error.localizedDescription)"
            }
        } else {
            // Local-only mode (pre-migration)
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
                await fetchData()
            } catch {
                errorMessage = EventError.saveFailed.localizedDescription
            }
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
                #if DEBUG
                print("Failed to update calendar event: \(error)")
                #endif
                // Continue even if calendar sync fails
            }
        }

        if useBackend {
            // Backend mode: update on backend
            if let backendId = eventBackendIds[event.id],
               let eventType = event.eventType,
               let backendTypeId = eventTypeBackendIds[eventType.id] {

                // Convert properties to API format
                // IMPORTANT: Always send properties (even if empty) to support deletion
                // Sending nil means "don't update", sending {} means "clear all properties"
                Log.api.info("EventStore.updateEvent - event.properties count: \(event.properties.count)")
                for (key, propValue) in event.properties {
                    Log.api.info("  Property '\(key)': type=\(propValue.type.rawValue), value=\(String(describing: propValue.value.value))")
                }

                let apiProperties: [String: APIPropertyValue] = event.properties.mapValues { propValue in
                    APIPropertyValue(
                        type: propValue.type.rawValue,
                        value: propValue.value
                    )
                }

                Log.api.info("EventStore.updateEvent - apiProperties count: \(apiProperties.count)")

                let request = UpdateEventRequest(
                    eventTypeId: backendTypeId,
                    timestamp: event.timestamp,
                    notes: event.notes,
                    isAllDay: event.isAllDay,
                    endDate: event.endDate,
                    sourceType: event.sourceType.rawValue,
                    externalId: event.externalId,
                    originalTitle: event.originalTitle,
                    geofenceId: event.geofenceId?.uuidString,
                    locationLatitude: event.locationLatitude,
                    locationLongitude: event.locationLongitude,
                    locationName: event.locationName,
                    properties: apiProperties
                )

                do {
                    if isOnline {
                        _ = try await apiClient!.updateEvent(id: backendId, request)
                    } else {
                        // Queue for sync when online
                        try? syncQueue?.enqueue(type: .updateEvent, entityId: event.id, payload: request)
                    }
                } catch {
                    errorMessage = "Failed to update event: \(error.localizedDescription)"
                    return
                }
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
                #if DEBUG
                print("Failed to delete calendar event: \(error)")
                #endif
                // Continue even if calendar sync fails
            }
        }

        if useBackend {
            // Backend mode: delete from backend
            if let backendId = eventBackendIds[event.id] {
                do {
                    if isOnline {
                        try await apiClient!.deleteEvent(id: backendId)
                    } else {
                        // Queue for deletion when online
                        try? syncQueue?.enqueue(
                            type: .deleteEvent,
                            entityId: event.id,
                            payload: backendId.data(using: .utf8) ?? Data()
                        )
                    }
                } catch {
                    errorMessage = "Failed to delete event: \(error.localizedDescription)"
                    return
                }
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

    func createEventType(name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        if useBackend {
            // Backend mode: create on backend, cache locally
            do {
                let request = CreateEventTypeRequest(
                    name: name,
                    color: colorHex,
                    icon: iconName
                )

                if isOnline {
                    // Online: create on backend
                    let apiEventType = try await apiClient!.createEventType(request)

                    // Cache locally
                    let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
                    modelContext.insert(newType)
                    eventTypeBackendIds[newType.id] = apiEventType.id

                    try modelContext.save()
                    reloadWidgets()
                } else {
                    // Offline: create locally and queue for sync
                    let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
                    modelContext.insert(newType)
                    try modelContext.save()
                    reloadWidgets()

                    // Queue for backend sync
                    try? syncQueue?.enqueue(type: .createEventType, entityId: newType.id, payload: request)
                }

                await fetchData()
            } catch {
                errorMessage = "Failed to create event type: \(error.localizedDescription)"
            }
        } else {
            // Local-only mode (pre-migration)
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
    }

    func updateEventType(_ eventType: EventType, name: String, colorHex: String, iconName: String) async {
        guard let modelContext else { return }

        if useBackend {
            // Backend mode: update on backend
            if let backendId = eventTypeBackendIds[eventType.id] {
                let request = UpdateEventTypeRequest(
                    name: name,
                    color: colorHex,
                    icon: iconName
                )

                do {
                    if isOnline {
                        // Online: update on backend immediately
                        _ = try await apiClient!.updateEventType(id: backendId, request)
                    } else {
                        // Offline: queue for sync when online
                        let queuedUpdate = QueuedEventTypeUpdate(backendId: backendId, request: request)
                        try? syncQueue?.enqueue(type: .updateEventType, entityId: eventType.id, payload: queuedUpdate)
                    }
                } catch {
                    errorMessage = "Failed to update event type: \(error.localizedDescription)"
                    return
                }
            }
        }

        // Update locally
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

        if useBackend {
            // Backend mode: delete from backend
            if let backendId = eventTypeBackendIds[eventType.id] {
                do {
                    if isOnline {
                        try await apiClient!.deleteEventType(id: backendId)
                    } else {
                        // Queue for deletion when online
                        try? syncQueue?.enqueue(
                            type: .deleteEventType,
                            entityId: eventType.id,
                            payload: backendId.data(using: .utf8) ?? Data()
                        )
                    }
                } catch {
                    errorMessage = "Failed to delete event type: \(error.localizedDescription)"
                    return
                }
            }
        }

        // Delete locally
        modelContext.delete(eventType)

        do {
            try modelContext.save()
            reloadWidgets()
            await fetchData()
        } catch {
            errorMessage = EventError.deleteFailed.localizedDescription
        }
    }

    func events(for eventType: EventType) -> [Event] {
        events.filter { $0.eventType?.id == eventType.id }
    }
    
    func events(on date: Date) -> [Event] {
        let calendar = Calendar.current
        return events.filter { event in
            if event.isAllDay {
                // For all-day events, check if the date falls within the event duration
                if let endDate = event.endDate {
                    return date >= calendar.startOfDay(for: event.timestamp) &&
                           date <= calendar.startOfDay(for: endDate)
                } else {
                    // Single day all-day event
                    return calendar.isDate(event.timestamp, inSameDayAs: date)
                }
            } else {
                // Regular timed event
                return calendar.isDate(event.timestamp, inSameDayAs: date)
            }
        }.sorted { first, second in
            // Sort all-day events first, then by timestamp
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }
            return first.timestamp < second.timestamp
        }
    }

    // MARK: - Geofence Support

    /// Sync an existing event to the backend (used by GeofenceManager)
    /// - Parameter event: The event to sync
    func syncEventToBackend(_ event: Event) async {
        guard useBackend else { return }
        guard let eventType = event.eventType else { return }
        guard let backendTypeId = eventTypeBackendIds[eventType.id] else {
            #if DEBUG
            print("⚠️ No backend ID for event type: \(eventType.name)")
            #endif
            return
        }
        
        // Map source type for backend compatibility
        // Backend may not support all source types - map to "manual" as fallback
        let backendSourceType: String
        switch event.sourceType {
        case .manual:
            backendSourceType = "manual"
        case .imported:
            backendSourceType = "imported"
        case .geofence:
            // Backend doesn't support "geofence" yet - use "manual" as fallback
            backendSourceType = "manual"
        case .healthKit:
            // Backend doesn't support "healthkit" yet - use "manual" as fallback
            backendSourceType = "manual"
        }

        do {
            // Check if this event already exists on the backend
            let existingBackendId = eventBackendIds[event.id]

            // Convert properties to API format
            let apiProperties = convertLocalPropertiesToAPI(event.properties)

            if existingBackendId != nil {
                // Update existing backend event
                let request = UpdateEventRequest(
                    eventTypeId: backendTypeId,
                    timestamp: event.timestamp,
                    notes: event.notes,
                    isAllDay: event.isAllDay,
                    endDate: event.endDate,
                    sourceType: backendSourceType,
                    externalId: event.externalId,
                    originalTitle: event.originalTitle,
                    geofenceId: event.geofenceId?.uuidString,
                    locationLatitude: event.locationLatitude,
                    locationLongitude: event.locationLongitude,
                    locationName: event.locationName,
                    properties: apiProperties
                )

                if isOnline {
                    _ = try await apiClient!.updateEvent(id: existingBackendId!, request)
                    #if DEBUG
                    print("✅ Updated event on backend: \(event.id)")
                    #endif
                } else {
                    // Queue for sync when online
                    try? syncQueue?.enqueue(type: .updateEvent, entityId: event.id, payload: request)
                    #if DEBUG
                    print("📦 Queued event update for sync: \(event.id)")
                    #endif
                }

            } else {
                // Create new backend event
                let request = CreateEventRequest(
                    eventTypeId: backendTypeId,
                    timestamp: event.timestamp,
                    notes: event.notes,
                    isAllDay: event.isAllDay,
                    endDate: event.endDate,
                    sourceType: backendSourceType,
                    externalId: event.externalId,
                    originalTitle: event.originalTitle,
                    geofenceId: event.geofenceId?.uuidString,
                    locationLatitude: event.locationLatitude,
                    locationLongitude: event.locationLongitude,
                    locationName: event.locationName,
                    properties: apiProperties
                )

                if isOnline {
                    let apiEvent = try await apiClient!.createEvent(request)
                    eventBackendIds[event.id] = apiEvent.id
                    reloadWidgets()
                    #if DEBUG
                    print("✅ Created event on backend: \(event.id)")
                    #endif
                } else {
                    // Queue for sync when online
                    try? syncQueue?.enqueue(type: .createEvent, entityId: event.id, payload: request)
                    reloadWidgets()
                    #if DEBUG
                    print("📦 Queued event creation for sync: \(event.id)")
                    #endif
                }
            }

        } catch {
            #if DEBUG
            print("❌ Failed to sync event to backend: \(error.localizedDescription)")
            #endif
        }
    }

    /// Sync an auto-created EventType to the backend (used by HealthKitService)
    /// - Parameter eventType: The EventType to sync
    func syncEventTypeToBackend(_ eventType: EventType) async {
        guard useBackend else { return }

        // Check if already synced
        if eventTypeBackendIds[eventType.id] != nil {
            #if DEBUG
            print("ℹ️ EventType already synced: \(eventType.name)")
            #endif
            return
        }

        let request = CreateEventTypeRequest(
            name: eventType.name,
            color: eventType.colorHex,
            icon: eventType.iconName
        )

        do {
            if isOnline {
                let apiEventType = try await apiClient!.createEventType(request)
                eventTypeBackendIds[eventType.id] = apiEventType.id
                #if DEBUG
                print("✅ Synced EventType to backend: \(eventType.name)")
                #endif
            } else {
                // Queue for sync when online
                try? syncQueue?.enqueue(type: .createEventType, entityId: eventType.id, payload: request)
                #if DEBUG
                print("📦 Queued EventType for sync: \(eventType.name)")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Failed to sync EventType to backend: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Property Conversion Helpers

    /// Convert API properties to local PropertyValue format
    private func convertAPIPropertiesToLocal(_ apiProperties: [String: APIPropertyValue]?) -> [String: PropertyValue] {
        guard let apiProperties = apiProperties else { return [:] }

        var localProperties: [String: PropertyValue] = [:]
        for (key, apiValue) in apiProperties {
            guard let propType = PropertyType(rawValue: apiValue.type) else { continue }
            localProperties[key] = PropertyValue(type: propType, value: apiValue.value.value)
        }
        return localProperties
    }

    /// Convert local properties to API format
    private func convertLocalPropertiesToAPI(_ properties: [String: PropertyValue]) -> [String: APIPropertyValue]? {
        if properties.isEmpty { return nil }
        return properties.mapValues { propValue in
            APIPropertyValue(
                type: propValue.type.rawValue,
                value: propValue.value
            )
        }
    }

    // MARK: - Geofence CRUD with Backend Sync

    /// Create a geofence with backend sync
    /// - Parameters:
    ///   - geofence: The local geofence to create
    /// - Returns: True if creation was successful
    @discardableResult
    func createGeofence(_ geofence: Geofence) async -> Bool {
        guard let modelContext else { return false }

        // Insert locally first
        modelContext.insert(geofence)

        if useBackend {
            // Get backend EventType IDs for the geofence's event types
            let backendEntryTypeId: String? = geofence.eventTypeEntryID.flatMap { eventTypeBackendIds[$0] }
            let backendExitTypeId: String? = geofence.eventTypeExitID.flatMap { eventTypeBackendIds[$0] }

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
                if isOnline {
                    let apiGeofence = try await apiClient!.createGeofence(request)
                    geofenceBackendIds[geofence.id] = apiGeofence.id
                    #if DEBUG
                    print("✅ Created geofence on backend: \(geofence.name)")
                    #endif
                } else {
                    // Queue for sync when online
                    try? syncQueue?.enqueue(type: .createGeofence, entityId: geofence.id, payload: request)
                    #if DEBUG
                    print("📦 Queued geofence creation for sync: \(geofence.name)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("❌ Failed to create geofence on backend: \(error.localizedDescription)")
                #endif
                // Continue with local creation even if backend fails
            }
        }

        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
            return false
        }
    }

    /// Update a geofence with backend sync
    /// - Parameter geofence: The geofence with updated values
    func updateGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        if useBackend {
            if let backendId = geofenceBackendIds[geofence.id] {
                // Get backend EventType IDs
                let backendEntryTypeId: String? = geofence.eventTypeEntryID.flatMap { eventTypeBackendIds[$0] }
                let backendExitTypeId: String? = geofence.eventTypeExitID.flatMap { eventTypeBackendIds[$0] }

                let request = UpdateGeofenceRequest(
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
                    if isOnline {
                        _ = try await apiClient!.updateGeofence(id: backendId, request)
                        #if DEBUG
                        print("✅ Updated geofence on backend: \(geofence.name)")
                        #endif
                    } else {
                        // Queue for sync when online
                        let queuedUpdate = QueuedGeofenceUpdate(backendId: backendId, request: request)
                        try? syncQueue?.enqueue(type: .updateGeofence, entityId: geofence.id, payload: queuedUpdate)
                        #if DEBUG
                        print("📦 Queued geofence update for sync: \(geofence.name)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("❌ Failed to update geofence on backend: \(error.localizedDescription)")
                    #endif
                }
            }
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
        }
    }

    /// Delete a geofence with backend sync
    /// - Parameter geofence: The geofence to delete
    func deleteGeofence(_ geofence: Geofence) async {
        guard let modelContext else { return }

        if useBackend {
            if let backendId = geofenceBackendIds[geofence.id] {
                do {
                    if isOnline {
                        try await apiClient!.deleteGeofence(id: backendId)
                        #if DEBUG
                        print("✅ Deleted geofence from backend: \(geofence.name)")
                        #endif
                    } else {
                        // Queue for deletion when online
                        try? syncQueue?.enqueue(
                            type: .deleteGeofence,
                            entityId: geofence.id,
                            payload: backendId.data(using: .utf8) ?? Data()
                        )
                        #if DEBUG
                        print("📦 Queued geofence deletion for sync: \(geofence.name)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("❌ Failed to delete geofence from backend: \(error.localizedDescription)")
                    #endif
                    return
                }
            }
        }

        // Delete locally
        modelContext.delete(geofence)
        geofenceBackendIds.removeValue(forKey: geofence.id)

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to delete geofence: \(error.localizedDescription)"
        }
    }

    /// Sync an existing local geofence to the backend
    /// - Parameter geofence: The geofence to sync
    func syncGeofenceToBackend(_ geofence: Geofence) async {
        guard useBackend else { return }

        // Check if already synced
        if geofenceBackendIds[geofence.id] != nil {
            return
        }

        let backendEntryTypeId: String? = geofence.eventTypeEntryID.flatMap { eventTypeBackendIds[$0] }
        let backendExitTypeId: String? = geofence.eventTypeExitID.flatMap { eventTypeBackendIds[$0] }

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
            if isOnline {
                let apiGeofence = try await apiClient!.createGeofence(request)
                geofenceBackendIds[geofence.id] = apiGeofence.id
                #if DEBUG
                print("✅ Synced geofence to backend: \(geofence.name)")
                #endif
            } else {
                try? syncQueue?.enqueue(type: .createGeofence, entityId: geofence.id, payload: request)
                #if DEBUG
                print("📦 Queued geofence for sync: \(geofence.name)")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Failed to sync geofence to backend: \(error.localizedDescription)")
            #endif
        }
    }
}