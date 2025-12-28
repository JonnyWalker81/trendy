//
//  ManageHealthKitCategoriesView.swift
//  trendy
//
//  Simple toggle-based view for enabling/disabling HealthKit categories
//

import SwiftUI

struct ManageHealthKitCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?

    private let settings = HealthKitSettings.shared

    // Track enabled state for each category
    @State private var categoryStates: [HealthDataCategory: Bool] = [:]
    @State private var hasChanges = false

    private var allCategories: [HealthDataCategory] {
        HealthDataCategory.allCases.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(allCategories, id: \.self) { category in
                        CategoryToggleRow(
                            category: category,
                            isEnabled: binding(for: category)
                        )
                    }
                } header: {
                    Text("Health Data Types")
                } footer: {
                    Text("Toggle categories on or off. Changes take effect immediately.")
                }

                Section {
                    Button {
                        enableAll()
                    } label: {
                        Label("Enable All", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(allEnabled)

                    Button(role: .destructive) {
                        disableAll()
                    } label: {
                        Label("Disable All", systemImage: "xmark.circle.fill")
                    }
                    .disabled(noneEnabled)
                }
            }
            .navigationTitle("Manage Health Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadCurrentState()
            }
        }
    }

    // MARK: - Computed Properties

    private var allEnabled: Bool {
        allCategories.allSatisfy { categoryStates[$0] == true }
    }

    private var noneEnabled: Bool {
        allCategories.allSatisfy { categoryStates[$0] != true }
    }

    // MARK: - State Management

    private func loadCurrentState() {
        let enabledCategories = settings.enabledCategories
        for category in allCategories {
            categoryStates[category] = enabledCategories.contains(category)
        }
    }

    private func binding(for category: HealthDataCategory) -> Binding<Bool> {
        Binding(
            get: { categoryStates[category] ?? false },
            set: { newValue in
                categoryStates[category] = newValue
                updateCategory(category, enabled: newValue)
            }
        )
    }

    private func updateCategory(_ category: HealthDataCategory, enabled: Bool) {
        if enabled {
            settings.setEnabled(category, enabled: true)
            healthKitService?.startMonitoring(category: category)
            print("✅ HealthKit: Enabled \(category.displayName)")
        } else {
            healthKitService?.stopMonitoring(category: category)
            settings.setEnabled(category, enabled: false)
            print("✅ HealthKit: Disabled \(category.displayName)")
        }
    }

    private func enableAll() {
        for category in allCategories {
            if categoryStates[category] != true {
                categoryStates[category] = true
                updateCategory(category, enabled: true)
            }
        }
    }

    private func disableAll() {
        for category in allCategories {
            if categoryStates[category] == true {
                categoryStates[category] = false
                updateCategory(category, enabled: false)
            }
        }
    }
}

// MARK: - Category Toggle Row

private struct CategoryToggleRow: View {
    let category: HealthDataCategory
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.title2)
                    .foregroundStyle(isEnabled ? .pink : .secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.body)

                    Text(categoryDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.pink)
    }

    private var categoryDescription: String {
        switch category {
        case .workout: return "Auto-log workouts"
        case .steps: return "Daily step count"
        case .sleep: return "Sleep sessions"
        case .activeEnergy: return "Active calories"
        case .mindfulness: return "Meditation sessions"
        case .water: return "Water intake"
        }
    }
}

#Preview {
    ManageHealthKitCategoriesView()
}
