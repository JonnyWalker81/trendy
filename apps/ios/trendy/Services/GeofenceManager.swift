//
//  GeofenceManager.swift
//  trendy
//
//  Manages CoreLocation geofence monitoring and automatic event creation
//

import Foundation
import CoreLocation
import SwiftData
import Observation

/// Manages geofence monitoring using CoreLocation
@Observable
class GeofenceManager: NSObject {

    // MARK: - Properties

    private let locationManager: CLLocationManager
    private let modelContext: ModelContext
    private let eventStore: EventStore
    private let notificationManager: NotificationManager?

    /// Current authorization status
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether location services are available
    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    /// Currently monitored regions
    var monitoredRegions: Set<CLRegion> {
        locationManager.monitoredRegions
    }

    /// Active geofence events (entry recorded, waiting for exit)
    private var activeGeofenceEvents: [UUID: UUID] = [:] // geofenceId -> eventId

    // MARK: - Initialization

    /// Initialize GeofenceManager
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - eventStore: EventStore for creating/updating events
    ///   - notificationManager: Optional NotificationManager for sending notifications
    init(modelContext: ModelContext, eventStore: EventStore, notificationManager: NotificationManager? = nil) {
        self.modelContext = modelContext
        self.eventStore = eventStore
        self.notificationManager = notificationManager
        self.locationManager = CLLocationManager()

        super.init()

        self.locationManager.delegate = self
        self.authorizationStatus = locationManager.authorizationStatus

        // Load active geofence events from storage
        loadActiveGeofenceEvents()
    }

    // MARK: - Authorization

    /// Request "When In Use" location permission
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request "Always" location permission (required for background geofence monitoring)
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Check if we have sufficient authorization for geofencing
    var hasGeofencingAuthorization: Bool {
        switch authorizationStatus {
        case .authorizedAlways:
            return true
        case .authorizedWhenInUse, .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Geofence Management

    /// Start monitoring all active geofences
    func startMonitoringAllGeofences() {
        guard hasGeofencingAuthorization else {
            print("⚠️ Cannot start monitoring: insufficient authorization")
            return
        }

        // Fetch all active geofences from SwiftData
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.isActive }
        )

        guard let geofences = try? modelContext.fetch(descriptor) else {
            print("❌ Failed to fetch geofences")
            return
        }

        // iOS has a limit of 20 monitored regions
        let geofencesToMonitor = Array(geofences.prefix(20))

        if geofences.count > 20 {
            print("⚠️ More than 20 active geofences. Only monitoring first 20.")
        }

        for geofence in geofencesToMonitor {
            startMonitoring(geofence: geofence)
        }

        print("✅ Started monitoring \(geofencesToMonitor.count) geofences")
    }

    /// Start monitoring a specific geofence
    /// - Parameter geofence: The geofence to monitor
    func startMonitoring(geofence: Geofence) {
        guard hasGeofencingAuthorization else {
            print("⚠️ Cannot start monitoring geofence: insufficient authorization")
            return
        }

        // iOS limit: 20 regions
        if locationManager.monitoredRegions.count >= 20 {
            print("⚠️ Already monitoring 20 regions. Cannot add more.")
            return
        }

        let region = geofence.circularRegion
        locationManager.startMonitoring(for: region)

        print("✅ Started monitoring geofence: \(geofence.name)")
    }

