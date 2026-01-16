//
//  GeofenceManager+Authorization.swift
//  trendy
//
//  Location authorization request flow
//

import Foundation
import CoreLocation

// MARK: - Authorization

extension GeofenceManager {

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
}
