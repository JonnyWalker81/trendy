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

    // MARK: - Notification Names

    /// Notification posted by AppDelegate when a geofence entry event is received during background launch
    static let backgroundEntryNotification = Notification.Name("GeofenceManager.backgroundEntry")

    /// Notification posted by AppDelegate when a geofence exit event is received during background launch
    static let backgroundExitNotification = Notification.Name("GeofenceManager.backgroundExit")

    // MARK: - Properties

    private let locationManager: CLLocationManager
    private let modelContext: ModelContext
    private let eventStore: EventStore
    private let notificationManager: NotificationManager?

    /// Current authorization status
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Last error that occurred during geofence operations
    /// UI can observe this to show alerts when geofence event saves fail
    var lastError: GeofenceError?

    /// Flag to track if we're waiting to upgrade from "When In Use" to "Always" authorization
    private var pendingAlwaysAuthorizationRequest = false

    /// Whether location services are available
    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    /// Currently monitored regions
    var monitoredRegions: Set<CLRegion> {
        locationManager.monitoredRegions
    }

    /// Active geofence events (entry recorded, waiting for exit)
    private var activeGeofenceEvents: [String: String] = [:] // geofenceId -> eventId

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

        // Register for background event notifications from AppDelegate
        // This allows us to receive geofence events that occurred during background launch
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundEntry(_:)),
            name: Self.backgroundEntryNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundExit(_:)),
            name: Self.backgroundExitNotification,
            object: nil
        )

        Log.geofence.debug("GeofenceManager initialized with background event observers")
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

    /// Current location if available (requires at least When In Use authorization)
    var currentLocation: CLLocationCoordinate2D? {
        guard authorizationStatus == .authorizedWhenInUse ||
              authorizationStatus == .authorizedAlways else {
            return nil
        }
        return locationManager.location?.coordinate
    }

    /// Request geofencing authorization using the proper two-step flow.
    /// This method handles the iOS requirement that "When In Use" must be granted
    /// before "Always" can be requested. The delegate callback will automatically
    /// request "Always" after "When In Use" is granted.
    /// - Returns: `true` if a settings redirect is needed (denied/restricted), `false` otherwise
    @discardableResult
    func requestGeofencingAuthorization() -> Bool {
        switch authorizationStatus {
        case .notDetermined:
            // Step 1: Request "When In Use" first, the delegate will handle step 2
            pendingAlwaysAuthorizationRequest = true
            locationManager.requestWhenInUseAuthorization()
            Log.geofence.info("Requesting When In Use authorization (step 1 of 2)")
            return false

        case .authorizedWhenInUse:
            // Step 2: Already have "When In Use", request upgrade to "Always"
            locationManager.requestAlwaysAuthorization()
            Log.geofence.info("Requesting Always authorization (upgrade from When In Use)")
            return false

        case .denied, .restricted:
            // Can't request programmatically, user must go to Settings
            Log.geofence.warning("Authorization denied/restricted, settings redirect needed")
            return true

        case .authorizedAlways:
            // Already have full authorization
            Log.geofence.debug("Already have Always authorization")
            return false

        @unknown default:
            Log.geofence.warning("Unknown authorization status: \(authorizationStatus.rawValue)")
            return false
        }
    }

    // MARK: - Lifecycle

    deinit {
        locationManager.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Geofence Management

    /// Start monitoring all active geofences
    func startMonitoringAllGeofences() {
        guard hasGeofencingAuthorization else {
            Log.geofence.warning("Cannot start monitoring: insufficient authorization")
            return
        }

        // Fetch all active geofences from SwiftData
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.isActive }
        )

        guard let geofences = try? modelContext.fetch(descriptor) else {
            Log.geofence.error("Failed to fetch geofences from SwiftData")
            return
        }

        // iOS has a limit of 20 monitored regions
        let geofencesToMonitor = Array(geofences.prefix(20))

        if geofences.count > 20 {
            Log.geofence.warning("More than 20 active geofences", context: .with { ctx in
                ctx.add("total", geofences.count)
                ctx.add("monitoring", 20)
            })
        }

        for geofence in geofencesToMonitor {
            startMonitoring(geofence: geofence)
        }

        Log.geofence.info("Started monitoring geofences", context: .with { ctx in
            ctx.add("count", geofencesToMonitor.count)
        })
    }

    /// Start monitoring a specific geofence
    /// - Parameter geofence: The geofence to monitor
    func startMonitoring(geofence: Geofence) {
        guard hasGeofencingAuthorization else {
            Log.geofence.warning("Cannot start monitoring geofence: insufficient authorization", context: .with { ctx in
                ctx.add("name", geofence.name)
                ctx.add("status", authorizationStatus.description)
            })
            return
        }

        // iOS limit: 20 regions
        if locationManager.monitoredRegions.count >= 20 {
            Log.geofence.warning("Already monitoring 20 regions, cannot add more")
            return
        }

        let region = geofence.circularRegion
        locationManager.startMonitoring(for: region)

        // Request state for this region to check if we're already inside
        locationManager.requestState(for: region)

        Log.geofence.debug("Started monitoring geofence", context: .with { ctx in
            ctx.add("name", geofence.name)
            ctx.add("id", geofence.id)
            ctx.add("radius", Int(geofence.radius))
            ctx.add("latitude", geofence.latitude)
            ctx.add("longitude", geofence.longitude)
            ctx.add("totalRegions", locationManager.monitoredRegions.count)
        })
    }

    /// Stop monitoring a specific geofence
    /// - Parameter geofence: The geofence to stop monitoring
    func stopMonitoring(geofence: Geofence) {
        // Use regionIdentifier which prefers backendId when available
        let identifier = geofence.regionIdentifier

        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
            Log.geofence.debug("Stopped monitoring geofence", context: .with { ctx in
                ctx.add("name", geofence.name)
                ctx.add("id", identifier)
            })
        }
    }

    /// Stop monitoring all geofences
    func stopMonitoringAllGeofences() {
        let count = locationManager.monitoredRegions.count
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        Log.geofence.info("Stopped monitoring all geofences", context: .with { ctx in
            ctx.add("count", count)
        })
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
            Log.geofence.warning("Cannot reconcile regions: insufficient authorization")
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

        Log.geofence.info("Starting region reconciliation", context: .with { ctx in
            ctx.add("desired_count", desiredLimited.count)
            ctx.add("system_count", systemRegions.count)
        })

        // 1. Remove stale regions (in system but not in desired)
        for region in systemRegions {
            if !desiredIds.contains(region.identifier) {
                locationManager.stopMonitoring(for: region)
                stoppedCount += 1
                Log.geofence.debug("Stopped monitoring stale region", context: .with { ctx in
                    ctx.add("region_id", region.identifier)
                })
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

            Log.geofence.debug("Started monitoring region", context: .with { ctx in
                ctx.add("region_id", def.identifier)
                ctx.add("name", def.name)
            })
        }

        Log.geofence.info("Region reconciliation complete", context: .with { ctx in
            ctx.add("desired", desiredLimited.count)
            ctx.add("stopped", stoppedCount)
            ctx.add("started", startedCount)
            ctx.add("total_monitored", locationManager.monitoredRegions.count)
        })
    }

    /// Ensures all active geofences are registered with iOS.
    /// Safe to call at any lifecycle point - idempotent operation.
    /// Call this on: app launch, scene activation, authorization restoration.
    func ensureRegionsRegistered() {
        guard hasGeofencingAuthorization else {
            Log.geofence.debug("ensureRegionsRegistered: skipping, no authorization")
            return
        }

        // Fetch active geofences from SwiftData
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.isActive }
        )

        guard let geofences = try? modelContext.fetch(descriptor) else {
            Log.geofence.error("ensureRegionsRegistered: failed to fetch geofences")
            return
        }

        // Convert to GeofenceDefinition for reconciliation
        let definitions = geofences.map { geofence in
            GeofenceDefinition(
                identifier: geofence.regionIdentifier,
                name: geofence.name,
                latitude: geofence.latitude,
                longitude: geofence.longitude,
                radius: geofence.radius,
                notifyOnEntry: geofence.notifyOnEntry,
                notifyOnExit: geofence.notifyOnExit
            )
        }

        Log.geofence.info("ensureRegionsRegistered called", context: .with { ctx in
            ctx.add("desired_count", definitions.count)
            ctx.add("current_ios_count", locationManager.monitoredRegions.count)
        })

        reconcileRegions(desired: definitions)
    }

    // MARK: - Debug/Testing Methods
    
    #if DEBUG
    /// Simulate a geofence entry for testing purposes
    /// - Parameter geofenceId: The geofence ID to simulate entry for
    func simulateEntry(geofenceId: String) {
        Log.geofence.debug("DEBUG: Simulating geofence entry", context: .with { ctx in
            ctx.add("geofenceId", geofenceId)
        })
        handleGeofenceEntry(geofenceId: geofenceId)
    }

    /// Simulate a geofence exit for testing purposes
    /// - Parameter geofenceId: The geofence ID to simulate exit for
    func simulateExit(geofenceId: String) {
        Log.geofence.debug("DEBUG: Simulating geofence exit", context: .with { ctx in
            ctx.add("geofenceId", geofenceId)
        })
        handleGeofenceExit(geofenceId: geofenceId)
    }
    #endif

    // MARK: - Active Geofence Events

    /// Load active geofence events from UserDefaults
    private func loadActiveGeofenceEvents() {
        if let data = UserDefaults.standard.data(forKey: "activeGeofenceEvents"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
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
    func activeEvent(for geofenceId: String) -> String? {
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
    var activeGeofenceIds: [String] {
        Array(activeGeofenceEvents.keys)
    }

    // MARK: - Background Event Handlers

    /// Handle background entry notification from AppDelegate
    /// Called when app is relaunched due to a geofence entry event
    @objc private func handleBackgroundEntry(_ notification: Notification) {
        guard let identifier = notification.userInfo?["identifier"] as? String else {
            Log.geofence.warning("Background entry notification missing identifier")
            return
        }

        Log.geofence.info("Processing background entry event", context: .with { ctx in
            ctx.add("identifier", identifier)
        })

        // Forward to existing entry handling flow using same dispatch pattern as delegate
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                Log.geofence.warning("Unknown region identifier on background entry", context: .with { ctx in
                    ctx.add("identifier", identifier)
                })
                return
            }
            self.handleGeofenceEntry(geofenceId: localId)
        }
    }

    /// Handle background exit notification from AppDelegate
    /// Called when app is relaunched due to a geofence exit event
    @objc private func handleBackgroundExit(_ notification: Notification) {
        guard let identifier = notification.userInfo?["identifier"] as? String else {
            Log.geofence.warning("Background exit notification missing identifier")
            return
        }

        Log.geofence.info("Processing background exit event", context: .with { ctx in
            ctx.add("identifier", identifier)
        })

        // Forward to existing exit handling flow using same dispatch pattern as delegate
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                Log.geofence.warning("Unknown region identifier on background exit", context: .with { ctx in
                    ctx.add("identifier", identifier)
                })
                return
            }
            self.handleGeofenceExit(geofenceId: localId)
        }
    }

    // MARK: - Event Creation/Update

    /// Handle geofence entry - create a new event
    private func handleGeofenceEntry(geofenceId: String) {
        Log.geofence.debug("handleGeofenceEntry called", context: .with { ctx in
            ctx.add("geofenceId", geofenceId)
        })

        // Fetch the geofence
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )

        guard let geofence = try? modelContext.fetch(descriptor).first else {
            Log.geofence.error("Geofence not found in database", context: .with { ctx in
                ctx.add("geofenceId", geofenceId)
            })
            return
        }

        Log.geofence.debug("Found geofence", context: .with { ctx in
            ctx.add("name", geofence.name)
        })

        // Check if already has an active event
        if let existingEventId = activeGeofenceEvents[geofenceId] {
            Log.geofence.warning("Geofence already has an active event", context: .with { ctx in
                ctx.add("name", geofence.name)
                ctx.add("existingEventId", existingEventId)
            })
            return
        }

        // Get the entry event type by ID
        guard let eventTypeEntryID = geofence.eventTypeEntryID else {
            Log.geofence.error("Geofence has no eventTypeEntryID set", context: .with { ctx in
                ctx.add("name", geofence.name)
            })
            return
        }

        Log.geofence.debug("Looking for EventType", context: .with { ctx in
            ctx.add("eventTypeId", eventTypeEntryID)
        })

        // Fetch the EventType by ID
        let eventTypeDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { eventType in eventType.id == eventTypeEntryID }
        )

        guard let eventType = try? modelContext.fetch(eventTypeDescriptor).first else {
            Log.geofence.error("EventType not found", context: .with { ctx in
                ctx.add("eventTypeId", eventTypeEntryID)
                ctx.add("geofenceName", geofence.name)
            })
            return
        }

        Log.geofence.debug("Found EventType", context: .with { ctx in
            ctx.add("name", eventType.name)
        })

        // Create the event with entry timestamp property
        Log.geofence.debug("Creating new Event for geofence entry")
        let entryTime = Date()
        let entryProperties: [String: PropertyValue] = [
            "Entered At": PropertyValue(type: .date, value: entryTime)
        ]

        // Use geofence ID for linking (now single canonical ID)
        let event = Event(
            timestamp: entryTime,
            eventType: eventType,
            notes: "Auto-logged by geofence: \(geofence.name)",
            sourceType: .geofence,
            geofenceId: geofence.id,  // Uses canonical UUIDv7 string ID
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

            Log.geofence.info("Created geofence entry event", context: .with { ctx in
                ctx.add("geofenceName", geofence.name)
                ctx.add("eventId", event.id)
                ctx.add("eventType", eventType.name)
            })

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

            // Sync to backend (SyncEngine handles offline queueing)
            Task { @MainActor in
                await eventStore.syncEventToBackend(event)
            }

        } catch {
            Log.geofence.error("Failed to save geofence entry event", error: error)
            lastError = .entryEventSaveFailed(geofence.name, error)
        }
    }

    /// Handle geofence exit - update the existing event with end date
    private func handleGeofenceExit(geofenceId: String) {
        // Fetch the geofence
        let geofenceDescriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )

        guard let geofence = try? modelContext.fetch(geofenceDescriptor).first else {
            Log.geofence.error("Geofence not found for exit", context: .with { ctx in
                ctx.add("geofenceId", geofenceId)
            })
            return
        }

        // Get the active event for this geofence
        guard let eventId = activeGeofenceEvents[geofenceId] else {
            Log.geofence.warning("No active event found for geofence exit", context: .with { ctx in
                ctx.add("name", geofence.name)
            })
            return
        }

        // Fetch the event
        let eventDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in event.id == eventId }
        )

        guard let event = try? modelContext.fetch(eventDescriptor).first else {
            Log.geofence.error("Event not found for geofence exit", context: .with { ctx in
                ctx.add("eventId", eventId)
            })
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

            Log.geofence.info("Updated geofence exit event", context: .with { ctx in
                ctx.add("geofenceName", geofence.name)
                ctx.add("eventId", event.id)
                ctx.add("durationSeconds", Int(duration))
            })

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

            // Sync to backend (SyncEngine handles offline queueing)
            Task { @MainActor in
                await eventStore.syncEventToBackend(event)
            }

        } catch {
            Log.geofence.error("Failed to save geofence exit event", error: error)
            lastError = .exitEventSaveFailed(geofence.name, error)
        }
    }

    /// Clear the last error (call after UI has handled it)
    func clearError() {
        lastError = nil
    }
}

