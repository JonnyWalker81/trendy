//
//  SyncStatusBanner.swift
//  trendy
//
//  Displays sync status and progress during data synchronization.
//

import SwiftUI

/// A banner that displays sync status and progress at the top of list views.
struct SyncStatusBanner: View {
    let syncState: SyncEngine.SyncState
    let progress: SyncProgress
    var onRetry: (() async -> Void)?

    var body: some View {
        Group {
            switch syncState {
            case .idle:
                EmptyView()

            case .syncing(let phase):
                syncingBanner(phase: phase)

            case .error(let message):
                errorBanner(message: message)
            }
        }
    }

    @ViewBuilder
    private func syncingBanner(phase: SyncEngine.SyncPhase) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.secondary)

            Text(phase.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if progress.total > 0 {
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
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
            syncState: .syncing(.downloading),
            progress: SyncProgress(total: 150, completed: 45, phase: "Downloading events...")
        )
        Spacer()
    }
}

#Preview("Error") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .error("Network connection lost"),
            progress: SyncProgress(),
            onRetry: { }
        )
        Spacer()
    }
}

#Preview("Idle") {
    VStack(spacing: 0) {
        SyncStatusBanner(
            syncState: .idle,
            progress: SyncProgress()
        )
        Spacer()
    }
}
