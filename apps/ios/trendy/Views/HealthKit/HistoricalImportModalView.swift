//
//  HistoricalImportModalView.swift
//  trendy
//
//  Modal view for historical HealthKit data import with progress tracking
//

import SwiftUI

struct HistoricalImportModalView: View {
    let categoryName: String
    @Binding var current: Int
    @Binding var total: Int
    let onCancel: () -> Void

    @State private var startTime: Date?
    @State private var lastUpdateTime: Date = Date()
    @State private var estimatedTimeRemaining: TimeInterval?
    @State private var processingRate: Double = 0  // items per second
    @State private var showCancelConfirmation = false

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    private var percentComplete: Int {
        Int(progress * 100)
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon and circular progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color(UIColor.systemGray5), lineWidth: 12)
                    .frame(width: 140, height: 140)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                // Center content
                VStack(spacing: 4) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.pink)
                        .symbolEffect(.pulse, options: .repeating)

                    Text("\(percentComplete)%")
                        .font(.title2.bold())
                        .monospacedDigit()
                }
            }

            // Title and category
            VStack(spacing: 8) {
                Text("Importing Health Data")
                    .font(.title2.bold())

                Text(categoryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Progress details
            VStack(spacing: 16) {
                // Linear progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 12)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 12)
                .padding(.horizontal)

                // Stats row
                HStack(spacing: 24) {
                    StatView(
                        title: "Processed",
                        value: "\(current)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )

                    StatView(
                        title: "Total",
                        value: "\(total)",
                        icon: "circle.grid.3x3.fill",
                        color: .blue
                    )

                    StatView(
                        title: "Remaining",
                        value: "\(max(0, total - current))",
                        icon: "clock.fill",
                        color: .orange
                    )
                }

                // Time estimate
                if let estimate = estimatedTimeRemaining, estimate > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                        Text("About \(formatTimeRemaining(estimate)) remaining")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else if current > 0 && current < total {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating time remaining...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Cancel button
            Button(role: .destructive) {
                showCancelConfirmation = true
            } label: {
                Label("Cancel Import", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemBackground))
        .confirmationDialog(
            "Cancel Import?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Import", role: .destructive) {
                onCancel()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("Progress will be saved. You can continue the import later.")
        }
        .onAppear {
            startTime = Date()
        }
        .onChange(of: current) { oldValue, newValue in
            updateTimeEstimate(oldCurrent: oldValue, newCurrent: newValue)
        }
    }

    private func updateTimeEstimate(oldCurrent: Int, newCurrent: Int) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdateTime)

        // Calculate processing rate (items per second)
        if elapsed > 0 && newCurrent > oldCurrent {
            let itemsProcessed = Double(newCurrent - oldCurrent)
            let instantRate = itemsProcessed / elapsed

            // Smooth the rate using exponential moving average
            if processingRate == 0 {
                processingRate = instantRate
            } else {
                processingRate = (processingRate * 0.7) + (instantRate * 0.3)
            }

            // Calculate remaining time
            let remaining = total - newCurrent
            if processingRate > 0 {
                estimatedTimeRemaining = Double(remaining) / processingRate
            }
        }

        lastUpdateTime = now
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "less than a minute"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes == 0 {
                return hours == 1 ? "1 hour" : "\(hours) hours"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
}

// MARK: - Stat View Component

private struct StatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.bold())
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var current = 42
    @Previewable @State var total = 500

    HistoricalImportModalView(
        categoryName: "All Categories",
        current: $current,
        total: $total,
        onCancel: { Log.healthKit.debug("Historical import cancelled (preview)") }
    )
}
