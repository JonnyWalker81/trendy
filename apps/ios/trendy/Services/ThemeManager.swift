//
//  ThemeManager.swift
//  trendy
//
//  Created by Claude Code
//

import SwiftUI

/// Manages the app's theme state and persistence
@Observable
@MainActor
final class ThemeManager {
    private static let themeKey = "app_theme"

    /// The currently selected theme
    var currentTheme: AppTheme {
        didSet {
            saveTheme()
        }
    }

    /// Initialize with saved preference or default to system
    init() {
        if let savedTheme = UserDefaults.standard.string(forKey: Self.themeKey),
           let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }
    }

    /// Persist theme selection to UserDefaults
    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.themeKey)
    }
}
