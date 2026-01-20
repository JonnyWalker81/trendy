//
//  OnboardingViewModel.swift
//  trendy
//
//  State machine and coordinator for the onboarding flow
//

import Foundation
import SwiftUI
import PostHog

/// ViewModel managing onboarding state machine, persistence, and coordination
@Observable
@MainActor
class OnboardingViewModel {
    // MARK: - Dependencies

    private let supabaseService: SupabaseService
    private let profileService: ProfileService
    private let googleSignInService: GoogleSignInService
    private var eventStore: EventStore?
    private var appRouter: AppRouter?
    private var onboardingStatusService: OnboardingStatusService?

    // MARK: - Published State

    /// Current step in the onboarding flow
    private(set) var currentStep: OnboardingStep = .welcome

    /// Whether an async operation is in progress
    private(set) var isLoading = false

    /// Current error message to display
    var errorMessage: String?

    /// Whether onboarding is complete (triggers navigation to main app)
    private(set) var isComplete = false

    /// Created event type during onboarding (for use in log first event step)
    private(set) var createdEventType: EventType?

    /// Whether Google Sign-In is available
    var isGoogleSignInAvailable: Bool {
        googleSignInService.isAvailable
    }

    // MARK: - Private State

    /// Timestamp when onboarding started (for analytics duration)
    private var startTime: Date?

    /// Whether we're in sign-in mode vs sign-up mode on auth screen
    var isSignInMode = false

    // MARK: - Local Persistence Keys

    private static let localStepKey = "onboarding_current_step"
    private static let localStartTimeKey = "onboarding_start_time"
    private static let localCompleteKey = "onboarding_complete"

    // MARK: - Initialization

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
        self.profileService = ProfileService(supabaseService: supabaseService)
        self.googleSignInService = GoogleSignInService(supabaseService: supabaseService)

