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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SyncStatusViewModel.self) private var syncStatusViewModel
    @Environment(SyncHistoryStore.self) private var syncHistoryStore
    @State private var eventStore: EventStore?
    @State private var insightsViewModel = InsightsViewModel()
    @StateObject private var calendarManager = CalendarManager()
    @State private var notificationManager = NotificationManager()
    @State private var geofenceManager: GeofenceManager?
    @State private var healthKitService: HealthKitService?
    @State private var selectedTab = 0
    @State private var isLoading = true
    @State private var showIndicator = false
    @State private var successHideTask: Task<Void, Never>?

    #if DEBUG
    /// Check if running in screenshot mode for UI tests
    private var isScreenshotMode: Bool {
        let result = ScreenshotMockData.isScreenshotMode
        Log.ui.debug("isScreenshotMode check", context: .with { ctx in
            ctx.add("result", result)
            ctx.add("uitest_env", ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_MODE"] ?? "nil")
        })
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
                        // CRITICAL: PersistenceController already refreshed its mainContext via
                        // UIScene.willEnterForegroundNotification (fires before scenePhase=.active).
                        // Now reset SyncEngine's cached DataStore and update EventStore's reference.
                        await store.resetSyncEngineDataStore()

                        // Import any pending events created by the widget while we were in background
                        await store.importPendingWidgetEvents()

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
                            Log.geofence.debug("App became active - reconciled geofences with device", context: .with { ctx in
                                ctx.add("count", definitions.count)
                            })
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
            // Dashboard is the default tab (tag 0) - render immediately for fast startup
            BubblesView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)
                .accessibilityIdentifier("dashboardTab")

            // Non-default tabs wrapped in LazyView to defer rendering until SELECTED
            // LazyView uses selection binding to truly defer - onAppear doesn't work
            // because TabView fires onAppear for ALL tabs when measuring layout
            LazyView(tag: 1, selection: $selectedTab) {
                EventListView()
            }
            .tabItem {
                Label("List", systemImage: "list.bullet")
            }
            .tag(1)
            .accessibilityIdentifier("eventListTab")

            LazyView(tag: 2, selection: $selectedTab) {
                CalendarView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(2)
            .accessibilityIdentifier("calendarTab")

            LazyView(tag: 3, selection: $selectedTab) {
                AnalyticsView()
            }
            .tabItem {
                Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(3)
            .accessibilityIdentifier("analyticsTab")

            LazyView(tag: 4, selection: $selectedTab) {
                EventTypeSettingsView()
            }
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
        .overlay(alignment: .bottom) {
            if showIndicator {
                SyncIndicatorView(
                    displayState: syncStatusViewModel.displayState,
                    onRetry: {
                        await eventStore?.fetchData()
                    }
                )
                .padding(.bottom, 52) // Position above tab bar (49pt height + margin)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: showIndicator)
        .onChange(of: syncStatusViewModel.shouldShowIndicator) { _, shouldShow in
            showIndicator = shouldShow
        }
        .onChange(of: syncStatusViewModel.displayState) { _, newState in
            // Handle success auto-hide: when displayState becomes .success,
            // start a 2-second timer then hide the indicator
            if case .success = newState {
                // Cancel any existing hide task
                successHideTask?.cancel()
                successHideTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                            showIndicator = false
                        }
                    }
                }
            }
        }
        .task(id: eventStore?.currentSyncState) {
            // Refresh SyncStatusViewModel when EventStore sync state changes
            if let store = eventStore {
                await syncStatusViewModel.refresh(from: store)
            }
        }
    }

    // MARK: - Initialization Methods

    #if DEBUG
    /// Initialize for screenshot mode - uses local SwiftData only, no network calls
    private func initializeForScreenshotMode() async {
        Log.ui.debug("Screenshot mode: Initializing with local-only EventStore")

        // Create a local-only EventStore (no API client needed)
        let store = EventStore()
        store.setModelContext(modelContext)
        store.setCalendarManager(calendarManager)

        eventStore = store

        // Inject mock data if not already present
        ScreenshotMockData.injectMockData(into: modelContext)

        // Load data from SwiftData
        await store.fetchData()

        Log.ui.debug("Screenshot mode: Initialization complete", context: .with { ctx in
            ctx.add("event_types_count", store.eventTypes.count)
        })
    }
    #endif

    /// Normal initialization with API client and all services
    private func initializeNormally() async {
        // Initialize EventStore with APIClient from environment
        guard let apiClient = apiClient else {
            Log.ui.error("APIClient not available in environment")
            return
        }

        let store = EventStore(apiClient: apiClient)
        eventStore = store

        store.setModelContext(modelContext, syncHistoryStore: syncHistoryStore)
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