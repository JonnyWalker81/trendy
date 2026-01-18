//
//  SyncStatusBanner.swift
//  trendy
//
//  Displays sync status and pending mutation count during data synchronization.
//

import SwiftUI
import Combine

/// A banner that displays sync status and pending mutation count at the top of list views.
struct SyncStatusBanner: View {
    let syncState: SyncState
    let pendingCount: Int
    let lastSyncTime: Date?
    var onRetry: (() async -> Void)?

    /// Internal state for countdown timer (only used when rate limited)
    @State private var countdownRemaining: TimeInterval = 0
    @State private var countdownTimer: Timer.TimerPublisher = Timer.publish(every: 1, on: .main, in: .common)
    @State private var timerCancellable: Cancellable?

    init(syncState: SyncState, pendingCount: Int, lastSyncTime: Date? = nil, onRetry: (() async -> Void)? = nil) {
        self.syncState = syncState
        self.pendingCount = pendingCount
        self.lastSyncTime = lastSyncTime
        self.onRetry = onRetry
    }

    private var lastSyncText: String? {
        guard let lastSyncTime = lastSyncTime else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncTime, relativeTo: Date())
    }

    var body: some View {
        Group {
            switch syncState {
            case .idle:
                if pendingCount > 0 {
                    pendingBanner()
                } else if let lastSync = lastSyncText {
                    syncedBanner(lastSync: lastSync)
                } else {
                    EmptyView()
                }

            case .syncing(let synced, let total):
                syncingBanner(synced: synced, total: total)

            case .pulling:
                pullingBanner()

            case .rateLimited(let retryAfter, let pending):
                rateLimitedBanner(retryAfter: retryAfter, pending: pending)
                    .onAppear {
                        startCountdown(from: retryAfter)
                    }
                    .onDisappear {
                        stopCountdown()
                    }
                    .onReceive(countdownTimer) { _ in
                        if countdownRemaining > 0 {
                            countdownRemaining -= 1
                        }
                    }

            case .error(let message):
                errorBanner(message: message)
            }
        }
        .onChange(of: syncState) { oldState, newState in
            // When transitioning to rate limited, start the countdown
            if case .rateLimited(let retryAfter, _) = newState {
                startCountdown(from: retryAfter)
            } else {
                // When leaving rate limited state, stop the timer
                stopCountdown()
            }
        }
    }

    /// Start the countdown timer from the given duration
    private func startCountdown(from duration: TimeInterval) {
        countdownRemaining = duration
        // Create a new timer publisher and connect it
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
        timerCancellable = countdownTimer.connect()
    }

    /// Stop the countdown timer
    private func stopCountdown() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    @ViewBuilder
    private func pendingBanner() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)

            Text("\(pendingCount) pending change\(pendingCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if let onRetry = onRetry {
                Button("Sync Now") {
                    Task {
                        await onRetry()
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func syncingBanner(synced: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.secondary)

            if total > 0 {
                // Show progress with percentage
                let percent = Int((Double(synced) / Double(total)) * 100)
                Text("Synced \(synced) of \(total) (\(percent)%)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if pendingCount > 0 {
                // Fallback to pending count when total unknown
                Text("Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s")...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Syncing...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func pullingBanner() -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.secondary)

            Text("Downloading updates...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func rateLimitedBanner(retryAfter: TimeInterval, pending: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                // Use pendingCount from parent (which gets refreshed) instead of static pending value
                Text("Rate limited - \(pendingCount) pending")
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Use countdownRemaining (updated by timer) instead of static retryAfter
                Text("Auto-retry in \(formatDuration(countdownRemaining > 0 ? countdownRemaining : retryAfter))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onRetry = onRetry {
                Button("Retry Now") {
                    Task {
                        await onRetry()
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }

    /// Format duration in seconds to a human-readable string
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let intSeconds = Int(seconds)
        if intSeconds >= 60 {
            let minutes = intSeconds / 60
            let remainingSeconds = intSeconds % 60
            if remainingSeconds > 0 {
                return "\(minutes)m \(remainingSeconds)s"
            }
            return "\(minutes)m"
        }
        return "\(intSeconds)s"
    }

    @ViewBuilder
    private func syncedBanner(lastSync: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Synced \(lastSync)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync failed")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let onRetry = onRetry {
                Button("Retry") {
                    Task {
                        await onRetry()
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.1))
    }
}

#Preview("Syncing") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .syncing(synced: 0, total: 0),
            pendingCount: 0
        )
        Spacer()
    }
}

#Preview("Pending") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .idle,
            pendingCount: 3
        )
        Spacer()
    }
}

#Preview("Error") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .error("Network connection lost"),
            pendingCount: 0,
            onRetry: { }
        )
        Spacer()
    }
}

#Preview("Rate Limited") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .rateLimited(retryAfter: 45, pending: 1234),
            pendingCount: 1234,
            onRetry: { }
        )
        Spacer()
    }
}

#Preview("Syncing with Progress") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .syncing(synced: 250, total: 500),
            pendingCount: 250
        )
        Spacer()
    }
}

#Preview("Idle") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .idle,
            pendingCount: 0
        )
        Spacer()
    }
}

#Preview("Synced") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .idle,
            pendingCount: 0,
            lastSyncTime: Date().addingTimeInterval(-300)
        )
        Spacer()
    }
}

#Preview("Pulling") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .pulling,
            pendingCount: 0
        )
        Spacer()
    }
}
