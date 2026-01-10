//
//  OnboardingStep.swift
//  trendy
//
//  State machine for onboarding flow
//

import Foundation

/// State machine enum representing each step in the onboarding flow
enum OnboardingStep: String, Codable, CaseIterable {
    case welcome
    case auth
    case createEventType
    case logFirstEvent
    case permissions
    case finish

    /// Next step in the flow
    var next: OnboardingStep? {
        switch self {
        case .welcome: return .auth
        case .auth: return .createEventType
        case .createEventType: return .logFirstEvent
        case .logFirstEvent: return .permissions
        case .permissions: return .finish
        case .finish: return nil
        }
    }

    /// Previous step (for back navigation)
    var previous: OnboardingStep? {
        switch self {
        case .welcome: return nil
        case .auth: return .welcome
        case .createEventType: return nil  // Can't go back after auth
        case .logFirstEvent: return .createEventType
        case .permissions: return .logFirstEvent
        case .finish: return nil
        }
    }

    /// Whether this step can be skipped
    var isSkippable: Bool {
        switch self {
        case .permissions: return true
        default: return false
        }
    }

    /// Whether back navigation is allowed from this step
    var canGoBack: Bool {
        previous != nil
    }

    /// Step number for progress indicator (1-indexed, grouped by phase)
    var stepNumber: Int {
        switch self {
        case .welcome: return 1
        case .auth: return 1
        case .createEventType: return 2
        case .logFirstEvent: return 3
        case .permissions: return 4
        case .finish: return 4
        }
    }

    /// Total steps for progress indicator
    static var totalSteps: Int { 4 }

    /// User-friendly title for each step
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .auth: return "Create Account"
        case .createEventType: return "First Event Type"
        case .logFirstEvent: return "Log Event"
        case .permissions: return "Permissions"
        case .finish: return "Ready"
        }
    }

    /// Whether this step requires authentication
    var requiresAuth: Bool {
        switch self {
        case .welcome, .auth: return false
        default: return true
        }
    }
}
