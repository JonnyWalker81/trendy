//
//  GeofenceDebugView.swift
//  trendy
//
//  Debug view to diagnose geofence registration and monitoring issues
//

import SwiftUI
import SwiftData
import CoreLocation

struct GeofenceDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Geofence> { $0.isActive }, sort: \Geofence.name) private var activeGeofences: [Geofence]
    @Query(sort: \Geofence.name) private var allGeofences: [Geofence]

    @Environment(GeofenceManager.self) private var geofenceManager: GeofenceManager?

    @State private var refreshTrigger = false
    @State private var isSyncing = false

    // MARK: - Health Status

    private var healthStatus: GeofenceHealthStatus? {
        geofenceManager?.healthStatus
    }

    private var iosRegionCount: Int {
        geofenceManager?.monitoredRegions.count ?? 0
    }

    private var appActiveCount: Int {
        activeGeofences.count
    }

    var body: some View {
        List {
            // System Status Section
            Section {
                statusRow(
                    title: "Authorization",
                    value: geofenceManager?.authorizationStatus.description ?? "Unknown",
                    isGood: geofenceManager?.hasGeofencingAuthorization == true
                )

                statusRow(
                    title: "Location Services",
                    value: geofenceManager?.isLocationServicesEnabled == true ? "Enabled" : "Disabled",
                    isGood: geofenceManager?.isLocationServicesEnabled == true
                )
            } header: {
                Text("System Status")
            }

            // Health Status Section
            Section {
                // Overall status indicator
                HStack {
                    if let status = healthStatus {
                        if status.isHealthy {
                            Label("Healthy", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(status.statusSummary, systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("Unknown", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Counts comparison
                if let status = healthStatus {
                    LabeledContent("Registered with iOS") {
                        Text("\(status.registeredWithiOS.count)")
                            .font(.title3.bold())
                    }

                    LabeledContent("Active in App") {
                        Text("\(status.savedInApp.count)")
                            .font(.title3.bold())
                    }
                }
            } header: {
                Text("Health Status")
            }

            // Missing from iOS Section
            if let status = healthStatus, !status.missingFromiOS.isEmpty {
                Section {
                    ForEach(Array(status.missingFromiOS).sorted(), id: \.self) { identifier in
                        let geofence = allGeofences.first { $0.regionIdentifier == identifier }
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(geofence?.name ?? "Unknown")
                                    .font(.subheadline)
                                Text(identifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("Not Registered")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Missing from iOS (\(status.missingFromiOS.count))")
                } footer: {
                    Text("These geofences are active in the app but not registered with iOS. Tap 'Fix Registration Issues' to register them.")
                }
            }

            // Orphaned in iOS Section
            if let status = healthStatus, !status.orphanedIniOS.isEmpty {
                Section {
                    ForEach(Array(status.orphanedIniOS).sorted(), id: \.self) { identifier in
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text("Unknown Region")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(identifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("Orphaned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Orphaned in iOS (\(status.orphanedIniOS.count))")
                } footer: {
                    Text("These regions are registered with iOS but have no matching geofence in the app. They may be from a previous app version. Use 'Fix Registration Issues' to clean up.")
                }
            }

            // Registered Regions Section
            Section {
                if let regions = geofenceManager?.monitoredRegions, !regions.isEmpty {
                    let sortedRegions = regions.sorted { $0.identifier < $1.identifier }
                    ForEach(sortedRegions, id: \.identifier) { region in
                        let identifier = region.identifier
                        let geofence = allGeofences.first { $0.regionIdentifier == identifier }
                        let isOrphaned = healthStatus?.orphanedIniOS.contains(identifier) ?? false
                        let circularRegion = region as? CLCircularRegion
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if let geofence = geofence {
                                    Text(geofence.name)
                                        .font(.subheadline)
                                    Text(identifier)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("Unknown Region")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                    Text(identifier)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let circular = circularRegion {
                                    Text("\(String(format: "%.4f", circular.center.latitude)), \(String(format: "%.4f", circular.center.longitude))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Radius: \(Int(circular.radius))m")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isOrphaned {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } else {
                    Text("No regions registered with iOS")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Text("Registered Regions (\(iosRegionCount))")
            }

            // Active Events Section
            Section {
                let activeCount = geofenceManager?.activeGeofenceEventCount ?? 0
                if activeCount > 0, let activeIds = geofenceManager?.activeGeofenceIds {
                    ForEach(activeIds, id: \.self) { geofenceId in
                        let geofence = allGeofences.first { $0.id == geofenceId }
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(geofence?.name ?? "Unknown")
                                    .font(.subheadline)
                                Text("Awaiting exit event")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No active entry events")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Text("Active Events (Awaiting Exit)")
            } footer: {
                Text("These are geofences where entry was detected but exit hasn't occurred yet.")
            }

            // Last Event Section
            Section {
                HStack {
                    Text("Last Event")
                    Spacer()
                    Text(geofenceManager?.lastEventDescription ?? "None")
                        .foregroundStyle(.secondary)
                }

                if let timestamp = geofenceManager?.lastEventTimestamp {
                    HStack {
                        Text("Timestamp")
                        Spacer()
                        Text(timestamp, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Recent Activity")
            }

            // Actions Section
            Section {
                Button {
                    refreshGeofences()
                } label: {
                    Label("Refresh Geofences", systemImage: "arrow.clockwise")
                }

                Button {
                    isSyncing = true
                    fixRegistrationIssues()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSyncing = false
                    }
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Fix Registration Issues")
                    }
                }
                .disabled(isSyncing)
                .foregroundStyle(.orange)

                Button(role: .destructive) {
                    clearAllRegions()
                } label: {
                    Label("Clear All iOS Regions", systemImage: "trash")
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("'Refresh' adds missing regions. 'Fix Registration Issues' reconciles iOS regions with app database (adds missing, removes orphaned). 'Clear All' removes all iOS region monitoring.")
            }

            // iOS Settings Reminder
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Verify in iOS Settings")
                        .font(.subheadline.bold())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Go to Settings > Privacy & Security > Location Services")
                        Text("2. Find 'trendy' in the list")
                        Text("3. Verify it shows 'Always'")
                        Text("4. Look for hollow arrow = geofences active")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
            } header: {
                Text("iOS Settings")
            }
        }
        .navigationTitle("Geofence Debug")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            refreshTrigger.toggle()
        }
    }

    // MARK: - Helper Views

    private func statusRow(title: String, value: String, isGood: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .foregroundStyle(isGood ? Color.primary : Color.orange)
                Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isGood ? Color.green : Color.orange)
            }
        }
    }

    // MARK: - Actions

    private func refreshGeofences() {
        Log.geofence.debug("Debug: Refreshing geofences...")
        geofenceManager?.startMonitoringAllGeofences()
    }

    private func fixRegistrationIssues() {
        Log.geofence.debug("Debug: Fixing registration issues...")
        geofenceManager?.ensureRegionsRegistered()
    }

    private func clearAllRegions() {
        Log.geofence.debug("Debug: Clearing all iOS regions...")
        geofenceManager?.stopMonitoringAllGeofences()
    }
}

#Preview {
    NavigationStack {
        GeofenceDebugView()
    }
}
