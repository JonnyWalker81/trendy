//
//  EventStore.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
class EventStore {
    private(set) var events: [Event] = []
    private(set) var eventTypes: [EventType] = []
    var isLoading = false
    var errorMessage: String?
    
    private var modelContext: ModelContext?
    private var calendarManager: CalendarManager?
    var syncWithCalendar = true
    
    init() { }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
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
            let eventDescriptor = FetchDescriptor<Event>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let typeDescriptor = FetchDescriptor<EventType>(
                sortBy: [SortDescriptor(\.name)]
            )
            
            events = try modelContext.fetch(eventDescriptor)
            eventTypes = try modelContext.fetch(typeDescriptor)
        } catch {
            errorMessage = EventError.fetchFailed.localizedDescription
        }
        
        isLoading = false
    }
    
    func recordEvent(type: EventType, timestamp: Date = Date(), isAllDay: Bool = false, endDate: Date? = nil, notes: String? = nil) async {
        guard let modelContext else { return }
        
        let newEvent = Event(
            timestamp: timestamp,
            eventType: type,
            notes: notes,
            isAllDay: isAllDay,
            endDate: endDate
        )
        
        // Sync with system calendar if enabled
        if syncWithCalendar, let calendarManager = calendarManager, calendarManager.isAuthorized {
            do {
                let calendarEventId = try await calendarManager.addEventToCalendar(
                    title: type.name,
                    startDate: timestamp,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    notes: notes
                )
                newEvent.calendarEventId = calendarEventId
            } catch {
                print("Failed to add event to calendar: \(error)")
                // Continue even if calendar sync fails
            }
        }
        
        modelContext.insert(newEvent)
        
        do {
            try modelContext.save()
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
        
        let newType = EventType(name: name, colorHex: colorHex, iconName: iconName)
        modelContext.insert(newType)
        
        do {
            try modelContext.save()
            await fetchData()
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
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