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

    /// Set of geofence IDs currently being processed (for race condition prevention)
    /// This is the "early claim" pattern used in HealthKit processing.
    /// @MainActor ensures thread-safe access since all geofence event handling
    /// is dispatched to the main actor.
    @MainActor internal static var processingGeofenceIds: Set<String> = []

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

        // Process any pending events that arrived before we were initialized.
        // This handles the race condition where iOS delivers geofence events
        // during background launch before GeofenceManager is ready.
        processPendingBackgroundEvents()
    }

    /// Process any pending geofence events that arrived before initialization.
    /// This drains the AppDelegate's pending events queue and processes each event.
    private func processPendingBackgroundEvents() {
        let pendingEvents = AppDelegate.drainPendingEvents()

        guard !pendingEvents.isEmpty else {
            Log.geofence.debug("No pending background events to process")
            return
        }

        Log.geofence.info("Processing pending background events", context: .with { ctx in
            ctx.add("count", pendingEvents.count)
        })

        for event in pendingEvents {
            Task { @MainActor in
                guard let localId = eventStore.lookupLocalGeofenceId(from: event.regionIdentifier) else {
                    Log.geofence.warning("Unknown region identifier in pending event", context: .with { ctx in
                        ctx.add("identifier", event.regionIdentifier)
                        ctx.add("type", event.type == .entry ? "entry" : "exit")
                        ctx.add("age_seconds", Int(Date().timeIntervalSince(event.timestamp)))
                    })
                    return
                }

                switch event.type {
                case .entry:
                    Log.geofence.info("Processing pending entry event", context: .with { ctx in
                        ctx.add("identifier", event.regionIdentifier)
                        ctx.add("age_seconds", Int(Date().timeIntervalSince(event.timestamp)))
                    })
                    handleGeofenceEntry(geofenceId: localId)
                case .exit:
                    Log.geofence.info("Processing pending exit event", context: .with { ctx in
                        ctx.add("identifier", event.regionIdentifier)
                        ctx.add("age_seconds", Int(Date().timeIntervalSince(event.timestamp)))
                    })
                    handleGeofenceExit(geofenceId: localId)
                }
            }
        }
    }

    // MARK: - Lifecycle

    deinit {
        locationManager.delegate = nil
        NotificationCenter.default.removeObserver(self)
    }
}
