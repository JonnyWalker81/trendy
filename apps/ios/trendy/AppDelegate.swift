//
//  AppDelegate.swift
//  trendy
//
//  Handles background location launches for geofence events.
//  When iOS terminates the app and a geofence event occurs, iOS relaunches
//  the app with the .location key in launch options. This AppDelegate
//  creates a CLLocationManager immediately to receive pending region events.
//
//  IMPORTANT: This AppDelegate uses a pending events queue to handle the race condition
//  where geofence events arrive before GeofenceManager is initialized. Events are stored
//  and can be retrieved once the manager is ready.
//

import Foundation
import UIKit
import CoreLocation

/// Represents a pending geofence event received during background launch
/// before GeofenceManager was ready to process it.
struct PendingGeofenceEvent {
    enum EventType {
        case entry
        case exit
    }

    let type: EventType
    let regionIdentifier: String
    let timestamp: Date

    init(type: EventType, regionIdentifier: String) {
        self.type = type
        self.regionIdentifier = regionIdentifier
        self.timestamp = Date()
    }
}

/// AppDelegate for handling background location launches
///
/// SwiftUI's ScenePhase cannot handle didFinishLaunchingWithOptions with the .location key.
/// This AppDelegate is integrated via UIApplicationDelegateAdaptor to ensure geofence events
/// received when the app is terminated are properly handled.
///
/// ## Background Launch Race Condition
///
/// When iOS launches the app in the background for a geofence event:
/// 1. AppDelegate.didFinishLaunchingWithOptions is called
/// 2. CLLocationManager delegate methods fire with pending events
/// 3. GeofenceManager may NOT be initialized yet (SwiftUI app initialization is async)
///
/// To handle this, AppDelegate stores pending events in a queue that GeofenceManager
/// can drain once it's ready. Events older than 5 minutes are considered stale and discarded.
class AppDelegate: NSObject, UIApplicationDelegate, CLLocationManagerDelegate {

    // MARK: - Notification Names

    /// Notification posted on every app launch to trigger geofence re-registration.
    /// GeofenceManager observes this to ensure regions are registered after:
    /// device restart, iOS eviction, app updates, or normal user launch.
    static let normalLaunchNotification = Notification.Name("GeofenceManager.normalLaunch")

    // MARK: - Pending Events Queue

    /// Thread-safe queue of pending geofence events received before GeofenceManager was ready.
    /// Access via `drainPendingEvents()` to retrieve and clear all pending events.
    private static var pendingEvents: [PendingGeofenceEvent] = []
    private static let pendingEventsLock = NSLock()

    /// Maximum age of pending events (5 minutes). Events older than this are discarded.
    private static let maxEventAge: TimeInterval = 300

    /// Retrieve and clear all pending geofence events.
    /// Called by GeofenceManager once it's ready to process events.
    /// - Returns: Array of pending events, filtered to remove stale events (> 5 min old)
    static func drainPendingEvents() -> [PendingGeofenceEvent] {
        pendingEventsLock.lock()
        defer { pendingEventsLock.unlock() }

        let now = Date()
        let validEvents = pendingEvents.filter { now.timeIntervalSince($0.timestamp) < maxEventAge }

        let staleCount = pendingEvents.count - validEvents.count
        if staleCount > 0 {
            Log.geofence.warning("Discarding stale pending events", context: .with { ctx in
                ctx.add("stale_count", staleCount)
                ctx.add("max_age_seconds", Int(maxEventAge))
            })
        }

        Log.geofence.info("Draining pending geofence events", context: .with { ctx in
            ctx.add("valid_count", validEvents.count)
            ctx.add("total_count", pendingEvents.count)
        })

        pendingEvents.removeAll()
        return validEvents
    }

    /// Add an event to the pending queue.
    private static func enqueuePendingEvent(_ event: PendingGeofenceEvent) {
        pendingEventsLock.lock()
        defer { pendingEventsLock.unlock() }

        pendingEvents.append(event)
        Log.geofence.debug("Enqueued pending geofence event", context: .with { ctx in
            ctx.add("type", event.type == .entry ? "entry" : "exit")
            ctx.add("identifier", event.regionIdentifier)
            ctx.add("queue_size", pendingEvents.count)
        })
    }

    /// Check if there are any pending events.
    static var hasPendingEvents: Bool {
        pendingEventsLock.lock()
        defer { pendingEventsLock.unlock() }
        return !pendingEvents.isEmpty
    }

    // MARK: - Properties

    /// Location manager for receiving pending region events during background launch.
    /// This is separate from GeofenceManager's location manager and exists only to
    /// receive events that occur when the app is relaunched due to a location event.
    private var locationManager: CLLocationManager?

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Check if app was launched due to a location event
        if launchOptions?[.location] != nil {
            Log.geofence.info("App launched due to location event - initializing location manager for pending events")

            // Create CLLocationManager immediately to receive pending region events.
            // The delegate methods will be called after this method returns.
            locationManager = CLLocationManager()
            locationManager?.delegate = self

            Log.geofence.debug("Location manager initialized for background launch", context: .with { ctx in
                ctx.add("authorization", locationManager?.authorizationStatus.description ?? "unknown")
                ctx.add("monitoredRegions", locationManager?.monitoredRegions.count ?? 0)
            })
        }

        // For all launches (background or normal), notify GeofenceManager to ensure regions
        // This handles device restart, iOS eviction, app updates, and normal app launch scenarios
        NotificationCenter.default.post(name: Self.normalLaunchNotification, object: nil)
        Log.geofence.info("Posted normal launch notification for region re-registration")

        return true
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Log.geofence.info("Background launch: Entered region", context: .with { ctx in
            ctx.add("identifier", region.identifier)
        })

        // Store in pending queue for GeofenceManager to process once ready.
        // This handles the race condition where events arrive before GeofenceManager is initialized.
        Self.enqueuePendingEvent(PendingGeofenceEvent(type: .entry, regionIdentifier: region.identifier))

        // Also post notification for immediate processing if GeofenceManager is already listening.
        NotificationCenter.default.post(
            name: GeofenceManager.backgroundEntryNotification,
            object: nil,
            userInfo: ["identifier": region.identifier]
        )
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Log.geofence.info("Background launch: Exited region", context: .with { ctx in
            ctx.add("identifier", region.identifier)
        })

        // Store in pending queue for GeofenceManager to process once ready.
        Self.enqueuePendingEvent(PendingGeofenceEvent(type: .exit, regionIdentifier: region.identifier))

        // Also post notification for immediate processing if GeofenceManager is already listening.
        NotificationCenter.default.post(
            name: GeofenceManager.backgroundExitNotification,
            object: nil,
            userInfo: ["identifier": region.identifier]
        )
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

        Log.geofence.debug("Background launch: Region state determined", context: .with { ctx in
            ctx.add("identifier", region.identifier)
            ctx.add("state", stateDescription)
        })
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region {
            Log.geofence.error("Background launch: Monitoring failed for region", context: .with { ctx in
                ctx.add("identifier", region.identifier)
                ctx.add(error: error)
            })
        } else {
            Log.geofence.error("Background launch: Monitoring failed", error: error)
        }
    }
}

// Note: CLAuthorizationStatus.description extension is defined in GeofenceManager.swift
