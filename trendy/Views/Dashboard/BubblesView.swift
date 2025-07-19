//
//  BubblesView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct BubblesView: View {
    @Environment(EventStore.self) private var eventStore
    @State private var showingAddEventType = false
    @State private var selectedEventType: EventType?
    @State private var showingNoteInput = false
    
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
                                Task {
                                    await recordEvent(eventType)
                                }
                            } onLongPress: {
                                selectedEventType = eventType
                                showingNoteInput = true
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
            }
            .sheet(isPresented: $showingNoteInput) {
                if let eventType = selectedEventType {
                    NoteInputView(eventType: eventType) { note in
                        Task {
                            await recordEvent(eventType, withNote: note)
                        }
                    }
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
                        .fill(Color.secondary.opacity(0.2))
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
    
    private func recordEvent(_ eventType: EventType, withNote note: String? = nil) async {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        await eventStore.recordEvent(type: eventType)
    }
}

struct NoteInputView: View {
    let eventType: EventType
    let onSave: (String) -> Void
    
    @State private var noteText = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Add a note for \(eventType.name)") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(noteText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}