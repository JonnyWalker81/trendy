//
//  RelativeTimestampView.swift
//  trendy
//
//  Reusable timestamp component showing relative time by default,
//  absolute time on tap.
//

import SwiftUI

/// A timestamp view that shows relative time ("5 min ago") by default
/// and toggles to absolute time ("3:42 PM") on tap.
struct RelativeTimestampView: View {
    let date: Date
    var font: Font = .caption
    var color: Color = .dsMutedForeground

    @State private var showAbsolute = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Static formatters to avoid recreation on each render
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        Text(displayText)
            .font(font)
            .foregroundStyle(color)
            .scaleEffect(showAbsolute ? 1.0 : 1.0) // Base scale
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: showAbsolute)
            .onTapGesture {
                if !reduceMotion {
                    // Subtle scale animation on tap
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                        showAbsolute.toggle()
                    }
                } else {
                    showAbsolute.toggle()
                }
            }
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Tap to toggle between relative and absolute time")
    }

    private var displayText: String {
        if showAbsolute {
            return Self.absoluteFormatter.string(from: date)
        } else {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
    }

    private var accessibilityText: String {
        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        let absolute = Self.absoluteFormatter.string(from: date)
        return showAbsolute ? "At \(absolute)" : "\(relative)"
    }
}

// MARK: - Preview

#Preview("5 minutes ago") {
    VStack(spacing: 20) {
        RelativeTimestampView(date: Date().addingTimeInterval(-300))

        RelativeTimestampView(
            date: Date().addingTimeInterval(-3600),
            font: .subheadline,
            color: .dsSecondaryForeground
        )

        RelativeTimestampView(
            date: Date().addingTimeInterval(-86400),
            font: .footnote
        )
    }
    .padding()
}
