//
//  AppTheme.swift
//  trendy
//
//  Created by Claude Code
//

import SwiftUI

/// Represents the available theme options for the app
enum AppTheme: String, CaseIterable, Codable {
    case system
    case light
    case dark

    /// Display name for UI presentation
    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    /// SF Symbol icon for the theme
    var iconName: String {
        switch self {
        case .system:
            return "iphone"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    /// Converts the theme to SwiftUI's ColorScheme
    /// Returns nil for system (follows device setting)
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
