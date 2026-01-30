//
//  Colors.swift
//  trendy
//
//  Design System Color Tokens
//  Generated from tokens/colors.json
//  DO NOT EDIT DIRECTLY - Run: node tokens/generate.js
//

import SwiftUI
import UIKit

/// Semantic color tokens for the Trendy design system
/// These colors automatically adapt to light/dark mode
extension Color {
    /// Main app background
    static let dsBackground = Color(light: "#FFFFFF", dark: "#0F172A")

    /// Primary text color
    static let dsForeground = Color(light: "#1E293B", dark: "#F1F5F9")

    /// Card and elevated surface background
    static let dsCard = Color(light: "#F8FAFC", dark: "#1E293B")

    /// Text on card surfaces
    static let dsCardForeground = Color(light: "#1E293B", dark: "#F1F5F9")

    /// Popover and dropdown background
    static let dsPopover = Color(light: "#FFFFFF", dark: "#1E293B")

    /// Text in popovers
    static let dsPopoverForeground = Color(light: "#1E293B", dark: "#F1F5F9")

    /// Primary brand color for buttons, links, focus states
    static let dsPrimary = Color(light: "#2563EB", dark: "#60A5FA")

    /// Text on primary colored backgrounds
    static let dsPrimaryForeground = Color(light: "#FFFFFF", dark: "#0F172A")

    /// Secondary buttons and less prominent elements
    static let dsSecondary = Color(light: "#E2E8F0", dark: "#334155")

    /// Text on secondary backgrounds
    static let dsSecondaryForeground = Color(light: "#475569", dark: "#E2E8F0")

    /// Muted backgrounds for subtle distinction
    static let dsMuted = Color(light: "#F1F5F9", dark: "#1E293B")

    /// Secondary/muted text
    static let dsMutedForeground = Color(light: "#64748B", dark: "#94A3B8")

    /// Accent color for highlights and hover states
    static let dsAccent = Color(light: "#EFF6FF", dark: "#1E3A5F")

    /// Text on accent backgrounds
    static let dsAccentForeground = Color(light: "#1E40AF", dark: "#BFDBFE")

    /// Danger/error states and destructive actions
    static let dsDestructive = Color(light: "#DC2626", dark: "#EF4444")

    /// Text on destructive backgrounds
    static let dsDestructiveForeground = Color(light: "#FFFFFF", dark: "#0F172A")

    /// Success states and confirmations
    static let dsSuccess = Color(light: "#059669", dark: "#34D399")

    /// Text on success backgrounds
    static let dsSuccessForeground = Color(light: "#FFFFFF", dark: "#0F172A")

    /// Warning states and cautions
    static let dsWarning = Color(light: "#D97706", dark: "#FBBF24")

    /// Text on warning backgrounds
    static let dsWarningForeground = Color(light: "#FFFFFF", dark: "#0F172A")

    /// Link text color (distinct from primary)
    static let dsLink = Color(light: "#2563EB", dark: "#93C5FD")

    /// Default border color
    static let dsBorder = Color(light: "#E2E8F0", dark: "#334155")

    /// Input field borders
    static let dsInput = Color(light: "#CBD5E1", dark: "#475569")

    /// Focus ring color
    static let dsRing = Color(light: "#2563EB", dark: "#60A5FA")

    /// Chart color 1
    static let dsChart1 = Color(light: "#2563EB", dark: "#60A5FA")

    /// Chart color 2
    static let dsChart2 = Color(light: "#059669", dark: "#34D399")

    /// Chart color 3
    static let dsChart3 = Color(light: "#D97706", dark: "#FBBF24")

    /// Chart color 4
    static let dsChart4 = Color(light: "#7C3AED", dark: "#A78BFA")

    /// Chart color 5
    static let dsChart5 = Color(light: "#DB2777", dark: "#F472B6")

}


// MARK: - Color Initializer with Light/Dark Support

extension Color {
    /// Creates a color that adapts to light/dark mode
    init(light: String, dark: String) {
        self.init(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: dark) ?? .clear
                : UIColor(hex: light) ?? .clear
        })
    }
}

// MARK: - UIColor Hex Initializer

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        // Must be exactly 6 hex characters
        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
