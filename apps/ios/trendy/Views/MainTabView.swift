//
//  MainTabView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI
import SwiftData
import HealthKit

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.apiClient) private var apiClient
    @Environment(\.foundationModelService) private var foundationModelService
    @Environment(\.scenePhase) private var scenePhase
    @State private var eventStore: EventStore?
    @State private var insightsViewModel = InsightsViewModel()
    @StateObject private var calendarManager = CalendarManager()
    @State private var notificationManager = NotificationManager()
    @State private var geofenceManager: GeofenceManager?
    @State private var healthKitService: HealthKitService?
    @State private var selectedTab = 0
    @State private var isLoading = true

    #if DEBUG
    /// Check if running in screenshot mode for UI tests
    private var isScreenshotMode: Bool {
        let result = ScreenshotMockData.isScreenshotMode
        print("📸 isScreenshotMode check: \(result)")
        print("📸 Arguments: \(ProcessInfo.processInfo.arguments)")
        print("📸 Environment UITEST_SCREENSHOT_MODE: \(ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_MODE"] ?? "nil")")
        return result
    }
    #endif

    var body: some View {
        ZStack {
            #if DEBUG
            // In screenshot mode, skip the loading check for geofenceManager
            if isScreenshotMode {
                if eventStore == nil {
                    LoadingView()
                        .transition(.opacity.combined(with: .scale))
                } else {
                    mainTabContent
                }
            } else {
                if isLoading || eventStore == nil || geofenceManager == nil {
                    LoadingView(
                        syncState: eventStore?.currentSyncState,
                        pendingCount: eventStore?.currentPendingCount
                    )
                    .transition(.opacity.combined(with: .scale))
                } else {
                    mainTabContent
                }
            }
            #else
            if isLoading || eventStore == nil || geofenceManager == nil {
                LoadingView(
                    syncState: eventStore?.currentSyncState,
                    pendingCount: eventStore?.currentPendingCount
                )
                .transition(.opacity.combined(with: .scale))
            } else {
                mainTabContent
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .task {
            #if DEBUG
            if isScreenshotMode {
                await initializeForScreenshotMode()
                return
            }
            #endif
            await initializeNormally()
        }
        .onDisappear {
            // Clean up widget notification observer
            eventStore?.removeWidgetNotificationObserver()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Log.geofence.debug("Scene became active, ensuring regions registered")

                // Ensure geofences are re-registered when app becomes active
                // This handles iOS potentially dropping regions under memory pressure
                geofenceManager?.ensureRegionsRegistered()

                // Sync data and reconcile geofences when app becomes active
                if let store = eventStore {
                    Task {
                        // Refresh HealthKit daily aggregates first to ensure fresh data
                        if let hkService = healthKitService, hkService.hasHealthKitAuthorization {
                            await hkService.refreshDailyAggregates()
                        }

                        // Check network status SYNCHRONOUSLY before making any network calls.
                        // This is critical because when returning from background:
                        // 1. The cached `isOnline` value may be stale (still `true` from before going offline)
                        // 2. NWPathMonitor callbacks run on a background queue and may not have fired yet
                        // 3. If we proceed with stale `true`, the Supabase SDK will try to refresh tokens
                        // 4. Supabase SDK has 60-second default timeout, causing UI freeze
                        //
                        // By checking `monitor.currentPath` synchronously, we get the actual current state.
                        let isCurrentlyOnline = store.checkNetworkPathSynchronously()

                        if isCurrentlyOnline {
                            await store.fetchData()
                        } else {
                            Log.sync.debug("Scene active but offline (sync check) - skipping fetchData")
                            // Still refresh sync state UI to show accurate pending count
                            await store.refreshSyncStateForUI()
                        }

                        // Reconcile geofences with device after sync to pick up server-side changes
                        // (ensureRegionsRegistered already ran above for immediate re-registration)
                        if let geoManager = geofenceManager, geoManager.hasGeofencingAuthorization {
                            let definitions = store.getLocalGeofenceDefinitions()
                            geoManager.reconcileRegions(desired: definitions)
                            #if DEBUG
                            print("📍 App became active - reconciled \(definitions.count) geofences with device")
                            #endif
                        }
                    }
                }
            }
        }
    }

    // MARK: - Main Tab Content

    @ViewBuilder
    private var mainTabContent: some View {
        TabView(selection: $selectedTab) {
            BubblesView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)
                .accessibilityIdentifier("dashboardTab")

            EventListView()
                .tabItem {
                    Label("List", systemImage: "list.bullet")
                }
                .tag(1)
                .accessibilityIdentifier("eventListTab")

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(2)
                .accessibilityIdentifier("calendarTab")

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)
                .accessibilityIdentifier("analyticsTab")

            EventTypeSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
                .accessibilityIdentifier("settingsTab")
        }
        .accessibilityIdentifier("mainTabView")
        .environment(eventStore)
        .environment(insightsViewModel)
        .environmentObject(calendarManager)
        .environment(notificationManager)
        .environment(geofenceManager)
        .environment(healthKitService)
    }

    // MARK: - Initialization Methods

    #if DEBUG
    /// Initialize for screenshot mode - uses local SwiftData only, no network calls
    private func initializeForScreenshotMode() async {
        print("📸 Screenshot mode: Initializing with local-only EventStore")

        // Create a local-only EventStore (no API client needed)
        let store = EventStore()
        store.setModelContext(modelContext)
        store.setCalendarManager(calendarManager)

        eventStore = store

        // Inject mock data if not already present
        ScreenshotMockData.injectMockData(into: modelContext)

        // Load data from SwiftData
        await store.fetchData()

        print("📸 Screenshot mode: Initialization complete with \(store.eventTypes.count) event types")
    }
    #endif

    /// Normal initialization with API client and all services
    private func initializeNormally() async {
        // Initialize EventStore with APIClient from environment
        guard let apiClient = apiClient else {
            print("Error: APIClient not available in environment")
            return
        }

        let store = EventStore(apiClient: apiClient)
        eventStore = store

        store.setModelContext(modelContext)
        store.setCalendarManager(calendarManager)

        // Configure InsightsViewModel with API client
        insightsViewModel.configure(with: apiClient)

        // Configure AI services for insights
        if let foundationModelService = foundationModelService {
            insightsViewModel.configureAI(
                foundationModelService: foundationModelService,
                eventStore: store
            )
        }

        // Initialize GeofenceManager with dependencies
        let geoManager = GeofenceManager(
            modelContext: modelContext,
            eventStore: store,
            notificationManager: notificationManager
        )
        geofenceManager = geoManager

        // Initialize HealthKitService if available
        if HKHealthStore.isHealthDataAvailable() {
            let hkService = HealthKitService(
                modelContext: modelContext,
                eventStore: store,
                notificationManager: notificationManager
            )
            healthKitService = hkService

            // Start monitoring if authorized
            if hkService.hasHealthKitAuthorization {
                hkService.startMonitoringAllConfigurations()
            }
        }

        // Set up widget notification observer to sync widget-created events
        store.setupWidgetNotificationObserver()

        // STEP 1: Load cached data for instant UI display (no sync, no network)
        await store.fetchFromLocalOnly()

        // STEP 2: Show UI immediately with cached data
        withAnimation {
            isLoading = false
        }

        // STEP 3: Reconcile geofences with cached definitions first (instant)
        if geoManager.hasGeofencingAuthorization {
            let definitions = store.getLocalGeofenceDefinitions()
            geoManager.reconcileRegions(desired: definitions)
            Log.geofence.debug("App launch - reconciled geofences with cached definitions", context: .with { ctx in
                ctx.add("count", definitions.count)
            })
        }

        // STEP 4: Start background sync (fire-and-forget, does not block UI)
        // User sees cached data immediately; new data appears as sync completes
        Task {
            await store.fetchData()

            // Re-reconcile geofences after sync completes to pick up server changes
            if geoManager.hasGeofencingAuthorization {
                let updatedDefinitions = store.getLocalGeofenceDefinitions()
                geoManager.reconcileRegions(desired: updatedDefinitions)
                Log.geofence.debug("Post-sync - reconciled geofences with server data", context: .with { ctx in
                    ctx.add("count", updatedDefinitions.count)
                })
            }
        }
    }

}