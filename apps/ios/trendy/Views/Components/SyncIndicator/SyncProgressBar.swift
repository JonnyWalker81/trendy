//
//  SyncProgressBar.swift
//  trendy
//
//  A determinate progress bar with count display for sync operations.
//  Shows "Syncing X of Y" text above a horizontal progress bar.
//

import SwiftUI

/// A progress bar showing sync progress with a count display.
/// Respects the reduce motion accessibility setting for animations.
struct SyncProgressBar: View {

    // MARK: - Properties

    /// Number of items synced so far
    let current: Int

    /// Total number of items to sync
    let total: Int

    /// Accessibility setting for reduced motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed Properties

    /// Progress value between 0 and 1
    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(Double(current) / Double(total), 1.0)
    }

    /// Percentage value (0-100)
    private var percent: Int {
        Int(progress * 100)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Count display with percentage
            Text("Syncing \(current) of \(total) (\(percent)%)")
                .font(.subheadline)
                .foregroundStyle(Color.dsPrimaryForeground)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(0, geometry.size.width * progress), height: 4)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.2),
                            value: progress
                        )
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Previews

#Preview("Progress: 3 of 5") {
    SyncProgressBar(current: 3, total: 5)
        .padding()
        .background(Color.dsPrimary)
}

#Preview("Progress: 0 of 10") {
    SyncProgressBar(current: 0, total: 10)
        .padding()
        .background(Color.dsPrimary)
}

#Preview("Progress: 10 of 10 (Complete)") {
    SyncProgressBar(current: 10, total: 10)
        .padding()
        .background(Color.dsPrimary)
}

#Preview("Progress: Edge Case (0 total)") {
    SyncProgressBar(current: 0, total: 0)
        .padding()
        .background(Color.dsPrimary)
}

#Preview("Progress: Large Numbers") {
    SyncProgressBar(current: 250, total: 500)
        .padding()
        .background(Color.dsPrimary)
}
