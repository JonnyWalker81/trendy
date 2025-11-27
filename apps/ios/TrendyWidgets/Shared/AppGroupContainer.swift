//
//  AppGroupContainer.swift
//  TrendyWidgets
//
//  Shared App Group configuration for SwiftData access between main app and widgets.
//

import Foundation
import SwiftData

/// App Group identifier for sharing data between main app and widget extension
let appGroupIdentifier = "group.com.memento.trendy"

/// Shared ModelContainer configuration for widgets
enum AppGroupContainer {
    /// Creates a ModelContainer using the shared App Group storage
    /// - Returns: A ModelContainer configured for the shared store
    static func createSharedModelContainer() -> ModelContainer {
        let schema = Schema([
            Event.self,
            EventType.self,
            PropertyDefinition.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupIdentifier)
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create shared ModelContainer: \(error)")
        }
    }
}
