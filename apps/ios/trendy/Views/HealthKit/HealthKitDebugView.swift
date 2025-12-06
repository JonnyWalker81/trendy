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

    @State private var sleepSamples: [(start: Date, end: Date, duration: TimeInterval, sleepType: String, source: String)] = []
    @State private var isLoadingSleep = false
    @State private var isForcing = false
    @State private var isClearing = false
    @State private var isRefreshing = false

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
            } header: {
                Text("Cache Status")
            } footer: {
                Text("'Last Sleep Date' prevents re-processing. If stuck, clear the sleep cache.")
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

            // Actions Section
            Section {
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
            } header: {
                Text("Actions")
            } footer: {
                Text("'Force Sleep Check' runs aggregation now. 'Clear Sleep Cache' allows re-processing old data. 'Refresh Observers' restarts background monitoring.")
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

    private func refreshObservers() {
        guard let service = healthKitService else { return }
        isRefreshing = true
        service.refreshAllObservers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }
}

#Preview {
    NavigationStack {
        HealthKitDebugView()
    }
}
