//
//  EventListView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct EventListView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @State private var searchText = ""
    @State private var selectedEventTypeID: String?

    // Cached computed values to avoid expensive recalculations on every render
    @State private var cachedGroupedEvents: [Date: [Event]] = [:]
    @State private var cachedSortedDates: [Date] = []
    @State private var lastEventsHash: Int = 0

    private var selectedEventType: EventType? {
        guard let id = selectedEventTypeID else { return nil }
        return eventStore.eventTypes.first { $0.id == id }
    }

    private var filteredEvents: [Event] {
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

    // Use cached values for rendering
    private var groupedEvents: [Date: [Event]] { cachedGroupedEvents }
    private var sortedDates: [Date] { cachedSortedDates }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sync status banner at top
                SyncStatusBanner(
                    syncState: eventStore.currentSyncState,
                    pendingCount: eventStore.currentPendingCount,
                    lastSyncTime: eventStore.currentLastSyncTime,
                    onRetry: {
                        await eventStore.performSync()
                    }
                )

                // HealthKit refresh indicator
                if healthKitService?.isRefreshingDailyAggregates == true {
                    HealthKitRefreshBanner()
                        .animation(.easeInOut(duration: 0.3), value: healthKitService?.isRefreshingDailyAggregates)
                }

                List {
                    if !eventStore.eventTypes.isEmpty {
                        filterSection
                    }

                    // Use cached data for empty check to avoid expensive recalculation
                    if cachedSortedDates.isEmpty {
                        if eventStore.isLoading && !eventStore.hasLoadedOnce {
                            // Initial loading - show loading indicator
                            ProgressView("Loading...")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 50)
                                .listRowBackground(Color.clear)
                        } else if eventStore.hasLoadedOnce {
                            // Truly empty after loading completed
                            emptyStateView
                        } else {
                            // Cache not yet populated - show brief loading
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 50)
                                .listRowBackground(Color.clear)
                        }
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
            }
            .navigationTitle("Events")
            .searchable(text: $searchText, prompt: "Search events")
            .refreshable {
                await eventStore.fetchData(force: true)
            }
            .task {
                // Only fetch if data hasn't been loaded yet
                // MainTabView handles initial load; this is a fallback for edge cases
                if !eventStore.hasLoadedOnce {
                    await eventStore.fetchData()
                }
                // Initial cache population
                updateCachedData()
            }
            .onAppear {
                // Rebuild cache when view appears (e.g., switching tabs)
                // This handles events added while on another tab, where .onChange didn't fire
                // because this view wasn't in the active view hierarchy
                updateCachedData()
            }
            .onChange(of: eventStore.events.count) { _, _ in
                updateCachedData()
            }
            .onChange(of: searchText) { _, _ in
                updateCachedData()
            }
            .onChange(of: selectedEventTypeID) { _, _ in
                updateCachedData()
            }
        }
        .accessibilityIdentifier("eventListView")
    }

    /// Updates cached grouped events and sorted dates
    /// Called only when underlying data changes, not on every render
    /// Performs expensive grouping on background thread to keep UI responsive
    private func updateCachedData() {
        let events = filteredEvents
        let newHash = events.count  // Simple hash based on count

        // Skip if data hasn't meaningfully changed
        if newHash == lastEventsHash && !cachedSortedDates.isEmpty {
            return
        }

        lastEventsHash = newHash

        // For small datasets, compute synchronously
        if events.count < 100 {
            cachedGroupedEvents = Dictionary(grouping: events) { event in
                Calendar.current.startOfDay(for: event.timestamp)
            }
            cachedSortedDates = cachedGroupedEvents.keys.sorted(by: >)
        } else {
            // For large datasets, compute on background thread
            let eventsCopy = events
            Task.detached(priority: .userInitiated) {
                let grouped = Dictionary(grouping: eventsCopy) { event in
                    Calendar.current.startOfDay(for: event.timestamp)
                }
                let sorted = grouped.keys.sorted(by: >)
                await MainActor.run {
                    cachedGroupedEvents = grouped
                    cachedSortedDates = sorted
                }
            }
        }
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
                        .accessibilityIdentifier("filterChip_\(eventType.id)")
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

/// Banner shown when HealthKit data is being refreshed
struct HealthKitRefreshBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.pink)

            Text("Updating health data...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}