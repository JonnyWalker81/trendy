//
//  EventEditView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EventStore.self) private var eventStore
    @EnvironmentObject private var calendarManager: CalendarManager
    
    let eventType: EventType
    let existingEvent: Event?
    
    @State private var selectedDate = Date()
    @State private var endDate = Date()
    @State private var isAllDay = false
    @State private var notes = ""
    @State private var showEndDate = false
    
    init(eventType: EventType, existingEvent: Event? = nil) {
        self.eventType = eventType
        self.existingEvent = existingEvent
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: eventType.colorHex) ?? Color.blue)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: eventType.iconName)
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            )
                        
                        Text(eventType.name)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Toggle("All-day", isOn: $isAllDay)
                    
                    if isAllDay {
                        DatePicker("Date", 
                                 selection: $selectedDate, 
                                 displayedComponents: .date)
                        
                        Toggle("End date", isOn: $showEndDate)
                        
                        if showEndDate {
                            DatePicker("End date", 
                                     selection: $endDate, 
                                     in: selectedDate...,
                                     displayedComponents: .date)
                        }
                    } else {
                        DatePicker("Date & Time", 
                                 selection: $selectedDate, 
                                 displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                if eventStore.syncWithCalendar && calendarManager.isAuthorized {
                    Section {
                        HStack {
                            Image(systemName: "calendar.badge.checkmark")
                                .foregroundColor(.green)
                            Text("This event will be synced to your calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(existingEvent == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEvent()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let event = existingEvent {
                selectedDate = event.timestamp
                isAllDay = event.isAllDay
                notes = event.notes ?? ""
                if let eventEndDate = event.endDate {
                    showEndDate = true
                    endDate = eventEndDate
                }
            }
        }
    }
    
    private func saveEvent() {
        Task {
            if let existingEvent {
                // Update existing event
                existingEvent.timestamp = selectedDate
                existingEvent.isAllDay = isAllDay
                existingEvent.notes = notes.isEmpty ? nil : notes
                existingEvent.endDate = (isAllDay && showEndDate) ? endDate : nil
                
                await eventStore.updateEvent(existingEvent)
            } else {
                // Create new event
                await eventStore.recordEvent(
                    type: eventType,
                    timestamp: selectedDate,
                    isAllDay: isAllDay,
                    endDate: (isAllDay && showEndDate) ? endDate : nil,
                    notes: notes.isEmpty ? nil : notes
                )
            }
            dismiss()
        }
    }
}