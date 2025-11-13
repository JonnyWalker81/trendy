//
//  EventTypeSettingsView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct EventTypeSettingsView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(ThemeManager.self) private var themeManager
    @State private var showingAddEventType = false
    @State private var editingEventType: EventType?
    @State private var showingCalendarImport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: Binding(
                        get: { themeManager.currentTheme },
                        set: { themeManager.currentTheme = $0 }
                    )) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Label {
                                Text(theme.displayName)
                            } icon: {
                                Image(systemName: theme.iconName)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Appearance")
                }

                Section {
                    ForEach(eventStore.eventTypes) { eventType in
                        EventTypeRow(eventType: eventType) {
                            editingEventType = eventType
                        }
                    }
                    .onDelete(perform: deleteEventTypes)
                } header: {
                    Text("Event Types")
                } footer: {
                    if eventStore.eventTypes.isEmpty {
                        Text("Tap the + button to create your first event type")
                    }
                }
                
                Section {
                    Button {
                        showingAddEventType = true
                    } label: {
                        Label("Add Event Type", systemImage: "plus.circle.fill")
                    }
                    
                    Button {
                        showingCalendarImport = true
                    } label: {
                        Label("Import from Calendar", systemImage: "calendar.badge.plus")
                    }
                    
                    NavigationLink {
                        CalendarSyncSettingsView()
                    } label: {
                        Label("Calendar Sync", systemImage: "calendar.badge.checkmark")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddEventType) {
                AddEventTypeView()
            }
            .sheet(item: $editingEventType) { eventType in
                EditEventTypeView(eventType: eventType)
            }
            .sheet(isPresented: $showingCalendarImport) {
                CalendarImportView()
            }
            .task {
                await eventStore.fetchData()
            }
        }
    }
    
    private func deleteEventTypes(at offsets: IndexSet) {
        for index in offsets {
            let eventType = eventStore.eventTypes[index]
            Task {
                await eventStore.deleteEventType(eventType)
            }
        }
    }
}

struct EventTypeRow: View {
    let eventType: EventType
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(eventType.color)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: eventType.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(eventType.name)
                    .font(.headline)
                
                let eventCount = eventType.events?.count ?? 0
                Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

struct EditEventTypeView: View {
    let eventType: EventType
    @Environment(\.dismiss) private var dismiss
    @Environment(EventStore.self) private var eventStore
    
    @State private var name: String
    @State private var selectedColor: Color
    @State private var selectedIcon: String
    
    init(eventType: EventType) {
        self.eventType = eventType
        _name = State(initialValue: eventType.name)
        _selectedColor = State(initialValue: eventType.color)
        _selectedIcon = State(initialValue: eventType.iconName)
    }
    
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown
    ]
    
    private let icons: [String] = [
        "circle.fill", "star.fill", "heart.fill", "bolt.fill",
        "flame.fill", "drop.fill", "leaf.fill", "pawprint.fill",
        "pills.fill", "bandage.fill", "cross.fill", "bed.double.fill",
        "figure.walk", "figure.run", "dumbbell.fill", "sportscourt.fill",
        "brain.fill", "book.fill", "pencil", "briefcase.fill",
        "cart.fill", "cup.and.saucer.fill", "fork.knife", "car.fill"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Event Type Name") {
                    TextField("Name", text: $name)
                }
                
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? Color.chipBackground : Color.clear)
                                )
                                .foregroundColor(selectedIcon == icon ? .primary : .secondary)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Edit Event Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await eventStore.updateEventType(
                                eventType,
                                name: name,
                                colorHex: selectedColor.hexString,
                                iconName: selectedIcon
                            )
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}