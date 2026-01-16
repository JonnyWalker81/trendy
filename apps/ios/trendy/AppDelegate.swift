//
//  AppDelegate.swift
//  trendy
//
//  Handles background location launches for geofence events.
//  When iOS terminates the app and a geofence event occurs, iOS relaunches
//  the app with the .location key in launch options. This AppDelegate
//  creates a CLLocationManager immediately to receive pending region events.
//

import Foundation
import UIKit
import CoreLocation

/// AppDelegate for handling background location launches
///
/// SwiftUI's ScenePhase cannot handle didFinishLaunchingWithOptions with the .location key.
/// This AppDelegate is integrated via UIApplicationDelegateAdaptor to ensure geofence events
/// received when the app is terminated are properly handled.
class AppDelegate: NSObject, UIApplicationDelegate, CLLocationManagerDelegate {

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

        return true
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Log.geofence.info("Background launch: Entered region", context: .with { ctx in
            ctx.add("identifier", region.identifier)
        })

        // Forward to GeofenceManager via NotificationCenter.
        // GeofenceManager may not be initialized yet during background launch,
        // so we use notifications to decouple the event delivery.
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

        // Forward to GeofenceManager via NotificationCenter.
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
