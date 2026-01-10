//
//  OnboardingAnalytics.swift
//  trendy
//
//  Analytics event definitions for onboarding tracking via PostHog
//

import Foundation

/// Analytics event names for PostHog tracking during onboarding
enum OnboardingAnalyticsEvent: String {
    // Flow events
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case onboardingAbandoned = "onboarding_abandoned"

    // Auth events
    case onboardingAuthViewed = "onboarding_auth_viewed"
    case onboardingAuthSucceeded = "onboarding_auth_succeeded"
    case onboardingAuthFailed = "onboarding_auth_failed"
    case onboardingAuthMethodUsed = "onboarding_auth_method_used"

    // Event type events
    case onboardingEventTypeViewed = "onboarding_event_type_viewed"
    case onboardingEventTypeCreated = "onboarding_event_type_created"
    case onboardingEventTypeSkipped = "onboarding_event_type_skipped"

    // First event events
    case onboardingFirstEventViewed = "onboarding_first_event_viewed"
    case onboardingFirstEventLogged = "onboarding_first_event_logged"
    case onboardingFirstEventSkipped = "onboarding_first_event_skipped"

    // Permission events
    case onboardingPermissionPrompted = "onboarding_permission_prompted"
    case onboardingPermissionResult = "onboarding_permission_result"
    case onboardingPermissionsSkipped = "onboarding_permissions_skipped"
}

/// Permission types tracked during onboarding
enum OnboardingPermissionType: String, CaseIterable {
    case notifications
    case location
    case healthkit

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .notifications: return "Notifications"
        case .location: return "Location"
        case .healthkit: return "HealthKit"
        }
    }

    /// Icon for the permission type
    var iconName: String {
        switch self {
        case .notifications: return "bell.fill"
        case .location: return "location.fill"
        case .healthkit: return "heart.fill"
        }
    }

    /// Title for the pre-prompt screen
    var promptTitle: String {
        switch self {
        case .notifications: return "Stay on Track"
        case .location: return "Auto-Log Places"
        case .healthkit: return "Import Health Data"
        }
    }

    /// Description for the pre-prompt screen
    var promptDescription: String {
        switch self {
        case .notifications:
            return "Get reminders to log events and maintain your streaks."
        case .location:
            return "Automatically log events when you arrive or leave locations."
        case .healthkit:
            return "Import workouts, steps, and sleep data from Apple Health."
        }
    }

    /// Button text for enabling
    var enableButtonText: String {
        switch self {
        case .notifications: return "Enable Notifications"
        case .location: return "Enable Location"
        case .healthkit: return "Connect HealthKit"
        }
    }
}

/// Authentication method used during onboarding
enum OnboardingAuthMethod: String {
    case emailSignup = "email_signup"
    case emailSignin = "email_signin"
    case google = "google"
    case apple = "apple"
}
