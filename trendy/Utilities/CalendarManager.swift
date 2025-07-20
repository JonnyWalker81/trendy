//
//  CalendarManager.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import EventKit
import SwiftUI

@MainActor
class CalendarManager: ObservableObject {
    private let eventStore = EKEventStore()
    @Published var isAuthorized = false
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                self.isAuthorized = granted
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            }
            return granted
        } catch {
            print("Error requesting calendar access: \(error)")
            return false
        }
    }
    
    func addEventToCalendar(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        notes: String? = nil,
        calendarIdentifier: String? = nil
    ) async throws -> String {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.isAllDay = isAllDay
        
        if isAllDay {
            // For all-day events, set end date to the same day if not provided
            event.endDate = endDate ?? startDate
        } else {
            // For timed events, default to 1 hour duration if no end date
            event.endDate = endDate ?? startDate.addingTimeInterval(3600)
        }
        
        event.notes = notes
        
        // Use specified calendar or default
        if let calendarId = calendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: calendarId) {
            event.calendar = calendar
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
    }
    
    func updateCalendarEvent(
        identifier: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool? = nil,
        notes: String? = nil
    ) async throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw CalendarError.eventNotFound
        }
        
        if let title = title {
            event.title = title
        }
        if let startDate = startDate {
            event.startDate = startDate
        }
        if let endDate = endDate {
            event.endDate = endDate
        }
        if let isAllDay = isAllDay {
            event.isAllDay = isAllDay
        }
        if let notes = notes {
            event.notes = notes
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw CalendarError.updateFailed(error.localizedDescription)
        }
    }
    
    func deleteCalendarEvent(identifier: String) async throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw CalendarError.eventNotFound
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            throw CalendarError.deleteFailed(error.localizedDescription)
        }
    }
    
    func getAvailableCalendars() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }
}

enum CalendarError: LocalizedError {
    case notAuthorized
    case eventNotFound
    case saveFailed(String)
    case updateFailed(String)
    case deleteFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized"
        case .eventNotFound:
            return "Calendar event not found"
        case .saveFailed(let reason):
            return "Failed to save event: \(reason)"
        case .updateFailed(let reason):
            return "Failed to update event: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete event: \(reason)"
        }
    }
}