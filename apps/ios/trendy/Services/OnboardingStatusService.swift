//
//  OnboardingStatusService.swift
//  trendy
//
//  Service layer combining backend API with local cache
//  Handles sync, offline queuing, and cache updates
//

import Foundation

/// Service for managing onboarding status with backend sync and local cache
@Observable
@MainActor
class OnboardingStatusService {

    private let apiClient: APIClient
    private let supabaseService: SupabaseService

    /// Most recent status from cache or backend
    private(set) var currentStatus: CachedOnboardingStatus?

    /// Whether a sync operation is in progress
    private(set) var isSyncing = false

    /// Last sync error (if any)
    private(set) var lastSyncError: Error?

    init(apiClient: APIClient, supabaseService: SupabaseService) {
        self.apiClient = apiClient
        self.supabaseService = supabaseService
    }

    // MARK: - Private Helpers

    /// Get user ID from cached session (synchronous)
    /// Returns nil if no cached session
    private func cachedUserId() -> String? {
        // Explicitly call the synchronous overload that uses cached session
        let getId: () throws -> String = supabaseService.getUserId
        return try? getId()
    }

    // MARK: - Synchronous Cache Access

    /// Read cached status for current user (SYNCHRONOUS)
    /// Returns nil if not authenticated or no cache
    func readCachedStatus() -> CachedOnboardingStatus? {
        guard let userId = cachedUserId() else {
            return nil
        }
        return OnboardingCache.read(userId: userId)
    }

    /// Check if current user has completed onboarding (from cache)
    func isOnboardingComplete() -> Bool {
        readCachedStatus()?.completed ?? false
    }

    /// Check if any user has ever completed onboarding on this device
    func hasAnyUserCompletedOnboarding() -> Bool {
        OnboardingCache.hasAnyUserCompletedOnboarding()
    }

    // MARK: - Backend Sync

