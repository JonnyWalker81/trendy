//
//  SyncStatusViewModel.swift
//  trendy
//
//  Observable view model for sync status, providing UI-bindable properties
//  for the floating sync indicator and other sync-aware views.
//

import Foundation
import Observation

/// Observable view model that provides sync status for UI binding.
/// Centralizes sync state observation so multiple views can share the same state.
@Observable
@MainActor
final class SyncStatusViewModel {

    // MARK: - State Properties

    /// The current sync state from SyncEngine
    private(set) var state: SyncState = .idle

    /// Number of pending mutations waiting to sync
    private(set) var pendingCount: Int = 0

    /// Timestamp of the last successful sync
    private(set) var lastSyncTime: Date?

    /// Number of consecutive sync failures (for error escalation)
    private(set) var failureCount: Int = 0

    /// Whether the device has network connectivity
    private(set) var isOnline: Bool = true

    /// Whether a sync just completed successfully (for success state display)
    private(set) var justSynced: Bool = false

    // MARK: - Error Persistence Properties

    /// Persisted error that stays until dismissed or resolved
    private(set) var persistedError: (message: String, timestamp: Date)?

    /// Whether the last error was authentication-related (401/403)
    private(set) var lastErrorWasAuthError: Bool = false

    /// Number of consecutive sync failures for escalation tracking
    private(set) var consecutiveFailureCount: Int = 0

    /// Whether errors should be visually escalated (3+ consecutive failures)
    var isErrorEscalated: Bool {
        consecutiveFailureCount >= 3
    }

    // MARK: - Computed Properties

    /// The current display state for the sync indicator
    var displayState: SyncIndicatorDisplayState {
        // If we have a persisted error, show error state even when sync is idle
        if let errorInfo = persistedError {
            let (userMessage, _) = SyncErrorView.classifyError(errorInfo.message)
            return .error(message: userMessage, canRetry: !lastErrorWasAuthError)
        }

        return SyncIndicatorDisplayState.from(
            syncState: state,
            pendingCount: pendingCount,
            isOnline: isOnline,
            failureCount: consecutiveFailureCount,
            justSynced: justSynced
        )
    }

    /// Whether the sync indicator should be visible
    var shouldShowIndicator: Bool {
        displayState != .hidden
    }

    /// Relative time since last sync (e.g., "5 min ago")
    var lastSyncRelativeText: String? {
        guard let lastSyncTime else { return nil }
        return Self.relativeFormatter.localizedString(for: lastSyncTime, relativeTo: Date())
    }

    /// Absolute time of last sync (e.g., "3:42 PM")
    var lastSyncAbsoluteText: String? {
        guard let lastSyncTime else { return nil }
        return Self.absoluteFormatter.string(from: lastSyncTime)
    }

    // MARK: - Static Formatters

    /// Formatter for relative time display ("5 min ago")
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Formatter for absolute time display ("3:42 PM")
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    // MARK: - Update Methods

    /// Refreshes sync status from EventStore.
    /// Call this periodically or when sync state may have changed.
    ///
    /// - Parameter eventStore: The EventStore to read state from
    func refresh(from eventStore: EventStore) async {
        let previousState = state

        // Read cached values from EventStore (already on MainActor)
        state = eventStore.currentSyncState
        pendingCount = eventStore.currentPendingCount
        lastSyncTime = eventStore.currentLastSyncTime
        isOnline = eventStore.isOnline

        // Handle error state from sync engine
        if case .error(let message) = state {
            recordError(message: message)
        }

        // Detect sync completion for success state
        if previousState.isSyncing && !state.isSyncing && pendingCount == 0 {
            // Only show success if no error occurred
            if case .error = state {
                // Error already recorded above
            } else {
                justSynced = true
                recordSuccess()

                // Auto-clear success state after delay
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    justSynced = false
                }
            }
        }

        // Reset failure count on successful sync (legacy support)
        if previousState.isSyncing && state == .idle && pendingCount == 0 {
            failureCount = 0
        }
    }

    /// Manually sets the online status.
    /// Use when network status changes are detected.
    ///
    /// - Parameter online: Whether the device is online
    func setOnline(_ online: Bool) {
        isOnline = online
    }

    /// Increments the failure count for error escalation.
    /// Call when a sync operation fails.
    func incrementFailureCount() {
        failureCount += 1
    }

    /// Resets the failure count.
    /// Call when a sync operation succeeds.
    func resetFailureCount() {
        failureCount = 0
    }

    /// Forces the success state display.
    /// Useful for testing or manual sync completion UI.
    func showSuccess() {
        justSynced = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            justSynced = false
        }
    }

    /// Clears the just-synced flag immediately.
    func clearSuccessState() {
        justSynced = false
    }

    // MARK: - Error Persistence Methods

    /// Records an error for persistence until dismissed or resolved.
    /// Classifies the error and tracks consecutive failures for escalation.
    ///
    /// - Parameter message: The error message from sync engine
    func recordError(message: String) {
        persistedError = (message: message, timestamp: Date())

        // Classify error to determine if it's auth-related
        let (_, isAuth) = SyncErrorView.classifyError(message)
        lastErrorWasAuthError = isAuth

        // Track consecutive failures for escalation
        consecutiveFailureCount += 1
    }

    /// Dismisses the current persisted error.
    /// Does NOT reset consecutive failure count - that only resets on success.
    func dismissError() {
        persistedError = nil
    }

    /// Records a successful sync, clearing errors and resetting failure tracking.
    func recordSuccess() {
        persistedError = nil
        consecutiveFailureCount = 0
        lastErrorWasAuthError = false
    }

    /// The technical details of the persisted error (for SyncErrorView expansion)
    var persistedErrorDetails: String? {
        persistedError?.message
    }
}
