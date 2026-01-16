//
//  SyncStatusBanner.swift
//  trendy
//
//  Displays sync status and pending mutation count during data synchronization.
//

import SwiftUI

/// A banner that displays sync status and pending mutation count at the top of list views.
struct SyncStatusBanner: View {
    let syncState: SyncState
    let pendingCount: Int
    let lastSyncTime: Date?
    var onRetry: (() async -> Void)?

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

            case .syncing:
                syncingBanner()

            case .error(let message):
                errorBanner(message: message)
            }
        }
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
    private func syncingBanner() -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.secondary)

            Text("Syncing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
            syncState: .syncing,
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
