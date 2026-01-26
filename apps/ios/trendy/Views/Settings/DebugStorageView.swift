//
//  DebugStorageView.swift
//  trendy
//
//  Debug view for inspecting and clearing App Group container storage.
//

import SwiftUI
import SwiftData

struct DebugStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.supabaseService) private var supabaseService
    @Environment(EventStore.self) private var eventStore
    @State private var containerInfo: ContainerInfo?
    @State private var isLoading = true
    @State private var isSyncing = false
    @State private var showingClearConfirmation = false
    @State private var showingClearAndLogoutConfirmation = false
    @State private var showingForceResyncConfirmation = false
    @State private var showingClearSuccess = false
    @State private var showingResyncSuccess = false
    @State private var errorMessage: String?

    // SwiftData counts
    @State private var eventCount = 0
    @State private var eventTypeCount = 0
    @State private var geofenceCount = 0
    @State private var pendingMutationCount = 0
    @State private var propertyDefinitionCount = 0
    @State private var healthKitConfigCount = 0

    // Error messages for failed model counts
    @State private var modelErrors: [String: String] = [:]

    // Sync status diagnostics
    @State private var syncStatusInfo: SyncStatusInfo?
    @State private var isAnalyzingSyncStatus = false

    // Sync geofences
    @State private var isSyncingGeofences = false
    @State private var showingGeofenceSyncSuccess = false
    @State private var geofenceSyncResult: String?

    // Clear mutation queue
    @State private var showingClearMutationsConfirmation = false
    @State private var showingClearMutationsSuccess = false
    @State private var clearMutationsResult: String?

    // User info
    @State private var currentUserId: String = "Loading..."
    @State private var geofenceTestResult: String?

    // Skip cursor
    @State private var showingSkipCursorConfirmation = false
    @State private var showingSkipCursorSuccess = false
    @State private var skipCursorResult: String?
    @State private var isSkippingCursor = false
    @State private var estimatedBacklog: Int = 0

    // Deduplication
    @State private var isDeduplicating = false
    @State private var showingDeduplicationConfirmation = false
    @State private var showingDeduplicationResult = false
    @State private var deduplicationResult: EventStore.DeduplicationResult?
    @State private var duplicateAnalysis: EventStore.DeduplicationResult?

    // Onboarding reset
    @State private var showingResetOnboardingConfirmation = false
    @State private var showingResetOnboardingSuccess = false

    var body: some View {
        List {
            mainContent
        }
        .navigationTitle("Debug Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await loadContainerInfo()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await loadContainerInfo()
            await loadUserId()
        }
        .modifier(ClearDataDialogs(
            showingClearConfirmation: $showingClearConfirmation,
            showingClearSuccess: $showingClearSuccess,
            showingClearAndLogoutConfirmation: $showingClearAndLogoutConfirmation,
            clearAllData: clearAllData,
            logOutAndClearAllData: logOutAndClearAllData
        ))
        .modifier(SyncDialogs(
            showingForceResyncConfirmation: $showingForceResyncConfirmation,
            showingResyncSuccess: $showingResyncSuccess,
            showingGeofenceSyncSuccess: $showingGeofenceSyncSuccess,
            geofenceSyncResult: geofenceSyncResult,
            forceResync: forceResync,
            loadSwiftDataCounts: loadSwiftDataCounts
        ))
        .modifier(MutationDialogs(
            showingClearMutationsConfirmation: $showingClearMutationsConfirmation,
            showingClearMutationsSuccess: $showingClearMutationsSuccess,
            clearMutationsResult: clearMutationsResult,
            clearMutationQueue: clearMutationQueue,
            loadSwiftDataCounts: loadSwiftDataCounts
        ))
        .modifier(SkipCursorDialogs(
            showingSkipCursorConfirmation: $showingSkipCursorConfirmation,
            showingSkipCursorSuccess: $showingSkipCursorSuccess,
            skipCursorResult: skipCursorResult,
            estimatedBacklog: estimatedBacklog,
            skipToLatestCursor: skipToLatestCursor,
            loadSwiftDataCounts: loadSwiftDataCounts
        ))
        .modifier(DeduplicationDialogs(
            showingDeduplicationConfirmation: $showingDeduplicationConfirmation,
            showingDeduplicationResult: $showingDeduplicationResult,
            duplicateAnalysis: duplicateAnalysis,
            deduplicationResult: deduplicationResult,
            performDeduplication: performDeduplication,
            loadSwiftDataCounts: loadSwiftDataCounts
        ))
        .modifier(ResetOnboardingDialogs(
            showingResetOnboardingConfirmation: $showingResetOnboardingConfirmation,
            showingResetOnboardingSuccess: $showingResetOnboardingSuccess,
            resetOnboarding: resetOnboarding
        ))
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            loadingSection
        } else if let info = containerInfo {
            loadedContent(info)
        }

        if let error = errorMessage {
            Section {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Loading storage info...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func loadedContent(_ info: ContainerInfo) -> some View {
        userInfoSection
        appGroupSection(info)
        swiftDataCountsSection
        syncStatusDiagnosticsSection
        filesSection(info)
        noteSection
        syncActionsSection
        dangerZoneSection
    }

    private func appGroupSection(_ info: ContainerInfo) -> some View {
        Section {
            LabeledContent("App Group ID", value: appGroupIdentifier)
            LabeledContent("Container Path") {
                Text(info.containerPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            LabeledContent("Total Size", value: info.formattedTotalSize)
        } header: {
            Text("App Group Container")
        }
    }

    private var userInfoSection: some View {
        Section {
            LabeledContent("User ID") {
                Text(currentUserId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Environment") {
                Text(AppEnvironment.current.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Sync Cursor Key") {
                let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
                Text(cursorKey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Sync Cursor Value") {
                let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
                let cursorValue = UserDefaults.standard.integer(forKey: cursorKey)
                Text("\(cursorValue)")
                    .font(.caption)
                    .foregroundStyle(cursorValue > 0 ? .green : .orange)
            }
        } header: {
            Text("Authentication & Environment")
        }
    }

    private func loadUserId() async {
        if let supabase = supabaseService {
            do {
                currentUserId = try await supabase.getUserId()
            } catch {
                currentUserId = "Error: \(error.localizedDescription)"
            }
        } else {
            currentUserId = "Not logged in"
        }
    }

    private var swiftDataCountsSection: some View {
        Section {
            countRow("Events", count: eventCount, errorKey: "Event")
            countRow("Event Types", count: eventTypeCount, errorKey: "EventType")
            countRow("Geofences", count: geofenceCount, errorKey: "Geofence")
            countRow("Property Definitions", count: propertyDefinitionCount, errorKey: "PropertyDefinition")
            countRow("HealthKit Configs", count: healthKitConfigCount, errorKey: "HealthKitConfiguration")
            countRow("Pending Mutations", count: pendingMutationCount, errorKey: "PendingMutation")
        } header: {
            Text("SwiftData Records")
        } footer: {
            if !modelErrors.isEmpty {
                Text("Errors indicate schema mismatch. Use 'Force Full Resync' to fix.")
            } else {
                Text("These are the number of records in the local SwiftData database.")
            }
        }
    }

    /// Helper to display count with error handling for corrupted tables
    private func countRow(_ label: String, count: Int, errorKey: String? = nil) -> some View {
        LabeledContent(label) {
            if count < 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Error")
                        .foregroundStyle(.red)
                    if let key = errorKey, let errorMsg = modelErrors[key] {
                        Text(errorMsg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Text("\(count)")
            }
        }
    }

    private func filesSection(_ info: ContainerInfo) -> some View {
        Section {
            ForEach(info.files, id: \.path) { file in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.body)
                        Text(file.relativePath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Files (\(info.files.count))")
        } footer: {
            if info.files.isEmpty {
                Text("No files found in container.")
            }
        }
    }

    private var noteSection: some View {
        Section {
            Text("Local data is synced from the backend. If you clear local data while logged in, it will be re-downloaded on next launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Note")
        }
    }

    private var syncActionsSection: some View {
        Section {
            Button {
                showingForceResyncConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Force Full Resync")
                    Spacer()
                    if isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(isSyncing)

            Button {
                Task {
                    await testGeofenceFetch()
                }
            } label: {
                HStack {
                    Image(systemName: "location.circle")
                    Text("Test Geofence Fetch")
                }
            }

            if let result = geofenceTestResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.contains("Error") ? .red : .green)
            }

            // Sync geofences from server
            Button {
                Task {
                    await syncGeofencesFromServer()
                }
            } label: {
                HStack {
                    Image(systemName: "location.north.circle")
                    Text("Sync Geofences from Server")
                    Spacer()
                    if isSyncingGeofences {
                        ProgressView()
                    }
                }
            }
            .disabled(isSyncingGeofences || isSyncing)

            // Clear mutation queue (for retry storm recovery)
            if pendingMutationCount > 0 {
                Button(role: .destructive) {
                    showingClearMutationsConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Clear Mutation Queue (\(pendingMutationCount))")
                    }
                }
                .disabled(isSyncing)
            }

            // Skip change log backlog
            // Now allowed even with pending mutations - they are independent operations
            // The skip cursor operation doesn't affect pending mutations, and sometimes
            // you need to skip the cursor to unblock sync when rate-limited by pull phase
            Button {
                Task {
                    await calculateBacklog()
                    showingSkipCursorConfirmation = true
                }
            } label: {
                HStack {
                    Image(systemName: "forward.end.fill")
                    Text("Skip Change Log Backlog")
                    Spacer()
                    if isSkippingCursor {
                        ProgressView()
                    }
                }
            }
            .disabled(isSkippingCursor || isSyncing)

            // Deduplication
            Button {
                Task {
                    duplicateAnalysis = await eventStore.analyzeDuplicates()
                    showingDeduplicationConfirmation = true
                }
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Remove Duplicate Events")
                    Spacer()
                    if isDeduplicating {
                        ProgressView()
                    }
                }
            }
            .disabled(isDeduplicating || isSyncing)
        } header: {
            Text("Sync Actions")
        } footer: {
            if pendingMutationCount > 0 {
                Text("'Clear Mutation Queue' abandons unsynced changes. 'Skip Change Log Backlog' jumps cursor to latest - safe even with pending mutations.")
            } else {
                Text("'Skip Change Log Backlog' jumps cursor to latest when stuck with thousands of stale entries. 'Remove Duplicate Events' cleans up HealthKit duplicates.")
            }
        }
    }

    private func syncGeofencesFromServer() async {
        isSyncingGeofences = true
        defer { isSyncingGeofences = false }

        do {
            let count = try await eventStore.syncGeofencesFromServer()
            if count > 0 {
                geofenceSyncResult = "Successfully synced \(count) geofence(s) from the server."
            } else {
                geofenceSyncResult = "No geofences found on the server, or you are offline."
            }
            showingGeofenceSyncSuccess = true
        } catch {
            geofenceSyncResult = "Error: \(error.localizedDescription)"
            showingGeofenceSyncSuccess = true
        }
    }

    private func clearMutationQueue() async {
        let clearedCount = await eventStore.clearPendingMutations()
        if clearedCount > 0 {
            clearMutationsResult = "Cleared \(clearedCount) pending mutation(s). Circuit breaker has been reset."
        } else {
            clearMutationsResult = "No mutations to clear."
        }
        showingClearMutationsSuccess = true
    }

    private func calculateBacklog() async {
        let cursorKey = "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
        let currentCursor = UserDefaults.standard.integer(forKey: cursorKey)

        do {
            let latestCursor = try await eventStore.getLatestCursor()
            estimatedBacklog = max(0, Int(latestCursor) - currentCursor)
        } catch {
            estimatedBacklog = 0
        }
    }

    private func skipToLatestCursor() async {
        isSkippingCursor = true
        defer { isSkippingCursor = false }

        do {
            let newCursor = try await eventStore.skipToLatestCursor()
            skipCursorResult = "Cursor updated to \(newCursor). Next sync will start from here."
            showingSkipCursorSuccess = true
        } catch {
            skipCursorResult = "Error: \(error.localizedDescription)"
            showingSkipCursorSuccess = true
        }
    }

    private func performDeduplication() async {
        isDeduplicating = true
        defer { isDeduplicating = false }

        deduplicationResult = await eventStore.deduplicateHealthKitEvents()
        showingDeduplicationResult = true
    }

    private func testGeofenceFetch() async {
        geofenceTestResult = "Fetching via EventStore..."
        do {
            // Use EventStore's API client to fetch geofences
            let geofences = try await eventStore.testFetchGeofences()
            geofenceTestResult = "Success: \(geofences.count) geofences returned"
            Log.geofence.debug("Test geofence fetch succeeded", context: .with { ctx in
                ctx.add("count", geofences.count)
            })
        } catch {
            geofenceTestResult = "Error: \(error.localizedDescription)"
            Log.geofence.debug("Test geofence fetch failed", error: error)
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Clear Local Data Only")
                }
            }

            Button(role: .destructive) {
                showingClearAndLogoutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.circle.fill")
                    Text("Log Out & Clear All Data")
                }
            }

            Button(role: .destructive) {
                showingResetOnboardingConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                    Text("Reset Onboarding (Debug)")
                }
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("'Log Out & Clear All Data' will sign you out and delete all local data. 'Reset Onboarding' clears onboarding state to test the flow again.")
        }
    }

    // MARK: - Sync Status Diagnostics

    @ViewBuilder
    private var syncStatusDiagnosticsSection: some View {
        Section {
            if isAnalyzingSyncStatus {
                HStack {
                    ProgressView()
                    Text("Analyzing sync status...")
                        .foregroundStyle(.secondary)
                }
            } else if let info = syncStatusInfo {
                syncStatusInfoContent(info)
            } else {
                analyzeButton
            }
        } header: {
            Text("Sync Status Diagnostics")
        } footer: {
            syncStatusDiagnosticsFooter
        }
    }

    @ViewBuilder
    private func syncStatusInfoContent(_ info: SyncStatusInfo) -> some View {
        LabeledContent("Events pending sync") {
            Text("\(info.eventsPending)")
                .foregroundStyle(info.eventsPending > 0 ? .orange : .secondary)
        }

        LabeledContent("Events synced") {
            Text("\(info.eventsSynced)")
                .foregroundStyle(.secondary)
        }

        LabeledContent("Events failed") {
            Text("\(info.eventsFailed)")
                .foregroundStyle(info.eventsFailed > 0 ? .red : .secondary)
        }

        LabeledContent("EventTypes pending sync") {
            Text("\(info.eventTypesPending)")
                .foregroundStyle(info.eventTypesPending > 0 ? .orange : .secondary)
        }

        LabeledContent("EventTypes synced") {
            Text("\(info.eventTypesSynced)")
                .foregroundStyle(.secondary)
        }

        LabeledContent("Same name EventTypes") {
            Text("\(info.eventTypesWithSameName)")
                .foregroundStyle(info.eventTypesWithSameName > 0 ? .orange : .secondary)
        }

        if !info.details.isEmpty {
            DisclosureGroup("Details") {
                ForEach(info.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var analyzeButton: some View {
        Button {
            Task {
                await analyzeSyncStatus()
            }
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Analyze Sync Status")
            }
        }
    }

    @ViewBuilder
    private var syncStatusDiagnosticsFooter: some View {
        if let info = syncStatusInfo {
            if info.hasPendingItems {
                Text("Some items are pending sync. They will sync when the app is online.")
            } else {
                Text("All items are synced.")
            }
        } else {
            Text("Tap 'Analyze' to check sync status in the local database.")
        }
    }

    // MARK: - Sync Actions

    private func forceResync() async {
        isSyncing = true
        await eventStore.forceFullResync()
        await loadSwiftDataCounts()
        isSyncing = false
        showingResyncSuccess = true
    }

    // MARK: - Data Loading

    private func loadContainerInfo() async {
        isLoading = true
        errorMessage = nil

        // Load SwiftData counts
        await loadSwiftDataCounts()

        // Load file system info
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            errorMessage = "Could not access App Group container"
            isLoading = false
            return
        }

        var files: [FileInfo] = []
        var totalSize: Int64 = 0

        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: containerURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if resourceValues.isDirectory == false {
                        let size = Int64(resourceValues.fileSize ?? 0)
                        totalSize += size

                        let relativePath = fileURL.path.replacingOccurrences(of: containerURL.path, with: "")
                        files.append(FileInfo(
                            name: fileURL.lastPathComponent,
                            path: fileURL.path,
                            relativePath: relativePath,
                            size: size
                        ))
                    }
                } catch {
                    Log.data.debug("Error reading file", error: error)
                }
            }
        }

        // Sort files by size (largest first)
        files.sort { $0.size > $1.size }

        containerInfo = ContainerInfo(
            containerPath: containerURL.path,
            files: files,
            totalSize: totalSize
        )

        isLoading = false
    }

    private func loadSwiftDataCounts() async {
        // Use mainContext to avoid SQLite file locking issues with concurrent ModelContext instances.
        // Creating new ModelContext(container) can cause "default.store couldn't be opened" errors.
        let context = modelContext.container.mainContext

        // Clear previous errors
        modelErrors.removeAll()

        // Helper to safely get count and capture errors
        func safeCount<T: PersistentModel>(_ type: T.Type, name: String) -> Int {
            do {
                let count = try context.fetchCount(FetchDescriptor<T>())
                guard count >= 0 && count < 10_000_000 else {
                    modelErrors[name] = "Invalid count: \(count)"
                    return -1
                }
                return count
            } catch {
                modelErrors[name] = String(describing: error).prefix(100).description
                return -1
            }
        }

        eventCount = safeCount(Event.self, name: "Event")
        eventTypeCount = safeCount(EventType.self, name: "EventType")
        geofenceCount = safeCount(Geofence.self, name: "Geofence")
        pendingMutationCount = safeCount(PendingMutation.self, name: "PendingMutation")
        propertyDefinitionCount = safeCount(PropertyDefinition.self, name: "PropertyDefinition")
        healthKitConfigCount = safeCount(HealthKitConfiguration.self, name: "HealthKitConfiguration")
    }

    // MARK: - Clear Data

    private func logOutAndClearAllData() async {
        // First, sign out from Supabase
        if let supabase = supabaseService {
            do {
                try await supabase.signOut()
                Log.auth.info("Signed out from Supabase for data clear")
            } catch {
                Log.auth.warning("Error signing out during data clear", error: error)
                // Continue anyway - we still want to clear local data
            }
        }

        // Then clear all local data
        clearAllData()
    }

    private func clearAllData() {
        // Don't try to delete SwiftData records while the app is running -
        // this causes crashes because other parts of the app hold references.
        // Instead, just mark for deletion on next launch and exit immediately.

        // Clear UserDefaults for this app group
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
            defaults.synchronize()
            Log.data.info("Cleared App Group UserDefaults", context: .with { ctx in
                ctx.add("app_group", appGroupIdentifier)
            })
        }

        // Clear standard UserDefaults app-specific keys
        let standardDefaults = UserDefaults.standard
        let keysToRemove = standardDefaults.dictionaryRepresentation().keys.filter { key in
            // Remove app-specific keys (adjust patterns as needed)
            key.hasPrefix("migration") ||
            key.hasPrefix("sync") ||
            key.hasPrefix("last") ||
            key.hasPrefix("has") ||
            key.contains("trendy") ||
            key.contains("Trendy")
        }
        for key in keysToRemove {
            standardDefaults.removeObject(forKey: key)
        }
        Log.data.info("Cleared standard UserDefaults keys", context: .with { ctx in
            ctx.add("keys_removed", keysToRemove.count)
        })

        // Mark for file deletion on next launch
        // This flag is checked in trendyApp.swift BEFORE creating the ModelContainer
        UserDefaults.standard.set(true, forKey: "debug_clear_container_on_launch")
        UserDefaults.standard.synchronize()
        Log.data.info("Set flag to clear container on next launch")

        showingClearSuccess = true
    }

    private func resetOnboarding() async {
        // Clear OnboardingCache (all users)
        OnboardingCache.clearAll()
        Log.data.info("Cleared OnboardingCache")

        // Clear onboarding-related UserDefaults keys
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "onboarding_current_step")
        defaults.removeObject(forKey: "onboarding_start_time")
        defaults.removeObject(forKey: "onboarding_complete")
        defaults.synchronize()
        Log.data.info("Cleared onboarding UserDefaults keys")

        // Sign out from Supabase
        if let supabase = supabaseService {
            do {
                try await supabase.signOut()
                Log.auth.info("Signed out from Supabase for onboarding reset")
            } catch {
                Log.auth.warning("Error signing out during onboarding reset", error: error)
                // Continue anyway - we still want to reset onboarding
            }
        }

        showingResetOnboardingSuccess = true
    }
}

