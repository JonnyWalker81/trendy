//
//  CalendarImportManager.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import Foundation
import EventKit
import SwiftUI

@Observable
@MainActor
class CalendarImportManager {
    private let eventStore = EKEventStore()
    private(set) var hasCalendarAccess = false
    private(set) var availableCalendars: [EKCalendar] = []
    private(set) var isLoading = false
    var errorMessage: String?
    
    func requestCalendarAccess() async -> Bool {
        print("DEBUG: Requesting calendar access...")
        
        // Check current status first
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        print("DEBUG: Current authorization status: \(currentStatus.rawValue)")
        
        // If already denied, we can't request again
        if currentStatus == .denied || currentStatus == .restricted {
            print("DEBUG: Calendar access previously denied or restricted")
            errorMessage = "Calendar access denied. Please enable in Settings > Privacy > Calendars"
            return false
        }
        
        do {
            if #available(iOS 17.0, *) {
                print("DEBUG: Using iOS 17+ permission API")
                // For iOS 17+, we need to check if we can actually request
                if currentStatus == .notDetermined {
                    hasCalendarAccess = try await eventStore.requestFullAccessToEvents()
                } else if currentStatus == .fullAccess {
                    hasCalendarAccess = true
                } else {
                    hasCalendarAccess = false
                }
            } else {
                print("DEBUG: Using legacy permission API")
                hasCalendarAccess = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        print("DEBUG: Permission callback - granted: \(granted), error: \(String(describing: error))")
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
            
            print("DEBUG: Calendar access granted: \(hasCalendarAccess)")
            
            if hasCalendarAccess {
                loadAvailableCalendars()
            }
            
            return hasCalendarAccess
        } catch {
            print("DEBUG: Error requesting calendar access: \(error)")
            errorMessage = "Failed to request calendar access: \(error.localizedDescription). Make sure calendar permissions are configured in the app's Info.plist."
            return false
        }
    }
    
    func checkCalendarAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        hasCalendarAccess = (status == .authorized || status == .fullAccess)
        
        if hasCalendarAccess {
            loadAvailableCalendars()
        }
        
        return hasCalendarAccess
    }
    
    private func loadAvailableCalendars() {
        let allCalendars = eventStore.calendars(for: .event)
        print("DEBUG: Found \(allCalendars.count) total calendars")
        
        availableCalendars = allCalendars
            .sorted { $0.title < $1.title }
        
        for calendar in availableCalendars {
            print("DEBUG: Calendar: \(calendar.title), Type: \(calendar.type.rawValue), Immutable: \(calendar.isImmutable)")
        }
    }
    
    func fetchEvents(
        from startDate: Date,
        to endDate: Date,
        calendars: [EKCalendar]? = nil
    ) async -> [EKEvent] {
        guard hasCalendarAccess else {
            errorMessage = "Calendar access not granted"
            return []
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        
        let events = eventStore.events(matching: predicate)
            .filter { event in
                // Filter out events without proper titles
                event.title?.isEmpty == false
            }
            .sorted { $0.startDate < $1.startDate }
        
        return events
    }
    
    func createEventMappings(
        from events: [EKEvent],
        existingEventTypes: [EventType]
    ) -> [EventTypeMapping] {
        // Group events by similar titles/patterns
        let groupedEvents = Dictionary(grouping: events) { event in
            extractEventTypeKey(from: event)
        }
        
        return groupedEvents.compactMap { (key, events) in
            guard !key.isEmpty else { return nil }
            
            // Try to find existing event type
            let existingType = existingEventTypes.first { eventType in
                eventType.name.localizedCaseInsensitiveContains(key) ||
                key.localizedCaseInsensitiveContains(eventType.name)
            }
            
            let mapping = EventTypeMapping(
                name: key,
                events: events,
                existingType: existingType
            )
            
            // Apply smart suggestions
            applySuggestions(to: mapping)
            
            return mapping
        }.sorted { $0.calendarEvents.count > $1.calendarEvents.count }
    }
    
    private func extractEventTypeKey(from event: EKEvent) -> String {
        guard let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return "" }
        
        // Common patterns to extract
        let patterns: [(pattern: String, group: String)] = [
            ("(?i)(doctor|dr\\.?|appointment|checkup|medical)", "Medical"),
            ("(?i)(gym|workout|exercise|fitness|run|yoga)", "Exercise"),
            ("(?i)(meeting|call|conference|standup|1:1)", "Work"),
            ("(?i)(breakfast|lunch|dinner|coffee|meal)", "Meal"),
            ("(?i)(therapy|counseling|session)", "Therapy"),
            ("(?i)(dentist|dental)", "Dental"),
            ("(?i)(class|lecture|course|lesson)", "Education"),
            ("(?i)(travel|flight|trip)", "Travel")
        ]
        
        for (pattern, group) in patterns {
            if let _ = title.range(of: pattern, options: .regularExpression) {
                return group
            }
        }
        
        // If no pattern matches, use the first significant word
        let words = title.components(separatedBy: .whitespacesAndNewlines)
        if let firstSignificantWord = words.first(where: { $0.count > 3 }) {
            return firstSignificantWord.capitalized
        }
        
        return title
    }
    
    private func applySuggestions(to mapping: EventTypeMapping) {
        var updatedMapping = mapping
        
        // Suggest colors based on type
        switch mapping.name.lowercased() {
        case let name where name.contains("medical") || name.contains("doctor"):
            updatedMapping.suggestedColor = "#FF3B30" // Red
            updatedMapping.suggestedIcon = "cross.fill"
        case let name where name.contains("exercise") || name.contains("gym"):
            updatedMapping.suggestedColor = "#34C759" // Green
            updatedMapping.suggestedIcon = "figure.run"
        case let name where name.contains("work") || name.contains("meeting"):
            updatedMapping.suggestedColor = "#007AFF" // Blue
            updatedMapping.suggestedIcon = "briefcase.fill"
        case let name where name.contains("meal") || name.contains("food"):
            updatedMapping.suggestedColor = "#FF9500" // Orange
            updatedMapping.suggestedIcon = "fork.knife"
        case let name where name.contains("therapy"):
            updatedMapping.suggestedColor = "#AF52DE" // Purple
            updatedMapping.suggestedIcon = "brain.fill"
        case let name where name.contains("dental"):
            updatedMapping.suggestedColor = "#5AC8FA" // Light Blue
            updatedMapping.suggestedIcon = "mouth.fill"
        case let name where name.contains("education") || name.contains("class"):
            updatedMapping.suggestedColor = "#FFCC00" // Yellow
            updatedMapping.suggestedIcon = "book.fill"
        case let name where name.contains("travel"):
            updatedMapping.suggestedColor = "#FF6482" // Pink
            updatedMapping.suggestedIcon = "airplane"
        default:
            // Use calendar color if available
            if let calendarColor = mapping.calendarEvents.first?.calendar.cgColor {
                let uiColor = UIColor(cgColor: calendarColor)
                updatedMapping.suggestedColor = Color(uiColor).hexString
            }
        }
    }
    
    func checkForDuplicates(
        events: [EKEvent],
        existingEvents: [Event]
    ) -> Set<String> {
        let existingExternalIds = Set(existingEvents.compactMap { $0.externalId })
        let newEventIds = Set(events.compactMap { $0.eventIdentifier })
        return existingExternalIds.intersection(newEventIds)
    }
}