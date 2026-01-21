//
//  GeofenceListView.swift
//  trendy
//
//  List and manage geofences
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct GeofenceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Geofence.name) private var geofences: [Geofence]
    @Query(sort: \EventType.name) private var eventTypes: [EventType]
    @State private var showingAddGeofence = false
    @State private var selectedGeofenceID: String?
    @State private var showingDeleteConfirmation = false
    @State private var geofenceToDeleteID: String?

    // GeofenceManager should be passed in as environment
    @Environment(GeofenceManager.self) private var geofenceManager: GeofenceManager?
    @Environment(EventStore.self) private var eventStore: EventStore?

    @State private var isRefreshing = false
    @State private var hasPerformedInitialSync = false

    private var selectedGeofence: Geofence? {
        guard let id = selectedGeofenceID else { return nil }
        return geofences.first { $0.id == id }
    }
    
    private var geofenceToDelete: Geofence? {
        guard let id = geofenceToDeleteID else { return nil }
        return geofences.first { $0.id == id }
    }
    
    private var needsLocationPermission: Bool {
        guard let manager = geofenceManager else { return true }
        return !manager.hasGeofencingAuthorization
    }

    var body: some View {
        NavigationStack {
            Group {
                if needsLocationPermission {
                    locationPermissionView
                } else if geofences.isEmpty {
                    emptyState
                } else {
                    geofenceList
                }
            }
            .navigationTitle("Geofences")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isRefreshing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGeofence = true }) {
                        Label("Add Geofence", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddGeofence) {
                AddGeofenceView()
            }
            .sheet(isPresented: Binding(
                get: { selectedGeofenceID != nil },
                set: { if !$0 { selectedGeofenceID = nil } }
            )) {
                if let geofenceID = selectedGeofenceID,
                   let geofence = geofences.first(where: { $0.id == geofenceID }) {
                    EditGeofenceView(geofence: geofence)
                }
            }
            .alert("Delete Geofence", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let geofence = geofenceToDelete {
                        deleteGeofence(geofence)
                    }
                }
                Button("Cancel", role: .cancel) {
                    geofenceToDeleteID = nil
                }
            } message: {
                if let geofence = geofenceToDelete {
                    Text("Are you sure you want to delete '\(geofence.name)'? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this geofence?")
                }
            }
            .task {
                // Perform initial sync when view first appears
                guard !hasPerformedInitialSync else { return }
                hasPerformedInitialSync = true
                await refreshGeofences()
            }
        }
    }

    // MARK: - Empty State

    // MARK: - Location Permission View
    
    private var locationPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.circle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Location Permission Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Geofencing requires \"Always\" location permission to automatically track events when you enter or leave a location, even when the app is in the background.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                // Show current status
                if let manager = geofenceManager {
                    HStack {
                        Text("Current Status:")
                            .foregroundStyle(.secondary)
                        Text(manager.authorizationStatus.description)
                            .fontWeight(.medium)
                            .foregroundStyle(manager.hasGeofencingAuthorization ? .green : .orange)
                    }
                    .font(.caption)
                }
                
                Button(action: requestLocationPermission) {
                    Label("Enable Location Access", systemImage: "location.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .font(.subheadline)
            }
            .padding(.top)
            
            // Debug info
            #if DEBUG
            VStack(alignment: .leading, spacing: 4) {
                Text("Debug Info:")
                    .font(.caption.bold())
                if let manager = geofenceManager {
                    Text("Monitored regions: \(manager.monitoredRegions.count)")
                    Text("Location services enabled: \(manager.isLocationServicesEnabled ? "Yes" : "No")")
                } else {
                    Text("GeofenceManager: nil")
                }
                Text("Active geofences in DB: \(geofences.filter { $0.isActive }.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.top, 20)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func requestLocationPermission() {
        guard let manager = geofenceManager else {
            Log.geofence.error("GeofenceManager not available")
            return
        }

        // Use the GeofenceManager's proper two-step authorization flow
        // The delegate will handle requesting "Always" after "When In Use" is granted
        let needsSettingsRedirect = manager.requestGeofencingAuthorization()

        if needsSettingsRedirect {
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 100)

                Image(systemName: "location.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("No Geofences")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Create a geofence to automatically track events when you enter or leave a location")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: { showingAddGeofence = true }) {
                    Label("Add Geofence", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Syncing with server...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else {
                    Text("Pull down to refresh from server")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
        }
        .refreshable {
            await refreshGeofences()
        }
    }

    // MARK: - Geofence List

    private var geofenceList: some View {
        List {
            // Status section
            Section {
                HStack {
                    Image(systemName: geofenceManager?.hasGeofencingAuthorization == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(geofenceManager?.hasGeofencingAuthorization == true ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text("Monitoring Status")
                            .font(.subheadline.bold())
                        Text(geofenceManager?.hasGeofencingAuthorization == true
                             ? "Active - \(geofenceManager?.monitoredRegions.count ?? 0) regions monitored"
                             : "Requires \"Always\" location permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Debug view link - always visible for troubleshooting
                NavigationLink {
                    GeofenceDebugView()
                } label: {
                    HStack {
                        Label("Debug Status", systemImage: "ladybug")
                        Spacer()
                        if let manager = geofenceManager {
                            let regionCount = manager.monitoredRegions.count
                            let activeCount = geofences.filter { $0.isActive }.count
                            if regionCount != activeCount {
                                Text("Mismatch")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            
            // Geofences section
            Section("Your Geofences") {
                ForEach(geofences) { geofence in
                    GeofenceRow(geofence: geofence)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedGeofenceID = geofence.id
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                geofenceToDeleteID = geofence.id
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                toggleGeofenceActive(geofence)
                            } label: {
                                Label(
                                    geofence.isActive ? "Deactivate" : "Activate",
                                    systemImage: geofence.isActive ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(geofence.isActive ? .orange : .green)
                        }
                }
            }
            
            #if DEBUG
            // Debug section for testing
            Section("Debug Actions") {
                NavigationLink {
                    GeofenceDebugView()
                } label: {
                    Label("Debug Status View", systemImage: "ladybug")
                }

                Button {
                    printDebugInfo()
                } label: {
                    Label("Print Debug to Console", systemImage: "terminal")
                }

                Button {
                    repairBrokenGeofences()
                } label: {
                    Label("Repair Broken Geofences", systemImage: "wrench.and.screwdriver")
                }
                .tint(.orange)

                ForEach(geofences.filter { $0.isActive }) { geofence in
                    HStack {
                        Text(geofence.name)
                            .font(.caption)
                        Spacer()
                        Button("Simulate Entry") {
                            simulateGeofenceEntry(geofence)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Simulate Exit") {
                            simulateGeofenceExit(geofence)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            #endif
        }
        .refreshable {
            await refreshGeofences()
        }
    }

    // MARK: - Refresh Geofences

    private func refreshGeofences() async {
        guard let store = eventStore else {
            Log.geofence.warning("Cannot refresh: EventStore not available")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        Log.geofence.debug("Syncing geofences with backend")

        // Fetch from backend and reconcile with local SwiftData
        let definitions = await store.reconcileGeofencesWithBackend(forceRefresh: true)

        // Reconcile CLLocationManager regions if geofenceManager is available
        if let geoManager = geofenceManager {
            geoManager.reconcileRegions(desired: definitions)
        }

        Log.geofence.info("Sync complete", context: .with { ctx in
            ctx.add("geofence_count", definitions.count)
        })
    }
    
    #if DEBUG
    private func printDebugInfo() {
        Log.geofence.debug("========== GEOFENCE DEBUG INFO ==========")
        Log.geofence.debug("GeofenceManager available", context: .with { ctx in
            ctx.add("available", geofenceManager != nil)
        })
        if let manager = geofenceManager {
            Log.geofence.debug("GeofenceManager status", context: .with { ctx in
                ctx.add("authorization_status", manager.authorizationStatus.description)
                ctx.add("has_authorization", manager.hasGeofencingAuthorization)
                ctx.add("location_services_enabled", manager.isLocationServicesEnabled)
                ctx.add("monitored_regions_count", manager.monitoredRegions.count)
            })
            for region in manager.monitoredRegions {
                if let circular = region as? CLCircularRegion {
                    Log.geofence.debug("Monitored region", context: .with { ctx in
                        ctx.add("region_id", region.identifier)
                        ctx.add("latitude", circular.center.latitude)
                        ctx.add("longitude", circular.center.longitude)
                        ctx.add("radius", circular.radius)
                    })
                } else {
                    Log.geofence.debug("Monitored region", context: .with { ctx in
                        ctx.add("region_id", region.identifier)
                    })
                }
            }
        }
        Log.geofence.debug("Geofences in database", context: .with { ctx in
            ctx.add("count", geofences.count)
        })
        for geofence in geofences {
            let eventTypeStatus: String
            if let eventTypeID = geofence.eventTypeEntryID {
                if let eventType = eventTypes.first(where: { $0.id == eventTypeID }) {
                    eventTypeStatus = "found: \(eventType.name) (\(eventTypeID))"
                } else {
                    eventTypeStatus = "MISSING (\(eventTypeID))"
                }
            } else {
                eventTypeStatus = "Not set"
            }
            Log.geofence.debug("Geofence detail", context: .with { ctx in
                ctx.add("name", geofence.name)
                ctx.add("is_active", geofence.isActive)
                ctx.add("event_type_status", eventTypeStatus)
                ctx.add("latitude", geofence.latitude)
                ctx.add("longitude", geofence.longitude)
                ctx.add("radius", geofence.radius)
            })
        }
        Log.geofence.debug("Available EventTypes", context: .with { ctx in
            ctx.add("count", eventTypes.count)
        })
        for eventType in eventTypes {
            Log.geofence.debug("EventType", context: .with { ctx in
                ctx.add("name", eventType.name)
                ctx.add("id", eventType.id)
            })
        }
        Log.geofence.debug("========== END DEBUG INFO ==========")
    }
    
    private func repairBrokenGeofences() {
        Log.geofence.info("Starting geofence repair")

        var repaired = 0
        for geofence in geofences {
            guard let eventTypeID = geofence.eventTypeEntryID else { continue }

            // Check if the EventType exists
            let eventTypeExists = eventTypes.contains { $0.id == eventTypeID }

            if !eventTypeExists {
                Log.geofence.warning("Geofence has broken eventTypeID", context: .with { ctx in
                    ctx.add("geofence_name", geofence.name)
                    ctx.add("broken_event_type_id", eventTypeID)
                })

                // Try to find a matching EventType by name
                // This is a heuristic - we look for an EventType with a similar name
                if let matchingType = eventTypes.first(where: {
                    geofence.name.lowercased().contains($0.name.lowercased()) ||
                    $0.name.lowercased().contains(geofence.name.lowercased())
                }) {
                    geofence.eventTypeEntryID = matchingType.id
                    Log.geofence.info("Auto-matched geofence to EventType", context: .with { ctx in
                        ctx.add("geofence_name", geofence.name)
                        ctx.add("matched_event_type", matchingType.name)
                        ctx.add("matched_event_type_id", matchingType.id)
                    })
                    repaired += 1
                } else if let firstType = eventTypes.first {
                    // Fallback: assign the first available EventType
                    geofence.eventTypeEntryID = firstType.id
                    Log.geofence.warning("No match found, assigned to first EventType", context: .with { ctx in
                        ctx.add("geofence_name", geofence.name)
                        ctx.add("assigned_event_type", firstType.name)
                        ctx.add("assigned_event_type_id", firstType.id)
                    })
                    repaired += 1
                } else {
                    Log.geofence.error("No EventTypes available to assign", context: .with { ctx in
                        ctx.add("geofence_name", geofence.name)
                    })
                }
            }
        }

        if repaired > 0 {
            do {
                try modelContext.save()
                Log.geofence.info("Geofence repair complete", context: .with { ctx in
                    ctx.add("repaired_count", repaired)
                })
            } catch {
                Log.geofence.error("Failed to save repairs", error: error)
            }
        } else {
            Log.geofence.debug("No broken geofences found")
        }
    }
    
    private func simulateGeofenceEntry(_ geofence: Geofence) {
        Log.geofence.debug("Simulating geofence ENTRY", context: .with { ctx in
            ctx.add("geofence_name", geofence.name)
            ctx.add("geofence_id", geofence.id)
        })
        geofenceManager?.simulateEntry(geofenceId: geofence.id)
    }

    private func simulateGeofenceExit(_ geofence: Geofence) {
        Log.geofence.debug("Simulating geofence EXIT", context: .with { ctx in
            ctx.add("geofence_name", geofence.name)
            ctx.add("geofence_id", geofence.id)
        })
        geofenceManager?.simulateExit(geofenceId: geofence.id)
    }
    #endif

    // MARK: - Actions

    private func toggleGeofenceActive(_ geofence: Geofence) {
        geofence.isActive.toggle()

        // Sync to backend
        Task {
            await eventStore?.updateGeofence(geofence)
        }

        do {
            try modelContext.save()

            // Update monitoring
            if geofence.isActive {
                geofenceManager?.startMonitoring(geofence: geofence)
            } else {
                geofenceManager?.stopMonitoring(geofence: geofence)
            }
        } catch {
            Log.geofence.error("Failed to toggle geofence", error: error, context: .with { ctx in
                ctx.add("geofence_name", geofence.name)
                ctx.add("geofence_id", geofence.id)
            })
        }
    }

    private func deleteGeofence(_ geofence: Geofence) {
        // Stop monitoring
        geofenceManager?.stopMonitoring(geofence: geofence)

        // Delete from backend and local storage via EventStore
        Task {
            await eventStore?.deleteGeofence(geofence)
        }
    }
}

// MARK: - Geofence Row

struct GeofenceRow: View {
    let geofence: Geofence
    @Query private var eventTypes: [EventType]
    
    // Look up event type by ID
    private var eventTypeEntry: EventType? {
        guard let id = geofence.eventTypeEntryID else { return nil }
        return eventTypes.first { $0.id == id }
    }
    
    // Check if event type is missing (ID set but not found)
    private var isEventTypeMissing: Bool {
        geofence.eventTypeEntryID != nil && eventTypeEntry == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Name and active status
                VStack(alignment: .leading, spacing: 4) {
                    Text(geofence.name)
                        .font(.headline)

                    if isEventTypeMissing {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Event type missing - tap to fix")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if let eventType = eventTypeEntry {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: eventType.colorHex) ?? .blue)
                                .frame(width: 8, height: 8)
                            Text(eventType.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No event type selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Active/Inactive badge
                if geofence.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Inactive", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Location and radius info
            HStack(spacing: 12) {
                Label("\(Int(geofence.radius))m", systemImage: "circle.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if geofence.notifyOnEntry || geofence.notifyOnExit {
                    Label("Notifications", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Geofence View

struct EditGeofenceView: View {
    let geofence: Geofence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationManager.self) private var notificationManager: NotificationManager?
    @Environment(GeofenceManager.self) private var geofenceManager: GeofenceManager?
    @Environment(EventStore.self) private var eventStore: EventStore?
    @Query private var eventTypes: [EventType]
    
    @State private var name: String = ""
    @State private var radius: Double = 100
    @State private var isActive: Bool = true
    @State private var selectedEventTypeID: String?
    @State private var notifyOnEntry: Bool = false
    @State private var notifyOnExit: Bool = false
    @State private var hasUnsavedChanges = false
    @State private var showingNotificationPermissionAlert = false
    
    // Check if the current eventTypeEntryID is valid
    private var isEventTypeValid: Bool {
        guard let id = geofence.eventTypeEntryID else { return false }
        return eventTypes.contains { $0.id == id }
    }
    
    // Look up event type by ID
    private var eventTypeEntry: EventType? {
        guard let id = selectedEventTypeID ?? geofence.eventTypeEntryID else { return nil }
        return eventTypes.first { $0.id == id }
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        radius >= 50 &&
        radius <= 10000
    }

    var body: some View {
        NavigationStack {
            Form {
                // Warning if event type is invalid
                if !isEventTypeValid && geofence.eventTypeEntryID != nil {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text("Event Type Missing")
                                    .font(.headline)
                                Text("The linked event type no longer exists. Please select a new one below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Radius")
                            Spacer()
                            Text("\(Int(radius))m")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $radius, in: 50...10000, step: 50)
                            .onChange(of: radius) { _, _ in
                                hasUnsavedChanges = true
                            }
                        Text("Range: 50m - 10,000m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Toggle("Active", isOn: $isActive)
                        .onChange(of: isActive) { _, _ in
                            hasUnsavedChanges = true
                        }
                } header: {
                    Text("Details")
                }

                Section("Location") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        Text("\(geofence.latitude, specifier: "%.6f")")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Longitude")
                        Spacer()
                        Text("\(geofence.longitude, specifier: "%.6f")")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Event Type", selection: $selectedEventTypeID) {
                        Text("None").tag(nil as String?)
                        ForEach(eventTypes) { eventType in
                            HStack {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(eventType.name)
                            }
                            .tag(eventType.id as String?)
                        }
                    }
                    .onChange(of: selectedEventTypeID) { _, _ in
                        hasUnsavedChanges = true
                    }
                } header: {
                    Text("Event Type")
                } footer: {
                    Text("Select the event type to log when entering this geofence.")
                }

                Section {
                    Toggle("Notify on Entry", isOn: $notifyOnEntry)
                        .onChange(of: notifyOnEntry) { _, newValue in
                            hasUnsavedChanges = true
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            }
                        }
                    Toggle("Notify on Exit", isOn: $notifyOnExit)
                        .onChange(of: notifyOnExit) { _, newValue in
                            hasUnsavedChanges = true
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            }
                        }
                } header: {
                    Text("Notifications")
                } footer: {
                    if let manager = notificationManager, manager.authorizationStatus == .denied {
                        Text("Notifications are disabled. Enable them in Settings to receive geofence alerts.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Edit Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasUnsavedChanges || !isValid)
                }
            }
            .onAppear {
                // Initialize with current values
                name = geofence.name
                radius = geofence.radius
                isActive = geofence.isActive
                selectedEventTypeID = geofence.eventTypeEntryID
                notifyOnEntry = geofence.notifyOnEntry
                notifyOnExit = geofence.notifyOnExit
            }
            .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    notifyOnEntry = geofence.notifyOnEntry
                    notifyOnExit = geofence.notifyOnExit
                }
            } message: {
                Text("Notifications are disabled for this app. Please enable them in Settings to receive geofence alerts.")
            }
        }
    }
    
    private func requestNotificationPermissionIfNeeded() {
        guard let manager = notificationManager else { return }
        
        switch manager.authorizationStatus {
        case .notDetermined:
            Task {
                do {
                    try await manager.requestAuthorization()
                } catch {
                    Log.general.warning("Failed to request notification permission", error: error)
                }
            }
        case .denied:
            showingNotificationPermissionAlert = true
        default:
            break
        }
    }
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let radiusChanged = geofence.radius != radius
        let activeChanged = geofence.isActive != isActive

        geofence.name = trimmedName
        geofence.radius = radius
        geofence.isActive = isActive
        geofence.eventTypeEntryID = selectedEventTypeID
        geofence.notifyOnEntry = notifyOnEntry
        geofence.notifyOnExit = notifyOnExit

        // Sync to backend
        Task {
            await eventStore?.updateGeofence(geofence)
        }

        do {
            try modelContext.save()

            // If radius or active status changed, refresh monitoring
            if radiusChanged || activeChanged {
                if isActive {
                    geofenceManager?.stopMonitoring(geofence: geofence)
                    geofenceManager?.startMonitoring(geofence: geofence)
                } else {
                    geofenceManager?.stopMonitoring(geofence: geofence)
                }
            }

            Log.geofence.info("Updated geofence", context: .with { ctx in
                ctx.add("geofence_name", trimmedName)
                ctx.add("geofence_id", geofence.id)
            })
            dismiss()
        } catch {
            Log.geofence.error("Failed to save geofence", error: error, context: .with { ctx in
                ctx.add("geofence_name", trimmedName)
            })
        }
    }
}

// Preview removed due to complexity - use live app for testing
