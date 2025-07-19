//
//  CalendarImportView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import EventKit

struct CalendarImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(EventStore.self) private var eventStore
    @State private var importManager = CalendarImportManager()
    
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedCalendars = Set<String>()
    @State private var calendarEvents: [EKEvent] = []
    @State private var eventTypeMappings: [EventTypeMapping] = []
    
    @State private var currentStep = ImportStep.dateRange
    @State private var showingImportProgress = false
    @State private var importSummary: ImportSummary?
    
    enum ImportStep {
        case dateRange
        case calendarSelection
        case eventPreview
        case importing
        case summary
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .dateRange:
                    dateRangeView
                case .calendarSelection:
                    calendarSelectionView
                case .eventPreview:
                    eventPreviewView
                case .importing:
                    ImportProgressView()
                case .summary:
                    if let summary = importSummary {
                        importSummaryView(summary)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if currentStep != .importing && currentStep != .summary {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Next") {
                            Task {
                                await handleNextStep()
                            }
                        }
                        .disabled(!canProceed)
                    }
                }
            }
            .task {
                // First check existing permission
                if importManager.checkCalendarAccess() {
                    print("Calendar access already granted")
                } else {
                    print("Requesting calendar access...")
                    let hasAccess = await importManager.requestCalendarAccess()
                    print("Calendar access result: \(hasAccess)")
                }
            }
            .alert("Error", isPresented: .constant(importManager.errorMessage != nil)) {
                Button("OK") {
                    importManager.errorMessage = nil
                }
            } message: {
                Text(importManager.errorMessage ?? "")
            }
        }
    }
    
    private var dateRangeView: some View {
        Form {
            Section {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
            } header: {
                Text("Select Date Range")
            } footer: {
                Text("Choose the date range for events you want to import")
            }
            
            Section {
                HStack {
                    Button("Last Week") {
                        startDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
                        endDate = Date()
                    }
                    
                    Spacer()
                    
                    Button("Last Month") {
                        startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                        endDate = Date()
                    }
                    
                    Spacer()
                    
                    Button("Last 3 Months") {
                        startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                        endDate = Date()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }
    
    private var calendarSelectionView: some View {
        Form {
            Section {
                if importManager.availableCalendars.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No calendars available")
                            .foregroundColor(.secondary)
                        
                        Text("Permission Status: \(importManager.hasCalendarAccess ? "Granted" : "Not Granted")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !importManager.hasCalendarAccess {
                            Button("Request Permission") {
                                Task {
                                    let granted = await importManager.requestCalendarAccess()
                                    print("Permission granted: \(granted)")
                                    if granted {
                                        // Force UI update
                                        await MainActor.run {
                                            currentStep = .calendarSelection
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Text("Make sure you have calendars in the Calendar app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        #if DEBUG
                        Button("Use Test Data") {
                            // Skip to preview with mock data
                            createMockEventData()
                            currentStep = .eventPreview
                        }
                        .font(.caption)
                        .foregroundColor(.orange)
                        #endif
                    }
                } else {
                    ForEach(importManager.availableCalendars, id: \.calendarIdentifier) { calendar in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 20, height: 20)
                            
                            Text(calendar.title)
                            
                            Spacer()
                            
                            if selectedCalendars.contains(calendar.calendarIdentifier) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleCalendar(calendar)
                        }
                    }
                }
            } header: {
                Text("Select Calendars")
            } footer: {
                Text("Choose which calendars to import events from")
            }
            
            Section {
                HStack {
                    Text("Selected")
                    Spacer()
                    Text("\(selectedCalendars.count) calendar\(selectedCalendars.count == 1 ? "" : "s")")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var eventPreviewView: some View {
        Form {
            Section {
                if eventTypeMappings.isEmpty {
                    Text("No events found in the selected date range")
                        .foregroundColor(.secondary)
                } else {
                    ForEach($eventTypeMappings) { $mapping in
                        EventTypeMappingRow(mapping: $mapping)
                    }
                }
            } header: {
                Text("Event Types to Import")
            } footer: {
                Text("Review and customize how events will be imported")
            }
            
            if !eventTypeMappings.isEmpty {
                Section {
                    HStack {
                        Text("Selected Events")
                        Spacer()
                        Text("\(selectedEventsCount)")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text("Total Events")
                        Spacer()
                        Text("\(totalEventsCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("New Event Types")
                        Spacer()
                        Text("\(newEventTypesCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    HStack {
                        Button("Select All") {
                            for index in eventTypeMappings.indices {
                                eventTypeMappings[index].isSelected = true
                            }
                        }
                        .disabled(eventTypeMappings.allSatisfy { $0.isSelected })
                        
                        Spacer()
                        
                        Button("Select None") {
                            for index in eventTypeMappings.indices {
                                eventTypeMappings[index].isSelected = false
                            }
                        }
                        .disabled(eventTypeMappings.allSatisfy { !$0.isSelected })
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    private func importSummaryView(_ summary: ImportSummary) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Import Complete")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Imported Events:")
                    Spacer()
                    Text("\(summary.importedEvents)")
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Skipped Events:")
                    Spacer()
                    Text("\(summary.skippedEvents)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("New Event Types:")
                    Spacer()
                    Text("\(summary.newEventTypes)")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var navigationTitle: String {
        switch currentStep {
        case .dateRange: return "Select Dates"
        case .calendarSelection: return "Select Calendars"
        case .eventPreview: return "Preview Import"
        case .importing: return "Importing..."
        case .summary: return "Import Complete"
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .dateRange:
            return startDate < endDate
        case .calendarSelection:
            return !selectedCalendars.isEmpty
        case .eventPreview:
            return !eventTypeMappings.isEmpty && eventTypeMappings.contains { $0.isSelected }
        default:
            return false
        }
    }
    
    private var totalEventsCount: Int {
        eventTypeMappings.reduce(0) { $0 + $1.calendarEvents.count }
    }
    
    private var newEventTypesCount: Int {
        eventTypeMappings.filter { $0.shouldCreateNew }.count
    }
    
    private var selectedEventsCount: Int {
        eventTypeMappings.filter { $0.isSelected }.reduce(0) { $0 + $1.calendarEvents.count }
    }
    
    private func toggleCalendar(_ calendar: EKCalendar) {
        if selectedCalendars.contains(calendar.calendarIdentifier) {
            selectedCalendars.remove(calendar.calendarIdentifier)
        } else {
            selectedCalendars.insert(calendar.calendarIdentifier)
        }
    }
    
    private func handleNextStep() async {
        switch currentStep {
        case .dateRange:
            currentStep = .calendarSelection
            
        case .calendarSelection:
            await fetchAndPreviewEvents()
            currentStep = .eventPreview
            
        case .eventPreview:
            await performImport()
            
        default:
            break
        }
    }
    
    private func fetchAndPreviewEvents() async {
        let calendars = importManager.availableCalendars.filter {
            selectedCalendars.contains($0.calendarIdentifier)
        }
        
        calendarEvents = await importManager.fetchEvents(
            from: startDate,
            to: endDate,
            calendars: calendars
        )
        
        eventTypeMappings = importManager.createEventMappings(
            from: calendarEvents,
            existingEventTypes: eventStore.eventTypes
        )
    }
    
    private func performImport() async {
        currentStep = .importing
        
        var importedCount = 0
        var skippedCount = 0
        var newTypesCount = 0
        var errors: [String] = []
        
        // Import only selected events
        for mapping in eventTypeMappings where mapping.isSelected {
            var eventType: EventType
            
            if mapping.shouldCreateNew {
                // Create new event type
                await eventStore.createEventType(
                    name: mapping.name,
                    colorHex: mapping.suggestedColor,
                    iconName: mapping.suggestedIcon
                )
                newTypesCount += 1
                
                // Fetch the newly created type
                await eventStore.fetchData()
                guard let newType = eventStore.eventTypes.first(where: { $0.name == mapping.name }) else {
                    errors.append("Failed to create event type: \(mapping.name)")
                    continue
                }
                eventType = newType
            } else if let existingType = mapping.existingEventType {
                eventType = existingType
            } else {
                errors.append("No event type for: \(mapping.name)")
                continue
            }
            
            // Import individual events
            for calendarEvent in mapping.calendarEvents {
                // Check for duplicates
                let isDuplicate = eventStore.events.contains { event in
                    event.externalId == calendarEvent.eventIdentifier
                }
                
                if isDuplicate {
                    skippedCount += 1
                    continue
                }
                
                // Create new event
                let newEvent = Event(
                    timestamp: calendarEvent.startDate,
                    eventType: eventType,
                    notes: calendarEvent.notes,
                    sourceType: .imported,
                    externalId: calendarEvent.eventIdentifier,
                    originalTitle: calendarEvent.title,
                    isAllDay: calendarEvent.isAllDay,
                    endDate: calendarEvent.endDate
                )
                
                modelContext.insert(newEvent)
                importedCount += 1
            }
        }
        
        // Save all changes
        do {
            try modelContext.save()
            await eventStore.fetchData()
        } catch {
            errors.append("Failed to save: \(error.localizedDescription)")
        }
        
        importSummary = ImportSummary(
            totalEvents: calendarEvents.count,
            importedEvents: importedCount,
            skippedEvents: skippedCount,
            newEventTypes: newTypesCount,
            errors: errors,
            startDate: startDate,
            endDate: endDate
        )
        
        currentStep = .summary
    }
    
    #if DEBUG
    private func createMockEventData() {
        // Create mock event type mappings for testing
        let mockEvents = [
            ("Doctor Appointment", "Medical", "#FF3B30", "cross.fill"),
            ("Gym Session", "Exercise", "#34C759", "figure.run"),
            ("Team Meeting", "Work", "#007AFF", "briefcase.fill"),
            ("Dentist Checkup", "Dental", "#5AC8FA", "mouth.fill"),
            ("Therapy Session", "Therapy", "#AF52DE", "brain.fill")
        ]
        
        eventTypeMappings = mockEvents.map { (name, type, color, icon) in
            var mapping = EventTypeMapping(
                name: type,
                events: [], // Empty for mock
                existingType: nil
            )
            mapping.suggestedColor = color
            mapping.suggestedIcon = icon
            return mapping
        }
    }
    #endif
}

struct EventTypeMappingRow: View {
    @Binding var mapping: EventTypeMapping
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: mapping.suggestedColor) ?? .blue)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: mapping.suggestedIcon)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading) {
                    Text(mapping.name)
                        .font(.headline)
                    
                    Text("\(mapping.calendarEvents.count) event\(mapping.calendarEvents.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $mapping.isSelected)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            
            if mapping.isSelected {
                HStack {
                    Spacer()
                    
                if mapping.shouldCreateNew {
                    Text("New")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                } else {
                    Text("Existing")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
                }
            }
        }
    }
}