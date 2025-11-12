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
    private let apiClient: APIClient

    // UserDefaults-backed properties (can't use @AppStorage with @Observable)
    @ObservationIgnored private var useBackend: Bool {
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
    private var eventTypeBackendIds: [UUID: String] = [:]
    private var eventBackendIds: [UUID: String] = [:]

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

    deinit {
        monitor.cancel()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.syncQueue = SyncQueue(modelContext: context, apiClient: apiClient)

        // Enable backend mode after migration
        if migrationCompleted {
            useBackend = true
        }

        Task {
            await fetchData()
        }
    }

    func setCalendarManager(_ manager: CalendarManager) {
        self.calendarManager = manager
    }
    
    func fetchData() async {
        guard let modelContext else { return }

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
            print("Fetch error: \(error.localizedDescription)")
            errorMessage = "Failed to sync. Showing cached data."
            try? await fetchFromLocal()
        }

        isLoading = false
    }

    private func fetchFromBackend() async throws {
        guard let modelContext else { return }

        // Fetch from API
        let apiEventTypes = try await apiClient.getEventTypes()
        let apiEvents = try await apiClient.getEvents()

        // Clear local cache and repopulate
        // (In production, you might want more sophisticated sync logic)
        let localEventDescriptor = FetchDescriptor<Event>()
        let localTypeDescriptor = FetchDescriptor<EventType>()

        let localEvents = try modelContext.fetch(localEventDescriptor)
        let localTypes = try modelContext.fetch(localTypeDescriptor)

        // Delete all local cached data
        for event in localEvents {
            modelContext.delete(event)
        }
        for type in localTypes {
            modelContext.delete(type)
        }

        // Insert backend data as local cache
        for apiType in apiEventTypes {
            let localType = EventType(
                name: apiType.name,
                colorHex: apiType.color,
                iconName: apiType.icon
            )
            modelContext.insert(localType)
            eventTypeBackendIds[localType.id] = apiType.id
        }

        // Fetch updated types to build relationship
        let updatedTypes = try modelContext.fetch(localTypeDescriptor)

        for apiEvent in apiEvents {
            // Find matching local event type by backend ID
            guard let localType = updatedTypes.first(where: {
                eventTypeBackendIds[$0.id] == apiEvent.eventTypeId
            }) else {
                continue
            }

            let localEvent = Event(
                timestamp: apiEvent.timestamp,
                eventType: localType,
                notes: apiEvent.notes,
                sourceType: apiEvent.sourceType == "manual" ? .manual : .imported,
                externalId: apiEvent.externalId,
                originalTitle: apiEvent.originalTitle,
                isAllDay: apiEvent.isAllDay,
                endDate: apiEvent.endDate
            )
            modelContext.insert(localEvent)
            eventBackendIds[localEvent.id] = apiEvent.id
        }

        try modelContext.save()

        // Update in-memory arrays
        try await fetchFromLocal()
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
    
    func recordEvent(type: EventType, timestamp: Date = Date(), isAllDay: Bool = false, endDate: Date? = nil, notes: String? = nil) async {
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
                print("Failed to add event to calendar: \(error)")
                // Continue even if calendar sync fails
            }
        }

        if useBackend {
            // Backend mode: create on backend, cache locally
            do {
                guard let backendTypeId = eventTypeBackendIds[type.id] else {
                    throw EventError.saveFailed
                }

                let request = CreateEventRequest(
                    eventTypeId: backendTypeId,
                    timestamp: timestamp,
                    notes: notes,
                    isAllDay: isAllDay,
                    endDate: endDate,
                    sourceType: "manual",
                    externalId: nil,
                    originalTitle: nil
                )

                if isOnline {
                    // Online: create on backend
                    let apiEvent = try await apiClient.createEvent(request)

                    // Cache locally
                    let newEvent = Event(
                        timestamp: timestamp,
                        eventType: type,
                        notes: notes,
                        sourceType: .manual,
                        isAllDay: isAllDay,
                        endDate: endDate
                    )
                    newEvent.calendarEventId = calendarEventId
                    modelContext.insert(newEvent)
                    eventBackendIds[newEvent.id] = apiEvent.id

                    try modelContext.save()
                } else {
                    // Offline: create locally and queue for sync
                    let newEvent = Event(
                        timestamp: timestamp,
                        eventType: type,
                        notes: notes,
                        sourceType: .manual,
                        isAllDay: isAllDay,
                        endDate: endDate
                    )
                    newEvent.calendarEventId = calendarEventId
                    modelContext.insert(newEvent)
                    try modelContext.save()

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
                endDate: endDate
            )
            newEvent.calendarEventId = calendarEventId
            modelContext.insert(newEvent)

            do {
                try modelContext.save()
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
                print("Failed to update calendar event: \(error)")
                // Continue even if calendar sync fails
            }
        }
        
        do {
            try modelContext.save()
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
                print("Failed to delete calendar event: \(error)")
                // Continue even if calendar sync fails
            }
        }

        if useBackend {
            // Backend mode: delete from backend
            if let backendId = eventBackendIds[event.id] {
                do {
                    if isOnline {
                        try await apiClient.deleteEvent(id: backendId)
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
                    let apiEventType = try await apiClient.createEventType(request)

                    // Cache locally
                    let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
                    modelContext.insert(newType)
                    eventTypeBackendIds[newType.id] = apiEventType.id

                    try modelContext.save()
                } else {
                    // Offline: create locally and queue for sync
                    let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
                    modelContext.insert(newType)
                    try modelContext.save()

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
                await fetchData()
            } catch {
                errorMessage = EventError.saveFailed.localizedDescription
            }
        }
    }
    
    func updateEventType(_ eventType: EventType, name: String, colorHex: String, iconName: String) async {
        eventType.name = name
        eventType.colorHex = colorHex
        eventType.iconName = iconName
        
        do {
            try modelContext?.save()
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
                        try await apiClient.deleteEventType(id: backendId)
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
}