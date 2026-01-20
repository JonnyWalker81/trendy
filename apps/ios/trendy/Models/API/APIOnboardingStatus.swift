//
//  APIOnboardingStatus.swift
//  trendy
//
//  API models for onboarding status (matches backend OnboardingStatus schema)
//

import Foundation

/// API response model for onboarding status (matches backend OnboardingStatus)
struct APIOnboardingStatus: Codable {
    let userId: String
    let completed: Bool
    let welcomeCompletedAt: Date?
    let authCompletedAt: Date?
    let permissionsCompletedAt: Date?
    let notificationsStatus: String?
    let notificationsCompletedAt: Date?
    let healthkitStatus: String?
    let healthkitCompletedAt: Date?
    let locationStatus: String?
    let locationCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case completed
        case welcomeCompletedAt = "welcome_completed_at"
        case authCompletedAt = "auth_completed_at"
        case permissionsCompletedAt = "permissions_completed_at"
        case notificationsStatus = "notifications_status"
        case notificationsCompletedAt = "notifications_completed_at"
        case healthkitStatus = "healthkit_status"
        case healthkitCompletedAt = "healthkit_completed_at"
        case locationStatus = "location_status"
        case locationCompletedAt = "location_completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Request model for updating onboarding status
struct UpdateOnboardingStatusRequest: Codable {
    var completed: Bool?
    var welcomeCompletedAt: Date?
    var authCompletedAt: Date?
    var permissionsCompletedAt: Date?
    var notificationsStatus: String?
    var notificationsCompletedAt: Date?
    var healthkitStatus: String?
    var healthkitCompletedAt: Date?
    var locationStatus: String?
    var locationCompletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completed
        case welcomeCompletedAt = "welcome_completed_at"
        case authCompletedAt = "auth_completed_at"
        case permissionsCompletedAt = "permissions_completed_at"
        case notificationsStatus = "notifications_status"
        case notificationsCompletedAt = "notifications_completed_at"
        case healthkitStatus = "healthkit_status"
        case healthkitCompletedAt = "healthkit_completed_at"
        case locationStatus = "location_status"
        case locationCompletedAt = "location_completed_at"
    }
}

/// Valid permission status values (matches backend CHECK constraint)
enum PermissionStatus: String, Codable {
    case granted
    case denied
    case skipped
    case notRequested = "not_requested"
}
