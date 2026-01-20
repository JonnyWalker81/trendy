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

    /// Progress value for OnboardingProgressBar (0.0 to 1.0)
    /// Evenly distributes steps across the progress bar
    var progress: Double {
        let allSteps = OnboardingStep.allCases
        guard let index = allSteps.firstIndex(of: self) else { return 0 }
        // Returns: welcome=0.0, auth=0.2, createEventType=0.4, logFirstEvent=0.6, permissions=0.8, finish=1.0
        return Double(index) / Double(allSteps.count - 1)
    }
}
