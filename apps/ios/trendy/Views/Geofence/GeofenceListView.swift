//
//  GeofenceListView.swift
//  trendy
//
//  List and manage geofences
//

import SwiftUI
import SwiftData
import MapKit

struct GeofenceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Geofence.name) private var geofences: [Geofence]
    @State private var showingAddGeofence = false
    @State private var selectedGeofence: Geofence?
    @State private var showingDeleteConfirmation = false
    @State private var geofenceToDelete: Geofence?

    // GeofenceManager should be passed in as environment
    @Environment(GeofenceManager.self) private var geofenceManager

    var body: some View {
        NavigationStack {
            Group {
                if geofences.isEmpty {
                    emptyState
                } else {
                    geofenceList
                }
            }
            .navigationTitle("Geofences")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGeofence = true }) {
                        Label("Add Geofence", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddGeofence) {
                AddGeofenceView()
            }
            .sheet(item: $selectedGeofence) { geofence in
                EditGeofenceView(geofence: geofence)
            }
            .alert("Delete Geofence", isPresented: $showingDeleteConfirmation, presenting: geofenceToDelete) { geofence in
                Button("Delete", role: .destructive) {
                    deleteGeofence(geofence)
                }
                Button("Cancel", role: .cancel) {}
            } message: { geofence in
                Text("Are you sure you want to delete '\(geofence.name)'? This action cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Geofences")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a geofence to automatically track events when you enter or leave a location")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showingAddGeofence = true }) {
                Label("Add Geofence", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Geofence List

    private var geofenceList: some View {
        List {
            ForEach(geofences) { geofence in
                GeofenceRow(geofence: geofence)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedGeofence = geofence
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            geofenceToDelete = geofence
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            toggleGeofenceActive(geofence)
                        } label: {
                            Label(
                                geofence.isActive ? "Deactivate" : "Activate",
                                systemImage: geofence.isActive ? "pause.circle" : "play.circle"
                            )
                        }
                        .tint(geofence.isActive ? .orange : .green)
                    }
            }
        }
    }

    // MARK: - Actions

    private func toggleGeofenceActive(_ geofence: Geofence) {
        geofence.isActive.toggle()

        do {
            try modelContext.save()

            // Update monitoring
            if geofence.isActive {
                geofenceManager.startMonitoring(geofence: geofence)
            } else {
                geofenceManager.stopMonitoring(geofence: geofence)
            }
        } catch {
            print("Failed to toggle geofence: \(error)")
        }
    }

    private func deleteGeofence(_ geofence: Geofence) {
        // Stop monitoring
        geofenceManager.stopMonitoring(geofence: geofence)

        // Delete from SwiftData
        modelContext.delete(geofence)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete geofence: \(error)")
        }
    }
}

// MARK: - Geofence Row

struct GeofenceRow: View {
    let geofence: Geofence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Name and active status
                VStack(alignment: .leading, spacing: 4) {
                    Text(geofence.name)
                        .font(.headline)

                    if let eventTypeEntry = geofence.eventTypeEntry {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: eventTypeEntry.colorHex) ?? .blue)
                                .frame(width: 8, height: 8)
                            Text(eventTypeEntry.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Active/Inactive badge
                if geofence.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Inactive", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Location and radius info
            HStack(spacing: 12) {
                Label("\(Int(geofence.radius))m", systemImage: "circle.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if geofence.notifyOnEntry || geofence.notifyOnExit {
                    Label("Notifications", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Geofence View (Placeholder)

struct EditGeofenceView: View {
    let geofence: Geofence
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Text("Name: \(geofence.name)")
                    Text("Radius: \(Int(geofence.radius))m")
                    Text("Active: \(geofence.isActive ? "Yes" : "No")")
                }

                Section("Location") {
                    Text("Latitude: \(geofence.latitude, specifier: "%.6f")")
                    Text("Longitude: \(geofence.longitude, specifier: "%.6f")")
                }

                if let eventType = geofence.eventTypeEntry {
                    Section("Event Type") {
                        HStack {
                            Circle()
                                .fill(Color(hex: eventType.colorHex) ?? .blue)
                                .frame(width: 20, height: 20)
                            Text(eventType.name)
                        }
                    }
                }

                Section("Notifications") {
                    Text("On Entry: \(geofence.notifyOnEntry ? "Yes" : "No")")
                    Text("On Exit: \(geofence.notifyOnExit ? "Yes" : "No")")
                }
            }
            .navigationTitle(geofence.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Preview removed due to complexity - use live app for testing