// MARK: - Data Models

struct ContainerInfo {
    let containerPath: String
    let files: [FileInfo]
    let totalSize: Int64

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

struct FileInfo {
    let name: String
    let path: String
    let relativePath: String
    let size: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct SyncStatusInfo {
    // Events
    var eventsPending: Int = 0
    var eventsSynced: Int = 0
    var eventsFailed: Int = 0

    // EventTypes
    var eventTypesPending: Int = 0
    var eventTypesSynced: Int = 0
    var eventTypesWithSameName: Int = 0

    // Details for display
    var details: [String] = []

    var hasPendingItems: Bool {
        eventsPending > 0 || eventTypesPending > 0 || eventsFailed > 0
    }
}

// MARK: - Sync Status Analysis Extension

extension DebugStorageView {
    func analyzeSyncStatus() async {
        isAnalyzingSyncStatus = true
        defer { isAnalyzingSyncStatus = false }

        // Use mainContext to avoid SQLite file locking issues with concurrent ModelContext instances.
        let context = modelContext.container.mainContext
        var info = SyncStatusInfo()

        do {
            // Fetch all events
            let allEvents = try context.fetch(FetchDescriptor<Event>())

            // Count by sync status
            let pendingStatus = SyncStatus.pending.rawValue
            let syncedStatus = SyncStatus.synced.rawValue
            let failedStatus = SyncStatus.failed.rawValue

            info.eventsPending = allEvents.filter { $0.syncStatusRaw == pendingStatus }.count
            info.eventsSynced = allEvents.filter { $0.syncStatusRaw == syncedStatus }.count
            info.eventsFailed = allEvents.filter { $0.syncStatusRaw == failedStatus }.count

            if info.eventsPending > 0 {
                info.details.append("Events pending sync: \(info.eventsPending)")
                let pendingEvents = allEvents.filter { $0.syncStatusRaw == pendingStatus }
                for event in pendingEvents.prefix(5) {
                    let typeName = event.eventType?.name ?? "Unknown"
                    let dateStr = event.timestamp.formatted(date: .abbreviated, time: .shortened)
                    info.details.append("  - \(typeName) @ \(dateStr)")
                }
                if info.eventsPending > 5 {
                    info.details.append("  ... and \(info.eventsPending - 5) more")
                }
            }

            if info.eventsFailed > 0 {
                info.details.append("Events failed to sync: \(info.eventsFailed)")
            }

            // Fetch all event types
            let allEventTypes = try context.fetch(FetchDescriptor<EventType>())

            info.eventTypesPending = allEventTypes.filter { $0.syncStatusRaw == pendingStatus }.count
            info.eventTypesSynced = allEventTypes.filter { $0.syncStatusRaw == syncedStatus }.count

            // Check for EventTypes with same name (potential duplicates)
            let typesByName = Dictionary(grouping: allEventTypes) { $0.name }
            let sameNameGroups = typesByName.filter { $0.value.count > 1 }
            info.eventTypesWithSameName = sameNameGroups.values.reduce(0) { $0 + $1.count - 1 }

            if !sameNameGroups.isEmpty {
                info.details.append("Same name EventType groups: \(sameNameGroups.count)")
                for (name, types) in sameNameGroups.prefix(5) {
                    let ids = types.map { $0.id.prefix(8) }.joined(separator: ", ")
                    info.details.append("  - \"\(name)\": \(types.count) copies (ids: \(ids))")
                }
            }

        } catch {
            info.details.append("Error analyzing: \(error.localizedDescription)")
        }

        syncStatusInfo = info
    }
}

// MARK: - Dialog ViewModifiers (extracted to help Swift type-checker)

private struct ClearDataDialogs: ViewModifier {
    @Binding var showingClearConfirmation: Bool
    @Binding var showingClearSuccess: Bool
    @Binding var showingClearAndLogoutConfirmation: Bool
    let clearAllData: () -> Void
    let logOutAndClearAllData: () async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Clear All Data?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Data", role: .destructive) {
                    clearAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all local data. You will need to restart the app. This cannot be undone.")
            }
            .alert("Data Cleared", isPresented: $showingClearSuccess) {
                Button("OK") {
                    exit(0)
                }
            } message: {
                Text("All local data has been cleared. The app will now close. Please reopen it to start fresh.")
            }
            .confirmationDialog(
                "Log Out & Clear All Data?",
                isPresented: $showingClearAndLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Log Out & Clear All", role: .destructive) {
                    Task {
                        await logOutAndClearAllData()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will sign you out and delete all local data. The app will restart without syncing from the server. You'll need to log in again.")
            }
    }
}

private struct SyncDialogs: ViewModifier {
    @Binding var showingForceResyncConfirmation: Bool
    @Binding var showingResyncSuccess: Bool
    @Binding var showingGeofenceSyncSuccess: Bool
    let geofenceSyncResult: String?
    let forceResync: () async -> Void
    let loadSwiftDataCounts: () async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Force Full Resync?",
                isPresented: $showingForceResyncConfirmation,
                titleVisibility: .visible
            ) {
                Button("Resync Now") {
                    Task {
                        await forceResync()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset the sync cursor, re-download all data from the backend, and remove any stale local data.")
            }
            .alert("Resync Complete", isPresented: $showingResyncSuccess) {
                Button("OK") {}
            } message: {
                Text("All data has been re-synced from the backend. Stale local data has been removed.")
            }
            .alert("Geofence Sync Complete", isPresented: $showingGeofenceSyncSuccess) {
                Button("OK") {
                    Task {
                        await loadSwiftDataCounts()
                    }
                }
            } message: {
                Text(geofenceSyncResult ?? "Geofences have been synced from the server.")
            }
    }
}

private struct MutationDialogs: ViewModifier {
    @Binding var showingClearMutationsConfirmation: Bool
    @Binding var showingClearMutationsSuccess: Bool
    let clearMutationsResult: String?
    let clearMutationQueue: () async -> Void
    let loadSwiftDataCounts: () async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Clear Mutation Queue?",
                isPresented: $showingClearMutationsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Queue", role: .destructive) {
                    Task {
                        await clearMutationQueue()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear all pending sync mutations. Any unsynced local changes will be lost and NOT synced to the backend. Use this to recover from a retry storm.")
            }
            .alert("Mutation Queue Cleared", isPresented: $showingClearMutationsSuccess) {
                Button("OK") {
                    Task {
                        await loadSwiftDataCounts()
                    }
                }
            } message: {
                Text(clearMutationsResult ?? "The mutation queue has been cleared.")
            }
    }
}