        // Restore start time from local storage
        if let startTimeInterval = UserDefaults.standard.object(forKey: Self.localStartTimeKey) as? TimeInterval {
            startTime = Date(timeIntervalSince1970: startTimeInterval)
        }
    }

    /// Set the EventStore for event type/event creation
    func setEventStore(_ store: EventStore) {
        self.eventStore = store
    }

    /// Set the AppRouter for navigation transitions
    func setAppRouter(_ router: AppRouter) {
        self.appRouter = router
    }

    /// Set the OnboardingStatusService for step tracking
    func setOnboardingStatusService(_ service: OnboardingStatusService) {
        self.onboardingStatusService = service
    }

    // MARK: - Initial State Determination

    /// Determine initial state based on auth and profile
    /// Call this on app launch to route appropriately
    func determineInitialState() async {
        Log.auth.debug("determineInitialState: Starting", context: .with { ctx in
            ctx.add("supabaseService.isAuthenticated", String(supabaseService.isAuthenticated))
            ctx.add("localCompleteKey", String(UserDefaults.standard.bool(forKey: Self.localCompleteKey)))
        })

        isLoading = true
        defer { isLoading = false }

        // Check local completion flag first (fast path)
        if UserDefaults.standard.bool(forKey: Self.localCompleteKey) && supabaseService.isAuthenticated {
            Log.auth.debug("determineInitialState: Already complete (fast path)")
            isComplete = true
            return
        }

        // Check if user is authenticated
        guard supabaseService.isAuthenticated else {
            Log.auth.debug("determineInitialState: NOT authenticated, falling back to local state")
            // Not authenticated - check for local progress
            if let savedStep = UserDefaults.standard.string(forKey: Self.localStepKey),
               let step = OnboardingStep(rawValue: savedStep) {
                currentStep = step
                // If we had progress past auth but session is gone, restart
                if step.requiresAuth {
                    currentStep = .welcome
                }
            } else {
                currentStep = .welcome
                trackOnboardingStarted()
            }
            trackViewedEventForStep(currentStep)
            return
        }

        Log.auth.debug("determineInitialState: IS authenticated, checking profile...")

        // Authenticated - check profile for onboarding status
        do {
            // Ensure profile exists
            Log.auth.debug("determineInitialState: Calling ensureProfileExists...")
            let profile = try await profileService.ensureProfileExists()
            Log.auth.debug("determineInitialState: Got profile", context: .with { ctx in
                ctx.add("onboardingComplete", String(profile.onboardingComplete))
                ctx.add("onboardingStep", profile.onboardingStep ?? "nil")
            })

            if profile.onboardingComplete {
                // Onboarding complete - signal to show main app
                Log.auth.debug("determineInitialState: Profile says onboarding complete!")
                UserDefaults.standard.set(true, forKey: Self.localCompleteKey)
                isComplete = true
                return
            }

            // Determine step from profile or local storage
            if let stepRaw = profile.onboardingStep,
               let step = OnboardingStep(rawValue: stepRaw) {
                Log.auth.debug("determineInitialState: Using step from profile: \(stepRaw)")
                currentStep = step
            } else if let localStep = UserDefaults.standard.string(forKey: Self.localStepKey),
                      let step = OnboardingStep(rawValue: localStep),
                      step.requiresAuth {
                // Use local step if it's past auth
                Log.auth.debug("determineInitialState: Using step from local storage: \(localStep)")
                currentStep = step
            } else {
                // Start from event type creation (after auth)
                Log.auth.debug("determineInitialState: No saved step, defaulting to createEventType")
                currentStep = .createEventType
            }

            // Check if user already has event types
            await checkExistingEventTypes()

            // Track viewed event for the determined step
            trackViewedEventForStep(currentStep)
            Log.auth.debug("determineInitialState: Done, currentStep=\(currentStep.rawValue)")

        } catch {
            Log.auth.error("determineInitialState: Failed to check profile", error: error)
            // Fallback to local state
            if let savedStep = UserDefaults.standard.string(forKey: Self.localStepKey),
               let step = OnboardingStep(rawValue: savedStep) {
                Log.auth.debug("determineInitialState: Fallback to local step: \(savedStep)")
                currentStep = step
            } else {
                Log.auth.debug("determineInitialState: Fallback to createEventType")
                currentStep = .createEventType
            }
            trackViewedEventForStep(currentStep)
        }
    }

    /// Check if user already has event types and skip creation if so
    private func checkExistingEventTypes() async {
        guard let eventStore = eventStore else { return }

        // Fetch data to see if event types exist
        await eventStore.fetchData(force: true)

        if !eventStore.eventTypes.isEmpty {
            // User has event types - use first one and skip creation
            createdEventType = eventStore.eventTypes.first

            // If on createEventType step, advance
            if currentStep == .createEventType {
                Log.auth.info("User has existing event types, skipping creation")
                currentStep = .logFirstEvent
                await persistStep(.logFirstEvent)
            }
        }
    }

    // MARK: - Navigation

    /// Advance to next step
    func advanceToNextStep() async {
        guard let nextStep = currentStep.next else {
            await completeOnboarding()
            return
        }

        currentStep = nextStep
        trackViewedEventForStep(nextStep)
        await persistStep(nextStep)
    }

    /// Go back to previous step (if allowed)
    func goBack() {
        guard let previousStep = currentStep.previous else { return }
        currentStep = previousStep
        trackViewedEventForStep(previousStep)
        // Don't persist backward navigation to allow fresh start
    }

    /// Skip current step (if skippable)
    func skipCurrentStep() async {
        guard currentStep.isSkippable else { return }

        // Track skip in analytics
        switch currentStep {
        case .permissions:
            trackEvent(.onboardingPermissionsSkipped)
        default:
            break
        }

        await advanceToNextStep()
    }

    /// Jump to a specific step (for "I have an account" flow)
    func jumpToStep(_ step: OnboardingStep) {
        currentStep = step
    }

    // MARK: - Step Persistence

    private func persistStep(_ step: OnboardingStep) async {
        // Always save locally (immediate)
        UserDefaults.standard.set(step.rawValue, forKey: Self.localStepKey)

        // Mark step completed in OnboardingStatusService (handles cache + backend sync)
        if let onboardingStatusService = onboardingStatusService {
            await onboardingStatusService.markStepCompleted(step)
        }

        // Save to backend via ProfileService if authenticated (async, fire-and-forget)
        if supabaseService.isAuthenticated {
            Task {
                do {
                    try await profileService.updateOnboardingStep(step)
                } catch {
                    Log.auth.error("Failed to persist step to backend", error: error)
                    // Continue anyway - local state is saved
                }
            }
        }
    }

    // MARK: - Authentication

    /// Sign up with email and password
    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Validate input
            guard isValidEmail(email) else {
                errorMessage = "Please enter a valid email address"
                isLoading = false
                return
            }
            guard password.count >= 6 else {
                errorMessage = "Password must be at least 6 characters"
                isLoading = false
                return
            }

            let session = try await supabaseService.signUp(email: email, password: password)

            // Identify user in PostHog
            PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                "email": email,
                "auth_method": OnboardingAuthMethod.emailSignup.rawValue
            ])

            trackEvent(.onboardingAuthSucceeded, properties: ["method": OnboardingAuthMethod.emailSignup.rawValue])

            // Start onboarding timer
            startTime = Date()
            UserDefaults.standard.set(startTime!.timeIntervalSince1970, forKey: Self.localStartTimeKey)

            // Ensure profile exists
            _ = try await profileService.ensureProfileExists()

            await advanceToNextStep()
        } catch {
            errorMessage = mapAuthError(error)
            trackEvent(.onboardingAuthFailed, properties: [
                "method": OnboardingAuthMethod.emailSignup.rawValue,
                "error": error.localizedDescription
            ])
        }

        isLoading = false
    }

    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        Log.auth.debug("OnboardingViewModel.signIn: Starting", context: .with { ctx in
            ctx.add("email", email)
        })

        isLoading = true
        errorMessage = nil

        do {
            // Validate input
            guard isValidEmail(email) else {
                Log.auth.debug("OnboardingViewModel.signIn: Invalid email format")
                errorMessage = "Please enter a valid email address"
                isLoading = false
                return
            }
            guard !password.isEmpty else {
                Log.auth.debug("OnboardingViewModel.signIn: Empty password")
                errorMessage = "Please enter your password"
                isLoading = false
                return
            }

            Log.auth.debug("OnboardingViewModel.signIn: Calling supabaseService.signIn...")
            let session = try await supabaseService.signIn(email: email, password: password)
            Log.auth.info("OnboardingViewModel.signIn: Success", context: .with { ctx in
                ctx.add("user_id", session.user.id.uuidString)
            })

            PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                "email": email,
                "auth_method": OnboardingAuthMethod.emailSignin.rawValue
            ])

            trackEvent(.onboardingAuthSucceeded, properties: ["method": OnboardingAuthMethod.emailSignin.rawValue])

            // Sync onboarding status from backend to check if user completed onboarding
            // This uses the onboarding_status table which is the source of truth
            Log.auth.debug("OnboardingViewModel.signIn: Syncing onboarding status from backend...")
            let status = await onboardingStatusService?.syncFromBackend(timeout: 3.0)

            Log.auth.debug("OnboardingViewModel.signIn: Backend status", context: .with { ctx in
                ctx.add("completed", String(status?.completed ?? false))
                ctx.add("currentStep", status?.currentStep ?? "nil")
            })

            // If backend says onboarding is complete, transition to main app
            if let status = status, status.completed {
                Log.auth.debug("OnboardingViewModel.signIn: Onboarding complete per backend, transitioning via AppRouter")
                isComplete = true
                appRouter?.transitionToAuthenticated()
                isLoading = false
                return
            }

            // Determine which step to continue from based on backend status
            if let status = status, let stepRaw = status.currentStep,
               let step = OnboardingStep(rawValue: stepRaw) {
                Log.auth.debug("OnboardingViewModel.signIn: Continuing from backend step", context: .with { ctx in
                    ctx.add("step", stepRaw)
                })
                currentStep = step
            } else {
                // Default: after auth, go to createEventType (first post-auth step)
                Log.auth.debug("OnboardingViewModel.signIn: No backend step, defaulting to createEventType")
                currentStep = .createEventType
            }

            // Check if user already has event types (skip createEventType if so)
            await checkExistingEventTypes()

            Log.auth.debug("OnboardingViewModel.signIn: Complete", context: .with { ctx in
                ctx.add("isComplete", String(isComplete))
                ctx.add("currentStep", currentStep.rawValue)
            })
        } catch {
            Log.auth.error("OnboardingViewModel.signIn: Failed", error: error)
            errorMessage = "Invalid email or password"
            trackEvent(.onboardingAuthFailed, properties: ["method": OnboardingAuthMethod.emailSignin.rawValue])
        }

        isLoading = false
        Log.auth.debug("OnboardingViewModel.signIn: Complete, isLoading=false")
    }

    /// Sign in with Google
    func signInWithGoogle(from viewController: UIViewController) async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await googleSignInService.signIn(presentingViewController: viewController)

            PostHogSDK.shared.identify(session.user.id.uuidString, userProperties: [
                "email": session.user.email ?? "",
                "auth_method": OnboardingAuthMethod.google.rawValue
            ])

            trackEvent(.onboardingAuthSucceeded, properties: ["method": OnboardingAuthMethod.google.rawValue])

            // Start onboarding timer for new users
            if startTime == nil {
                startTime = Date()
                UserDefaults.standard.set(startTime!.timeIntervalSince1970, forKey: Self.localStartTimeKey)
            }

            // Sync onboarding status from backend to check if user completed onboarding
            // This uses the onboarding_status table which is the source of truth
            Log.auth.debug("OnboardingViewModel.signInWithGoogle: Syncing onboarding status from backend...")
            let status = await onboardingStatusService?.syncFromBackend(timeout: 3.0)

            Log.auth.debug("OnboardingViewModel.signInWithGoogle: Backend status", context: .with { ctx in
                ctx.add("completed", String(status?.completed ?? false))
                ctx.add("currentStep", status?.currentStep ?? "nil")
            })

            // If backend says onboarding is complete, transition to main app
            if let status = status, status.completed {
                Log.auth.debug("OnboardingViewModel.signInWithGoogle: Onboarding complete per backend, transitioning via AppRouter")
                isComplete = true
                appRouter?.transitionToAuthenticated()
                isLoading = false
                return
            }

            // Determine which step to continue from based on backend status
            if let status = status, let stepRaw = status.currentStep,
               let step = OnboardingStep(rawValue: stepRaw) {
                Log.auth.debug("OnboardingViewModel.signInWithGoogle: Continuing from backend step", context: .with { ctx in
                    ctx.add("step", stepRaw)
                })
                currentStep = step
            } else {
                // Default: after auth, go to createEventType (first post-auth step)
                Log.auth.debug("OnboardingViewModel.signInWithGoogle: No backend step, defaulting to createEventType")
                currentStep = .createEventType
            }

            // Check if user already has event types (skip createEventType if so)
            await checkExistingEventTypes()

            Log.auth.debug("OnboardingViewModel.signInWithGoogle: Complete", context: .with { ctx in
                ctx.add("isComplete", String(isComplete))
                ctx.add("currentStep", currentStep.rawValue)
            })
        } catch let error as GoogleSignInError {
            if error.isUserCancellation {
                // User cancelled - don't show error
                Log.auth.debug("Google Sign-In cancelled by user")
            } else {
                errorMessage = error.localizedDescription
                trackEvent(.onboardingAuthFailed, properties: [
                    "method": OnboardingAuthMethod.google.rawValue,
                    "error": error.localizedDescription
                ])
            }
        } catch {
            errorMessage = error.localizedDescription
            trackEvent(.onboardingAuthFailed, properties: [
                "method": OnboardingAuthMethod.google.rawValue,
                "error": error.localizedDescription
            ])
        }

        isLoading = false
    }

    // MARK: - Event Type Creation

    /// Create event type from template
    func createEventType(from template: EventTypeTemplate) async {
        guard let eventStore = eventStore else {
            Log.auth.error("EventStore not set")
            return
        }

        isLoading = true

        await eventStore.createEventType(
            name: template.name,
            colorHex: template.colorHex,
            iconName: template.iconName
        )

        // Find the created event type
        createdEventType = eventStore.eventTypes.first { $0.name == template.name }

        trackEvent(.onboardingEventTypeCreated, properties: [
            "template_id": template.id,
            "template_name": template.name
        ])

        isLoading = false
        await advanceToNextStep()
    }

    /// Create custom event type
    func createCustomEventType(name: String, colorHex: String, iconName: String) async {
        guard let eventStore = eventStore else {
            Log.auth.error("EventStore not set")
            return
        }

        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a name for your event type"
            return
        }

        isLoading = true
        errorMessage = nil

        await eventStore.createEventType(
            name: name.trimmingCharacters(in: .whitespaces),
            colorHex: colorHex,
            iconName: iconName
        )

        createdEventType = eventStore.eventTypes.first { $0.name == name }

        trackEvent(.onboardingEventTypeCreated, properties: [
            "template_id": "custom",
            "custom_name": name
        ])

        isLoading = false
        await advanceToNextStep()
    }

    /// Skip event type creation (if user already has event types)
    func skipEventTypeCreation() async {
        trackEvent(.onboardingEventTypeSkipped)

        // Use first existing event type for log first event step
        createdEventType = eventStore?.eventTypes.first

        await advanceToNextStep()
    }

    // MARK: - First Event Logging

    /// Log the first event
    func logFirstEvent(notes: String? = nil) async {
        guard let eventStore = eventStore else {
            Log.auth.error("EventStore not set")
            await advanceToNextStep()
            return
        }

        guard let eventType = createdEventType ?? eventStore.eventTypes.first else {
            Log.auth.warning("No event type available for first event")
            await advanceToNextStep()
            return
        }

        isLoading = true

        await eventStore.recordEvent(
            type: eventType,
            timestamp: Date(),
            notes: notes?.trimmingCharacters(in: .whitespaces).isEmpty == false ? notes : nil
        )

        trackEvent(.onboardingFirstEventLogged, properties: [
            "event_type_name": eventType.name,
            "has_notes": notes?.isEmpty == false
        ])

        isLoading = false
        await advanceToNextStep()
    }

    /// Skip first event logging
    func skipFirstEvent() async {
        trackEvent(.onboardingFirstEventSkipped)
        await advanceToNextStep()
    }

    // MARK: - Permissions

    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        trackEvent(.onboardingPermissionPrompted, properties: ["type": OnboardingPermissionType.notifications.rawValue])

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

            // Update profile
            Task {
                try? await profileService.updatePermission(.notifications, enabled: granted)
            }

            trackEvent(.onboardingPermissionResult, properties: [
                "type": OnboardingPermissionType.notifications.rawValue,
                "granted": granted
            ])

            return granted
        } catch {
            Log.auth.error("Failed to request notification permission", error: error)
            trackEvent(.onboardingPermissionResult, properties: [
                "type": OnboardingPermissionType.notifications.rawValue,
                "granted": false,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    /// Request location permission (Always authorization for geofencing)
    func requestLocationPermission(geofenceManager: GeofenceManager) async -> Bool {
        trackEvent(.onboardingPermissionPrompted, properties: ["type": OnboardingPermissionType.location.rawValue])

        let needsSettings = geofenceManager.requestGeofencingAuthorization()

        // Wait a moment for the system dialog to be processed
        try? await Task.sleep(nanoseconds: 500_000_000)

        let granted = geofenceManager.hasGeofencingAuthorization

        // Update profile
        Task {
            try? await profileService.updatePermission(.location, enabled: granted)
        }

        trackEvent(.onboardingPermissionResult, properties: [
            "type": OnboardingPermissionType.location.rawValue,
            "granted": granted,
            "needs_settings": needsSettings
        ])

        return granted
    }

    /// Request HealthKit permission
    func requestHealthKitPermission(healthKitService: HealthKitService?) async -> Bool {
        guard let healthKitService = healthKitService else {
            trackEvent(.onboardingPermissionResult, properties: [
                "type": OnboardingPermissionType.healthkit.rawValue,
                "granted": false,
                "reason": "not_available"
            ])
            return false
        }

        trackEvent(.onboardingPermissionPrompted, properties: ["type": OnboardingPermissionType.healthkit.rawValue])

        do {
            try await healthKitService.requestAuthorization()
            let granted = healthKitService.isAuthorized

            // Update profile
            Task {
                try? await profileService.updatePermission(.healthkit, enabled: granted)
            }

            trackEvent(.onboardingPermissionResult, properties: [
                "type": OnboardingPermissionType.healthkit.rawValue,
                "granted": granted
            ])

            return granted
        } catch {
            Log.auth.error("Failed to request HealthKit permission", error: error)
            trackEvent(.onboardingPermissionResult, properties: [
                "type": OnboardingPermissionType.healthkit.rawValue,
                "granted": false,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    // MARK: - Completion

    private func completeOnboarding() async {
        // Update backend
        do {
            try await profileService.completeOnboarding()
        } catch {
            Log.auth.error("Failed to mark onboarding complete in backend", error: error)
            // Continue anyway - we'll set local flag
        }

        // Set local completion flag
        UserDefaults.standard.set(true, forKey: Self.localCompleteKey)

        // Clear step state
        UserDefaults.standard.removeObject(forKey: Self.localStepKey)

        // Track completion with duration
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        trackEvent(.onboardingCompleted, properties: [
            "duration_seconds": Int(duration)
        ])

        // Clear start time
        UserDefaults.standard.removeObject(forKey: Self.localStartTimeKey)

        isComplete = true

        // Transition to main app via AppRouter
        Task { @MainActor in
            await appRouter?.handleOnboardingComplete()
        }
    }

    // MARK: - Sign Out

    /// Handle sign out - signs out from Supabase and resets onboarding state
    func handleSignOut() async {
        // Sign out from Supabase
        do {
            try await supabaseService.signOut()
        } catch {
            Log.auth.error("Failed to sign out from Supabase", error: error)
        }

        // Clear local onboarding state
        UserDefaults.standard.removeObject(forKey: Self.localStepKey)
        UserDefaults.standard.removeObject(forKey: Self.localStartTimeKey)
        UserDefaults.standard.removeObject(forKey: Self.localCompleteKey)

        // Sign out from Google if used
        googleSignInService.signOut()

        // Reset state
        currentStep = .welcome
        createdEventType = nil
        startTime = nil
        errorMessage = nil
        isComplete = false
        isSignInMode = false

        PostHogSDK.shared.reset()
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func mapAuthError(_ error: Error) -> String {
        // Map common Supabase auth errors to user-friendly messages
        let errorString = error.localizedDescription.lowercased()
        if errorString.contains("email") && errorString.contains("registered") {
            return "This email is already registered. Try signing in instead."
        } else if errorString.contains("invalid") {
            return "Invalid email or password"
        } else if errorString.contains("network") {
            return "Network error. Please check your connection."
        } else if errorString.contains("rate") || errorString.contains("limit") {
            return "Too many attempts. Please wait a moment and try again."
        }
        return "An error occurred. Please try again."
    }

    // MARK: - Analytics

    private func trackOnboardingStarted() {
        startTime = Date()
        UserDefaults.standard.set(startTime!.timeIntervalSince1970, forKey: Self.localStartTimeKey)
        trackEvent(.onboardingStarted)
    }

    private func trackEvent(_ event: OnboardingAnalyticsEvent, properties: [String: Any] = [:]) {
        var props = properties
        props["current_step"] = currentStep.rawValue
        PostHogSDK.shared.capture(event.rawValue, properties: props)
    }

    /// Track "viewed" events for funnel analysis when entering a step
    private func trackViewedEventForStep(_ step: OnboardingStep) {
        switch step {
        case .auth:
            trackEvent(.onboardingAuthViewed)
        case .createEventType:
            trackEvent(.onboardingEventTypeViewed)
        case .logFirstEvent:
            trackEvent(.onboardingFirstEventViewed)
        default:
            break
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when onboarding is completed
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}
