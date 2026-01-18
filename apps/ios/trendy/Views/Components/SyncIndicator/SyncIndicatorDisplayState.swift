//
//  SyncIndicatorDisplayState.swift
//  trendy
//
//  Display state machine for the sync indicator. Maps the underlying SyncState
//  plus context (pending count, online status, failure count) to UI display states.
//

import Foundation

/// Display states for the floating sync indicator.
/// Each state maps to a distinct visual appearance and behavior.
enum SyncIndicatorDisplayState: Equatable {
    /// Indicator should not be visible
    case hidden

    /// Device is offline with pending changes
    /// - Parameter pending: Number of pending changes waiting to sync
    case offline(pending: Int)

    /// Actively syncing data
    /// - Parameters:
    ///   - current: Number of items synced so far
    ///   - total: Total number of items to sync (0 for indeterminate)
    case syncing(current: Int, total: Int)

    /// Sync error occurred
    /// - Parameters:
    ///   - message: User-friendly error message
    ///   - canRetry: Whether the error is retryable
    case error(message: String, canRetry: Bool)

    /// Sync completed successfully (shows briefly before hiding)
    case success

    // MARK: - Factory Method

    /// Creates a display state from the underlying sync state and context.
    ///
    /// State priority:
    /// 1. Offline with pending -> .offline
    /// 2. Syncing/pulling -> .syncing
    /// 3. Rate limited -> .error (retryable)
    /// 4. Error -> .error
    /// 5. Idle with pending=0 and just synced -> .success
    /// 6. Otherwise -> .hidden
    ///
    /// - Parameters:
    ///   - syncState: The underlying SyncState from SyncEngine
    ///   - pendingCount: Number of pending mutations
    ///   - isOnline: Whether the device has network connectivity
    ///   - failureCount: Number of consecutive sync failures (for error escalation)
    ///   - justSynced: Whether a sync just completed successfully
    /// - Returns: The appropriate display state for the indicator
    static func from(
        syncState: SyncState,
        pendingCount: Int,
        isOnline: Bool,
        failureCount: Int = 0,
        justSynced: Bool = false
    ) -> Self {
        // Priority 1: Offline with pending changes
        if !isOnline && pendingCount > 0 {
            return .offline(pending: pendingCount)
        }

        // Priority 2: Active sync operations
        switch syncState {
        case .syncing(let synced, let total):
            return .syncing(current: synced, total: total)

        case .pulling:
            // Indeterminate progress for pull operations
            return .syncing(current: 0, total: 0)

        case .rateLimited(_, let pending):
            // Rate limited is a retryable error condition
            let message = failureCount >= 3
                ? "Server busy - will retry automatically"
                : "Rate limited - retrying soon"
            return .error(message: message, canRetry: true)

        case .error(let message):
            // Determine if error is retryable based on message content
            let isRetryable = !message.lowercased().contains("auth") &&
                              !message.lowercased().contains("sign in")
            let userMessage = Self.userFriendlyMessage(from: message, failureCount: failureCount)
            return .error(message: userMessage, canRetry: isRetryable)

        case .idle:
            // Show success briefly after sync completes
            if justSynced && pendingCount == 0 {
                return .success
            }
            // Show offline state if offline (even without pending)
            if !isOnline {
                return .offline(pending: pendingCount)
            }
            // Hide when idle with nothing pending
            return .hidden
        }
    }

    // MARK: - Helpers

    /// Converts technical error messages to user-friendly ones.
    private static func userFriendlyMessage(from message: String, failureCount: Int) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("network") || lowercased.contains("connection") {
            return "No connection"
        }

        if lowercased.contains("401") || lowercased.contains("auth") || lowercased.contains("unauthorized") {
            return "Session expired - sign in again"
        }

        if lowercased.contains("500") || lowercased.contains("server") {
            return "Server error - try again later"
        }

        if lowercased.contains("timeout") {
            return "Request timed out"
        }

        // Escalate visibility after multiple failures
        if failureCount >= 3 {
            return "Sync failed - tap for details"
        }

        // Default to a shortened version of the original
        if message.count > 30 {
            return String(message.prefix(27)) + "..."
        }

        return message
    }
}
