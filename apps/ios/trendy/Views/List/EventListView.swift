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

    /// Tracks whether the initial data load has completed (for showing loading state)
    @State private var hasCompletedInitialLoad = false

    /// Number of date sections to display (for pagination to avoid List layout explosion)
    /// Start with fewer sections to enable fast initial render, expand as user scrolls
    @State private var visibleSectionCount: Int = 10

    /// Timer for periodic sync state refresh during active syncing
    @State private var syncStateRefreshTimer: Timer?

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

    /// Dates to display (limited for initial render performance)
    /// SwiftUI List layout solver becomes expensive with many sections
    private var visibleDates: [Date] {
        Array(sortedDates.prefix(visibleSectionCount))
    }

    /// Whether there are more dates to load
    private var hasMoreDates: Bool {
        sortedDates.count > visibleSectionCount
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // HealthKit refresh indicator
                if healthKitService?.isRefreshingDailyAggregates == true {
                    HealthKitRefreshBanner()
                        .animation(.easeInOut(duration: 0.3), value: healthKitService?.isRefreshingDailyAggregates)
                }

                // Show loading state until initial data processing is complete
                // This prevents blocking the main thread with expensive List rendering
                if !hasCompletedInitialLoad {
                    loadingPlaceholder
                } else {
                    eventsList
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
                // Initial cache population on background thread to avoid blocking main thread
                await updateCachedDataAsync()
                hasCompletedInitialLoad = true
            }
            .onChange(of: eventStore.events.count) { _, _ in
                Task {
                    await updateCachedDataAsync()
                }
            }
            .onChange(of: searchText) { _, _ in
                // Reset pagination when filter changes
                visibleSectionCount = 10
                Task {
                    await updateCachedDataAsync()
                }
            }
            .onChange(of: selectedEventTypeID) { _, _ in
                // Reset pagination when filter changes
                visibleSectionCount = 10
                Task {
                    await updateCachedDataAsync()
                }
            }
            .onChange(of: eventStore.currentSyncState) { oldState, newState in
                // Start/stop periodic refresh based on sync state
                switch newState {
                case .syncing(_, _), .pulling:
                    startSyncStateRefreshTimer()
                case .rateLimited:
                    // During rate limit, refresh every few seconds to update pending count if it changes
                    startSyncStateRefreshTimer(interval: 5.0)
                default:
                    stopSyncStateRefreshTimer()
                }
            }
            .onDisappear {
                stopSyncStateRefreshTimer()
            }
        }
        .accessibilityIdentifier("eventListView")
    }

    /// Loading placeholder shown before data processing completes
    private var loadingPlaceholder: some View {
        List {
            ProgressView("Loading events...")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
                .listRowBackground(Color.clear)
        }
    }

    /// The main events list - only rendered after initial data load
    private var eventsList: some View {
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
                // Use visibleDates to limit initial render - prevents List layout explosion
                ForEach(visibleDates, id: \.self) { date in
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

                // Load more button when there are additional dates
                if hasMoreDates {
                    Section {
                        Button {
                            // Load 20 more sections at a time
                            visibleSectionCount += 20
                        } label: {
                            HStack {
                                Spacer()
                                Text("Load Earlier Events")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
    }

    /// Start periodic refresh of sync state during active operations
    private func startSyncStateRefreshTimer(interval: TimeInterval = 1.0) {
        stopSyncStateRefreshTimer()
        syncStateRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                await eventStore.refreshSyncStateForUI()
            }
        }
    }

    /// Stop the sync state refresh timer
    private func stopSyncStateRefreshTimer() {
        syncStateRefreshTimer?.invalidate()
        syncStateRefreshTimer = nil
    }

    /// Updates cached grouped events and sorted dates asynchronously.
    /// Always runs the expensive grouping on a background thread to avoid blocking the main thread.
    /// This is critical for preventing hangs when switching to the Events tab.
    @MainActor
    private func updateCachedDataAsync() async {
        let events = filteredEvents
        let newHash = events.count  // Simple hash based on count

        // Skip if data hasn't meaningfully changed
        if newHash == lastEventsHash && !cachedSortedDates.isEmpty {
            return
        }

        lastEventsHash = newHash

        // Always compute on background thread to keep UI responsive
        // Even for small datasets, the cumulative work can add up during tab switches
        let eventsCopy = events
        let (grouped, sorted) = await Task.detached(priority: .userInitiated) {
            let grouped = Dictionary(grouping: eventsCopy) { event in
                Calendar.current.startOfDay(for: event.timestamp)
            }
            let sorted = grouped.keys.sorted(by: >)
            return (grouped, sorted)
        }.value

        cachedGroupedEvents = grouped
        cachedSortedDates = sorted
    }

    /// Synchronous cache update for immediate needs (called from onAppear when returning to tab).
    /// Uses cached results if available, otherwise triggers async update.
    private func updateCachedData() {
        let events = filteredEvents
        let newHash = events.count

        // Skip if data hasn't meaningfully changed
        if newHash == lastEventsHash && !cachedSortedDates.isEmpty {
            return
        }

        // For synchronous path, we can't do async work, so schedule it
        Task {
            await updateCachedDataAsync()
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