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

    /// Timestamp of last geofence event (for debugging)
    var lastEventTimestamp: Date?

    /// Last geofence event description (for debugging)
    var lastEventDescription: String = "None"

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
            print("⚠️ Cannot start monitoring geofence '\(geofence.name)': insufficient authorization (current: \(authorizationStatus.description))")
            return
        }

        // iOS limit: 20 regions
        if locationManager.monitoredRegions.count >= 20 {
            print("⚠️ Already monitoring 20 regions. Cannot add more.")
            return
        }

        let region = geofence.circularRegion
        locationManager.startMonitoring(for: region)
        
        // Request state for this region to check if we're already inside
        locationManager.requestState(for: region)

        print("✅ Started monitoring geofence: \(geofence.name) (ID: \(geofence.id), radius: \(geofence.radius)m)")
        print("   📍 Location: \(geofence.latitude), \(geofence.longitude)")
        print("   📊 Total monitored regions: \(locationManager.monitoredRegions.count)")
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

    /// Reconciles CLLocationManager monitored regions with desired state.
    /// Removes stale regions and adds missing ones. This is the primary method
    /// for keeping iOS regions in sync with backend geofences.
    /// - Parameter desired: Array of GeofenceDefinitions representing desired state
    func reconcileRegions(desired: [GeofenceDefinition]) {
        guard hasGeofencingAuthorization else {
            print("⚠️ Cannot reconcile regions: insufficient authorization")
            return
        }

        // Limit to 20 (iOS maximum)
        let desiredLimited = Array(desired.prefix(20))

        // Build lookup by identifier
        let desiredById = Dictionary(uniqueKeysWithValues: desiredLimited.map { ($0.identifier, $0) })
        let desiredIds = Set(desiredById.keys)

        // Get current system regions
        let systemRegions = locationManager.monitoredRegions
        let systemIds = Set(systemRegions.compactMap { $0.identifier })

        var stoppedCount = 0
        var startedCount = 0

        // 1. Remove stale regions (in system but not in desired)
        for region in systemRegions {
            if !desiredIds.contains(region.identifier) {
                locationManager.stopMonitoring(for: region)
                stoppedCount += 1
                print("📍 Stopped monitoring stale region: \(region.identifier)")
            }
        }

        // 2. Add missing regions (in desired but not in system)
        for def in desiredLimited where !systemIds.contains(def.identifier) {
            let center = CLLocationCoordinate2D(latitude: def.latitude, longitude: def.longitude)
            let region = CLCircularRegion(
                center: center,
                radius: def.radius,
                identifier: def.identifier
            )
            region.notifyOnEntry = def.notifyOnEntry
            region.notifyOnExit = def.notifyOnExit

            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
            startedCount += 1

            print("📍 Started monitoring region: \(def.identifier) (\(def.name))")
        }

        print("📍 Region reconciliation complete: \(desiredLimited.count) desired, \(stoppedCount) stopped, \(startedCount) started, \(locationManager.monitoredRegions.count) total monitored")
    }

    // MARK: - Debug/Testing Methods
    
    #if DEBUG
    /// Simulate a geofence entry for testing purposes
    /// - Parameter geofenceId: The geofence ID to simulate entry for
    func simulateEntry(geofenceId: UUID) {
        print("🧪 DEBUG: Simulating geofence entry for ID: \(geofenceId)")
        handleGeofenceEntry(geofenceId: geofenceId)
    }
    
    /// Simulate a geofence exit for testing purposes
    /// - Parameter geofenceId: The geofence ID to simulate exit for
    func simulateExit(geofenceId: UUID) {
        print("🧪 DEBUG: Simulating geofence exit for ID: \(geofenceId)")
        handleGeofenceExit(geofenceId: geofenceId)
    }
    #endif

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

    // MARK: - Debug Properties

    /// For debugging: list of monitored region identifiers
    var monitoredRegionIdentifiers: [String] {
        monitoredRegions.map { $0.identifier }.sorted()
    }

    /// For debugging: count of active (in-progress) geofence events
    var activeGeofenceEventCount: Int {
        activeGeofenceEvents.count
    }

    /// For debugging: list of active geofence IDs
    var activeGeofenceIds: [UUID] {
        Array(activeGeofenceEvents.keys)
    }

    // MARK: - Event Creation/Update

    /// Handle geofence entry - create a new event
    private func handleGeofenceEntry(geofenceId: UUID) {
        print("🔍 handleGeofenceEntry called for geofenceId: \(geofenceId)")
        
        // Fetch the geofence
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )

        guard let geofence = try? modelContext.fetch(descriptor).first else {
            print("❌ Geofence not found in database for ID: \(geofenceId)")
            return
        }
        
        print("✅ Found geofence: \(geofence.name)")

        // Check if already has an active event
        if activeGeofenceEvents[geofenceId] != nil {
            print("⚠️ Geofence \(geofence.name) already has an active event (ID: \(activeGeofenceEvents[geofenceId]!))")
            return
        }

        // Get the entry event type by ID
        guard let eventTypeEntryID = geofence.eventTypeEntryID else {
            print("❌ Geofence '\(geofence.name)' has NO eventTypeEntryID set!")
            print("   This geofence needs to be edited to select an Event Type.")
            return
        }
        
        print("🔍 Looking for EventType with ID: \(eventTypeEntryID)")
        
        // Fetch the EventType by ID
        let eventTypeDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { eventType in eventType.id == eventTypeEntryID }
        )
        
        guard let eventType = try? modelContext.fetch(eventTypeDescriptor).first else {
            print("❌ EventType not found for ID: \(eventTypeEntryID)")
            print("   The Event Type may have been deleted. Edit the geofence to select a new one.")
            return
        }
        
        print("✅ Found EventType: \(eventType.name)")

        // Create the event with entry timestamp property
        print("📝 Creating new Event...")
        let entryTime = Date()
        let entryProperties: [String: PropertyValue] = [
            "Entered At": PropertyValue(type: .date, value: entryTime)
        ]
        
        let event = Event(
            timestamp: entryTime,
            eventType: eventType,
            notes: "Auto-logged by geofence: \(geofence.name)",
            sourceType: .geofence,
            geofenceId: geofenceId,
            locationLatitude: geofence.latitude,
            locationLongitude: geofence.longitude,
            locationName: geofence.name,
            properties: entryProperties
        )

        modelContext.insert(event)

        do {
            try modelContext.save()

            // Track this as an active event
            activeGeofenceEvents[geofenceId] = event.id
            saveActiveGeofenceEvents()

            print("✅✅✅ SUCCESS! Created geofence entry event for: \(geofence.name)")
            print("   Event ID: \(event.id)")
            print("   Event Type: \(eventType.name)")
            print("   Timestamp: \(event.timestamp)")

            // Track for debugging
            lastEventTimestamp = Date()
            lastEventDescription = "Entry: \(geofence.name)"

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

        // Update the event with end date and exit properties
        let exitTime = Date()
        event.endDate = exitTime
        
        // Calculate duration in seconds
        let durationSeconds = exitTime.timeIntervalSince(event.timestamp)
        
        // Add "Exited At" and "Duration" properties while preserving existing properties
        var updatedProperties = event.properties
        updatedProperties["Exited At"] = PropertyValue(type: .date, value: exitTime)
        updatedProperties["Duration"] = PropertyValue(type: .duration, value: durationSeconds)
        event.properties = updatedProperties

        // Use duration for notification
        let duration = durationSeconds

        do {
            try modelContext.save()

            // Remove from active events
            activeGeofenceEvents.removeValue(forKey: geofenceId)
            saveActiveGeofenceEvents()

            print("✅ Updated geofence exit event: \(geofence.name)")

            // Track for debugging
            lastEventTimestamp = Date()
            lastEventDescription = "Exit: \(geofence.name)"

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
        print("   🔑 Has geofencing authorization: \(hasGeofencingAuthorization)")
        print("   📍 Location services enabled: \(isLocationServicesEnabled)")

        // Start monitoring if we now have authorization
        if hasGeofencingAuthorization && monitoredRegions.isEmpty {
            print("📍 Starting to monitor all geofences...")
            startMonitoringAllGeofences()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier

        print("📍🟢 ENTERED geofence: \(identifier)")
        print("   ⏰ Time: \(Date())")

        // Dispatch to main actor since EventStore is MainActor-isolated
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                print("⚠️ Unknown region identifier on entry: \(identifier)")
                return
            }
            handleGeofenceEntry(geofenceId: localId)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier

        print("📍🔴 EXITED geofence: \(identifier)")
        print("   ⏰ Time: \(Date())")

        // Dispatch to main actor since EventStore is MainActor-isolated
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                print("⚠️ Unknown region identifier on exit: \(identifier)")
                return
            }
            handleGeofenceExit(geofenceId: localId)
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let stateDescription: String
        switch state {
        case .inside:
            stateDescription = "INSIDE"
        case .outside:
            stateDescription = "OUTSIDE"
        case .unknown:
            stateDescription = "UNKNOWN"
        }

        print("📍 Region state determined for \(region.identifier): \(stateDescription)")

        // If we're already inside when we start monitoring, trigger entry
        if state == .inside {
            // Dispatch to main actor since EventStore is MainActor-isolated
            Task { @MainActor in
                guard let localId = eventStore.lookupLocalGeofenceId(from: region.identifier) else {
                    return
                }

                if activeGeofenceEvents[localId] == nil {
                    print("📍 Already inside geofence, triggering entry event...")
                    handleGeofenceEntry(geofenceId: localId)
                }
            }
        }
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
