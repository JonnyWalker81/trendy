//
//  HealthKitConfiguration.swift
//  trendy
//
//  Created by Claude Code on 11/25/25.
//

import Foundation
import SwiftData
import HealthKit

/// Represents the types of health data Trendy can monitor
enum HealthDataCategory: String, Codable, CaseIterable {
    case workout = "workout"
    case steps = "steps"
    case sleep = "sleep"
    case activeEnergy = "active_energy"
    case mindfulness = "mindfulness"
    case water = "water"

    var displayName: String {
        switch self {
        case .workout: return "Workout"
        case .steps: return "Steps"
        case .sleep: return "Sleep"
        case .activeEnergy: return "Active Energy"
        case .mindfulness: return "Mindfulness"
        case .water: return "Water"
        }
    }

    var iconName: String {
        switch self {
        case .workout: return "figure.run"
        case .steps: return "figure.walk"
        case .sleep: return "bed.double.fill"
        case .activeEnergy: return "flame.fill"
        case .mindfulness: return "brain.head.profile"
        case .water: return "drop.fill"
        }
    }

    var defaultEventTypeName: String {
        displayName
    }

    var defaultColor: String {
        switch self {
        case .workout: return "#FF2D55"      // Pink
        case .sleep: return "#5856D6"        // Purple
        case .steps: return "#34C759"        // Green
        case .activeEnergy: return "#FF9500" // Orange
        case .mindfulness: return "#AF52DE"  // Purple
        case .water: return "#007AFF"        // Blue
        }
    }

    var defaultIcon: String {
        iconName
    }

    /// Returns the HealthKit sample type for this category
    var hkSampleType: HKSampleType? {
        switch self {
        case .workout:
            return HKWorkoutType.workoutType()
        case .steps:
            return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .sleep:
            return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .activeEnergy:
            return HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .mindfulness:
            return HKCategoryType.categoryType(forIdentifier: .mindfulSession)
        case .water:
            return HKQuantityType.quantityType(forIdentifier: .dietaryWater)
        }
    }

    /// Whether this category supports immediate background delivery
    var supportsImmediateDelivery: Bool {
        switch self {
        case .workout, .sleep, .mindfulness:
            return true
        case .steps, .activeEnergy, .water:
            return false // Use hourly for cumulative data
        }
    }

    /// The recommended background delivery frequency
    var backgroundDeliveryFrequency: HKUpdateFrequency {
        supportsImmediateDelivery ? .immediate : .hourly
    }
}

/// SwiftData model linking HealthKit data types to EventTypes
/// Note: This model is deprecated - use HealthKitSettings (UserDefaults-based) instead
@Model
final class HealthKitConfiguration {
    /// UUIDv7 identifier - consistent with V2 schema pattern
    @Attribute(.unique) var id: String
    var healthDataCategory: String      // Raw value storage for SwiftData compatibility
    var eventTypeID: String?            // Links to EventType by UUIDv7 string
    var isEnabled: Bool
    var notifyOnDetection: Bool         // User-configurable notifications
    var createdAt: Date
    var updatedAt: Date

    /// Computed property for convenient enum access
    @Transient var category: HealthDataCategory {
        get { HealthDataCategory(rawValue: healthDataCategory) ?? .workout }
        set { healthDataCategory = newValue.rawValue }
    }

    init(
        category: HealthDataCategory,
        eventTypeID: String? = nil,
        isEnabled: Bool = true,
        notifyOnDetection: Bool = false
    ) {
        self.id = UUIDv7.generate()
        self.healthDataCategory = category.rawValue
        self.eventTypeID = eventTypeID
        self.isEnabled = isEnabled
        self.notifyOnDetection = notifyOnDetection
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Convenience initializer that takes an EventType object
    convenience init(
        category: HealthDataCategory,
        eventType: EventType?,
        isEnabled: Bool = true,
        notifyOnDetection: Bool = false
    ) {
        self.init(
            category: category,
            eventTypeID: eventType?.id,
            isEnabled: isEnabled,
            notifyOnDetection: notifyOnDetection
        )
    }
}
