//
//  EventTypeTemplate.swift
//  trendy
//
//  Predefined event type templates for onboarding
//

import Foundation
import SwiftUI
import UIKit

/// Predefined event type templates for quick onboarding
struct EventTypeTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let iconName: String
    let colorHex: String
    let description: String

    /// Whether this is the custom template that requires user input
    var isCustom: Bool {
        id == "custom"
    }

    /// SwiftUI Color from hex string
    var color: Color {
        // Use UIColor hex initializer from Colors.swift, then convert to Color
        if let uiColor = UIColor(hex: colorHex) {
            return Color(uiColor)
        }
        return .blue
    }

    /// All available templates
    static let templates: [EventTypeTemplate] = [
        EventTypeTemplate(
            id: "mood",
            name: "Mood",
            iconName: "face.smiling.fill",
            colorHex: "#FBBF24",
            description: "Track your daily mood and emotions"
        ),
        EventTypeTemplate(
            id: "workout",
            name: "Workout",
            iconName: "figure.run",
            colorHex: "#34D399",
            description: "Log your exercise sessions"
        ),
        EventTypeTemplate(
            id: "medication",
            name: "Medication",
            iconName: "pills.fill",
            colorHex: "#60A5FA",
            description: "Never miss a dose"
        ),
        EventTypeTemplate(
            id: "coffee",
            name: "Coffee",
            iconName: "cup.and.saucer.fill",
            colorHex: "#A78BFA",
            description: "Track your caffeine intake"
        ),
        EventTypeTemplate(
            id: "journal",
            name: "Journal",
            iconName: "book.fill",
            colorHex: "#F472B6",
            description: "Daily reflections and notes"
        ),
        EventTypeTemplate(
            id: "custom",
            name: "Custom",
            iconName: "plus.circle.fill",
            colorHex: "#94A3B8",
            description: "Create your own event type"
        )
    ]

    /// Get template by ID
    static func template(for id: String) -> EventTypeTemplate? {
        templates.first { $0.id == id }
    }
}
