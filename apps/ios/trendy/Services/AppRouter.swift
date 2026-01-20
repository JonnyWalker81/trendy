//
//  AppRouter.swift
//  trendy
//
//  Observable routing state machine for app-level navigation
//  Determines initial route synchronously to prevent loading flash
//
//  DESIGN: Cache-first strategy per CONTEXT.md
//  - Returning users with cache: instant route (no loading)
//  - Session restore happens async in background
//  - This avoids race condition with SupabaseService.restoreSession()
//

import Foundation
import SwiftUI

/// App-level route states
enum AppRoute: Equatable {
    case loading              // Brief loading while checking backend (cache miss only)
    case onboarding(step: OnboardingStep)  // New user onboarding flow
    case login                // Returning user, not authenticated
    case authenticated        // Main app
}

/// Observable router that manages app-level navigation state
/// Key feature: determineInitialRoute() is SYNCHRONOUS for instant routing
@Observable
@MainActor
class AppRouter {

    // MARK: - Published State

    /// Current route state
    private(set) var currentRoute: AppRoute = .loading

    // MARK: - Dependencies

    private let supabaseService: SupabaseService
    private let onboardingService: OnboardingStatusService

    // MARK: - Initialization

    init(supabaseService: SupabaseService, onboardingService: OnboardingStatusService) {
        self.supabaseService = supabaseService
        self.onboardingService = onboardingService
    }

    // MARK: - Route Determination

    /// Determine initial route SYNCHRONOUSLY from cached state
    /// Call this ONCE at app launch, before body is rendered
    ///
    /// IMPORTANT: Uses CACHE-FIRST strategy to avoid race condition.
    /// SupabaseService.restoreSession() is async (runs in Task in init),
    /// so currentSession may not be populated at this point.
    ///
    /// Strategy:
    /// 1. Check if ANY user has completed onboarding on this device
    /// 2. If yes AND cache exists for a user -> use cache to route
    /// 3. If cache exists with userId -> trust cache, session restore will happen in background
    /// 4. If no cache -> fresh install or logged-out user
    ///
    /// Key design: NO async in hot path - cache hit = instant route
    func determineInitialRoute() {
        // CACHE-FIRST: Don't rely on supabaseService.currentSession being populated
        // It may not be ready yet since restoreSession() is async

        // Check if we have ANY cached onboarding status (indicates returning user)
        let hasAnyCompletedUser = OnboardingCache.hasAnyUserCompletedOnboarding()

        Log.auth.debug("determineInitialRoute (cache-first)", context: .with { ctx in
            ctx.add("has_any_completed", String(hasAnyCompletedUser))
        })

        // Try to find a cached user with completed onboarding
        // This handles the common case: user completed onboarding, closed app, reopened
        if let cachedStatus = findMostRecentCachedStatus() {
            if cachedStatus.completed {
                // Returning user with completed onboarding
                // Session will restore in background, we'll handle auth failure later
                Log.auth.info("Route: authenticated (cache-first, completed)")
                currentRoute = .authenticated

                // Kick off background session verification
                Task { await verifySessionInBackground() }
                return
            } else if let stepRaw = cachedStatus.currentStep,
                      let step = OnboardingStep(rawValue: stepRaw) {
                // Incomplete onboarding - resume from cached step
                Log.auth.info("Route: onboarding (cache-first, resume)", context: .with { ctx in
                    ctx.add("step", stepRaw)
                })
                currentRoute = .onboarding(step: step)
                return
            }
        }

        // No usable cache - check if returning user (logged out) or fresh install
        if hasAnyCompletedUser {
            // Someone completed onboarding on this device before, but no cache for current user
            // This is a logged-out returning user -> show login
            Log.auth.info("Route: login (returning user, no current cache)")
            currentRoute = .login
        } else {
            // Fresh install - no one has ever completed onboarding on this device
            Log.auth.info("Route: onboarding (fresh install)")
            currentRoute = .onboarding(step: .welcome)
        }
    }

    /// Find most recent cached onboarding status
    /// Returns nil if no cache exists
    private func findMostRecentCachedStatus() -> CachedOnboardingStatus? {
        // First, try to get userId from cached session (sync)
        if let userId = try? supabaseService.getUserId() {
            return OnboardingCache.read(userId: userId)
        }

        // If no session, we can't determine user-specific cache
        // But we can check the "any completed" flag for routing decision
        return nil
    }

    /// Verify session is valid in background after cache-based routing
    /// If session is invalid, transition to login
    private func verifySessionInBackground() async {
        // Give SupabaseService time to restore session
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Now check if session was restored
        if supabaseService.currentSession == nil {
            Log.auth.warning("Session not restored, transitioning to login")
            transitionToLogin()
        } else {
            // Session valid - sync from backend in background
            _ = await onboardingService.syncFromBackend(timeout: 3.0)
            Log.auth.debug("Background session verification complete")
        }
    }

    // MARK: - Route Transitions

    /// Transition to main app (after onboarding completes)
    func transitionToAuthenticated() {
        Log.auth.info("Route transition: authenticated")
        currentRoute = .authenticated
    }

    /// Transition to login (after logout)
    func transitionToLogin() {
        Log.auth.info("Route transition: login")
        currentRoute = .login
    }

    /// Transition to onboarding (for new user or reset)
    func transitionToOnboarding(step: OnboardingStep = .welcome) {
        Log.auth.info("Route transition: onboarding", context: .with { ctx in
            ctx.add("step", step.rawValue)
        })
        currentRoute = .onboarding(step: step)
    }

    /// Update onboarding step (during flow)
    func updateOnboardingStep(_ step: OnboardingStep) {
        guard case .onboarding = currentRoute else { return }
        currentRoute = .onboarding(step: step)
    }

    // MARK: - Auth Event Handlers

    /// Handle successful login - sync and route
    /// Called from LoginView after AuthViewModel.signIn() succeeds
    func handleLogin() async {
        guard let userId = supabaseService.currentSession?.user.id.uuidString else {
            Log.auth.warning("handleLogin called but no session")
            return
        }

        Log.auth.info("handleLogin: syncing status for user", context: .with { ctx in
            ctx.add("user_id", userId)
        })

        // Sync from backend to get latest status
        let status = await onboardingService.syncFromBackend(timeout: 3.0)

        if let status = status, status.completed {
            // Returning user with completed onboarding
            transitionToAuthenticated()
        } else {
            // New user or incomplete onboarding - continue flow
            // Determine which step based on cached/synced state
            if let status = status, let stepRaw = status.currentStep,
               let step = OnboardingStep(rawValue: stepRaw) {
                transitionToOnboarding(step: step)
            } else {
                // Default: after auth, go to createEventType (first post-auth step)
                transitionToOnboarding(step: .createEventType)
            }
        }
    }

    /// Handle logout - preserve cache, transition to login
    func handleLogout() {
        onboardingService.handleLogout()
        transitionToLogin()
    }

    /// Handle onboarding completion
    func handleOnboardingComplete() async {
        await onboardingService.completeOnboarding()
        transitionToAuthenticated()
    }
}
