---
status: verifying
trigger: "After completing onboarding, killing the app, and relaunching, user is stuck on login screen. Entering credentials and tapping Sign In spins briefly then does nothing."
created: 2026-01-20T00:00:00Z
updated: 2026-01-20T16:40:00Z
---

## Current Focus

hypothesis: CONFIRMED - AuthViewModel.isAuthenticated is already true when signIn() succeeds, so setting it to true again doesn't trigger onChange
test: Traced the exact flow from app launch to login attempt
expecting: onChange handler never fires because value doesn't change from true to true
next_action: Implement fix - LoginView needs to handle case where user is already authenticated

## Symptoms

expected: User should stay logged in after app restart (or at minimum, login should work and navigate to main app)
actual: Login screen appears after restart, entering credentials shows spinner briefly then nothing happens, no navigation occurs
errors: No errors visible in Xcode console when tapping Sign In
reproduction: Complete onboarding -> Kill app -> Relaunch -> Try to login
started: Recently broke (used to work before)

## Eliminated

## Evidence

- timestamp: 2026-01-20T00:00:01Z
  checked: App launch flow in trendyApp.swift and AppRouter.swift
  found: Cache-first strategy determines route synchronously at launch
  implication: hasAnyUserCompletedOnboarding() returns true after onboarding completion, so app shows login screen (correct behavior for returning user)

- timestamp: 2026-01-20T00:00:02Z
  checked: LoginView.swift login flow
  found: Button sets isLoggingIn = true, then calls authViewModel.signIn(). onChange handler checks (isLoggingIn && isAuthenticated && !wasAuthenticated)
  implication: If auth succeeds, onChange should call appRouter.handleLogin()

- timestamp: 2026-01-20T00:00:03Z
  checked: AuthViewModel.signIn() flow
  found: Sets isLoading = true at start, then on success sets isAuthenticated = true, then sets isLoading = false at end
  implication: State changes happen in correct order

- timestamp: 2026-01-20T00:00:04Z
  checked: LoginView onChange handler for errorMessage
  found: If errorMessage != nil, sets isLoggingIn = false
  implication: If there's a transient error message, it would reset isLoggingIn

- timestamp: 2026-01-20T00:00:05Z
  checked: AppRouter.handleLogin() implementation
  found: Uses cachedUserId() which calls supabaseService.getUserId() synchronously from currentSession
  implication: If currentSession is nil when handleLogin() is called, cachedUserId() returns nil and handleLogin() exits early with warning

- timestamp: 2026-01-20T00:00:06Z
  checked: AuthViewModel.init() and checkAuthState()
  found: AuthViewModel.init() starts checkAuthState() async in a Task. If session is restored, sets isAuthenticated = true.
  implication: By the time user taps "Sign In", authViewModel.isAuthenticated may already be true

- timestamp: 2026-01-20T00:00:07Z
  checked: AuthViewModel.signIn() success path
  found: On success, sets self.isAuthenticated = true. If already true, value doesn't change.
  implication: onChange(of: authViewModel.isAuthenticated) ONLY fires when value actually changes

- timestamp: 2026-01-20T00:00:08Z
  checked: Session restore timing
  found: SupabaseService.restoreSession() is async, AuthViewModel.checkAuthState() is async, both run in Tasks at init
  implication: Race condition - session restore completes during the time user is typing credentials

## Resolution

root_cause: When app relaunches, AuthViewModel.checkAuthState() runs async and sets isAuthenticated=true if session is restored. By the time user taps "Sign In", isAuthenticated is already true. When signIn() succeeds and sets isAuthenticated=true again, the value doesn't change, so onChange(of: isAuthenticated) never fires, so handleLogin() is never called.

fix: Changed LoginView to use onChange(of: authViewModel.isLoading) instead of onChange(of: authViewModel.isAuthenticated). Now we detect when signIn() completes (isLoading transitions from true to false) and check if authenticated + no error. Also fixed SignupView to call appRouter.handleLogin() after successful signup.

verification: Build succeeded - user should test manually by: 1) Complete onboarding, 2) Kill app, 3) Relaunch, 4) Login - should now navigate to main app

files_changed:
- apps/ios/trendy/Views/Auth/LoginView.swift
- apps/ios/trendy/Views/Auth/SignupView.swift
