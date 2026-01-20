//
//  OnboardingCache.swift
//  trendy
//
//  Per-user local cache for onboarding status
//  Enables synchronous reads for instant route determination
//

import Foundation

/// Cached onboarding status for a specific user
struct CachedOnboardingStatus: Codable {
    let userId: String
    let completed: Bool
    let currentStep: String?  // For resuming incomplete onboarding
    let welcomeCompletedAt: Date?
    let authCompletedAt: Date?
    let createEventTypeCompletedAt: Date?  // Track createEventType step locally
    let logFirstEventCompletedAt: Date?    // Track logFirstEvent step locally
    let permissionsCompletedAt: Date?
    let lastSyncedAt: Date?   // When we last synced with backend
    let lastUpdatedAt: Date   // When this cache entry was last modified

    /// Create from API response
    init(from api: APIOnboardingStatus) {
        self.userId = api.userId
        self.completed = api.completed
        self.currentStep = Self.determineCurrentStep(from: api)
        self.welcomeCompletedAt = api.welcomeCompletedAt
        self.authCompletedAt = api.authCompletedAt
        self.createEventTypeCompletedAt = nil  // Not tracked by backend, set locally
        self.logFirstEventCompletedAt = nil    // Not tracked by backend, set locally
        self.permissionsCompletedAt = api.permissionsCompletedAt
        self.lastSyncedAt = Date()
        self.lastUpdatedAt = Date()
    }

    /// Create for local-only update (before backend sync)
    init(userId: String, completed: Bool, currentStep: String?,
         welcomeCompletedAt: Date? = nil, authCompletedAt: Date? = nil,
         createEventTypeCompletedAt: Date? = nil, logFirstEventCompletedAt: Date? = nil,
         permissionsCompletedAt: Date? = nil, lastSyncedAt: Date? = nil) {
        self.userId = userId
        self.completed = completed
        self.currentStep = currentStep
        self.welcomeCompletedAt = welcomeCompletedAt
        self.authCompletedAt = authCompletedAt
        self.createEventTypeCompletedAt = createEventTypeCompletedAt
        self.logFirstEventCompletedAt = logFirstEventCompletedAt
        self.permissionsCompletedAt = permissionsCompletedAt
        self.lastSyncedAt = lastSyncedAt
        self.lastUpdatedAt = Date()
    }

    /// Determine current step from API response timestamps
    private static func determineCurrentStep(from api: APIOnboardingStatus) -> String? {
        if api.completed { return nil }
        if api.permissionsCompletedAt != nil { return "finish" }
        // Note: createEventType and logFirstEvent are not in backend, so we infer
        // If auth is done but permissions isn't, we're somewhere between auth and permissions
        if api.authCompletedAt != nil { return "createEventType" }  // Start at first post-auth step
        if api.welcomeCompletedAt != nil { return "auth" }
        return "welcome"
    }
}

/// Per-user keyed UserDefaults cache for onboarding status
/// Enables synchronous reads for instant route determination without loading screens
enum OnboardingCache {

    private static let keyPrefix = "onboarding_status_"
    private static let anyCompletedKey = "onboarding_any_user_completed"

    // MARK: - Per-User Operations

    /// Generate cache key for a specific user
    private static func key(for userId: String) -> String {
        "\(keyPrefix)\(userId)"
    }

    /// Read cached status for a user (SYNCHRONOUS - no async)
    /// Returns nil if no cache exists for this user
    static func read(userId: String) -> CachedOnboardingStatus? {
        guard let data = UserDefaults.standard.data(forKey: key(for: userId)) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedOnboardingStatus.self, from: data)
    }

    /// Write status to cache for a user
    static func write(_ status: CachedOnboardingStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            Log.auth.error("Failed to encode onboarding status for cache")
            return
        }
        UserDefaults.standard.set(data, forKey: key(for: status.userId))

        // Track if any user has completed onboarding (for returning user detection)
        if status.completed {
            UserDefaults.standard.set(true, forKey: anyCompletedKey)
        }

        Log.auth.debug("Cached onboarding status", context: .with { ctx in
            ctx.add("user_id", status.userId)
            ctx.add("completed", String(status.completed))
            ctx.add("current_step", status.currentStep ?? "nil")
        })
    }

    /// Clear cache for a specific user
    static func clear(userId: String) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
        Log.auth.debug("Cleared onboarding cache", context: .with { ctx in
            ctx.add("user_id", userId)
        })
    }

    // MARK: - Global Operations

    /// Check if ANY user has ever completed onboarding on this device
    /// Used to distinguish fresh installs from returning users who logged out
    static func hasAnyUserCompletedOnboarding() -> Bool {
        // Fast path: check the flag
        if UserDefaults.standard.bool(forKey: anyCompletedKey) {
            return true
        }

        // Fallback: scan all cache keys (handles migration from old flag)
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            if let data = UserDefaults.standard.data(forKey: key),
               let status = try? JSONDecoder().decode(CachedOnboardingStatus.self, from: data),
               status.completed {
                // Update flag for future fast path
                UserDefaults.standard.set(true, forKey: anyCompletedKey)
                return true
            }
        }
        return false
    }

    /// Clear all onboarding caches (for debugging/testing)
    static func clearAll() {
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(keyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: anyCompletedKey)
        Log.auth.info("Cleared all onboarding caches")
    }
}