// MARK: - CLLocationManagerDelegate

extension GeofenceManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let previousStatus = authorizationStatus
        authorizationStatus = manager.authorizationStatus
        let servicesEnabled = CLLocationManager.locationServicesEnabled()

        Log.geofence.info("Authorization changed", context: .with { ctx in
            ctx.add("previous", previousStatus.description)
            ctx.add("current", authorizationStatus.description)
            ctx.add("servicesEnabled", servicesEnabled)
            ctx.add("hasGeofencingAuth", hasGeofencingAuthorization)
        })

        // Handle two-step authorization flow:
        // If we just got "When In Use" and we were waiting to request "Always", do it now
        if authorizationStatus == .authorizedWhenInUse && pendingAlwaysAuthorizationRequest {
            pendingAlwaysAuthorizationRequest = false
            Log.geofence.info("Requesting Always authorization (step 2 of 2)")
            locationManager.requestAlwaysAuthorization()
            return
        }

        // Clear the pending flag if authorization was denied or we got a final state
        if authorizationStatus == .denied || authorizationStatus == .restricted || authorizationStatus == .authorizedAlways {
            pendingAlwaysAuthorizationRequest = false
        }

        // Handle authorization gain or restoration
        // Use ensureRegionsRegistered for idempotent re-registration
        if hasGeofencingAuthorization && previousStatus != .authorizedAlways {
            Log.geofence.info("Authorization granted/restored, ensuring regions registered")
            ensureRegionsRegistered()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier

        Log.geofence.info("ENTERED geofence region", context: .with { ctx in
            ctx.add("identifier", identifier)
        })

        // Dispatch to main actor since EventStore is MainActor-isolated
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                Log.geofence.warning("Unknown region identifier on entry", context: .with { ctx in
                    ctx.add("identifier", identifier)
                })
                return
            }
            handleGeofenceEntry(geofenceId: localId)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier

        Log.geofence.info("EXITED geofence region", context: .with { ctx in
            ctx.add("identifier", identifier)
        })

        // Dispatch to main actor since EventStore is MainActor-isolated
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                Log.geofence.warning("Unknown region identifier on exit", context: .with { ctx in
                    ctx.add("identifier", identifier)
                })
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

        Log.geofence.debug("Region state determined", context: .with { ctx in
            ctx.add("identifier", region.identifier)
            ctx.add("state", stateDescription)
        })

        // If we're already inside when we start monitoring, trigger entry
        if state == .inside {
            // Dispatch to main actor since EventStore is MainActor-isolated
            Task { @MainActor in
                guard let localId = eventStore.lookupLocalGeofenceId(from: region.identifier) else {
                    return
                }

                if activeGeofenceEvents[localId] == nil {
                    Log.geofence.debug("Already inside geofence, triggering entry event", context: .with { ctx in
                        ctx.add("identifier", region.identifier)
                    })
                    handleGeofenceEntry(geofenceId: localId)
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region {
            Log.geofence.error("Monitoring failed for region", context: .with { ctx in
                ctx.add("identifier", region.identifier)
                ctx.add(error: error)
            })
        } else {
            Log.geofence.error("Monitoring failed", error: error)
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        Log.geofence.debug("Started monitoring region", context: .with { ctx in
            ctx.add("identifier", region.identifier)
        })
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
