//
//  SyncErrorView.swift
//  trendy
//
//  Error display component with tap-to-expand technical details.
//  Handles different error types (auth, network, server) with appropriate actions.
//

import SwiftUI

/// A view that displays sync errors with tap-to-expand details and actionable buttons.
/// Supports error escalation visual prominence after repeated failures.
struct SyncErrorView: View {
    /// User-friendly error message displayed prominently
    let userMessage: String

    /// Technical details shown when expanded (optional)
    let technicalDetails: String?

    /// Whether this is an authentication error (401/403)
    let isAuthError: Bool

    /// Whether errors are escalated (3+ consecutive failures)
    let isEscalated: Bool

    /// Callback to retry the sync operation
    let onRetry: () async -> Void

    /// Callback to prompt re-login (for auth errors)
    let onReLogin: () -> Void

    /// Callback to dismiss the error
    let onDismiss: () -> Void

    // MARK: - State

    @State private var showDetails = false
    @State private var isRetrying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: icon, message, action buttons
            HStack(spacing: 12) {
                // Error icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(Color.dsDestructive)

                // Error message
                Text(userMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsCardForeground)
                    .lineLimit(2)

                Spacer(minLength: 8)

                // Action buttons
                actionButtons
            }

            // Expandable technical details
            if showDetails, let details = technicalDetails {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(Color.dsMutedForeground)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.dsDestructive.opacity(isEscalated ? 0.2 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEscalated ? Color.dsDestructive : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard technicalDetails != nil else { return }
            if reduceMotion {
                showDetails.toggle()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showDetails.toggle()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(technicalDetails != nil ? "Double tap for details" : "")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Primary action: Sign In or Retry
            if isAuthError {
                Button("Sign In") {
                    onReLogin()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsPrimaryForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.dsPrimary)
                .clipShape(Capsule())
            } else {
                Button {
                    Task {
                        isRetrying = true
                        await onRetry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 50)
                    } else {
                        Text("Retry")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.dsPrimaryForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.dsPrimary)
                .clipShape(Capsule())
                .disabled(isRetrying)
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsMutedForeground)
            }
            .padding(6)
            .accessibilityLabel("Dismiss error")
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = "Sync error: \(userMessage)"
        if isEscalated {
            label += ". Multiple failures detected."
        }
        if isAuthError {
            label += " Sign in required."
        }
        return label
    }

    // MARK: - Error Classification

    /// Classifies an error message into a user-friendly message and auth error flag.
    ///
    /// - Parameter message: The technical error message
    /// - Returns: A tuple with user-friendly message and whether it's an auth error
    static func classifyError(_ message: String) -> (userMessage: String, isAuthError: Bool) {
        let lowercased = message.lowercased()

        // Auth errors
        if lowercased.contains("401") ||
           lowercased.contains("unauthorized") ||
           lowercased.contains("session expired") {
            return ("Session expired, sign in again", true)
        }

        if lowercased.contains("403") || lowercased.contains("forbidden") {
            return ("Access denied, sign in again", true)
        }

        // Network errors
        if lowercased.contains("network") ||
           lowercased.contains("connection") ||
           lowercased.contains("offline") {
            return ("No connection", false)
        }

        // Server errors
        if lowercased.contains("500") || lowercased.contains("server") {
            return ("Server error, try again later", false)
        }

        // Default
        return ("Sync failed", false)
    }
}

// MARK: - Previews

#Preview("Normal Error") {
    SyncErrorView(
        userMessage: "Sync failed",
        technicalDetails: "HTTP 500: Internal server error at /api/v1/events",
        isAuthError: false,
        isEscalated: false,
        onRetry: {},
        onReLogin: {},
        onDismiss: {}
    )
    .padding()
}

#Preview("Auth Error") {
    SyncErrorView(
        userMessage: "Session expired, sign in again",
        technicalDetails: "HTTP 401: Unauthorized - JWT token expired",
        isAuthError: true,
        isEscalated: false,
        onRetry: {},
        onReLogin: {},
        onDismiss: {}
    )
    .padding()
}

#Preview("Escalated Error") {
    SyncErrorView(
        userMessage: "Sync failed - tap for details",
        technicalDetails: "HTTP 503: Service temporarily unavailable. Retry-After: 60",
        isAuthError: false,
        isEscalated: true,
        onRetry: {},
        onReLogin: {},
        onDismiss: {}
    )
    .padding()
}

#Preview("Expanded Details") {
    VStack(spacing: 20) {
        Text("Tap to toggle details")
            .font(.caption)
            .foregroundStyle(.secondary)

        SyncErrorView(
            userMessage: "Server error, try again later",
            technicalDetails: "HTTP 500: Internal server error\nRequest ID: abc-123-def\nTimestamp: 2026-01-18T19:45:00Z",
            isAuthError: false,
            isEscalated: false,
            onRetry: {},
            onReLogin: {},
            onDismiss: {}
        )
    }
    .padding()
}

#Preview("No Details") {
    SyncErrorView(
        userMessage: "No connection",
        technicalDetails: nil,
        isAuthError: false,
        isEscalated: false,
        onRetry: {},
        onReLogin: {},
        onDismiss: {}
    )
    .padding()
}
