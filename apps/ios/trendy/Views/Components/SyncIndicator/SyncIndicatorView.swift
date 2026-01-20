//
//  SyncIndicatorView.swift
//  trendy
//
//  A floating pill indicator that displays sync status.
//  Shows different states: syncing, offline, error, and success.
//

import SwiftUI

/// A floating pill indicator that displays sync status with state-based appearance.
/// The indicator appears only when there's meaningful status to show.
struct SyncIndicatorView: View {

    // MARK: - Properties

    /// The current display state
    let displayState: SyncIndicatorDisplayState

    /// Action to retry failed sync operations
    let onRetry: () async -> Void

    /// Accessibility setting for reduced motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        // Use ZStack to layer passthrough visual content with interactive button overlay
        ZStack(alignment: .trailing) {
            // Visual pill - fully passthrough, does not intercept taps
            HStack(spacing: 12) {
                statusIcon
                statusContent
                Spacer()
                // Reserve space for action button but don't render it here
                actionButtonPlaceholder
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundColor.opacity(0.95))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
            .allowsHitTesting(false) // Entire pill is passthrough

            // Action button overlay - interactive, positioned over the placeholder
            HStack {
                Spacer()
                actionButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Action Button Placeholder

    /// Invisible placeholder to reserve space for action button in the passthrough layer
    @ViewBuilder
    private var actionButtonPlaceholder: some View {
        switch displayState {
        case .error(_, let canRetry) where canRetry:
            Text("Retry")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .opacity(0) // Invisible, just for layout

        case .offline(let pending) where pending > 0:
            Text("Sync Now")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .opacity(0) // Invisible, just for layout

        default:
            EmptyView()
        }
    }

    // MARK: - Background Color

    private var backgroundColor: Color {
        switch displayState {
        case .hidden, .success:
            return Color.dsSuccess
        case .offline:
            return Color.dsWarning
        case .syncing:
            return Color.dsPrimary
        case .error:
            return Color.dsDestructive
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch displayState {
        case .hidden:
            EmptyView()

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.dsSuccessForeground)
                .font(.title3)

        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(Color.dsWarningForeground)
                .font(.title3)

        case .syncing:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.dsPrimaryForeground)
                .scaleEffect(0.8)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsDestructiveForeground)
                .font(.title3)
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        switch displayState {
        case .hidden:
            EmptyView()

        case .success:
            Text("All synced")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.dsSuccessForeground)

        case .offline(let pending):
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsWarningForeground)
                if pending > 0 {
                    Text("\(pending) pending")
                        .font(.caption)
                        .foregroundStyle(Color.dsWarningForeground.opacity(0.8))
                }
            }

        case .syncing(let current, let total):
            if total > 0 {
                SyncProgressBar(current: current, total: total)
            } else {
                Text("Syncing...")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsPrimaryForeground)
            }

        case .error(let message, _):
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.dsDestructiveForeground)
                .lineLimit(2)
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch displayState {
        case .error(_, let canRetry) where canRetry:
            Button("Retry") {
                Task {
                    await onRetry()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dsDestructiveForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.2))
            .clipShape(Capsule())

        case .offline(let pending) where pending > 0:
            Button("Sync Now") {
                Task {
                    await onRetry()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dsWarningForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.2))
            .clipShape(Capsule())

        default:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Hidden") {
    VStack {
        SyncIndicatorView(
            displayState: .hidden,
            onRetry: {}
        )
        Spacer()
    }
}

#Preview("Success") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .success,
            onRetry: {}
        )
    }
}

#Preview("Offline with Pending") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .offline(pending: 5),
            onRetry: {}
        )
    }
}

#Preview("Offline no Pending") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .offline(pending: 0),
            onRetry: {}
        )
    }
}

#Preview("Syncing Determinate") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .syncing(current: 3, total: 5),
            onRetry: {}
        )
    }
}

#Preview("Syncing Indeterminate") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .syncing(current: 0, total: 0),
            onRetry: {}
        )
    }
}

#Preview("Error Retryable") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .error(message: "Connection failed", canRetry: true),
            onRetry: {}
        )
    }
}

#Preview("Error Not Retryable") {
    VStack {
        Spacer()
        SyncIndicatorView(
            displayState: .error(message: "Session expired - sign in again", canRetry: false),
            onRetry: {}
        )
    }
}

#Preview("All States") {
    VStack(spacing: 16) {
        SyncIndicatorView(
            displayState: .success,
            onRetry: {}
        )
        SyncIndicatorView(
            displayState: .offline(pending: 3),
            onRetry: {}
        )
        SyncIndicatorView(
            displayState: .syncing(current: 2, total: 5),
            onRetry: {}
        )
        SyncIndicatorView(
            displayState: .error(message: "Network error", canRetry: true),
            onRetry: {}
        )
    }
    .padding()
}
