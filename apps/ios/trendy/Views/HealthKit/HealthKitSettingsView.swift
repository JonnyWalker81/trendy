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
    @Query(sort: \EventType.name) private var eventTypes: [EventType]
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    @State private var showingAddConfiguration = false
    @State private var showingManageCategories = false
    @State private var selectedCategory: HealthDataCategory?
    @State private var showingDeleteConfirmation = false
    @State private var categoryToDelete: HealthDataCategory?
    @State private var isRequestingPermission = false
    @State private var refreshTrigger = false

    private let settings = HealthKitSettings.shared

    private var needsHealthKitPermission: Bool {
        _ = refreshTrigger
        guard let service = healthKitService else { return true }
        return !service.hasHealthKitAuthorization
    }

    private var enabledCategories: [HealthDataCategory] {
        Array(settings.enabledCategories).sorted { $0.displayName < $1.displayName }
    }

    private var availableCategories: [HealthDataCategory] {
        settings.availableCategories
    }

    var body: some View {
        NavigationStack {
            Group {
                if healthKitService == nil {
                    unavailableView
                } else if needsHealthKitPermission {
                    healthKitPermissionView
                } else if enabledCategories.isEmpty {
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
                AddHealthKitCategoriesView(availableCategories: availableCategories)
            }
            .sheet(isPresented: $showingManageCategories) {
                ManageHealthKitCategoriesView()
            }
            .sheet(item: $selectedCategory) { category in
                EditHealthKitCategoryView(category: category, eventTypes: eventTypes)
            }
            .alert("Stop Tracking", isPresented: $showingDeleteConfirmation) {
                Button("Stop Tracking", role: .destructive) {
                    if let category = categoryToDelete {
                        deleteCategory(category)
                    }
                }
                Button("Cancel", role: .cancel) {
                    categoryToDelete = nil
                }
            } message: {
                if let category = categoryToDelete {
                    Text("Stop tracking \(category.displayName)? This won't delete any existing events.")
                }
            }
            .onAppear {
                refreshTrigger.toggle()
                settings.logCurrentState()
            }
        }
    }

    // MARK: - Unavailable View

    private var unavailableView: some View {
        ContentUnavailableView(
            "HealthKit Unavailable",
            systemImage: "heart.slash",
            description: Text("HealthKit is not available on this device.")
        )
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

            Text("TrendSight needs access to your health data to automatically log workouts, sleep, steps, and other activities.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button(action: requestHealthKitPermission) {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Label("Enable Health Access", systemImage: "heart.fill")
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .disabled(isRequestingPermission)

                Button("Open Health Settings") {
                    if let healthURL = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(healthURL)
                    }
                }
                .font(.subheadline)

                Text("If you previously denied access, enable it in Health app under Sources > TrendSight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Health Tracking", systemImage: "heart.text.square")
        } description: {
            Text("Add health data types to automatically create events when workouts, sleep, and other activities are detected.")
        } actions: {
            Button(action: { showingAddConfiguration = true }) {
                Label("Add Health Tracking", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
    }

    // MARK: - Configuration List

    private var configurationList: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Health Tracking Active")
                            .font(.subheadline.bold())
                        Text("\(enabledCategories.count) types enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Tracked Health Data") {
                ForEach(enabledCategories, id: \.self) { category in
                    HealthKitCategoryRow(category: category)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = category
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                categoryToDelete = category
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }

            Section {
                Button(action: { showingManageCategories = true }) {
                    Label("Manage Categories", systemImage: "slider.horizontal.3")
                }

                if !availableCategories.isEmpty {
                    Button(action: { showingAddConfiguration = true }) {
                        Label("Add More Health Data", systemImage: "plus.circle")
                    }
                }
            }

            Section {
                NavigationLink {
                    HealthKitDebugView()
                } label: {
                    Label("HealthKit Debug", systemImage: "stethoscope")
                }
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("View raw health data, observer status, and diagnose issues.")
            }

            #if DEBUG || STAGING
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
        guard !isRequestingPermission else { return }
        isRequestingPermission = true

        Task {
            do {
                try await healthKitService?.requestAuthorization()
                healthKitService?.startMonitoringAllConfigurations()
            } catch {
                print("Failed to request HealthKit permission: \(error)")
            }

            await MainActor.run {
                isRequestingPermission = false
                refreshTrigger.toggle()
            }
        }
    }

    private func deleteCategory(_ category: HealthDataCategory) {
        healthKitService?.stopMonitoring(category: category)
        settings.setEnabled(category, enabled: false)
        categoryToDelete = nil
    }
}

// MARK: - Category Row

struct HealthKitCategoryRow: View {
    let category: HealthDataCategory
    private let settings = HealthKitSettings.shared
    @Query private var eventTypes: [EventType]

    private var linkedEventType: EventType? {
        guard let eventTypeId = settings.eventTypeId(for: category) else { return nil }
        return eventTypes.first { $0.id == eventTypeId }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.iconName)
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.displayName)
                    .font(.headline)

                if let eventType = linkedEventType {
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

            Spacer()

            HStack(spacing: 8) {
                if settings.notifyOnDetection(for: category) {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Image(systemName: category.supportsImmediateDelivery ? "bolt.fill" : "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Categories View

struct AddHealthKitCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(NotificationManager.self) private var notificationManager: NotificationManager?

    let availableCategories: [HealthDataCategory]
    private let settings = HealthKitSettings.shared

    @State private var selectedCategories: Set<HealthDataCategory> = []
    @State private var notifyOnDetection = false
    @State private var showingNotificationAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(availableCategories, id: \.self) { category in
                        Button {
                            toggleCategory(category)
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

                                Image(systemName: selectedCategories.contains(category) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCategories.contains(category) ? .pink : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Health Data Types")
                        Spacer()
                        if !selectedCategories.isEmpty {
                            Text("\(selectedCategories.count) selected")
                                .font(.caption)
                        }
                    }
                }

                if availableCategories.count > 1 {
                    Section {
                        Button { selectedCategories = Set(availableCategories) } label: {
                            Label("Select All", systemImage: "checkmark.circle.fill")
                        }
                        .disabled(selectedCategories.count == availableCategories.count)

                        Button { selectedCategories.removeAll() } label: {
                            Label("Deselect All", systemImage: "circle")
                        }
                        .disabled(selectedCategories.isEmpty)
                    }
                }

                Section {
                    Toggle("Notify on Detection", isOn: $notifyOnDetection)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive notifications when health activities are detected and logged.")
                }
            }
            .navigationTitle("Add Health Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addCategories() }
                        .fontWeight(.semibold)
                        .disabled(selectedCategories.isEmpty)
                }
            }
        }
    }

    private func toggleCategory(_ category: HealthDataCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func categoryDescription(for category: HealthDataCategory) -> String {
        switch category {
        case .workout: return "Auto-log workouts from Apple Health"
        case .steps: return "Daily step count summary"
        case .sleep: return "Track sleep sessions"
        case .activeEnergy: return "Daily active calories burned"
        case .mindfulness: return "Meditation and mindfulness sessions"
        case .water: return "Water intake logging"
        }
    }

    private func addCategories() {
        // Save to HealthKitSettings (UserDefaults - immediate, reliable)
        settings.enableCategories(selectedCategories)

        // Set notification preferences
        for category in selectedCategories {
            settings.setNotifyOnDetection(notifyOnDetection, for: category)
        }

        // Start monitoring
        for category in selectedCategories {
            healthKitService?.startMonitoring(category: category)
        }

        print("✅ HealthKit: Added \(selectedCategories.count) categories")
        settings.logCurrentState()

        dismiss()
    }
}

// MARK: - Edit Category View

struct EditHealthKitCategoryView: View {
    let category: HealthDataCategory
    let eventTypes: [EventType]

    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    private let settings = HealthKitSettings.shared

    @State private var selectedEventTypeId: String?
    @State private var notifyOnDetection = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: category.iconName)
                            .font(.title2)
                            .foregroundStyle(.pink)
                            .frame(width: 40)
                        Text(category.displayName)
                            .font(.headline)
                    }
                } header: {
                    Text("Health Data Type")
                }

                Section {
                    Picker("Event Type", selection: $selectedEventTypeId) {
                        Text("Auto-create").tag(nil as String?)
                        ForEach(eventTypes) { eventType in
                            HStack {
                                Circle()
                                    .fill(Color(hex: eventType.colorHex) ?? .blue)
                                    .frame(width: 12, height: 12)
                                Text(eventType.name)
                            }
                            .tag(eventType.id as String?)
                        }
                    }
                } footer: {
                    Text("Choose which event type to use when logging this health data.")
                }

                Section {
                    Toggle("Notify on Detection", isOn: $notifyOnDetection)
                } header: {
                    Text("Notifications")
                }

                Section {
                    HStack {
                        Text("Update Frequency")
                        Spacer()
                        Text(category.supportsImmediateDelivery ? "Real-time" : "Hourly")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Info")
                }
            }
            .navigationTitle("Edit \(category.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedEventTypeId = settings.eventTypeId(for: category)
                notifyOnDetection = settings.notifyOnDetection(for: category)
            }
        }
    }

    private func saveChanges() {
        settings.setEventTypeId(selectedEventTypeId, for: category)
        settings.setNotifyOnDetection(notifyOnDetection, for: category)
        print("✅ HealthKit: Updated \(category.displayName) settings (eventTypeId: \(selectedEventTypeId ?? "auto"))")
        dismiss()
    }
}

// MARK: - Identifiable Conformance

extension HealthDataCategory: Identifiable {
    public var id: String { rawValue }
}