    /// Sync onboarding status from backend and update cache
    /// Call this on login to ensure cache is current
    @discardableResult
    func syncFromBackend() async -> CachedOnboardingStatus? {
        guard let userId = cachedUserId() else {
            Log.auth.warning("Cannot sync onboarding status: not authenticated")
            return nil
        }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            let apiStatus = try await apiClient.getOnboardingStatus()
            let cached = CachedOnboardingStatus(from: apiStatus)
            OnboardingCache.write(cached)
            currentStatus = cached

            Log.auth.info("Synced onboarding status from backend", context: .with { ctx in
                ctx.add("user_id", userId)
                ctx.add("completed", String(apiStatus.completed))
            })

            return cached
        } catch {
            lastSyncError = error
            Log.auth.error("Failed to sync onboarding status", error: error)

            // Return cached status as fallback
            return OnboardingCache.read(userId: userId)
        }
    }

    /// Sync with timeout - returns cached status if backend takes too long
    /// - Parameter timeout: Maximum time to wait for backend (default 3 seconds)
    func syncFromBackend(timeout: TimeInterval = 3.0) async -> CachedOnboardingStatus? {
        guard let userId = cachedUserId() else {
            return nil
        }

        // Start with cached status
        let cached = OnboardingCache.read(userId: userId)

        // Try to sync from backend with timeout
        do {
            let result = try await withThrowingTaskGroup(of: CachedOnboardingStatus?.self) { group in
                group.addTask {
                    return await self.syncFromBackend()
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CancellationError()
                }

                // Return first successful result
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                return cached
            }
            return result
        } catch {
            Log.auth.warning("Backend sync timed out, using cached status")
            return cached
        }
    }

    // MARK: - Status Updates

    /// Mark a step as completed and sync to backend
    /// Updates cache immediately, then pushes to backend (fire-and-forget)
    func markStepCompleted(_ step: OnboardingStep) async {
        guard let userId = cachedUserId() else {
            Log.auth.warning("Cannot mark step complete: not authenticated")
            return
        }

        // Build update request based on step
        var request = UpdateOnboardingStatusRequest()
        let now = Date()

        // Handle ALL OnboardingStep cases explicitly - no default
        switch step {
        case .welcome:
            request.welcomeCompletedAt = now
        case .auth:
            request.authCompletedAt = now
        case .createEventType:
            // Backend doesn't track this step, but cache does
            // No request update needed, just cache update below
            break
        case .logFirstEvent:
            // Backend doesn't track this step, but cache does
            // No request update needed, just cache update below
            break
        case .permissions:
            request.permissionsCompletedAt = now
        case .finish:
            request.permissionsCompletedAt = now
            request.completed = true
        }

        // Update cache immediately (before backend call)
        let currentCached = OnboardingCache.read(userId: userId)
        let updatedCached = CachedOnboardingStatus(
            userId: userId,
            completed: step == .finish,
            currentStep: step.next?.rawValue,
            welcomeCompletedAt: step == .welcome ? now : currentCached?.welcomeCompletedAt,
            authCompletedAt: step == .auth ? now : currentCached?.authCompletedAt,
            createEventTypeCompletedAt: step == .createEventType ? now : currentCached?.createEventTypeCompletedAt,
            logFirstEventCompletedAt: step == .logFirstEvent ? now : currentCached?.logFirstEventCompletedAt,
            permissionsCompletedAt: (step == .permissions || step == .finish) ? now : currentCached?.permissionsCompletedAt,
            lastSyncedAt: currentCached?.lastSyncedAt
        )
        OnboardingCache.write(updatedCached)
        currentStatus = updatedCached

        // Push to backend (fire-and-forget, will retry on next sync)
        // Only push if there's something to push (steps tracked by backend)
        let shouldPushToBackend = step == .welcome || step == .auth || step == .permissions || step == .finish
        if shouldPushToBackend {
            Task.detached { [apiClient] in
                do {
                    _ = try await apiClient.updateOnboardingStatus(request)
                    Log.auth.debug("Pushed step completion to backend", context: .with { ctx in
                        ctx.add("step", step.rawValue)
                    })
                } catch {
                    Log.auth.warning("Failed to push step to backend (will retry)", error: error)
                    // TODO: Queue for retry via SyncEngine if needed
                }
            }
        } else {
            Log.auth.debug("Step tracked locally only (not in backend)", context: .with { ctx in
                ctx.add("step", step.rawValue)
            })
        }
    }

    /// Mark onboarding as complete
    func completeOnboarding() async {
        guard let userId = cachedUserId() else {
            Log.auth.warning("Cannot complete onboarding: not authenticated")
            return
        }

        // Update cache immediately
        let currentCached = OnboardingCache.read(userId: userId)
        let completedCached = CachedOnboardingStatus(
            userId: userId,
            completed: true,
            currentStep: nil,
            welcomeCompletedAt: currentCached?.welcomeCompletedAt,
            authCompletedAt: currentCached?.authCompletedAt,
            createEventTypeCompletedAt: currentCached?.createEventTypeCompletedAt,
            logFirstEventCompletedAt: currentCached?.logFirstEventCompletedAt,
            permissionsCompletedAt: Date(),
            lastSyncedAt: currentCached?.lastSyncedAt
        )
        OnboardingCache.write(completedCached)
        currentStatus = completedCached

        // Push to backend
        Task.detached { [apiClient] in
            do {
                let request = UpdateOnboardingStatusRequest(
                    completed: true,
                    permissionsCompletedAt: Date()
                )
                _ = try await apiClient.updateOnboardingStatus(request)
                Log.auth.info("Onboarding completion synced to backend")
            } catch {
                Log.auth.warning("Failed to sync completion to backend", error: error)
            }
        }
    }

    /// Reset onboarding (for testing/debug)
    func resetOnboarding() async {
        guard let userId = cachedUserId() else { return }

        // Clear local cache
        OnboardingCache.clear(userId: userId)
        currentStatus = nil

        // Reset on backend
        do {
            let resetStatus = try await apiClient.resetOnboardingStatus()
            let cached = CachedOnboardingStatus(from: resetStatus)
            OnboardingCache.write(cached)
            currentStatus = cached
            Log.auth.info("Onboarding reset complete")
        } catch {
            Log.auth.error("Failed to reset onboarding on backend", error: error)
        }
    }

    // MARK: - Logout Handling

    /// Handle user logout - preserves cache per CONTEXT.md
    /// "On logout: Keep onboarding cache - if user completed onboarding, don't show again on re-login"
    func handleLogout() {
        // Don't clear cache - user might re-login
        currentStatus = nil
        Log.auth.debug("Logout handled, cache preserved")
    }
}
