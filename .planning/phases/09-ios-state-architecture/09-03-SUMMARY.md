---
phase: 09-ios-state-architecture
plan: 03
subsystem: ios
tags: [swift, swiftui, approuter, notificationcenter, observable]

# Dependency graph
requires:
  - phase: 09-ios-state-architecture
    plan: 01
    provides: OnboardingStatusService for step tracking
  - phase: 09-ios-state-architecture
    plan: 02
    provides: AppRouter Observable with handleOnboardingComplete, handleLogin, transitionToAuthenticated methods
provides:
  - Views wired to AppRouter instead of NotificationCenter
  - OnboardingViewModel using AppRouter.handleOnboardingComplete()
  - OnboardingContainerView using AppRouter.transitionToAuthenticated()
  - LoginView using AppRouter.handleLogin() via onChange observer
  - ContentView simplified to screenshot-mode only
affects: [09-04-ios-state-architecture, 10-visual-design]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - onChange observer pattern for tracking auth success and calling AppRouter
    - Dependency injection via setAppRouter() and setOnboardingStatusService() methods
    - isLoggingIn flag to distinguish user-initiated login from session restore

key-files:
  created: []
  modified:
    - apps/ios/trendy/ViewModels/OnboardingViewModel.swift
    - apps/ios/trendy/Views/Onboarding/OnboardingContainerView.swift
    - apps/ios/trendy/ContentView.swift
    - apps/ios/trendy/Views/Auth/LoginView.swift

key-decisions:
  - "Setter methods (setAppRouter/setOnboardingStatusService) for dependency injection in view models"
  - "onChange observer pattern in LoginView since AuthViewModel.signIn() doesn't return success"
  - "isLoggingIn flag prevents spurious handleLogin calls during session restore"
  - "ContentView retained for DEBUG screenshot mode only"
  - "Notification.Name extension kept for potential future non-routing notifications"

patterns-established:
  - "onChange of authViewModel.isAuthenticated with tracking flag to detect user-initiated login"
  - "appRouter?.method() call pattern for optional router during transition period"

# Metrics
duration: 5min
completed: 2026-01-20
---

# Phase 9 Plan 3: Wire Views to AppRouter Summary

**Removed NotificationCenter routing from onboarding views and wired them to use AppRouter Observable state**

## Performance

- **Duration:** 5 min
- **Started:** 2026-01-20T19:49:40Z
- **Completed:** 2026-01-20T19:54:34Z
- **Tasks:** 4
- **Files modified:** 4

## Accomplishments
- Replaced all NotificationCenter.post(.onboardingCompleted) calls with AppRouter method calls
- OnboardingViewModel now calls appRouter.handleOnboardingComplete() when onboarding finishes
- OnboardingContainerView now calls appRouter.transitionToAuthenticated() when already complete
- LoginView wired to AppRouter.handleLogin() via onChange observer on isAuthenticated
- ContentView simplified to screenshot-mode only (routing moved to RootView)

## Task Commits

Each task was committed atomically:

1. **Task 1: Update OnboardingViewModel to use AppRouter** - `28768bf` (feat)
2. **Task 2: Update OnboardingContainerView to use AppRouter** - `47af301` (feat)
3. **Task 3: Simplify ContentView (remove routing logic)** - `6849ddd` (refactor)
4. **Task 4: Wire LoginView to AppRouter on auth success** - `02fcaa4` (feat)

## Files Modified
- `apps/ios/trendy/ViewModels/OnboardingViewModel.swift` - Added AppRouter/OnboardingStatusService dependencies, replaced NotificationCenter.post with AppRouter calls
- `apps/ios/trendy/Views/Onboarding/OnboardingContainerView.swift` - Added AppRouter environment, replaced NotificationCenter.post, removed onChange observer
- `apps/ios/trendy/ContentView.swift` - Removed all routing logic, kept only screenshot mode
- `apps/ios/trendy/Views/Auth/LoginView.swift` - Added AppRouter environment, onChange observers for auth success

## Decisions Made

1. **Setter methods for dependency injection** - Used `setAppRouter()` and `setOnboardingStatusService()` pattern since OnboardingViewModel is created before environment is available in view hierarchy.

2. **onChange observer pattern for LoginView** - AuthViewModel.signIn() doesn't return success/failure, so we use onChange of isAuthenticated to detect successful login. The isLoggingIn flag distinguishes user-initiated login from session restore.

3. **Keep ContentView for screenshot mode** - ContentView is still referenced in the project for DEBUG screenshot mode. Rather than removing it entirely, simplified it to only handle that case.

4. **Keep Notification.Name extension** - The `.onboardingCompleted` notification name is defined but no longer posted. Kept the extension for potential future non-routing uses of notifications.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- None - all tasks completed successfully on first attempt

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All views now wired to AppRouter
- NotificationCenter routing completely removed
- Ready for 09-04 (TBD) to continue state architecture improvements
- OnboardingStatusService.markStepCompleted() now called during onboarding flow

---
*Phase: 09-ios-state-architecture*
*Completed: 2026-01-20*
