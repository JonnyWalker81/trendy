//
//  GeofenceManager+CLLocationManagerDelegate.swift
//  trendy
//
//  CLLocationManagerDelegate protocol conformance
//

import Foundation
import CoreLocation

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
            ctx.add("monitoredRegionsCount", manager.monitoredRegions.count)
        })

        // Dispatch to main actor since EventStore is MainActor-isolated
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                // Enhanced logging for troubleshooting lookup failures
                Log.geofence.warning("Unknown region identifier on entry - geofence not found in local database", context: .with { ctx in
                    ctx.add("identifier", identifier)
                    ctx.add("hint", "Geofence may not be synced yet, or was deleted. Check if backend sync is complete.")
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
            ctx.add("monitoredRegionsCount", manager.monitoredRegions.count)
        })

        // Dispatch to main actor since EventStore is MainActor-isolated
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                // Enhanced logging for troubleshooting lookup failures
                Log.geofence.warning("Unknown region identifier on exit - geofence not found in local database", context: .with { ctx in
                    ctx.add("identifier", identifier)
                    ctx.add("hint", "Geofence may not be synced yet, or was deleted. Check if backend sync is complete.")
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
