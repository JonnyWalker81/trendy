//
//  StreakCardView.swift
//  trendy
//
//  Card view specifically for displaying streak insights
//

import SwiftUI

struct StreakCardView: View {
    let streak: APIInsight
    let eventTypeColor: Color

    init(streak: APIInsight) {
        self.streak = streak
        // Parse color from event type if available
        if let colorHex = streak.eventTypeA?.color {
            self.eventTypeColor = Color(hex: colorHex) ?? .orange
        } else {
            self.eventTypeColor = .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Flame icon with count
            ZStack {
                Circle()
                    .fill(eventTypeColor.opacity(0.2))
                    .frame(width: 50, height: 50)

                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(eventTypeColor)

                    Text("\(Int(streak.metricValue))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(eventTypeColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(streak.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(streak.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Badge if it's a new best
            if isNewBest {
                Text("Best!")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.3))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var isNewBest: Bool {
        // Check metadata for is_longest flag
        if let metadata = streak.metadata,
           let isLongest = metadata["is_longest"]?.value as? Bool {
            return isLongest
        }
        return false
    }
}

// MARK: - Compact Streak Badge for Dashboard

struct StreakBadgeView: View {
    let streak: APIInsight
    let color: Color

    init(streak: APIInsight) {
        self.streak = streak
        if let colorHex = streak.eventTypeA?.color {
            self.color = Color(hex: colorHex) ?? .orange
        } else {
            self.color = .orange
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.caption)
                .foregroundStyle(color)

            Text("\(Int(streak.metricValue))")
                .font(.caption)
                .fontWeight(.bold)

            if let eventType = streak.eventTypeA {
                Text(eventType.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}
