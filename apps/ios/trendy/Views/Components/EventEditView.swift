//
//  EventEditView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

/// Box class to hold properties - avoids copy-on-write issues with Dictionary
class PropertiesBox {
    var dict: [String: PropertyValue] = [:]

    init(_ dict: [String: PropertyValue] = [:]) {
        self.dict = dict
    }
}

// ObservableObject class to hold form state - survives view recreation with @StateObject
class EventEditFormState: ObservableObject, PropertyStorage {
    @Published var selectedDate: Date
    @Published var endDate: Date
    @Published var isAllDay: Bool
    @Published var notes: String
    @Published var showEndDate: Bool

    // Use a box to avoid copy-on-write issues
    private var propertiesBox = PropertiesBox()

    // PropertyStorage conformance - direct access to the boxed dictionary
    var properties: [String: PropertyValue] {
        get {
            let count = propertiesBox.dict.count
            let keys = propertiesBox.dict.keys.joined(separator: ", ")
            print("📖 GET properties - count: \(count), keys: \(keys), box: \(ObjectIdentifier(propertiesBox))")
            return propertiesBox.dict
        }
        set {
            let oldCount = propertiesBox.dict.count
            let newCount = newValue.count
            print("📝 SET properties - old: \(oldCount), new: \(newCount), keys: \(newValue.keys.joined(separator: ", ")), box: \(ObjectIdentifier(propertiesBox))")
            // Print stack trace to find who's setting it
            if newCount < oldCount {
                print("⚠️ PROPERTIES DECREASED! Stack trace:")
                Thread.callStackSymbols.prefix(10).forEach { print("   \($0)") }
            }
            propertiesBox.dict = newValue
            objectWillChange.send()  // Manually notify observers
        }
    }

    private var isInitialized = false
    private let instanceId = UUID()

    init() {
        // Default values - will be overwritten by initialize(from:)
        self.selectedDate = Date()
        self.endDate = Date()
        self.isAllDay = false
        self.notes = ""
        self.showEndDate = false
        print("🆔 EventEditFormState.init - instance: \(instanceId.uuidString.prefix(8)), object: \(ObjectIdentifier(self))")
    }

    func initialize(from event: Event?) {
        // Only initialize once to prevent re-initialization on view recreation
        guard !isInitialized else {
            print("🏗️ EventEditFormState.initialize - Already initialized (instance: \(instanceId.uuidString.prefix(8))), skipping")
            return
        }
        isInitialized = true

        if let event = event {
            self.selectedDate = event.timestamp
            self.endDate = event.endDate ?? Date()
            self.isAllDay = event.isAllDay
            self.notes = event.notes ?? ""
            self.showEndDate = event.endDate != nil
            self.properties = event.properties  // Use setter for logging
            print("🏗️ EventEditFormState.initialize - Loaded \(properties.count) properties (instance: \(instanceId.uuidString.prefix(8)))")
        } else {
            print("🏗️ EventEditFormState.initialize - New event (instance: \(instanceId.uuidString.prefix(8)))")
        }
    }
}

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EventStore.self) private var eventStore
    @EnvironmentObject private var calendarManager: CalendarManager

    let eventType: EventType
    let existingEvent: Event?

    // Query property definitions here instead of in DynamicPropertyFieldsView
    // to avoid @Query interfering with @ObservedObject
    @Query private var allPropertyDefinitions: [PropertyDefinition]

    // Use @StateObject - guaranteed to create only ONE instance that survives view recreation
    @StateObject private var formState = EventEditFormState()

    // Computed property definitions for this event type
    private var propertyDefinitions: [PropertyDefinition] {
        allPropertyDefinitions
            .filter { $0.eventTypeId == eventType.id }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    init(eventType: EventType, existingEvent: Event? = nil) {
        self.eventType = eventType
        self.existingEvent = existingEvent
        print("🏗️ EventEditView.init called")
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
                    Toggle("All-day", isOn: $formState.isAllDay)

                    if formState.isAllDay {
                        DatePicker("Date",
                                 selection: $formState.selectedDate,
                                 displayedComponents: .date)

                        Toggle("End date", isOn: $formState.showEndDate)

                        if formState.showEndDate {
                            DatePicker("End date",
                                     selection: $formState.endDate,
                                     in: formState.selectedDate...,
                                     displayedComponents: .date)
                        }
                    } else {
                        DatePicker("Date & Time",
                                 selection: $formState.selectedDate,
                                 displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Notes") {
                    TextEditor(text: $formState.notes)
                        .frame(minHeight: 100)
                }

                Section("Properties") {
                    DynamicPropertyFieldsView(
                        eventTypeId: eventType.id,
                        storage: formState,
                        propertyDefinitions: propertyDefinitions
                    )
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
            // Initialize form state from existing event (only happens once due to isInitialized flag)
            formState.initialize(from: existingEvent)
            print("📋 EventEditView.onAppear - formState object: \(ObjectIdentifier(formState)), properties count: \(formState.properties.count), keys: \(formState.properties.keys.joined(separator: ", "))")
        }
        .onChange(of: formState.properties) { oldValue, newValue in
            print("🔄 EventEditView.properties changed: \(oldValue.count) -> \(newValue.count), keys: \(newValue.keys.joined(separator: ", "))")
        }
    }
    
    private func saveEvent() {
        Task {
            // Log for debugging property issues (works in all builds)
            Log.data.info("EventEditView.saveEvent() - formState.properties count: \(formState.properties.count)")
            for (key, value) in formState.properties {
                Log.data.info("  formState property '\(key)': type=\(value.type.rawValue), value=\(String(describing: value.value.value))")
            }

            if let existingEvent {
                // Update existing event
                Log.data.info("Updating existing event: \(existingEvent.id)")
                existingEvent.timestamp = formState.selectedDate
                existingEvent.isAllDay = formState.isAllDay
                existingEvent.notes = formState.notes.isEmpty ? nil : formState.notes
                existingEvent.endDate = (formState.isAllDay && formState.showEndDate) ? formState.endDate : nil
                existingEvent.properties = formState.properties

                Log.data.info("After assignment, existingEvent.properties count: \(existingEvent.properties.count)")

                await eventStore.updateEvent(existingEvent)
            } else {
                // Create new event
                Log.data.info("Creating new event with \(formState.properties.count) properties")
                await eventStore.recordEvent(
                    type: eventType,
                    timestamp: formState.selectedDate,
                    isAllDay: formState.isAllDay,
                    endDate: (formState.isAllDay && formState.showEndDate) ? formState.endDate : nil,
                    notes: formState.notes.isEmpty ? nil : formState.notes,
                    properties: formState.properties
                )
            }
            dismiss()
        }
    }
}