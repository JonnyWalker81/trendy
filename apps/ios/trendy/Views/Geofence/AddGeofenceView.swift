//
//  AddGeofenceView.swift
//  trendy
//
//  Create a new geofence with map picker
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct AddGeofenceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventType.name) private var eventTypes: [EventType]

    @Environment(EventStore.self) private var eventStore: EventStore?
    @Environment(GeofenceManager.self) private var geofenceManager: GeofenceManager?
    @Environment(NotificationManager.self) private var notificationManager: NotificationManager?

    // Form fields
    @State private var name: String = ""
    @State private var radius: Double = 100
    @State private var selectedEventTypeEntryID: String?
    @State private var notifyOnEntry: Bool = false
    @State private var notifyOnExit: Bool = false
    @State private var showingNotificationPermissionAlert = false

    private var selectedEventTypeEntry: EventType? {
        guard let id = selectedEventTypeEntryID else { return nil }
        return eventTypes.first { $0.id == id }
    }

    // Map state
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var showingMapPicker = false

    // Validation
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                // Location Section
                Section {
                    // Show mini map preview if location selected
                    if let coordinate = selectedCoordinate {
                        Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 2000))) {
                            MapCircle(center: coordinate, radius: radius)
                                .foregroundStyle(Color.blue.opacity(0.2))
                                .stroke(Color.blue, lineWidth: 2)
                            
                            Annotation("", coordinate: coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(height: 150)
                        .listRowInsets(EdgeInsets())
                        .allowsHitTesting(false) // Disable interactions on preview
                    }
                    
                    Button(action: { showingMapPicker = true }) {
                        HStack {
                            Image(systemName: selectedCoordinate == nil ? "map" : "map.fill")
                                .foregroundStyle(selectedCoordinate == nil ? .blue : .green)
                            Text(selectedCoordinate == nil ? "Select Location on Map" : "Change Location")
                            Spacer()
                            if let coordinate = selectedCoordinate {
                                Text("\(coordinate.latitude, specifier: "%.4f"), \(coordinate.longitude, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button(action: useCurrentLocation) {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if selectedCoordinate == nil {
                        Text("Select a location for your geofence.")
                    }
                }

                // Details Section
                Section("Details") {
                    TextField("Geofence Name", text: $name)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Radius")
                            Spacer()
                            Text("\(Int(radius))m")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $radius, in: 50...10000, step: 50)
                        Text("Range: 50m - 10,000m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Event Type Section
                Section {
                    Picker("Event Type (Entry)", selection: $selectedEventTypeEntryID) {
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
                } header: {
                    Text("Event Type")
                } footer: {
                    Text("The event type to create when entering this geofence.")
                }

                // Notifications Section
                Section {
                    Toggle("Notify on Entry", isOn: $notifyOnEntry)
                        .onChange(of: notifyOnEntry) { _, newValue in
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            }
                        }
                    Toggle("Notify on Exit", isOn: $notifyOnExit)
                        .onChange(of: notifyOnExit) { _, newValue in
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
                    } else {
                        Text("Receive notifications when entering or exiting this geofence.")
                    }
                }
            }
            .navigationTitle("Add Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGeofence()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingMapPicker) {
                GeofenceMapPickerView(selectedCoordinate: $selectedCoordinate, radius: radius)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Turn off the toggle since notifications are denied
                    notifyOnEntry = false
                    notifyOnExit = false
                }
            } message: {
                Text("Notifications are disabled for this app. Please enable them in Settings to receive geofence alerts.")
            }
        }
    }

    // MARK: - Actions

    private func useCurrentLocation() {
        let manager = CLLocationManager()
        if let location = manager.location {
            selectedCoordinate = location.coordinate
            print("📍 Using current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedCoordinate != nil &&
        radius >= 50 &&
        radius <= 10000
    }

    private func saveGeofence() {
        guard isValid, let coordinate = selectedCoordinate else {
            errorMessage = "Please select a location and enter a valid name."
            showingError = true
            return
        }

        // Create geofence
        let geofence = Geofence(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: radius,
            eventTypeEntryID: selectedEventTypeEntryID,
            eventTypeExitID: nil,
            isActive: true,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )

        Task {
            // Use EventStore for backend sync if available
            if let eventStore = eventStore {
                let success = await eventStore.createGeofence(geofence)
                if success {
                    // Start monitoring
                    geofenceManager?.startMonitoring(geofence: geofence)
                    print("✅ Created geofence: \(geofence.name)")
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to save geofence"
                        showingError = true
                    }
                }
            } else {
                // Fallback to direct insert if EventStore not available
                modelContext.insert(geofence)
                do {
                    try modelContext.save()
                    geofenceManager?.startMonitoring(geofence: geofence)
                    print("✅ Created geofence: \(geofence.name)")
                    await MainActor.run {
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save geofence: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard let manager = notificationManager else { return }
        
        switch manager.authorizationStatus {
        case .notDetermined:
            // Request permission
            Task {
                do {
                    try await manager.requestAuthorization()
                } catch {
                    print("Failed to request notification permission: \(error)")
                }
            }
        case .denied:
            // Show alert to open settings
            showingNotificationPermissionAlert = true
        default:
            // Already authorized or provisional
            break
        }
    }
}

// MARK: - Full Screen Map Picker

struct GeofenceMapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    let radius: Double
    
    @State private var mapPosition: MapCameraPosition
    @State private var tempCoordinate: CLLocationCoordinate2D?
    @State private var searchText = ""
    
    init(selectedCoordinate: Binding<CLLocationCoordinate2D?>, radius: Double) {
        self._selectedCoordinate = selectedCoordinate
        self.radius = radius
        
        // Initialize map position based on existing selection or default
        if let coord = selectedCoordinate.wrappedValue {
            self._mapPosition = State(initialValue: .camera(MapCamera(centerCoordinate: coord, distance: 2000)))
            self._tempCoordinate = State(initialValue: coord)
        } else {
            // Default to a reasonable location (will be updated by location manager)
            self._mapPosition = State(initialValue: .automatic)
            self._tempCoordinate = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Full screen map
                MapReader { proxy in
                    Map(position: $mapPosition) {
                        if let coordinate = tempCoordinate {
                            MapCircle(center: coordinate, radius: radius)
                                .foregroundStyle(Color.blue.opacity(0.2))
                                .stroke(Color.blue, lineWidth: 2)
                            
                            Annotation("", coordinate: coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .ignoresSafeArea(edges: .bottom)
                    .onTapGesture { screenPosition in
                        if let coordinate = proxy.convert(screenPosition, from: .local) {
                            tempCoordinate = coordinate
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                    }
                }
                
                // Center crosshair (alternative selection method)
                VStack {
                    Spacer()
                    
                    // Bottom info panel
                    VStack(spacing: 12) {
                        if let coord = tempCoordinate {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                Text("\(coord.latitude, specifier: "%.6f"), \(coord.longitude, specifier: "%.6f")")
                                    .font(.caption.monospaced())
                            }
                        } else {
                            Text("Tap on the map to select a location")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 16) {
                            Button("Use Current Location") {
                                useCurrentLocation()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding()
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        selectedCoordinate = tempCoordinate
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(tempCoordinate == nil)
                }
            }
        }
    }
    
    private func useCurrentLocation() {
        let manager = CLLocationManager()
        if let location = manager.location {
            tempCoordinate = location.coordinate
            mapPosition = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 2000))
        }
    }
}

// MARK: - Alternative AddGeofenceView with MapReader (iOS 17+)

@available(iOS 17.0, *)
struct AddGeofenceViewWithMapReader: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventType.name) private var eventTypes: [EventType]

    @Environment(EventStore.self) private var eventStore: EventStore?
    @Environment(GeofenceManager.self) private var geofenceManager: GeofenceManager?
    @Environment(NotificationManager.self) private var notificationManager: NotificationManager?

    // Form fields
    @State private var name: String = ""
    @State private var radius: Double = 100
    @State private var selectedEventTypeEntryID: String?
    @State private var notifyOnEntry: Bool = false
    @State private var notifyOnExit: Bool = false
    @State private var showingNotificationPermissionAlert = false

    private var selectedEventTypeEntry: EventType? {
        guard let id = selectedEventTypeEntryID else { return nil }
        return eventTypes.first { $0.id == id }
    }

    // Map state
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var locationManager = CLLocationManager()
    @State private var showingMap = false

    // Validation
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                // Location Section
                Section {
                    if let coordinate = selectedCoordinate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                Text("Location Selected")
                                    .font(.headline)
                                Spacer()
                                Button("Change") {
                                    showingMap = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lat: \(coordinate.latitude, specifier: "%.6f")")
                                    .font(.caption)
                                    .monospaced()
                                Text("Lon: \(coordinate.longitude, specifier: "%.6f")")
                                    .font(.caption)
                                    .monospaced()
                            }
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(action: { showingMap = true }) {
                            Label("Select Location on Map", systemImage: "map")
                        }
                    }

                    Button(action: useCurrentLocation) {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                    .disabled(!(geofenceManager?.hasGeofencingAuthorization ?? false))
                } header: {
                    Text("Location")
                }

                // Details Section
                Section("Details") {
                    TextField("Geofence Name", text: $name)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Radius")
                            Spacer()
                            Text("\(Int(radius))m")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $radius, in: 50...10000, step: 50)
                        Text("Range: 50m - 10,000m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Event Type Section
                Section {
                    Picker("Event Type (Entry)", selection: $selectedEventTypeEntryID) {
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
                } header: {
                    Text("Event Type")
                } footer: {
                    Text("The event type to create when entering this geofence.")
                }

                // Notifications Section
                Section {
                    Toggle("Notify on Entry", isOn: $notifyOnEntry)
                        .onChange(of: notifyOnEntry) { _, newValue in
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            }
                        }
                    Toggle("Notify on Exit", isOn: $notifyOnExit)
                        .onChange(of: notifyOnExit) { _, newValue in
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
            .navigationTitle("Add Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGeofence()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingMap) {
                MapPickerView(selectedCoordinate: $selectedCoordinate)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    notifyOnEntry = false
                    notifyOnExit = false
                }
            } message: {
                Text("Notifications are disabled for this app. Please enable them in Settings to receive geofence alerts.")
            }
        }
    }

    // MARK: - Actions

    private func useCurrentLocation() {
        if let location = locationManager.location {
            selectedCoordinate = location.coordinate
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedCoordinate != nil &&
        radius >= 50 &&
        radius <= 10000
    }

    private func saveGeofence() {
        guard isValid, let coordinate = selectedCoordinate else {
            errorMessage = "Please select a location and enter a valid name."
            showingError = true
            return
        }

        let geofence = Geofence(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: radius,
            eventTypeEntryID: selectedEventTypeEntryID,
            eventTypeExitID: nil,
            isActive: true,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )

        Task {
            // Use EventStore for backend sync if available
            if let eventStore = eventStore {
                let success = await eventStore.createGeofence(geofence)
                if success {
                    geofenceManager?.startMonitoring(geofence: geofence)
                    print("✅ Created geofence: \(geofence.name)")
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to save geofence"
                        showingError = true
                    }
                }
            } else {
                // Fallback to direct insert if EventStore not available
                modelContext.insert(geofence)
                do {
                    try modelContext.save()
                    geofenceManager?.startMonitoring(geofence: geofence)
                    print("✅ Created geofence: \(geofence.name)")
                    await MainActor.run {
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save geofence: \(error.localizedDescription)"
                        showingError = true
                    }
                }
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
                    print("Failed to request notification permission: \(error)")
                }
            }
        case .denied:
            showingNotificationPermissionAlert = true
        default:
            break
        }
    }
}

// MARK: - Map Picker View

struct MapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var tempCoordinate: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $mapPosition) {
                    if let coordinate = tempCoordinate {
                        Annotation("", coordinate: coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onTapGesture { position in
                    if let coordinate = proxy.convert(position, from: .local) {
                        tempCoordinate = coordinate
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        selectedCoordinate = tempCoordinate
                        dismiss()
                    }
                    .disabled(tempCoordinate == nil)
                }
            }
            .onAppear {
                // Initialize with current selection or user location
                if let selectedCoordinate = selectedCoordinate {
                    tempCoordinate = selectedCoordinate
                    mapPosition = .camera(
                        MapCamera(
                            centerCoordinate: selectedCoordinate,
                            distance: 500,
                            heading: 0,
                            pitch: 0
                        )
                    )
                } else if let location = CLLocationManager().location {
                    mapPosition = .camera(
                        MapCamera(
                            centerCoordinate: location.coordinate,
                            distance: 500,
                            heading: 0,
                            pitch: 0
                        )
                    )
                }
            }
        }
    }
}

// Preview removed due to complexity - use live app for testing
