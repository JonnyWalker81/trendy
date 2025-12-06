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

    private var iosRegionCount: Int {
        geofenceManager?.monitoredRegions.count ?? 0
    }

    private var appActiveCount: Int {
        activeGeofences.count
    }

    private var isInSync: Bool {
        iosRegionCount == appActiveCount && iosRegionCount > 0
    }

    private var hasMismatch: Bool {
        iosRegionCount != appActiveCount
    }

    var body: some View {
        List {
            // Status Summary Section
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

            // Sync Status Section
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("iOS Monitored Regions")
                            .font(.subheadline)
                        Text("Regions registered with CLLocationManager")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(iosRegionCount)")
                        .font(.title2.bold())
                        .foregroundStyle(iosRegionCount > 0 ? Color.primary : Color.orange)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("App Active Geofences")
                            .font(.subheadline)
                        Text("Geofences marked as active in database")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(appActiveCount)")
                        .font(.title2.bold())
                }

                HStack {
                    if isInSync {
                        Label("In Sync", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if iosRegionCount == 0 && appActiveCount == 0 {
                        Label("No Geofences", systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    } else if iosRegionCount < appActiveCount {
                        Label("iOS Missing Regions", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if iosRegionCount > appActiveCount {
                        Label("Orphan Regions in iOS", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Unknown Status", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } header: {
                Text("Sync Status")
            } footer: {
                if hasMismatch && iosRegionCount < appActiveCount {
                    Text("iOS has fewer regions than expected. Tap 'Refresh Geofences' to re-register.")
                } else if hasMismatch && iosRegionCount > appActiveCount {
                    Text("iOS has more regions than expected. This may be from a previous app version.")
                }
            }

            // Registered Regions Section
            Section {
                if let identifiers = geofenceManager?.monitoredRegionIdentifiers, !identifiers.isEmpty {
                    ForEach(identifiers, id: \.self) { identifier in
                        let geofence = allGeofences.first { $0.id.uuidString == identifier }
                        HStack {
                            VStack(alignment: .leading) {
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
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
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
                    forceResync()
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
                        Text("Force Complete Re-sync")
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
                Text("'Refresh' adds missing regions. 'Force Re-sync' clears all and re-registers. 'Clear All' removes all iOS region monitoring.")
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
        print("🔄 Debug: Refreshing geofences...")
        geofenceManager?.startMonitoringAllGeofences()
    }

    private func forceResync() {
        print("🔄 Debug: Force re-syncing all geofences...")
        geofenceManager?.refreshMonitoredGeofences()
    }

    private func clearAllRegions() {
        print("🗑️ Debug: Clearing all iOS regions...")
        geofenceManager?.stopMonitoringAllGeofences()
    }
}

#Preview {
    NavigationStack {
        GeofenceDebugView()
    }
}
