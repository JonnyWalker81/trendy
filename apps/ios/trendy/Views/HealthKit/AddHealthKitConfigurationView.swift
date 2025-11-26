//
//  AddHealthKitConfigurationView.swift
//  trendy
//
//  View for adding a new HealthKit configuration
//

import SwiftUI
import SwiftData

struct AddHealthKitConfigurationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventType.name) private var eventTypes: [EventType]
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(NotificationManager.self) private var notificationManager: NotificationManager?

    let availableCategories: [HealthDataCategory]

    @State private var selectedCategory: HealthDataCategory?
    @State private var selectedEventTypeID: UUID?
    @State private var notifyOnDetection: Bool = false
    @State private var showingNotificationPermissionAlert = false

    private var isValid: Bool {
        selectedCategory != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Category selection
                Section {
                    ForEach(availableCategories, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Image(systemName: category.iconName)
                                    .font(.title2)
                                    .foregroundStyle(.pink)
                                    .frame(width: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(categoryDescription(for: category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedCategory == category {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.pink)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Health Data Type")
                } footer: {
                    Text("Select the type of health data to automatically track.")
                }

                // Event Type selection (optional)
                Section {
                    Picker("Event Type", selection: $selectedEventTypeID) {
                        Text("Auto-create").tag(nil as UUID?)
                        ForEach(eventTypes) { eventType in
                            HStack {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(eventType.name)
                            }
                            .tag(eventType.id as UUID?)
                        }
                    }
                } header: {
                    Text("Event Type")
                } footer: {
                    if selectedEventTypeID == nil, let category = selectedCategory {
                        Text("A new event type named \"\(category.defaultEventTypeName)\" will be created automatically.")
                    } else {
                        Text("Choose an existing event type or let Trendy create one automatically.")
                    }
                }

                // Notifications
                Section {
                    Toggle("Notify on Detection", isOn: $notifyOnDetection)
                        .onChange(of: notifyOnDetection) { _, newValue in
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            }
                        }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive a notification when this health activity is detected and logged.")
                }

                // Info section
                if let category = selectedCategory {
                    Section {
                        HStack {
                            Text("Delivery")
                            Spacer()
                            Text(category.supportsImmediateDelivery ? "Real-time" : "Hourly")
                                .foregroundStyle(.secondary)
                        }

                        if category == .steps {
                            HStack {
                                Text("Aggregation")
                                Spacer()
                                Text("Daily summary")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Tracking Details")
                    }
                }
            }
            .navigationTitle("Add Health Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addConfiguration()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                // Pre-select first available category
                if selectedCategory == nil, let first = availableCategories.first {
                    selectedCategory = first
                }
            }
            .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    notifyOnDetection = false
                }
            } message: {
                Text("Notifications are disabled for this app. Please enable them in Settings to receive health tracking alerts.")
            }
        }
    }

    // MARK: - Helpers

    private func categoryDescription(for category: HealthDataCategory) -> String {
        switch category {
        case .workout:
            return "Auto-log workouts from Apple Health"
        case .steps:
            return "Daily step count summary"
        case .sleep:
            return "Track sleep sessions"
        case .activeEnergy:
            return "Daily active calories burned"
        case .mindfulness:
            return "Meditation and mindfulness sessions"
        case .water:
            return "Water intake logging"
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard let manager = notificationManager else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            Task {
                do {
                    try await manager.requestAuthorization()
                } catch {
                    print("Failed to request notification permission: \(error)")
                }
            }
        case .denied:
            showingNotificationPermissionAlert = true
        default:
            break
        }
    }

    private func addConfiguration() {
        guard let category = selectedCategory else { return }

        let config = HealthKitConfiguration(
            category: category,
            eventTypeID: selectedEventTypeID,
            isEnabled: true,
            notifyOnDetection: notifyOnDetection
        )

        modelContext.insert(config)

        do {
            try modelContext.save()

            // Start monitoring this configuration
            healthKitService?.startMonitoring(configuration: config)

            print("Added HealthKit configuration for: \(category.displayName)")
            dismiss()
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }
}

// MARK: - Edit Configuration View

struct EditHealthKitConfigurationView: View {
    let configuration: HealthKitConfiguration
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventType.name) private var eventTypes: [EventType]
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(NotificationManager.self) private var notificationManager: NotificationManager?

    @State private var selectedEventTypeID: UUID?
    @State private var notifyOnDetection: Bool = false
    @State private var isEnabled: Bool = true
    @State private var hasChanges: Bool = false
    @State private var showingNotificationPermissionAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Category info (read-only)
                Section {
                    HStack {
                        Image(systemName: configuration.category.iconName)
                            .font(.title2)
                            .foregroundStyle(.pink)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(configuration.category.displayName)
                                .font(.headline)
                        }

                        Spacer()
                    }

                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _, _ in hasChanges = true }
                } header: {
                    Text("Health Data Type")
                }

                // Event Type selection
                Section {
                    Picker("Event Type", selection: $selectedEventTypeID) {
                        Text("Auto-create").tag(nil as UUID?)
                        ForEach(eventTypes) { eventType in
                            HStack {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(eventType.name)
                            }
                            .tag(eventType.id as UUID?)
                        }
                    }
                    .onChange(of: selectedEventTypeID) { _, _ in hasChanges = true }
                } header: {
                    Text("Event Type")
                } footer: {
                    if selectedEventTypeID == nil {
                        Text("A new event type will be created automatically when needed.")
                    }
                }

                // Notifications
                Section {
                    Toggle("Notify on Detection", isOn: $notifyOnDetection)
                        .onChange(of: notifyOnDetection) { _, newValue in
                            hasChanges = true
                            if newValue {
                                requestNotificationPermissionIfNeeded()
                            }
                        }
                } header: {
                    Text("Notifications")
                }

                // Info section
                Section {
                    HStack {
                        Text("Delivery")
                        Spacer()
                        Text(configuration.category.supportsImmediateDelivery ? "Real-time" : "Hourly")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Created")
                        Spacer()
                        Text(configuration.createdAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Info")
                }
            }
            .navigationTitle("Edit \(configuration.category.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
            .onAppear {
                selectedEventTypeID = configuration.eventTypeID
                notifyOnDetection = configuration.notifyOnDetection
                isEnabled = configuration.isEnabled
            }
            .alert("Enable Notifications", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    notifyOnDetection = configuration.notifyOnDetection
                }
            } message: {
                Text("Notifications are disabled for this app. Please enable them in Settings to receive health tracking alerts.")
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard let manager = notificationManager else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            Task {
                do {
                    try await manager.requestAuthorization()
                } catch {
                    print("Failed to request notification permission: \(error)")
                }
            }
        case .denied:
            showingNotificationPermissionAlert = true
        default:
            break
        }
    }

    private func saveChanges() {
        let enabledChanged = configuration.isEnabled != isEnabled

        configuration.eventTypeID = selectedEventTypeID
        configuration.notifyOnDetection = notifyOnDetection
        configuration.isEnabled = isEnabled
        configuration.updatedAt = Date()

        do {
            try modelContext.save()

            // Update monitoring if enabled status changed
            if enabledChanged {
                if isEnabled {
                    healthKitService?.startMonitoring(configuration: configuration)
                } else {
                    healthKitService?.stopMonitoring(configuration: configuration)
                }
            }

            print("Updated HealthKit configuration for: \(configuration.category.displayName)")
            dismiss()
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }
}