private struct SkipCursorDialogs: ViewModifier {
    @Binding var showingSkipCursorConfirmation: Bool
    @Binding var showingSkipCursorSuccess: Bool
    let skipCursorResult: String?
    let estimatedBacklog: Int
    let skipToLatestCursor: () async -> Void
    let loadSwiftDataCounts: () async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Skip Change Log Backlog?",
                isPresented: $showingSkipCursorConfirmation,
                titleVisibility: .visible
            ) {
                Button("Skip to Latest", role: .destructive) {
                    Task {
                        await skipToLatestCursor()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will skip downloading ~\(estimatedBacklog) change log entries. This is SAFE - it only affects which server changes to download, not your pending local changes. Use this when sync is stuck due to rate limiting.")
            }
            .alert("Cursor Skipped", isPresented: $showingSkipCursorSuccess) {
                Button("OK") {
                    Task {
                        await loadSwiftDataCounts()
                    }
                }
            } message: {
                Text(skipCursorResult ?? "Cursor has been updated to latest.")
            }
    }
}

private struct DeduplicationDialogs: ViewModifier {
    @Binding var showingDeduplicationConfirmation: Bool
    @Binding var showingDeduplicationResult: Bool
    let duplicateAnalysis: EventStore.DeduplicationResult?
    let deduplicationResult: EventStore.DeduplicationResult?
    let performDeduplication: () async -> Void
    let loadSwiftDataCounts: () async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove Duplicate Events?",
                isPresented: $showingDeduplicationConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Duplicates", role: .destructive) {
                    Task {
                        await performDeduplication()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let analysis = duplicateAnalysis {
                    if analysis.duplicatesFound > 0 {
                        Text("Found \(analysis.duplicatesFound) duplicate HealthKit events in \(analysis.groupsProcessed) groups. This will keep the synced version (or oldest) and remove duplicates.")
                    } else {
                        Text("No duplicate HealthKit events found.")
                    }
                } else {
                    Text("Analyzing duplicates...")
                }
            }
            .alert("Deduplication Complete", isPresented: $showingDeduplicationResult) {
                Button("OK") {
                    Task {
                        await loadSwiftDataCounts()
                    }
                }
            } message: {
                if let result = deduplicationResult {
                    if result.duplicatesRemoved > 0 {
                        Text("Removed \(result.duplicatesRemoved) duplicate events from \(result.groupsProcessed) groups.")
                    } else if result.duplicatesFound == 0 {
                        Text("No duplicate events found.")
                    } else {
                        Text("Processed \(result.groupsProcessed) groups.")
                    }
                } else {
                    Text("Deduplication completed.")
                }
            }
    }
}

private struct ResetOnboardingDialogs: ViewModifier {
    @Binding var showingResetOnboardingConfirmation: Bool
    @Binding var showingResetOnboardingSuccess: Bool
    let resetOnboarding: () async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Reset Onboarding?",
                isPresented: $showingResetOnboardingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Onboarding", role: .destructive) {
                    Task {
                        await resetOnboarding()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear all onboarding progress and sign you out. The app will close so you can restart and go through onboarding again.")
            }
            .alert("Onboarding Reset", isPresented: $showingResetOnboardingSuccess) {
                Button("OK") {
                    exit(0)
                }
            } message: {
                Text("Onboarding has been reset. The app will now close. Reopen to start onboarding fresh.")
            }
    }
}

#Preview {
    NavigationStack {
        DebugStorageView()
    }
}
