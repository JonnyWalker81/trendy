//
//  BubblesView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

struct BubblesView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarManager: CalendarManager
    @State private var showingAddEventType = false
    @State private var selectedEventTypeID: UUID?
    
    private var selectedEventType: EventType? {
        guard let id = selectedEventTypeID else { return nil }
        return eventStore.eventTypes.first { $0.id == id }
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 20)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if eventStore.eventTypes.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(eventStore.eventTypes) { eventType in
                            EventBubbleView(eventType: eventType) {
                                selectedEventTypeID = eventType.id
                            } onLongPress: {
                                // Quick record without opening edit view
                                Task {
                                    await recordEvent(eventType)
                                }
                            }
                        }
                        
                        addBubbleButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Trendy")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddEventType = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEventType) {
                AddEventTypeView()
                    .environment(eventStore)
            }
            .sheet(item: $selectedEventTypeID) { eventTypeID in
                if let eventType = eventStore.eventTypes.first(where: { $0.id == eventTypeID }) {
                    EventEditView(eventType: eventType)
                        .environment(eventStore)
                        .environmentObject(calendarManager)
                }
            }
            .task {
                await eventStore.fetchData()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Event Types")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the + button to create your first event type")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddEventType = true
            } label: {
                Label("Add Event Type", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var addBubbleButton: some View {
        Button {
            showingAddEventType = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.chipBackground)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                }
                
                Text("Add")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func recordEvent(_ eventType: EventType) async {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        await eventStore.recordEvent(type: eventType)
    }
}