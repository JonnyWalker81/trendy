//
//  LoadingView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct LoadingView: View {
    /// Optional sync state to show progress during initial load
    var syncState: SyncState?
    /// Optional pending count to show during sync
    var pendingCount: Int?

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 30) {
            // App icon or logo
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )

            VStack(spacing: 8) {
                Text("TrendSight")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                statusText
            }

            ProgressView()
                .scaleEffect(1.2)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            isAnimating = true
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch syncState {
        case .syncing(let synced, let total):
            if total > 0 {
                let percent = Int((Double(synced) / Double(total)) * 100)
                Text("Synced \(synced) of \(total) (\(percent)%)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if let count = pendingCount, count > 0 {
                Text("Syncing \(count) changes...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Syncing...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        case .rateLimited(_, let pending):
            Text("Rate limited - \(pending) pending")
                .font(.subheadline)
                .foregroundColor(.orange)
        case .error(let message):
            Text("Error: \(message)")
                .font(.subheadline)
                .foregroundColor(.red)
                .lineLimit(2)
        case .pulling:
            Text("Downloading updates...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        default:
            Text("Loading your data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}