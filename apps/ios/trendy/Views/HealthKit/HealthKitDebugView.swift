//
//  HealthKitDebugView.swift
//  trendy
//
//  Debug view to diagnose HealthKit monitoring and sleep detection issues
//

import SwiftUI
import HealthKit

struct HealthKitDebugView: View {
    @Environment(HealthKitService.self) private var healthKitService: HealthKitService?
    @Environment(EventStore.self) private var eventStore: EventStore?

    @State private var sleepSamples: [(start: Date, end: Date, duration: TimeInterval, sleepType: String, source: String)] = []
    @State private var stepSamples: [(date: Date, steps: Double, source: String)] = []
    @State private var workoutSamples: [(start: Date, end: Date, duration: TimeInterval, workoutType: String, calories: Double?, distance: Double?, source: String)] = []
    @State private var activeEnergySamples: [(date: Date, calories: Double, source: String)] = []
    @State private var isLoadingSleep = false
    @State private var isLoadingSteps = false
    @State private var isLoadingWorkouts = false
    @State private var isLoadingActiveEnergy = false
    @State private var isForcingActiveEnergy = false
    @State private var isClearingActiveEnergy = false
    @State private var isForcing = false
    @State private var isForcingSteps = false
    @State private var isClearing = false
    @State private var isClearingSteps = false
    @State private var isRefreshing = false
    @State private var isRefreshingAll = false
    @State private var isResyncingHealthKit = false
    @State private var isRestoringRelationships = false
    @State private var isReconciling = false
    @State private var reconcileResult: Int?

    private var enabledCategories: [HealthDataCategory] {
        Array(HealthKitSettings.shared.enabledCategories)
    }

