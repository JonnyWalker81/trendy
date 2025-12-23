//
//  HealthKitSettings.swift
//  trendy
//
//  Simple, reliable storage for HealthKit configuration using UserDefaults.
//  This replaces the SwiftData-based HealthKitConfiguration model which had
//  persistence issues due to uncommitted transactions on app termination.
//

import Foundation

/// Manages HealthKit integration settings using UserDefaults (App Group).
/// This provides reliable, immediate persistence for configuration data.
@Observable
final class HealthKitSettings {
    // MARK: - Singleton

    static let shared = HealthKitSettings()

    // MARK: - Storage

    private static let appGroupIdentifier = "group.com.memento.trendy"

    private let defaults: UserDefaults

    // MARK: - Keys

    private let enabledCategoriesKey = "healthKit.enabledCategories"
    private let notifyOnDetectionKey = "healthKit.notifyOnDetection"
    private let eventTypeLinksKey = "healthKit.eventTypeLinks"  // category -> eventTypeId mapping

    // MARK: - Initialization

    private init() {
        if let appGroupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            self.defaults = appGroupDefaults
            print("✅ HealthKitSettings: Using App Group UserDefaults")
        } else {
            self.defaults = .standard
            print("⚠️ HealthKitSettings: App Group not available, using standard UserDefaults")
        }
    }

    // MARK: - Enabled Categories

    /// Set of currently enabled HealthKit data categories
    var enabledCategories: Set<HealthDataCategory> {
        get {
            guard let rawValues = defaults.stringArray(forKey: enabledCategoriesKey) else {
                return []
            }
            return Set(rawValues.compactMap { HealthDataCategory(rawValue: $0) })
        }
        set {
            let rawValues = newValue.map { $0.rawValue }
            defaults.set(rawValues, forKey: enabledCategoriesKey)
            print("📱 HealthKitSettings: Saved \(newValue.count) enabled categories")
        }
    }

    /// Check if a specific category is enabled
    func isEnabled(_ category: HealthDataCategory) -> Bool {
        enabledCategories.contains(category)
    }

    /// Enable or disable a specific category
    func setEnabled(_ category: HealthDataCategory, enabled: Bool) {
        var categories = enabledCategories
        if enabled {
            categories.insert(category)
        } else {
            categories.remove(category)
        }
        enabledCategories = categories
    }

    /// Enable multiple categories at once
    func enableCategories(_ categories: Set<HealthDataCategory>) {
        var current = enabledCategories
        current.formUnion(categories)
        enabledCategories = current
    }

    /// Disable all categories
    func disableAllCategories() {
        enabledCategories = []
    }

    // MARK: - Notification Preferences

    /// Whether to send notifications when health data is detected
    /// Stored per-category
    func notifyOnDetection(for category: HealthDataCategory) -> Bool {
        let key = "\(notifyOnDetectionKey).\(category.rawValue)"
        return defaults.bool(forKey: key)
    }

    func setNotifyOnDetection(_ notify: Bool, for category: HealthDataCategory) {
        let key = "\(notifyOnDetectionKey).\(category.rawValue)"
        defaults.set(notify, forKey: key)
    }

    // MARK: - Event Type Links (using serverId for sync stability)

    /// Get the linked EventType serverId for a category (if any)
    /// Returns the backend server ID which is stable across syncs
    func eventTypeServerId(for category: HealthDataCategory) -> String? {
        guard let links = defaults.dictionary(forKey: eventTypeLinksKey) as? [String: String],
              let serverId = links[category.rawValue] else {
            return nil
        }
        return serverId
    }

    /// Link a category to a specific EventType using its serverId
    /// The serverId is the backend UUID which remains stable across syncs
    func setEventTypeServerId(_ serverId: String?, for category: HealthDataCategory) {
        var links = (defaults.dictionary(forKey: eventTypeLinksKey) as? [String: String]) ?? [:]
        if let serverId = serverId {
            links[category.rawValue] = serverId
        } else {
            links.removeValue(forKey: category.rawValue)
        }
        defaults.set(links, forKey: eventTypeLinksKey)
    }

    // MARK: - Legacy Migration (for existing local UUID links)

    /// Migrate old local UUID links to serverIds
    /// Call this after sync when EventTypes have their serverIds populated
    func migrateToServerIds(eventTypes: [any EventTypeProtocol]) {
        var links = (defaults.dictionary(forKey: eventTypeLinksKey) as? [String: String]) ?? [:]
        var migrated = 0

        for category in HealthDataCategory.allCases {
            guard let storedValue = links[category.rawValue] else { continue }

            // Check if this looks like a local UUID (not yet migrated)
            // Local UUIDs are uppercase, serverIds from backend are lowercase
            if let localUUID = UUID(uuidString: storedValue) {
                // Find the EventType with this local ID and get its serverId
                if let eventType = eventTypes.first(where: { $0.localId == localUUID }),
                   let serverId = eventType.backendServerId {
                    links[category.rawValue] = serverId
                    migrated += 1
                    print("📱 HealthKitSettings: Migrated \(category.displayName) from local UUID to serverId")
                }
            }
            // If it's already a serverId (lowercase UUID string), leave it alone
        }

        if migrated > 0 {
            defaults.set(links, forKey: eventTypeLinksKey)
            print("📱 HealthKitSettings: Migrated \(migrated) event type links to serverIds")
        }
    }

    // MARK: - Convenience

    /// Get all categories that are not yet enabled (available to add)
    var availableCategories: [HealthDataCategory] {
        let enabled = enabledCategories
        return HealthDataCategory.allCases.filter { !enabled.contains($0) }
    }

    /// Configuration summary for a category
    struct CategoryConfig {
        let category: HealthDataCategory
        let isEnabled: Bool
        let notifyOnDetection: Bool
        let linkedEventTypeServerId: String?
    }

    func config(for category: HealthDataCategory) -> CategoryConfig {
        CategoryConfig(
            category: category,
            isEnabled: isEnabled(category),
            notifyOnDetection: notifyOnDetection(for: category),
            linkedEventTypeServerId: eventTypeServerId(for: category)
        )
    }

    /// All enabled category configurations
    var enabledConfigs: [CategoryConfig] {
        enabledCategories.map { config(for: $0) }
    }

    // MARK: - Debug

    func logCurrentState() {
        print("📱 HealthKitSettings State:")
        print("   Enabled categories: \(enabledCategories.map { $0.displayName }.joined(separator: ", "))")
        for category in enabledCategories {
            let notify = notifyOnDetection(for: category) ? "yes" : "no"
            let linked = eventTypeServerId(for: category)?.prefix(8) ?? "auto"
            print("   - \(category.displayName): notify=\(notify), eventTypeServerId=\(linked)")
        }
    }
}
