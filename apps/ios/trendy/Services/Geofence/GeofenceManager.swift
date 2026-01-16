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

    internal let locationManager: CLLocationManager
    internal let modelContext: ModelContext
    internal let eventStore: EventStore
    internal let notificationManager: NotificationManager?

    /// Current authorization status
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Last error that occurred during geofence operations
    /// UI can observe this to show alerts when geofence event saves fail
    var lastError: GeofenceError?

    /// Flag to track if we're waiting to upgrade from "When In Use" to "Always" authorization
    internal var pendingAlwaysAuthorizationRequest = false

    /// Whether location services are available
    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    /// Currently monitored regions
    var monitoredRegions: Set<CLRegion> {
        locationManager.monitoredRegions
    }

    /// Active geofence events (entry recorded, waiting for exit)
    internal var activeGeofenceEvents: [String: String] = [:] // geofenceId -> eventId

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

        // Register for normal launch notifications from AppDelegate
        // This ensures regions are re-registered after device restart, iOS eviction, etc.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNormalLaunch(_:)),
            name: AppDelegate.normalLaunchNotification,
            object: nil
        )

        Log.geofence.debug("GeofenceManager initialized with background and launch event observers")
    }

    // MARK: - Lifecycle

    deinit {
        locationManager.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }
}
