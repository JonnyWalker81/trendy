//
//  HealthKitSettingsView.swift
//  trendy
//
//  Main settings view for HealthKit integration
//

import SwiftUI
import SwiftData
import HealthKit

struct HealthKitSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HealthKitConfiguration.createdAt) private var configurations: [HealthKitConfiguration]
    @Query(sort: \EventType.name) private var eventTypes: [EventType]
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    @State private var showingAddConfiguration = false
    @State private var selectedConfigurationID: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var configurationToDeleteID: UUID?

    private var needsHealthKitPermission: Bool {
        guard let service = healthKitService else { return true }
        return !service.hasHealthKitAuthorization
    }

    private var configurationToDelete: HealthKitConfiguration? {
        guard let id = configurationToDeleteID else { return nil }
        return configurations.first { $0.id == id }
    }

    // Get categories that don't have a configuration yet
    private var availableCategories: [HealthDataCategory] {
        let configuredCategories = Set(configurations.map { $0.category })
        return HealthDataCategory.allCases.filter { !configuredCategories.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if healthKitService == nil {
                    unavailableView
                } else if needsHealthKitPermission {
                    healthKitPermissionView
                } else if configurations.isEmpty {
                    emptyState
                } else {
                    configurationList
                }
            }
            .navigationTitle("Health Tracking")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !availableCategories.isEmpty && !needsHealthKitPermission {
                        Button(action: { showingAddConfiguration = true }) {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddConfiguration) {
                AddHealthKitConfigurationView(availableCategories: availableCategories)
            }
            .sheet(item: $selectedConfigurationID) { configID in
                if let config = configurations.first(where: { $0.id == configID }) {
                    EditHealthKitConfigurationView(configuration: config)
                }
            }
            .alert("Delete Configuration", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let config = configurationToDelete {
                        deleteConfiguration(config)
                    }
                }
                Button("Cancel", role: .cancel) {
                    configurationToDeleteID = nil
                }
            } message: {
                if let config = configurationToDelete {
                    Text("Are you sure you want to stop tracking \(config.category.displayName)? This won't delete any existing events.")
                } else {
                    Text("Are you sure you want to delete this configuration?")
                }
            }
        }
    }

    // MARK: - Unavailable View

    private var unavailableView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("HealthKit Unavailable")
                .font(.title2)
                .fontWeight(.semibold)

            Text("HealthKit is not available on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permission View

    private var healthKitPermissionView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "heart.circle")
                .font(.system(size: 60))
                .foregroundStyle(.pink)

            Text("Health Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Trendy needs access to your health data to automatically log workouts, sleep, steps, and other activities.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button(action: requestHealthKitPermission) {
                    Label("Enable Health Access", systemImage: "heart.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)

                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .font(.subheadline)
            }
            .padding(.top)

            Spacer()

            #if DEBUG || STAGING
            // Debug section - available even before permission granted
            VStack(spacing: 12) {
                Text("Debug Actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button {
                        Task {
                            await healthKitService?.simulateWorkoutDetection()
                        }
                    } label: {
                        Label("Workout", systemImage: "figure.run")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await healthKitService?.simulateSleepDetection()
                        }
                    } label: {
                        Label("Sleep", systemImage: "bed.double")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 20)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Health Tracking")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add health data types to automatically create events when workouts, sleep, and other activities are detected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showingAddConfiguration = true }) {
                Label("Add Health Tracking", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Configuration List

    private var configurationList: some View {
        List {
            // Status section
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Health Tracking Active")
                            .font(.subheadline.bold())
                        Text("\(configurations.filter { $0.isEnabled }.count) of \(configurations.count) types enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Configurations section
            Section("Tracked Health Data") {
                ForEach(configurations) { config in
                    HealthKitConfigurationRow(configuration: config)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedConfigurationID = config.id
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                configurationToDeleteID = config.id
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                toggleConfigurationEnabled(config)
                            } label: {
                                Label(
                                    config.isEnabled ? "Disable" : "Enable",
                                    systemImage: config.isEnabled ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(config.isEnabled ? .orange : .green)
                        }
                }
            }

            // Add more section (if categories available)
            if !availableCategories.isEmpty {
                Section {
                    Button(action: { showingAddConfiguration = true }) {
                        Label("Add More Health Data", systemImage: "plus.circle")
                    }
                }
            }

            #if DEBUG || STAGING
            // Debug section - available in Debug and Staging builds
            Section("Debug Actions") {
                Button {
                    Task {
                        await healthKitService?.simulateWorkoutDetection()
                    }
                } label: {
                    Label("Simulate Workout", systemImage: "figure.run")
                }

                Button {
                    Task {
                        await healthKitService?.simulateSleepDetection()
                    }
                } label: {
                    Label("Simulate Sleep", systemImage: "bed.double")
                }

                Button {
                    healthKitService?.refreshMonitoring()
                } label: {
                    Label("Refresh Monitoring", systemImage: "arrow.clockwise")
                }
            }
            #endif
        }
    }

    // MARK: - Actions

    private func requestHealthKitPermission() {
        Task {
            do {
                try await healthKitService?.requestAuthorization()
            } catch {
                print("Failed to request HealthKit permission: \(error)")
            }
        }
    }

    private func toggleConfigurationEnabled(_ config: HealthKitConfiguration) {
        config.isEnabled.toggle()
        config.updatedAt = Date()

        do {
            try modelContext.save()

            // Update monitoring
            if config.isEnabled {
                healthKitService?.startMonitoring(configuration: config)
            } else {
                healthKitService?.stopMonitoring(configuration: config)
            }
        } catch {
            print("Failed to toggle configuration: \(error)")
        }
    }

    private func deleteConfiguration(_ config: HealthKitConfiguration) {
        // Stop monitoring
        healthKitService?.stopMonitoring(configuration: config)

        // Delete from SwiftData
        modelContext.delete(config)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete configuration: \(error)")
        }
    }
}

// MARK: - Configuration Row

struct HealthKitConfigurationRow: View {
    let configuration: HealthKitConfiguration
    @Query private var eventTypes: [EventType]

    private var eventType: EventType? {
        guard let id = configuration.eventTypeID else { return nil }
        return eventTypes.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Category icon and name
                HStack(spacing: 12) {
                    Image(systemName: configuration.category.iconName)
                        .font(.title2)
                        .foregroundStyle(.pink)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.category.displayName)
                            .font(.headline)

                        if let eventType = eventType {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 8, height: 8)
                                Text(eventType.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Auto-creates event type")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Status badge
                if configuration.isEnabled {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Disabled", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Features row
            HStack(spacing: 12) {
                if configuration.notifyOnDetection {
                    Label("Notifications", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Label(
                    configuration.category.supportsImmediateDelivery ? "Real-time" : "Hourly",
                    systemImage: configuration.category.supportsImmediateDelivery ? "bolt.fill" : "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

