//
//  ProfileService.swift
//  trendy
//
//  Service for managing user profiles in Supabase
//

import Foundation
import Supabase

/// Service for managing user profiles in Supabase
/// Handles onboarding state persistence and user preferences
@Observable
@MainActor
class ProfileService {
    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    // MARK: - Profile Model

    /// Profile data model matching the Supabase profiles table
    struct Profile: Codable, Sendable {
        let id: String
        var onboardingComplete: Bool
        var onboardingStep: String?
        var notificationsEnabled: Bool?
        var locationEnabled: Bool?
        var healthkitEnabled: Bool?
        var onboardingStartedAt: Date?
        var onboardingCompletedAt: Date?
        var createdAt: Date?
        var updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case onboardingComplete = "onboarding_complete"
            case onboardingStep = "onboarding_step"
            case notificationsEnabled = "notifications_enabled"
            case locationEnabled = "location_enabled"
            case healthkitEnabled = "healthkit_enabled"
            case onboardingStartedAt = "onboarding_started_at"
            case onboardingCompletedAt = "onboarding_completed_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        /// Create a new profile for a user ID
        static func create(for userId: String) -> Profile {
            Profile(
                id: userId,
                onboardingComplete: false,
                onboardingStep: OnboardingStep.welcome.rawValue,
                notificationsEnabled: nil,
                locationEnabled: nil,
                healthkitEnabled: nil,
                onboardingStartedAt: Date(),
                onboardingCompletedAt: nil,
                createdAt: nil,
                updatedAt: nil
            )
        }
    }

    // MARK: - Fetch Operations

    /// Fetch profile for current user
    /// Returns nil if no profile exists
    func fetchProfile() async throws -> Profile? {
        let userId = try await supabaseService.getUserId()

        Log.auth.debug("Fetching profile", context: .with { ctx in
            ctx.add("user_id", userId)
        })

        let response: [Profile] = try await supabaseService.client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .execute()
            .value

        let profile = response.first

        Log.auth.debug("Profile fetch result", context: .with { ctx in
            ctx.add("user_id", userId)
            ctx.add("found", profile != nil)
            if let profile = profile {
                ctx.add("onboarding_complete", profile.onboardingComplete)
                ctx.add("onboarding_step", profile.onboardingStep ?? "nil")
            }
        })

        return profile
    }

    /// Check if onboarding is complete for current user
    func isOnboardingComplete() async throws -> Bool {
        let profile = try await fetchProfile()
        return profile?.onboardingComplete ?? false
    }

    // MARK: - Create/Update Operations

    /// Create or update profile
    func upsertProfile(_ profile: Profile) async throws {
        Log.auth.info("Upserting profile", context: .with { ctx in
            ctx.add("user_id", profile.id)
            ctx.add("onboarding_complete", profile.onboardingComplete)
        })

        try await supabaseService.client
            .from("profiles")
            .upsert(profile)
            .execute()
    }

    /// Ensure profile exists for current user, creating if necessary
    func ensureProfileExists() async throws -> Profile {
        let userId = try await supabaseService.getUserId()

        // Try to fetch existing profile
        if let existingProfile = try await fetchProfile() {
            return existingProfile
        }

        // Create new profile
        let newProfile = Profile.create(for: userId)
        try await upsertProfile(newProfile)

        Log.auth.info("Created new profile for user", context: .with { ctx in
            ctx.add("user_id", userId)
        })

        return newProfile
    }

    // MARK: - Onboarding Step Management

    /// Update the current onboarding step
    func updateOnboardingStep(_ step: OnboardingStep) async throws {
        let userId = try await supabaseService.getUserId()

        Log.auth.debug("Updating onboarding step", context: .with { ctx in
            ctx.add("user_id", userId)
            ctx.add("step", step.rawValue)
        })

        try await supabaseService.client
            .from("profiles")
            .update(["onboarding_step": step.rawValue])
            .eq("id", value: userId)
            .execute()
    }

    /// Mark onboarding as started
    func startOnboarding() async throws {
        let userId = try await supabaseService.getUserId()

        Log.auth.info("Starting onboarding", context: .with { ctx in
            ctx.add("user_id", userId)
        })

        let now = ISO8601DateFormatter().string(from: Date())

        try await supabaseService.client
            .from("profiles")
            .update([
                "onboarding_step": OnboardingStep.welcome.rawValue,
                "onboarding_started_at": now
            ])
            .eq("id", value: userId)
            .execute()
    }

    /// Mark onboarding as complete
    func completeOnboarding() async throws {
        let userId = try await supabaseService.getUserId()

        Log.auth.info("Completing onboarding", context: .with { ctx in
            ctx.add("user_id", userId)
        })

        let payload = OnboardingCompletePayload(
            onboardingComplete: true,
            onboardingStep: OnboardingStep.finish.rawValue,
            onboardingCompletedAt: Date()
        )

        try await supabaseService.client
            .from("profiles")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Update Payloads

    /// Payload for completing onboarding
    private struct OnboardingCompletePayload: Encodable {
        let onboardingComplete: Bool
        let onboardingStep: String
        let onboardingCompletedAt: Date

        enum CodingKeys: String, CodingKey {
            case onboardingComplete = "onboarding_complete"
            case onboardingStep = "onboarding_step"
            case onboardingCompletedAt = "onboarding_completed_at"
        }
    }

    // MARK: - Permission Preferences

    /// Update permission preference flags
    func updatePermissions(
        notifications: Bool? = nil,
        location: Bool? = nil,
        healthkit: Bool? = nil
    ) async throws {
        let userId = try await supabaseService.getUserId()

        var updates: [String: Bool] = [:]
        if let notifications = notifications {
            updates["notifications_enabled"] = notifications
        }
        if let location = location {
            updates["location_enabled"] = location
        }
        if let healthkit = healthkit {
            updates["healthkit_enabled"] = healthkit
        }

        guard !updates.isEmpty else { return }

        Log.auth.debug("Updating permission preferences", context: .with { ctx in
            ctx.add("user_id", userId)
            ctx.add("updates", updates.description)
        })

        try await supabaseService.client
            .from("profiles")
            .update(updates)
            .eq("id", value: userId)
            .execute()
    }

    /// Update a single permission preference
    func updatePermission(_ type: OnboardingPermissionType, enabled: Bool) async throws {
        switch type {
        case .notifications:
            try await updatePermissions(notifications: enabled)
        case .location:
            try await updatePermissions(location: enabled)
        case .healthkit:
            try await updatePermissions(healthkit: enabled)
        }
    }
}

// MARK: - Errors

enum ProfileServiceError: LocalizedError {
    case notAuthenticated
    case profileNotFound
    case updateFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .profileNotFound:
            return "Profile not found"
        case .updateFailed(let error):
            return "Failed to update profile: \(error.localizedDescription)"
        }
    }
}
