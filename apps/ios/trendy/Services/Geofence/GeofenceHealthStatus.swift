//
//  GeofenceHealthStatus.swift
//  trendy
//
//  Health status of geofence monitoring system
//

import Foundation
import CoreLocation

/// Health status of geofence monitoring system
struct GeofenceHealthStatus {
    /// Region identifiers currently registered with iOS CLLocationManager
    let registeredWithiOS: Set<String>

    /// Geofence identifiers saved in the app's SwiftData database (active only)
    let savedInApp: Set<String>

    /// Current authorization status
    let authorizationStatus: CLAuthorizationStatus

    /// Whether location services are enabled system-wide
    let locationServicesEnabled: Bool

    /// Geofences that are saved in app but NOT registered with iOS
    /// These need to be registered for monitoring to work
    var missingFromiOS: Set<String> {
        savedInApp.subtracting(registeredWithiOS)
    }

    /// Regions registered with iOS but NOT in app database
    /// These are orphaned and should be removed
    var orphanedIniOS: Set<String> {
        registeredWithiOS.subtracting(savedInApp)
    }

    /// Overall health check
    var isHealthy: Bool {
        authorizationStatus == .authorizedAlways &&
        locationServicesEnabled &&
        missingFromiOS.isEmpty &&
        orphanedIniOS.isEmpty
    }

    /// Human-readable status summary
    var statusSummary: String {
        if !locationServicesEnabled {
            return "Location services disabled"
        }
        if authorizationStatus != .authorizedAlways {
            return "Needs 'Always' authorization"
        }
        if !missingFromiOS.isEmpty {
            return "\(missingFromiOS.count) geofence(s) not registered with iOS"
        }
        if !orphanedIniOS.isEmpty {
            return "\(orphanedIniOS.count) orphan region(s) in iOS"
        }
        if savedInApp.isEmpty {
            return "No active geofences"
        }
        return "Healthy"
    }
}
