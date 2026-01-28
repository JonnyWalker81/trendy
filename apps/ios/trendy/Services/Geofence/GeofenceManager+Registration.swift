//
//  GeofenceManager+Registration.swift
//  trendy
//
//  Region registration, reconciliation, and monitoring
//

import Foundation
import CoreLocation
import SwiftData

// MARK: - Geofence Management

extension GeofenceManager {

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
        let definitions = geofences.map { GeofenceDefinition(from: $0) }

        Log.geofence.info("ensureRegionsRegistered called", context: .with { ctx in
            ctx.add("desired_count", definitions.count)
            ctx.add("current_ios_count", locationManager.monitoredRegions.count)
        })

        reconcileRegions(desired: definitions)
    }
}

// MARK: - Debug/Testing Methods

extension GeofenceManager {

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
}

// MARK: - Debug Properties

extension GeofenceManager {

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

    /// Current health status of geofence monitoring
    var healthStatus: GeofenceHealthStatus {
        // Get iOS registered region identifiers
        let iosRegionIds = Set(locationManager.monitoredRegions.map { $0.identifier })

        // Fetch active geofences from SwiftData
        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { $0.isActive }
        )
        let activeGeofences = (try? modelContext.fetch(descriptor)) ?? []
        let appGeofenceIds = Set(activeGeofences.map { $0.regionIdentifier })

        return GeofenceHealthStatus(
            registeredWithiOS: iosRegionIds,
            savedInApp: appGeofenceIds,
            authorizationStatus: authorizationStatus,
            locationServicesEnabled: CLLocationManager.locationServicesEnabled()
        )
    }
}
