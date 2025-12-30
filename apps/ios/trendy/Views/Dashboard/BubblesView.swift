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
    @Environment(InsightsViewModel.self) private var insightsViewModel
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarManager: CalendarManager
    @State private var showingAddEventType = false
    @State private var selectedEventTypeID: String?
    @State private var showingInsightDetail: APIInsight?

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
                VStack(spacing: 16) {
                    // Insights banner (only show when there are events and insights)
                    if !eventStore.eventTypes.isEmpty {
                        InsightsBannerView(viewModel: insightsViewModel) { insight in
                            showingInsightDetail = insight
                        }
                    }

                    if eventStore.eventTypes.isEmpty {
                        if eventStore.isLoading && !eventStore.hasLoadedOnce {
                            // Initial loading - show loading indicator
                            ProgressView("Loading...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 50)
                        } else {
                            // Truly empty after loading completed
                            emptyStateView
                        }
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
                                .accessibilityIdentifier("addEventTypeBubble")
                        }
                        .padding(.horizontal)
                        .accessibilityIdentifier("bubblesGrid")
                    }
                }
            }
            .navigationTitle("TrendSight")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddEventType = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addEventTypeButton")
                }
            }
            .sheet(isPresented: $showingAddEventType) {
                AddEventTypeView()
                    .environment(eventStore)
            }
            .sheet(isPresented: Binding(
                get: { selectedEventTypeID != nil },
                set: { if !$0 { selectedEventTypeID = nil } }
            )) {
                if let eventTypeID = selectedEventTypeID,
                   let eventType = eventStore.eventTypes.first(where: { $0.id == eventTypeID }) {
                    EventEditView(eventType: eventType)
                        .environment(eventStore)
                        .environmentObject(calendarManager)
                }
            }
            .sheet(item: $showingInsightDetail) { insight in
                InsightDetailSheet(insight: insight, viewModel: insightsViewModel)
            }
            .task {
                await eventStore.fetchData()
                // Fetch insights if needed
                if insightsViewModel.needsRefresh {
                    await insightsViewModel.fetchInsights()
                }
            }
        }
        .accessibilityIdentifier("dashboardView")
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