    var body: some View {
        List {
            // System Status Section
            Section {
                statusRow(
                    title: "HealthKit Available",
                    value: healthKitService?.isHealthKitAvailable == true ? "Yes" : "No",
                    isGood: healthKitService?.isHealthKitAvailable == true
                )

                statusRow(
                    title: "Authorization",
                    value: healthKitService?.isAuthorized == true ? "Requested" : "Not Requested",
                    isGood: healthKitService?.isAuthorized == true
                )

                statusRow(
                    title: "App Group Storage",
                    value: healthKitService?.isUsingAppGroupStorage == true ? "Active" : "Fallback",
                    isGood: healthKitService?.isUsingAppGroupStorage == true
                )
            } header: {
                Text("System Status")
            }

            // Monitoring Status Section
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Enabled Categories")
                            .font(.subheadline)
                        Text("Categories configured in settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(enabledCategories.count)")
                        .font(.title2.bold())
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Active Observers")
                            .font(.subheadline)
                        Text("Background queries running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(healthKitService?.activeObserverCategories.count ?? 0)")
                        .font(.title2.bold())
                        .foregroundStyle(
                            (healthKitService?.activeObserverCategories.count ?? 0) == enabledCategories.count
                            ? Color.primary : Color.orange
                        )
                }

                if let activeCategories = healthKitService?.activeObserverCategories, !activeCategories.isEmpty {
                    ForEach(activeCategories, id: \.rawValue) { category in
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundStyle(.green)
                            Text(category.displayName)
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Monitoring Status")
            } footer: {
                if enabledCategories.count != (healthKitService?.activeObserverCategories.count ?? 0) {
                    Text("Mismatch between enabled and active observers. Try 'Refresh Observers'.")
                }
            }

            // Cache Status Section
            Section {
                HStack {
                    Text("Processed Sample IDs")
                    Spacer()
                    Text("\(healthKitService?.processedSampleIdsCount ?? 0)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Last Sleep Date")
                    Spacer()
                    if let date = healthKitService?.lastSleepDateDebug {
                        Text(date, style: .date)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    Text("Last Step Date")
                    Spacer()
                    if let date = healthKitService?.lastStepDateDebug {
                        Text(date, style: .date)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    Text("Last Active Energy Date")
                    Spacer()
                    if let date = healthKitService?.lastActiveEnergyDateDebug {
                        Text(date, style: .date)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.orange)
                    }
                }

                HStack {
                    Text("Anchors Stored")
                    Spacer()
                    Text("\(healthKitService?.categoriesWithAnchors.count ?? 0)")
                        .foregroundStyle(.secondary)
                }

                if let categories = healthKitService?.categoriesWithAnchors, !categories.isEmpty {
                    ForEach(categories, id: \.rawValue) { category in
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                            Text(category.displayName)
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.leading, 8)
                    }
                }
            } header: {
                Text("Cache Status")
            } footer: {
                Text("'Last Sleep Date' prevents re-processing. Anchors enable incremental HealthKit queries.")
            }

            // Category Update Times Section
            Section {
                if let service = healthKitService {
                    ForEach(HealthDataCategory.allCases, id: \.rawValue) { category in
                        HStack {
                            Image(systemName: category.iconName)
                                .frame(width: 20)
                            Text(category.displayName)
                                .font(.subheadline)
                            Spacer()
                            if let lastUpdate = service.lastUpdateTime(for: category) {
                                VStack(alignment: .trailing) {
                                    Text(lastUpdate, style: .time)
                                        .font(.caption)
                                    Text(lastUpdate, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Never")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Last Update Times")
            } footer: {
                Text("Shows when each category last received data from HealthKit.")
            }

            // Raw Sleep Data Section
            Section {
                if isLoadingSleep {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading sleep data...")
                            .foregroundStyle(.secondary)
                    }
                } else if sleepSamples.isEmpty {
                    Text("No sleep data found in last 48 hours")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(Array(sleepSamples.enumerated()), id: \.offset) { _, sample in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(sample.sleepType)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(sleepTypeColor(sample.sleepType))
                                Spacer()
                                Text(formatDuration(sample.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("\(sample.start, style: .time) - \(sample.end, style: .time)")
                                    .font(.caption)
                                Spacer()
                                Text(sample.source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(sample.start, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    loadSleepData()
                } label: {
                    HStack {
                        if isLoadingSleep {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Sleep Data")
                    }
                }
                .disabled(isLoadingSleep)
            } header: {
                Text("Raw Sleep Data (Last 48h)")
            } footer: {
                Text("Shows raw sleep samples from HealthKit. If empty, your sleep tracker may not be syncing to Apple Health.")
            }

            // Raw Steps Data Section
            Section {
                if isLoadingSteps {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading step data...")
                            .foregroundStyle(.secondary)
                    }
                } else if stepSamples.isEmpty {
                    Text("No step data found in last 7 days")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(Array(stepSamples.enumerated()), id: \.offset) { _, sample in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.date, style: .date)
                                    .font(.subheadline)
                                Text(sample.source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(sample.steps).formatted()) steps")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Button {
                    loadStepData()
                } label: {
                    HStack {
                        if isLoadingSteps {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Step Data")
                    }
                }
                .disabled(isLoadingSteps)
            } header: {
                Text("Raw Step Data (Last 7 Days)")
            } footer: {
                Text("Shows daily step totals from HealthKit.")
            }

            // Raw Active Energy Data Section
            Section {
                if isLoadingActiveEnergy {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading active energy data...")
                            .foregroundStyle(.secondary)
                    }
                } else if activeEnergySamples.isEmpty {
                    Text("No active energy data found in last 7 days")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(Array(activeEnergySamples.enumerated()), id: \.offset) { _, sample in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.date, style: .date)
                                    .font(.subheadline)
                                Text(sample.source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(sample.calories)) kcal")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Button {
                    loadActiveEnergyData()
                } label: {
                    HStack {
                        if isLoadingActiveEnergy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Active Energy Data")
                    }
                }
                .disabled(isLoadingActiveEnergy)
            } header: {
                Text("Raw Active Energy Data (Last 7 Days)")
            } footer: {
                Text("Shows daily active energy totals from HealthKit.")
            }

            // Raw Workout Data Section
            Section {
                if isLoadingWorkouts {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading workout data...")
                            .foregroundStyle(.secondary)
                    }
                } else if workoutSamples.isEmpty {
                    Text("No workouts found in last 7 days")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(Array(workoutSamples.enumerated()), id: \.offset) { _, workout in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(workout.workoutType)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.orange)
                                Spacer()
                                Text(formatDuration(workout.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("\(workout.start, style: .time) - \(workout.end, style: .time)")
                                    .font(.caption)
                                Spacer()
                                if let calories = workout.calories {
                                    Text("\(Int(calories)) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            HStack {
                                Text(workout.start, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let distance = workout.distance, distance > 0 {
                                    Text(formatDistance(distance))
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(workout.source)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    loadWorkoutData()
                } label: {
                    HStack {
                        if isLoadingWorkouts {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Workout Data")
                    }
                }
                .disabled(isLoadingWorkouts)
            } header: {
                Text("Raw Workout Data (Last 7 Days)")
            } footer: {
                Text("Shows workouts from HealthKit including duration, calories, and distance.")
            }

            // Actions Section
            Section {
                Button {
                    forceRefreshAll()
                } label: {
                    HStack {
                        if isRefreshingAll {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                        }
                        Text("Force Refresh All Categories")
                    }
                }
                .disabled(isRefreshingAll)

                Button {
                    reconcileLast30Days()
                } label: {
                    HStack {
                        if isReconciling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        }
                        VStack(alignment: .leading) {
                            Text("Reconcile Last 30 Days")
                            if let result = reconcileResult {
                                Text("Last run: \(result) items reconciled")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(isReconciling)
                .foregroundStyle(.green)

                Button {
                    forceSleepCheck()
                } label: {
                    HStack {
                        if isForcing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "moon.zzz")
                        }
                        Text("Force Sleep Check")
                    }
                }
                .disabled(isForcing)

                Button {
                    clearSleepCache()
                } label: {
                    HStack {
                        if isClearing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Clear Sleep Cache")
                    }
                }
                .disabled(isClearing)
                .foregroundStyle(.orange)

                Button {
                    forceStepsCheck()
                } label: {
                    HStack {
                        if isForcingSteps {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "figure.walk")
                        }
                        Text("Force Steps Check")
                    }
                }
                .disabled(isForcingSteps)

                Button {
                    clearStepsCache()
                } label: {
                    HStack {
                        if isClearingSteps {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Clear Steps Cache")
                    }
                }
                .disabled(isClearingSteps)
                .foregroundStyle(.orange)

                Button {
                    forceActiveEnergyCheck()
                } label: {
                    HStack {
                        if isForcingActiveEnergy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "flame.fill")
                        }
                        Text("Force Active Energy Check")
                    }
                }
                .disabled(isForcingActiveEnergy)

                Button {
                    clearActiveEnergyCache()
                } label: {
                    HStack {
                        if isClearingActiveEnergy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Clear Active Energy Cache")
                    }
                }
                .disabled(isClearingActiveEnergy)
                .foregroundStyle(.orange)

                Button {
                    clearAllAnchors()
                } label: {
                    HStack {
                        Image(systemName: "bookmark.slash")
                        Text("Clear All Anchors")
                    }
                }
                .foregroundStyle(.red)

                Button {
                    clearAllUpdateTimes()
                } label: {
                    HStack {
                        Image(systemName: "clock.badge.xmark")
                        Text("Clear Update Times")
                    }
                }
                .foregroundStyle(.orange)

                Button {
                    refreshObservers()
                } label: {
                    HStack {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Refresh All Observers")
                    }
                }
                .disabled(isRefreshing)

                Button {
                    resyncHealthKitEvents()
                } label: {
                    HStack {
                        if isResyncingHealthKit {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                        }
                        Text("Resync All HealthKit Events")
                    }
                }
                .disabled(isResyncingHealthKit)
                .foregroundStyle(.blue)

                Button {
                    restoreEventRelationships()
                } label: {
                    HStack {
                        if isRestoringRelationships {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "link.badge.plus")
                        }
                        Text("Restore Event Type Links")
                    }
                }
                .disabled(isRestoringRelationships)
                .foregroundStyle(.purple)
            } header: {
                Text("Actions")
            } footer: {
                Text("'Force Refresh All' queries all categories. 'Force Sleep/Steps Check' runs aggregation. 'Clear Cache' allows re-processing. 'Refresh Observers' restarts monitoring. 'Resync All' pushes local HealthKit events to backend. 'Restore Event Type Links' fixes events showing 'Unknown'.")
            }

            // Troubleshooting Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sleep Not Working?")
                        .font(.subheadline.bold())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Check 'Raw Sleep Data' section above")
                        Text("2. If empty: Open your sleep app (EightSleep/Whoop) to sync")
                        Text("3. Verify sleep data appears in Apple Health app")
                        Text("4. Tap 'Clear Sleep Cache' then 'Force Sleep Check'")
                        Text("5. If still not working, check Sleep is enabled in settings")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Troubleshooting")
            }
        }
        .navigationTitle("HealthKit Debug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSleepData()
            loadStepData()
            loadActiveEnergyData()
            loadWorkoutData()
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

    private func sleepTypeColor(_ type: String) -> Color {
        switch type {
        case "Deep": return .indigo
        case "Core": return .blue
        case "REM": return .purple
        case "Asleep": return .cyan
        case "In Bed": return .gray
        case "Awake": return .orange
        default: return .secondary
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        } else {
            return "\(Int(meters)) m"
        }
    }

    // MARK: - Actions

    private func loadSleepData() {
        guard let service = healthKitService else { return }
        isLoadingSleep = true
        Task {
            let data = await service.debugQuerySleepData()
            await MainActor.run {
                sleepSamples = data
                isLoadingSleep = false
            }
        }
    }

    private func loadStepData() {
        guard let service = healthKitService else { return }
        isLoadingSteps = true
        Task {
            let data = await service.debugQueryStepData()
            await MainActor.run {
                stepSamples = data
                isLoadingSteps = false
            }
        }
    }

    private func loadWorkoutData() {
        guard let service = healthKitService else { return }
        isLoadingWorkouts = true
        Task {
            let data = await service.debugQueryWorkoutData()
            await MainActor.run {
                workoutSamples = data
                isLoadingWorkouts = false
            }
        }
    }

    private func forceSleepCheck() {
        guard let service = healthKitService else { return }
        isForcing = true
        Task {
            await service.forceSleepCheck()
            await MainActor.run {
                isForcing = false
            }
        }
    }

    private func clearSleepCache() {
        guard let service = healthKitService else { return }
        isClearing = true
        service.clearSleepCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isClearing = false
        }
    }

    private func forceStepsCheck() {
        guard let service = healthKitService else { return }
        isForcingSteps = true
        Task {
            await service.forceStepsCheck()
            await MainActor.run {
                isForcingSteps = false
                loadStepData() // Refresh display
            }
        }
    }

    private func clearStepsCache() {
        guard let service = healthKitService else { return }
        isClearingSteps = true
        service.clearStepsCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isClearingSteps = false
        }
    }

    private func loadActiveEnergyData() {
        guard let service = healthKitService else { return }
        isLoadingActiveEnergy = true
        Task {
            let data = await service.debugQueryActiveEnergyData()
            await MainActor.run {
                activeEnergySamples = data
                isLoadingActiveEnergy = false
            }
        }
    }

    private func forceActiveEnergyCheck() {
        guard let service = healthKitService else { return }
        isForcingActiveEnergy = true
        Task {
            await service.forceActiveEnergyCheck()
            await MainActor.run {
                isForcingActiveEnergy = false
                loadActiveEnergyData() // Refresh display
            }
        }
    }

    private func clearActiveEnergyCache() {
        guard let service = healthKitService else { return }
        isClearingActiveEnergy = true
        service.clearActiveEnergyCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isClearingActiveEnergy = false
        }
    }

    private func clearAllAnchors() {
        healthKitService?.clearAllAnchors()
    }

    private func clearAllUpdateTimes() {
        for category in HealthDataCategory.allCases {
            healthKitService?.clearUpdateTime(for: category)
        }
    }

    private func refreshObservers() {
        guard let service = healthKitService else { return }
        isRefreshing = true
        service.refreshAllObservers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }

    private func forceRefreshAll() {
        guard let service = healthKitService else { return }
        isRefreshingAll = true
        Task {
            await service.forceRefreshAllCategories()
            await MainActor.run {
                isRefreshingAll = false
            }
        }
    }

    private func reconcileLast30Days() {
        guard let service = healthKitService else { return }
        isReconciling = true
        reconcileResult = nil
        Task {
            let result = await service.reconcileHealthKitData(days: 30)
            await MainActor.run {
                reconcileResult = result
                isReconciling = false
                // Refresh all data displays
                loadStepData()
                loadActiveEnergyData()
                loadWorkoutData()
                loadSleepData()
            }
        }
    }

    private func resyncHealthKitEvents() {
        guard let store = eventStore else { return }
        isResyncingHealthKit = true
        Task {
            await store.resyncHealthKitEvents()
            await MainActor.run {
                isResyncingHealthKit = false
            }
        }
    }

    private func restoreEventRelationships() {
        guard let store = eventStore else { return }
        isRestoringRelationships = true
        Task {
            await store.restoreEventRelationships()
            await MainActor.run {
                isRestoringRelationships = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthKitDebugView()
    }
}
