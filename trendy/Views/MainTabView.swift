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
    @State private var eventStore = EventStore()
    @StateObject private var calendarManager = CalendarManager()
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
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .task {
            eventStore.setModelContext(modelContext)
            eventStore.setCalendarManager(calendarManager)
            
            // Give a moment for the UI to render
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Load initial data
            await eventStore.fetchData()
            
            // Hide loading screen
            withAnimation {
                isLoading = false
            }
        }
    }
}