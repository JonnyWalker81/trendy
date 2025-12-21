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
    @State private var queuedOperationCount = 0
    @State private var propertyDefinitionCount = 0
    @State private var healthKitConfigCount = 0

    // Duplicate diagnostics
    @State private var duplicateInfo: DuplicateInfo?
    @State private var isAnalyzingDuplicates = false
    @State private var showingCleanupConfirmation = false
    @State private var showingCleanupSuccess = false
    @State private var cleanupResult: String?

    // User info
    @State private var currentUserId: String = "Loading..."
    @State private var geofenceTestResult: String?

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
        .confirmationDialog(
            "Clean Up Duplicates?",
            isPresented: $showingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Up", role: .destructive) {
                Task {
                    await cleanupDuplicates()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove orphaned records (without serverId) and merge records with duplicate serverIds. This cannot be undone.")
        }
        .alert("Cleanup Complete", isPresented: $showingCleanupSuccess) {
            Button("OK") {
                Task {
                    await analyzeDuplicates()
                    await loadSwiftDataCounts()
                }
            }
        } message: {
            Text(cleanupResult ?? "Duplicate records have been cleaned up.")
        }
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
        duplicateDiagnosticsSection
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
            LabeledContent("Events", value: "\(eventCount)")
            LabeledContent("Event Types", value: "\(eventTypeCount)")
            LabeledContent("Geofences", value: "\(geofenceCount)")
            LabeledContent("Property Definitions", value: "\(propertyDefinitionCount)")
            LabeledContent("HealthKit Configs", value: "\(healthKitConfigCount)")
            LabeledContent("Pending Mutations", value: "\(pendingMutationCount)")
            LabeledContent("Queued Operations", value: "\(queuedOperationCount)")
        } header: {
            Text("SwiftData Records")
        } footer: {
            Text("These are the number of records in the local SwiftData database.")
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
        } header: {
            Text("Sync Actions")
        } footer: {
            Text("Resets the sync cursor and re-downloads all data from the backend. This will remove any stale local data that doesn't exist on the server.")
        }
    }

    private func testGeofenceFetch() async {
        geofenceTestResult = "Fetching via EventStore..."
        do {
            // Use EventStore's API client to fetch geofences
            let geofences = try await eventStore.testFetchGeofences()
            geofenceTestResult = "Success: \(geofences.count) geofences returned"
            for (i, g) in geofences.prefix(5).enumerated() {
                print("Geofence \(i): \(g.name) - \(g.id)")
            }
        } catch {
            geofenceTestResult = "Error: \(error.localizedDescription)"
            print("Geofence fetch error: \(error)")
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
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("'Log Out & Clear All Data' will sign you out and delete all local data. The app will start fresh without syncing from the server.")
        }
    }

    // MARK: - Extracted Subviews

    @ViewBuilder
    private var duplicateDiagnosticsSection: some View {
        Section {
            if isAnalyzingDuplicates {
                HStack {
                    ProgressView()
                    Text("Analyzing duplicates...")
                        .foregroundStyle(.secondary)
                }
            } else if let info = duplicateInfo {
                duplicateInfoContent(info)
            } else {
                analyzeButton
            }
        } header: {
            Text("Duplicate Diagnostics")
        } footer: {
            duplicateDiagnosticsFooter
        }
    }

    @ViewBuilder
    private func duplicateInfoContent(_ info: DuplicateInfo) -> some View {
        LabeledContent("Events without serverId") {
            Text("\(info.eventsWithNilServerId)")
                .foregroundStyle(info.eventsWithNilServerId > 0 ? .orange : .secondary)
        }

        LabeledContent("Duplicate serverIds (Events)") {
            Text("\(info.duplicateEventServerIds)")
                .foregroundStyle(info.duplicateEventServerIds > 0 ? .red : .secondary)
        }

        LabeledContent("Same timestamp+type") {
            Text("\(info.eventsWithSameTimestampAndType)")
                .foregroundStyle(info.eventsWithSameTimestampAndType > 0 ? .orange : .secondary)
        }

        LabeledContent("EventTypes without serverId") {
            Text("\(info.eventTypesWithNilServerId)")
                .foregroundStyle(info.eventTypesWithNilServerId > 0 ? .orange : .secondary)
        }

        LabeledContent("Duplicate serverIds (Types)") {
            Text("\(info.duplicateEventTypeServerIds)")
                .foregroundStyle(info.duplicateEventTypeServerIds > 0 ? .red : .secondary)
        }

        LabeledContent("Same name EventTypes") {
            Text("\(info.eventTypesWithSameName)")
                .foregroundStyle(info.eventTypesWithSameName > 0 ? .orange : .secondary)
        }

        if !info.duplicateDetails.isEmpty {
            DisclosureGroup("Duplicate Details") {
                ForEach(info.duplicateDetails, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if info.hasDuplicates {
            Button {
                showingCleanupConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Clean Up Duplicates")
                }
            }
            .foregroundStyle(.orange)
        }
    }

    private var analyzeButton: some View {
        Button {
            Task {
                await analyzeDuplicates()
            }
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Analyze for Duplicates")
            }
        }
    }

    @ViewBuilder
    private var duplicateDiagnosticsFooter: some View {
        if let info = duplicateInfo {
            if info.hasDuplicates {
                Text("Duplicates detected. Use 'Clean Up Duplicates' to remove orphaned records and merge duplicate serverIds.")
            } else {
                Text("No duplicates detected.")
            }
        } else {
            Text("Tap 'Analyze' to check for duplicate records in the local database.")
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
                    print("Error reading file: \(error)")
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
        do {
            // Create a fresh context to ensure we see the latest persisted data
            // This is necessary because SyncEngine uses its own context, and the
            // Environment's modelContext may have stale cached data
            let freshContext = ModelContext(modelContext.container)

            eventCount = try freshContext.fetchCount(FetchDescriptor<Event>())
            eventTypeCount = try freshContext.fetchCount(FetchDescriptor<EventType>())
            geofenceCount = try freshContext.fetchCount(FetchDescriptor<Geofence>())
            pendingMutationCount = try freshContext.fetchCount(FetchDescriptor<PendingMutation>())
            queuedOperationCount = try freshContext.fetchCount(FetchDescriptor<QueuedOperation>())
            propertyDefinitionCount = try freshContext.fetchCount(FetchDescriptor<PropertyDefinition>())
            healthKitConfigCount = try freshContext.fetchCount(FetchDescriptor<HealthKitConfiguration>())
        } catch {
            print("Error loading SwiftData counts: \(error)")
        }
    }

    // MARK: - Clear Data

    private func logOutAndClearAllData() async {
        // First, sign out from Supabase
        if let supabase = supabaseService {
            do {
                try await supabase.signOut()
                print("✅ Signed out from Supabase")
            } catch {
                print("⚠️ Error signing out: \(error)")
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
            print("✅ Cleared App Group UserDefaults")
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
        print("✅ Cleared \(keysToRemove.count) standard UserDefaults keys")

        // Mark for file deletion on next launch
        // This flag is checked in trendyApp.swift BEFORE creating the ModelContainer
        UserDefaults.standard.set(true, forKey: "debug_clear_container_on_launch")
        UserDefaults.standard.synchronize()
        print("✅ Set flag to clear container on next launch")

        showingClearSuccess = true
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

struct DuplicateInfo {
    // Events
    var eventsWithNilServerId: Int = 0
    var duplicateEventServerIds: Int = 0
    var eventsWithSameTimestampAndType: Int = 0

    // EventTypes
    var eventTypesWithNilServerId: Int = 0
    var duplicateEventTypeServerIds: Int = 0
    var eventTypesWithSameName: Int = 0

    // Details for display
    var duplicateDetails: [String] = []

    var hasDuplicates: Bool {
        eventsWithNilServerId > 0 ||
        duplicateEventServerIds > 0 ||
        eventsWithSameTimestampAndType > 0 ||
        eventTypesWithNilServerId > 0 ||
        duplicateEventTypeServerIds > 0 ||
        eventTypesWithSameName > 0
    }
}

// MARK: - Duplicate Analysis Extension

extension DebugStorageView {
    func analyzeDuplicates() async {
        isAnalyzingDuplicates = true
        defer { isAnalyzingDuplicates = false }

        let freshContext = ModelContext(modelContext.container)
        var info = DuplicateInfo()

        do {
            // Fetch all events
            let allEvents = try freshContext.fetch(FetchDescriptor<Event>())

            // 1. Events with nil serverId
            let eventsNilServerId = allEvents.filter { $0.serverId == nil }
            info.eventsWithNilServerId = eventsNilServerId.count

            if info.eventsWithNilServerId > 0 {
                info.duplicateDetails.append("Events without serverId: \(info.eventsWithNilServerId)")
                for event in eventsNilServerId.prefix(5) {
                    let typeName = event.eventType?.name ?? "Unknown"
                    let dateStr = event.timestamp.formatted(date: .abbreviated, time: .shortened)
                    info.duplicateDetails.append("  - \(typeName) @ \(dateStr)")
                }
                if eventsNilServerId.count > 5 {
                    info.duplicateDetails.append("  ... and \(eventsNilServerId.count - 5) more")
                }
            }

            // 2. Events with duplicate serverId
            let eventsByServerId = Dictionary(grouping: allEvents.filter { $0.serverId != nil }) { $0.serverId! }
            let duplicateServerIdGroups = eventsByServerId.filter { $0.value.count > 1 }
            info.duplicateEventServerIds = duplicateServerIdGroups.values.reduce(0) { $0 + $1.count - 1 }

            if !duplicateServerIdGroups.isEmpty {
                info.duplicateDetails.append("Duplicate serverId groups: \(duplicateServerIdGroups.count)")
                for (serverId, events) in duplicateServerIdGroups.prefix(3) {
                    info.duplicateDetails.append("  - serverId \(serverId.prefix(8))...: \(events.count) copies")
                }
            }

            // 3. Events with same timestamp + eventType (potential content duplicates)
            let eventsByContent = Dictionary(grouping: allEvents) { event -> String in
                let typeId = event.eventType?.id.uuidString ?? "nil"
                let timestamp = event.timestamp.timeIntervalSince1970
                return "\(typeId)-\(timestamp)"
            }
            let contentDuplicates = eventsByContent.filter { $0.value.count > 1 }
            info.eventsWithSameTimestampAndType = contentDuplicates.values.reduce(0) { $0 + $1.count - 1 }

            if !contentDuplicates.isEmpty {
                info.duplicateDetails.append("Same timestamp+type groups: \(contentDuplicates.count)")
                for (_, events) in contentDuplicates.prefix(3) {
                    if let first = events.first {
                        let typeName = first.eventType?.name ?? "Unknown"
                        let dateStr = first.timestamp.formatted(date: .abbreviated, time: .shortened)
                        info.duplicateDetails.append("  - \(typeName) @ \(dateStr): \(events.count) copies")
                    }
                }
            }

            // Fetch all event types
            let allEventTypes = try freshContext.fetch(FetchDescriptor<EventType>())

            // 4. EventTypes with nil serverId
            let typesNilServerId = allEventTypes.filter { $0.serverId == nil }
            info.eventTypesWithNilServerId = typesNilServerId.count

            if info.eventTypesWithNilServerId > 0 {
                info.duplicateDetails.append("EventTypes without serverId: \(info.eventTypesWithNilServerId)")
                for eventType in typesNilServerId.prefix(5) {
                    info.duplicateDetails.append("  - \(eventType.name)")
                }
            }

            // 5. EventTypes with duplicate serverId
            let typesByServerId = Dictionary(grouping: allEventTypes.filter { $0.serverId != nil }) { $0.serverId! }
            let duplicateTypeServerIdGroups = typesByServerId.filter { $0.value.count > 1 }
            info.duplicateEventTypeServerIds = duplicateTypeServerIdGroups.values.reduce(0) { $0 + $1.count - 1 }

            // 6. EventTypes with same name
            let typesByName = Dictionary(grouping: allEventTypes) { $0.name }
            let sameNameGroups = typesByName.filter { $0.value.count > 1 }
            info.eventTypesWithSameName = sameNameGroups.values.reduce(0) { $0 + $1.count - 1 }

            if !sameNameGroups.isEmpty {
                info.duplicateDetails.append("Same name EventType groups: \(sameNameGroups.count)")
                for (name, types) in sameNameGroups.prefix(5) {
                    let serverIds = types.compactMap { $0.serverId?.prefix(8) }.joined(separator: ", ")
                    info.duplicateDetails.append("  - \"\(name)\": \(types.count) copies (serverIds: \(serverIds.isEmpty ? "nil" : serverIds))")
                }
            }

        } catch {
            info.duplicateDetails.append("Error analyzing: \(error.localizedDescription)")
        }

        duplicateInfo = info
    }

    func cleanupDuplicates() async {
        let freshContext = ModelContext(modelContext.container)
        var deletedEvents = 0
        var deletedEventTypes = 0

        do {
            // Fetch all events
            let allEvents = try freshContext.fetch(FetchDescriptor<Event>())

            // 1. Delete events without serverId (orphaned - never synced)
            let eventsNilServerId = allEvents.filter { $0.serverId == nil }
            for event in eventsNilServerId {
                freshContext.delete(event)
                deletedEvents += 1
            }

            // 2. Merge events with duplicate serverId (keep first, delete rest)
            let eventsByServerId = Dictionary(grouping: allEvents.filter { $0.serverId != nil }) { $0.serverId! }
            for (_, events) in eventsByServerId where events.count > 1 {
                // Keep the first one (usually the oldest), delete the rest
                for event in events.dropFirst() {
                    freshContext.delete(event)
                    deletedEvents += 1
                }
            }

            // 3. Merge events with same timestamp + eventType (keep one with serverId if possible)
            // Re-fetch after deletions
            let remainingEvents = try freshContext.fetch(FetchDescriptor<Event>())
            let eventsByContent = Dictionary(grouping: remainingEvents) { event -> String in
                let typeId = event.eventType?.id.uuidString ?? "nil"
                let timestamp = event.timestamp.timeIntervalSince1970
                return "\(typeId)-\(timestamp)"
            }
            for (_, events) in eventsByContent where events.count > 1 {
                // Prefer keeping the one with a serverId
                let sorted = events.sorted { ($0.serverId != nil ? 0 : 1) < ($1.serverId != nil ? 0 : 1) }
                for event in sorted.dropFirst() {
                    freshContext.delete(event)
                    deletedEvents += 1
                }
            }

            // Fetch all event types
            let allEventTypes = try freshContext.fetch(FetchDescriptor<EventType>())

            // 4. Delete event types without serverId (but only if they have no events)
            let typesNilServerId = allEventTypes.filter { $0.serverId == nil }
            for eventType in typesNilServerId {
                let eventCount = eventType.events?.count ?? 0
                if eventCount == 0 {
                    freshContext.delete(eventType)
                    deletedEventTypes += 1
                }
            }

            // 5. Merge event types with duplicate serverId
            let typesByServerId = Dictionary(grouping: allEventTypes.filter { $0.serverId != nil }) { $0.serverId! }
            for (_, types) in typesByServerId where types.count > 1 {
                // Keep the first one, migrate events from others, then delete
                guard let keeper = types.first else { continue }
                for eventType in types.dropFirst() {
                    // Migrate events to the keeper
                    if let events = eventType.events {
                        for event in events {
                            event.eventType = keeper
                        }
                    }
                    freshContext.delete(eventType)
                    deletedEventTypes += 1
                }
            }

            // 6. Merge event types with same name (prefer one with serverId)
            // Re-fetch after deletions
            let remainingTypes = try freshContext.fetch(FetchDescriptor<EventType>())
            let typesByName = Dictionary(grouping: remainingTypes) { $0.name }
            for (_, types) in typesByName where types.count > 1 {
                // Prefer keeping the one with a serverId
                let sorted = types.sorted { ($0.serverId != nil ? 0 : 1) < ($1.serverId != nil ? 0 : 1) }
                guard let keeper = sorted.first else { continue }
                for eventType in sorted.dropFirst() {
                    // Migrate events to the keeper
                    if let events = eventType.events {
                        for event in events {
                            event.eventType = keeper
                        }
                    }
                    freshContext.delete(eventType)
                    deletedEventTypes += 1
                }
            }

            try freshContext.save()

            cleanupResult = "Deleted \(deletedEvents) duplicate events and \(deletedEventTypes) duplicate event types."
            showingCleanupSuccess = true

        } catch {
            cleanupResult = "Error during cleanup: \(error.localizedDescription)"
            showingCleanupSuccess = true
        }
    }
}

#Preview {
    NavigationStack {
        DebugStorageView()
    }
}
