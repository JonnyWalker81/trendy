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
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var calendarManager: CalendarManager
    @State private var showingAddEventType = false
    @State private var selectedEventTypeID: String?
    @State private var showingInsightDetail: APIInsight?
    @State private var isRefreshingHealthKit = false

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
                    // Sync status banner - visible during background sync
                    SyncStatusBanner(
                        syncState: eventStore.currentSyncState,
                        pendingCount: eventStore.currentPendingCount,
                        lastSyncTime: eventStore.currentLastSyncTime,
                        onRetry: {
                            await eventStore.performSync()
                        }
                    )

                    // Insights banner (only show when there are events and insights)
                    if !eventStore.eventTypes.isEmpty {
                        InsightsBannerView(viewModel: insightsViewModel) { insight in
                            showingInsightDetail = insight
                        }
                    }

                    // HealthKit status summary
                    if let service = healthKitService, service.hasHealthKitAuthorization {
                        healthKitSummarySection
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
                // Only fetch if data hasn't been loaded yet
                // MainTabView handles initial load; this is a fallback for edge cases
                if !eventStore.hasLoadedOnce {
                    await eventStore.fetchData()
                }

                #if DEBUG
                // In screenshot mode, inject mock insights instead of fetching from API
                insightsViewModel.injectMockInsightsForScreenshots()
                #endif

                // Fetch insights if needed (will be skipped if mock data was injected)
                if insightsViewModel.needsRefresh {
                    await insightsViewModel.fetchInsights()
                }
            }
        }
        .accessibilityIdentifier("dashboardView")
    }
    
    // MARK: - HealthKit Summary Section

    private var healthKitSummarySection: some View {
        let enabledCategories = Array(HealthKitSettings.shared.enabledCategories)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text("Health Tracking")
                    .font(.headline)
                Spacer()

                Button {
                    Task {
                        await refreshHealthKit()
                    }
                } label: {
                    if isRefreshingHealthKit || (healthKitService?.isRefreshing ?? false) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRefreshingHealthKit || (healthKitService?.isRefreshing ?? false))
            }

            if enabledCategories.isEmpty {
                Text("No health data types enabled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let oldestUpdate = oldestCategoryUpdate(for: enabledCategories)
                HStack {
                    Text("\(enabledCategories.count) types active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatRelativeTime(oldestUpdate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func formatRelativeTime(_ date: Date?) -> String {
        guard let date = date else { return "Never updated" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func oldestCategoryUpdate(for categories: [HealthDataCategory]) -> Date? {
        guard let service = healthKitService else { return nil }
        let updates = categories.compactMap { service.lastUpdateTime(for: $0) }
        return updates.min()
    }

    private func refreshHealthKit() async {
        isRefreshingHealthKit = true
        await healthKitService?.forceRefreshAllCategories()
        isRefreshingHealthKit = false
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