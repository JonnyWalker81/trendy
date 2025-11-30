//
//  EventListView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct EventListView: View {
    @Environment(EventStore.self) private var eventStore
    @State private var searchText = ""
    @State private var selectedEventTypeID: UUID?
    
    private var selectedEventType: EventType? {
        guard let id = selectedEventTypeID else { return nil }
        return eventStore.eventTypes.first { $0.id == id }
    }
    
    var filteredEvents: [Event] {
        let events = eventStore.events
        
        guard !searchText.isEmpty || selectedEventType != nil else {
            return events
        }
        
        return events.filter { event in
            let matchesSearch = searchText.isEmpty || 
                (event.eventType?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (event.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            
            let matchesType = selectedEventType == nil || event.eventType?.id == selectedEventType?.id
            
            return matchesSearch && matchesType
        }
    }
    
    var groupedEvents: [Date: [Event]] {
        Dictionary(grouping: filteredEvents) { event in
            Calendar.current.startOfDay(for: event.timestamp)
        }
    }
    
    var sortedDates: [Date] {
        groupedEvents.keys.sorted(by: >)
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !eventStore.eventTypes.isEmpty {
                    filterSection
                }
                
                if filteredEvents.isEmpty {
                    emptyStateView
                } else {
                    ForEach(sortedDates, id: \.self) { date in
                        Section {
                            ForEach(groupedEvents[date] ?? []) { event in
                                EventRowView(event: event)
                            }
                            .onDelete { indexSet in
                                deleteEvents(at: indexSet, for: date)
                            }
                        } header: {
                            Text(date, format: .dateTime.weekday().month().day().year())
                                .font(.headline)
                        }
                    }
                }
            }
            .navigationTitle("Events")
            .searchable(text: $searchText, prompt: "Search events")
            .refreshable {
                await eventStore.fetchData()
            }
            .task {
                await eventStore.fetchData()
            }
        }
        .accessibilityIdentifier("eventListView")
    }
    
    private var filterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: selectedEventTypeID == nil
                    ) {
                        selectedEventTypeID = nil
                    }
                    .accessibilityIdentifier("filterChip_all")

                    ForEach(eventStore.eventTypes) { eventType in
                        FilterChip(
                            title: eventType.name,
                            color: eventType.color,
                            isSelected: selectedEventTypeID == eventType.id
                        ) {
                            if selectedEventTypeID == eventType.id {
                                selectedEventTypeID = nil
                            } else {
                                selectedEventTypeID = eventType.id
                            }
                        }
                        .accessibilityIdentifier("filterChip_\(eventType.id.uuidString)")
                    }
                }
                .padding(.horizontal)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("filterChipsSection")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Events")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(searchText.isEmpty && selectedEventType == nil ? 
                 "Start tracking events from the Dashboard" : 
                 "No events match your search")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .listRowBackground(Color.clear)
    }
    
    private func deleteEvents(at offsets: IndexSet, for date: Date) {
        let eventsForDate = groupedEvents[date] ?? []
        for index in offsets {
            let event = eventsForDate[index]
            Task {
                await eventStore.deleteEvent(event)
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    var color: Color = .blue
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color.chipBackground)
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}