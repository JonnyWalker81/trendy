//
//  SyncSettingsView.swift
//  trendy
//
//  Settings section for sync status, last sync time, and sync history.
//

import SwiftUI

/// Settings view showing sync status, last sync time, and history
struct SyncSettingsView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(SyncHistoryStore.self) private var syncHistoryStore
    @State private var isRetrying = false
    @State private var showErrorDetails: UUID?

    var body: some View {
        Form {
            // Section 1: Sync Status
            Section {
                // Status row
                HStack {
                    Text("Status")
                    Spacer()
                    statusView
                }

                // Pending changes row
                HStack {
                    Text("Pending Changes")
                    Spacer()
                    Text("\(eventStore.currentPendingCount)")
                        .foregroundStyle(eventStore.currentPendingCount > 0 ? Color.dsWarning : Color.dsMutedForeground)
                }

                // Last synced row
                HStack {
                    Text("Last Synced")
                    Spacer()
                    if let lastSync = eventStore.currentLastSyncTime {
                        RelativeTimestampView(date: lastSync)
                    } else {
                        Text("Never")
                            .foregroundStyle(Color.dsMutedForeground)
                    }
                }

                // Sync Now button
                Button {
                    Task {
                        await triggerSync()
                    }
                } label: {
                    HStack {
                        if isRetrying || eventStore.currentSyncState.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                        }
                        Text("Sync Now")
                    }
                }
                .disabled(!canSync)
            } header: {
                Text("Sync Status")
            } footer: {
                syncStatusFooter
            }

            // Section 2: Sync History
            Section {
                if syncHistoryStore.entries.isEmpty {
                    Text("No sync history yet")
                        .foregroundStyle(Color.dsMutedForeground)
                        .font(.subheadline)
                } else {
                    ForEach(syncHistoryStore.entries) { entry in
                        syncHistoryRow(entry)
                    }
                }
            } header: {
                Text("Sync History")
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        switch eventStore.currentSyncState {
        case .idle:
            if eventStore.isOnline {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.dsSuccess)
                    Text("Online")
                        .foregroundStyle(Color.dsMutedForeground)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(Color.dsWarning)
                    Text("Offline")
                        .foregroundStyle(Color.dsWarning)
                }
            }

        case .syncing(let synced, let total):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                if total > 0 {
                    Text("Syncing \(synced)/\(total)")
                        .foregroundStyle(Color.dsPrimary)
                } else {
                    Text("Syncing...")
                        .foregroundStyle(Color.dsPrimary)
                }
            }

        case .pulling:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Pulling...")
                    .foregroundStyle(Color.dsPrimary)
            }

        case .rateLimited(let retryAfter, _):
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.dsWarning)
                Text("Rate limited (\(Int(retryAfter))s)")
                    .foregroundStyle(Color.dsWarning)
            }

        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.dsDestructive)
                Text("Error")
                    .foregroundStyle(Color.dsDestructive)
            }
            .help(message)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var syncStatusFooter: some View {
        if !eventStore.isOnline {
            Text("Connect to the internet to sync your data.")
        } else if eventStore.currentPendingCount > 0 {
            Text("You have \(eventStore.currentPendingCount) change\(eventStore.currentPendingCount == 1 ? "" : "s") waiting to sync.")
        } else {
            Text("Your data is up to date.")
        }
    }

    // MARK: - Sync History Row

    @ViewBuilder
    private func syncHistoryRow(_ entry: SyncHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Status icon
                statusIcon(for: entry.status)

                // Timestamp
                RelativeTimestampView(date: entry.timestamp, font: .subheadline)

                Spacer()

                // Duration
                Text(entry.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(Color.dsMutedForeground)
            }

            // Summary line
            if entry.status != .failed {
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(Color.dsMutedForeground)
            }

            // Error message (expandable)
            if entry.status == .failed, let errorMessage = entry.errorMessage {
                if showErrorDetails == entry.id {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.dsDestructive)
                        .padding(.top, 2)
                } else {
                    Text("Tap for details")
                        .font(.caption)
                        .foregroundStyle(Color.dsDestructive.opacity(0.7))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.status == .failed && entry.errorMessage != nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if showErrorDetails == entry.id {
                        showErrorDetails = nil
                    } else {
                        showErrorDetails = entry.id
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: SyncHistoryEntry.Status) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.dsSuccess)
                .font(.subheadline)
        case .partialSuccess:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.dsWarning)
                .font(.subheadline)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.dsDestructive)
                .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private var canSync: Bool {
        !isRetrying &&
        !eventStore.currentSyncState.isSyncing &&
        eventStore.isOnline
    }

    private func triggerSync() async {
        isRetrying = true
        await eventStore.fetchData(force: true)
        isRetrying = false
    }
}

// MARK: - Preview

#Preview("Sync Settings") {
    let mockStore = SyncHistoryStore()
    mockStore.recordSuccess(events: 5, eventTypes: 2, durationMs: 1500)
    mockStore.recordSuccess(events: 0, eventTypes: 0, durationMs: 350)
    mockStore.recordFailure(errorMessage: "Network connection lost", durationMs: 5000)
    mockStore.recordSuccess(events: 12, eventTypes: 0, durationMs: 2800)

    return NavigationStack {
        SyncSettingsView()
    }
    .environment(mockStore)
}
