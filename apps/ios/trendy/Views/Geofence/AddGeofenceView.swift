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

    @Environment(GeofenceManager.self) private var geofenceManager

    // Form fields
    @State private var name: String = ""
    @State private var radius: Double = 100
    @State private var selectedEventTypeEntry: EventType?
    @State private var notifyOnEntry: Bool = false
    @State private var notifyOnExit: Bool = false

    // Map state
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var locationManager = CLLocationManager()

    // Validation
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                // Map Section
                Section {
                    mapView
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())

                    Button(action: useCurrentLocation) {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                    .disabled(!geofenceManager.hasGeofencingAuthorization)

                    if let coordinate = selectedCoordinate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Lat: \(coordinate.latitude, specifier: "%.6f")")
                                .font(.caption)
                                .monospaced()
                            Text("Lon: \(coordinate.longitude, specifier: "%.6f")")
                                .font(.caption)
                                .monospaced()
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Tap on the map to select a location, or use your current location.")
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
                    Picker("Event Type (Entry)", selection: $selectedEventTypeEntry) {
                        Text("None").tag(nil as EventType?)
                        ForEach(eventTypes) { eventType in
                            HStack {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(eventType.name)
                            }
                            .tag(eventType as EventType?)
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
                    Toggle("Notify on Exit", isOn: $notifyOnExit)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive notifications when entering or exiting this geofence.")
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
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Default to current location if available
                if geofenceManager.hasGeofencingAuthorization {
                    useCurrentLocation()
                }
            }
        }
    }

    // MARK: - Map View

    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: .all) {
            // Show selected location with circle overlay
            if let coordinate = selectedCoordinate {
                Annotation("", coordinate: coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: radiusInPoints(for: radius), height: radiusInPoints(for: radius))

                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onTapGesture { location in
            // This doesn't work directly with Map - need to use MapReader
        }
        .overlay(alignment: .topTrailing) {
            // Map controls
            VStack(spacing: 8) {
                Button(action: useCurrentLocation) {
                    Image(systemName: "location.fill")
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .disabled(!geofenceManager.hasGeofencingAuthorization)
            }
            .padding()
        }
    }

    // Calculate radius in map points (approximate)
    private func radiusInPoints(for meters: Double) -> CGFloat {
        // Very rough approximation: 1 degree ≈ 111km
        // This should be calculated based on map zoom level
        return CGFloat(max(20, min(meters / 10, 200)))
    }

    // MARK: - Actions

    private func useCurrentLocation() {
        if let location = locationManager.location {
            selectedCoordinate = location.coordinate
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
            eventTypeEntry: selectedEventTypeEntry,
            eventTypeExit: nil,
            isActive: true,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )

        modelContext.insert(geofence)

        do {
            try modelContext.save()

            // Start monitoring
            geofenceManager.startMonitoring(geofence: geofence)

            print("✅ Created geofence: \(geofence.name)")
            dismiss()

        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Alternative AddGeofenceView with MapReader (iOS 17+)

@available(iOS 17.0, *)
struct AddGeofenceViewWithMapReader: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventType.name) private var eventTypes: [EventType]

    @Environment(GeofenceManager.self) private var geofenceManager

    // Form fields
    @State private var name: String = ""
    @State private var radius: Double = 100
    @State private var selectedEventTypeEntry: EventType?
    @State private var notifyOnEntry: Bool = false
    @State private var notifyOnExit: Bool = false

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
                    .disabled(!geofenceManager.hasGeofencingAuthorization)
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
                    Picker("Event Type (Entry)", selection: $selectedEventTypeEntry) {
                        Text("None").tag(nil as EventType?)
                        ForEach(eventTypes) { eventType in
                            HStack {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(eventType.name)
                            }
                            .tag(eventType as EventType?)
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
                    Toggle("Notify on Exit", isOn: $notifyOnExit)
                } header: {
                    Text("Notifications")
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
            eventTypeEntry: selectedEventTypeEntry,
            eventTypeExit: nil,
            isActive: true,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )

        modelContext.insert(geofence)

        do {
            try modelContext.save()
            geofenceManager.startMonitoring(geofence: geofence)
            print("✅ Created geofence: \(geofence.name)")
            dismiss()
        } catch {
            errorMessage = "Failed to save geofence: \(error.localizedDescription)"
            showingError = true
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
