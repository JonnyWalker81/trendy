//
//  ScreenshotMockData.swift
//  trendy
//
//  Mock data provider for App Store screenshots
//  Generates realistic-looking sample data for visual appeal
//

#if DEBUG
import Foundation
import SwiftUI
import SwiftData

/// Provides mock data for screenshot mode
struct ScreenshotMockData {

    // MARK: - Screenshot Mode Detection

    /// Check if app is running in screenshot mode
    static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot-mode") ||
        ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_MODE"] == "1"
    }

    /// Check if mock data should be injected
    static var shouldInjectMockData: Bool {
        isScreenshotMode &&
        (ProcessInfo.processInfo.environment["UITEST_MOCK_DATA"] == "1" ||
         ProcessInfo.processInfo.arguments.contains("--mock-data"))
    }

    /// Check if authentication should be skipped
    static var shouldSkipAuth: Bool {
        ProcessInfo.processInfo.environment["UITEST_SKIP_AUTH"] == "1"
    }

    // MARK: - Event Type Definitions

    /// Colorful event types for visually appealing screenshots
    static let eventTypes: [(name: String, colorHex: String, iconName: String)] = [
        ("Running", "#FF5722", "figure.run"),
        ("Water", "#2196F3", "drop.fill"),
        ("Meditation", "#9C27B0", "brain.head.profile"),
        ("Sleep", "#673AB7", "bed.double.fill"),
        ("Coffee", "#795548", "cup.and.saucer.fill"),
        ("Reading", "#009688", "book.fill"),
        ("Workout", "#E91E63", "dumbbell.fill"),
        ("Walk", "#4CAF50", "figure.walk")
    ]

    // MARK: - Event Definitions

    /// Sample events spread across recent days for realistic appearance
    static func generateEvents(for eventTypes: [EventType]) -> [(eventType: EventType, daysAgo: Int, hour: Int, notes: String?)] {
        guard eventTypes.count >= 8 else { return [] }

        return [
            // Today
            (eventTypes[0], 0, 7, "Morning 5K - felt great!"),
            (eventTypes[1], 0, 8, nil),
            (eventTypes[4], 0, 9, nil),
            (eventTypes[2], 0, 12, "15 min session"),
            (eventTypes[7], 0, 17, "Evening walk"),

            // Yesterday
            (eventTypes[0], 1, 6, "Hill training"),
            (eventTypes[1], 1, 10, nil),
            (eventTypes[5], 1, 20, "Finished chapter 5"),

            // 2 days ago
            (eventTypes[6], 2, 7, "Strength training"),
            (eventTypes[2], 2, 13, nil),
            (eventTypes[1], 2, 15, nil),

            // 3 days ago
            (eventTypes[7], 3, 8, "Walk in the park"),
            (eventTypes[4], 3, 10, nil),
            (eventTypes[3], 3, 22, "8 hours"),

            // 4 days ago
            (eventTypes[0], 4, 7, "Recovery run"),
            (eventTypes[6], 4, 18, "Upper body"),
            (eventTypes[2], 4, 21, "20 min deep meditation"),

            // 5 days ago
            (eventTypes[1], 5, 9, nil),
            (eventTypes[5], 5, 14, "Started new book"),
            (eventTypes[7], 5, 16, nil),

            // 6 days ago
            (eventTypes[0], 6, 6, "Long run"),
            (eventTypes[4], 6, 7, nil),
            (eventTypes[3], 6, 23, "7.5 hours"),

            // Week ago
            (eventTypes[6], 7, 7, "Leg day"),
            (eventTypes[2], 7, 12, nil),
            (eventTypes[1], 7, 18, nil),

            // More historical data for analytics
            (eventTypes[0], 8, 7, nil),
            (eventTypes[0], 10, 6, nil),
            (eventTypes[0], 12, 7, nil),
            (eventTypes[0], 14, 7, nil),
            (eventTypes[6], 9, 18, nil),
            (eventTypes[6], 11, 18, nil),
            (eventTypes[6], 13, 18, nil),
            (eventTypes[2], 9, 12, nil),
            (eventTypes[2], 11, 21, nil),
            (eventTypes[2], 13, 12, nil),
        ]
    }

    // MARK: - Data Injection

    /// Populate the database with mock data for screenshots
    @MainActor
    static func injectMockData(into context: ModelContext) {
        guard shouldInjectMockData else { return }

        // Always clear and inject fresh mock data in screenshot mode
        // This ensures we never accidentally show real user data
        clearMockData(from: context)

        print("📸 Screenshot mode: Injecting fresh mock data for screenshots")

        // Create event types
        var createdEventTypes: [EventType] = []

        for typeData in eventTypes {
            let eventType = EventType(
                name: typeData.name,
                colorHex: typeData.colorHex,
                iconName: typeData.iconName
            )
            context.insert(eventType)
            createdEventTypes.append(eventType)
        }

        // Create events
        let calendar = Calendar.current
        let now = Date()

        for eventData in generateEvents(for: createdEventTypes) {
            guard let date = calendar.date(byAdding: .day, value: -eventData.daysAgo, to: now),
                  let timestamp = calendar.date(bySettingHour: eventData.hour, minute: Int.random(in: 0...59), second: 0, of: date) else {
                continue
            }

            let event = Event(
                timestamp: timestamp,
                eventType: eventData.eventType,
                notes: eventData.notes
            )
            context.insert(event)
        }

        // Save context
        do {
            try context.save()
            print("📸 Screenshot mode: Successfully injected \(createdEventTypes.count) event types and \(generateEvents(for: createdEventTypes).count) events")
        } catch {
            print("📸 Screenshot mode: Failed to save mock data: \(error)")
        }
    }

    /// Clear mock data (for cleanup)
    @MainActor
    static func clearMockData(from context: ModelContext) {
        do {
            try context.delete(model: Event.self)
            try context.delete(model: EventType.self)
            try context.save()
            print("📸 Screenshot mode: Cleared mock data")
        } catch {
            print("📸 Screenshot mode: Failed to clear mock data: \(error)")
        }
    }
}

// MARK: - UserDefaults Extension for Screenshot Mode

extension UserDefaults {
    private static let screenshotModeKey = "screenshot_mode_enabled"
    private static let mockDataInjectedKey = "mock_data_injected"

    var isScreenshotModeEnabled: Bool {
        get { bool(forKey: Self.screenshotModeKey) }
        set { set(newValue, forKey: Self.screenshotModeKey) }
    }

    var hasMockDataBeenInjected: Bool {
        get { bool(forKey: Self.mockDataInjectedKey) }
        set { set(newValue, forKey: Self.mockDataInjectedKey) }
    }
}
#endif
