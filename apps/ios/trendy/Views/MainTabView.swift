//
//  MainTabView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.apiClient) private var apiClient
    @State private var eventStore: EventStore?
    @StateObject private var calendarManager = CalendarManager()
    @State private var notificationManager = NotificationManager()
    @State private var geofenceManager: GeofenceManager?
    @State private var selectedTab = 0
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if isLoading {
                LoadingView()
                    .transition(.opacity.combined(with: .scale))
            } else {
                TabView(selection: $selectedTab) {
            BubblesView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)
            
            EventListView()
                .tabItem {
                    Label("List", systemImage: "list.bullet")
                }
                .tag(1)
            
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(2)
            
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)
            
            EventTypeSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
                }
                .environment(eventStore)
                .environmentObject(calendarManager)
                .environment(notificationManager)
                .environment(geofenceManager ?? GeofenceManager(modelContext: modelContext, eventStore: EventStore(apiClient: apiClient!)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .task {
            // Initialize EventStore with APIClient from environment
            guard let apiClient = apiClient else {
                print("Error: APIClient not available in environment")
                return
            }

            let store = EventStore(apiClient: apiClient)
            eventStore = store

            store.setModelContext(modelContext)
            store.setCalendarManager(calendarManager)

            // Initialize GeofenceManager with dependencies
            let geoManager = GeofenceManager(
                modelContext: modelContext,
                eventStore: store,
                notificationManager: notificationManager
            )
            geofenceManager = geoManager

            // Start monitoring active geofences if authorized
            if geoManager.hasGeofencingAuthorization {
                geoManager.startMonitoringAllGeofences()
            }

            // Give a moment for the UI to render
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Load initial data
            await store.fetchData()

            // Hide loading screen
            withAnimation {
                isLoading = false
            }
        }
    }
}