    /// Stop monitoring a specific geofence
    /// - Parameter geofence: The geofence to stop monitoring
    func stopMonitoring(geofence: Geofence) {
        let identifier = geofence.id.uuidString

        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
            print("✅ Stopped monitoring geofence: \(geofence.name)")
        }
    }

    /// Stop monitoring all geofences
    func stopMonitoringAllGeofences() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        print("✅ Stopped monitoring all geofences")
    }

    /// Refresh monitored geofences (call after adding/updating/deleting geofences)
    func refreshMonitoredGeofences() {
        stopMonitoringAllGeofences()
        startMonitoringAllGeofences()
    }

    // MARK: - Active Geofence Events

    /// Load active geofence events from UserDefaults
    private func loadActiveGeofenceEvents() {
        if let data = UserDefaults.standard.data(forKey: "activeGeofenceEvents"),
           let decoded = try? JSONDecoder().decode([UUID: UUID].self, from: data) {
            activeGeofenceEvents = decoded
        }
    }

    /// Save active geofence events to UserDefaults
    private func saveActiveGeofenceEvents() {
        if let encoded = try? JSONEncoder().encode(activeGeofenceEvents) {
            UserDefaults.standard.set(encoded, forKey: "activeGeofenceEvents")
        }
    }

    /// Check if a geofence has an active event (user is currently inside)
    /// - Parameter geofenceId: The geofence ID
    /// - Returns: The active event ID if exists
    func activeEvent(for geofenceId: UUID) -> UUID? {
        return activeGeofenceEvents[geofenceId]
    }

    // MARK: - Event Creation/Update

    /// Handle geofence entry - create a new event
    private func handleGeofenceEntry(geofenceId: UUID) {
        // Fetch the geofence
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )

        guard let geofence = try? modelContext.fetch(descriptor).first else {
            print("❌ Geofence not found: \(geofenceId)")
            return
        }

        // Check if already has an active event
        if activeGeofenceEvents[geofenceId] != nil {
            print("⚠️ Geofence \(geofence.name) already has an active event")
            return
        }

        // Get the entry event type
        guard let eventType = geofence.eventTypeEntry else {
            print("⚠️ Geofence \(geofence.name) has no entry event type configured")
            return
        }

        // Create the event
        let event = Event(
            timestamp: Date(),
            eventType: eventType,
            notes: nil,
            sourceType: .geofence,
            geofenceId: geofenceId,
            locationLatitude: geofence.latitude,
            locationLongitude: geofence.longitude,
            locationName: geofence.name
        )

        modelContext.insert(event)

        do {
            try modelContext.save()

            // Track this as an active event
            activeGeofenceEvents[geofenceId] = event.id
            saveActiveGeofenceEvents()

            print("✅ Created geofence entry event: \(geofence.name)")

            // Send notification if enabled
            if geofence.notifyOnEntry, let notificationManager = notificationManager {
                Task {
                    await notificationManager.sendGeofenceEntryNotification(
                        geofenceName: geofence.name,
                        eventTypeName: eventType.name
                    )
                }
            }

            // Sync to backend if using backend mode
            Task { @MainActor in
                if eventStore.useBackend {
                    await eventStore.syncEventToBackend(event)
                }
            }

        } catch {
            print("❌ Failed to save geofence entry event: \(error)")
        }
    }

    /// Handle geofence exit - update the existing event with end date
    private func handleGeofenceExit(geofenceId: UUID) {
        // Fetch the geofence
        let geofenceDescriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )

        guard let geofence = try? modelContext.fetch(geofenceDescriptor).first else {
            print("❌ Geofence not found: \(geofenceId)")
            return
        }

        // Get the active event for this geofence
        guard let eventId = activeGeofenceEvents[geofenceId] else {
            print("⚠️ No active event found for geofence: \(geofence.name)")
            return
        }

        // Fetch the event
        let eventDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in event.id == eventId }
        )

        guard let event = try? modelContext.fetch(eventDescriptor).first else {
            print("❌ Event not found: \(eventId)")
            // Clean up orphaned active event
            activeGeofenceEvents.removeValue(forKey: geofenceId)
            saveActiveGeofenceEvents()
            return
        }

        // Update the event with end date
        event.endDate = Date()

        // Calculate duration
        let duration = event.endDate!.timeIntervalSince(event.timestamp)

        do {
            try modelContext.save()

            // Remove from active events
            activeGeofenceEvents.removeValue(forKey: geofenceId)
            saveActiveGeofenceEvents()

            print("✅ Updated geofence exit event: \(geofence.name)")

            // Send notification if enabled
            if geofence.notifyOnExit, let notificationManager = notificationManager, let eventType = event.eventType {
                Task {
                    await notificationManager.sendGeofenceExitNotification(
                        geofenceName: geofence.name,
                        eventTypeName: eventType.name,
                        duration: duration
                    )
                }
            }

            // Sync to backend if using backend mode
            Task { @MainActor in
                if eventStore.useBackend {
                    await eventStore.syncEventToBackend(event)
                }
            }

        } catch {
            print("❌ Failed to save geofence exit event: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension GeofenceManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        print("📍 Location authorization changed: \(authorizationStatus.description)")

        // Start monitoring if we now have authorization
        if hasGeofencingAuthorization && monitoredRegions.isEmpty {
            startMonitoringAllGeofences()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let geofenceId = UUID(uuidString: region.identifier) else {
            print("⚠️ Invalid region identifier: \(region.identifier)")
            return
        }

        print("📍 Entered geofence: \(region.identifier)")

        handleGeofenceEntry(geofenceId: geofenceId)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let geofenceId = UUID(uuidString: region.identifier) else {
            print("⚠️ Invalid region identifier: \(region.identifier)")
            return
        }

        print("📍 Exited geofence: \(region.identifier)")

        handleGeofenceExit(geofenceId: geofenceId)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region {
            print("❌ Monitoring failed for region \(region.identifier): \(error.localizedDescription)")
        } else {
            print("❌ Monitoring failed: \(error.localizedDescription)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("✅ Started monitoring region: \(region.identifier)")
    }
}

// MARK: - CLAuthorizationStatus Extension

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Authorized Always"
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        @unknown default:
            return "Unknown"
        }
    }
}
