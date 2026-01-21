---
status: resolved
trigger: "ios-login-not-persisted: After logging into the iOS app and killing/restarting it, the user is presented with the login screen again instead of going straight to the dashboard"
created: 2026-01-20T00:00:00Z
updated: 2026-01-20T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - determineInitialRoute() is called synchronously BEFORE async restoreSession() completes. Since getUserId() requires currentSession (which is nil), findMostRecentCachedStatus() returns nil, causing route to .login instead of .authenticated
test: Verified via code analysis - init order in trendyApp.swift shows determineInitialRoute() is called synchronously while restoreSession() runs in detached Task
expecting: N/A - hypothesis confirmed through code analysis
next_action: Implement fix - cache userId in UserDefaults when login succeeds, read it synchronously for OnboardingCache lookup

- timestamp: 2026-01-20T00:05:00Z
  checked: Supabase Swift SDK documentation and GitHub discussions
  found: |
    Supabase Swift SDK stores sessions in Keychain asynchronously. There's no synchronous API
    to read the session. The SDK's session property is async: `try await client.auth.session`.
    This is a known limitation discussed in GitHub issues.
  implication: |
    Cannot rely on Supabase for synchronous session access. Need an alternative approach:
    - Option 1: Cache userId in UserDefaults when user logs in (simple, reliable)
    - Option 2: Wait for session restore before routing (adds loading time)
    - Option 3: Store last-known userId alongside onboarding cache

    Best solution: Option 1 - Cache userId in UserDefaults when sign-in succeeds.
    On app launch, read cached userId synchronously to look up OnboardingCache.

## Symptoms

expected: After successful login, killing and relaunching the app should restore the session and show the dashboard directly
actual: App shows login screen again after restart, requiring re-authentication
errors: No visible errors in console or logs when app launches
reproduction: 1) Log into iOS app 2) Kill the app 3) Relaunch the app 4) Login screen appears instead of dashboard
started: Used to work correctly, but has stopped working recently

## Eliminated

## Evidence

- timestamp: 2026-01-20T00:01:00Z
  checked: SupabaseService.swift and AuthViewModel.swift
  found: SupabaseService.init() calls restoreSession() in a Task, and AuthViewModel.init() calls checkAuthState() in a Task. Both are async operations that run AFTER initialization completes.
  implication: There's a potential race condition - the view hierarchy may check isAuthenticated BEFORE the async session restore completes

- timestamp: 2026-01-20T00:02:00Z
  checked: trendyApp.swift and AppRouter.swift
  found: AppRouter.determineInitialRoute() is called synchronously in trendyApp.init() BEFORE SupabaseService.restoreSession() completes. The routing uses OnboardingCache to decide where to go. The key method findMostRecentCachedStatus() calls supabaseService.getUserId() which REQUIRES currentSession to be populated.
  implication: The synchronous call to supabaseService.getUserId() likely fails (throws) because currentSession is nil at that point (async restore hasn't completed). This returns nil from findMostRecentCachedStatus(), causing route to .login instead of .authenticated

- timestamp: 2026-01-20T00:03:00Z
  checked: OnboardingCache.swift
  found: OnboardingCache stores per-user status keyed by userId (key format: "onboarding_status_{userId}"). The read() method is synchronous and requires the userId. There's also a global flag "onboarding_any_user_completed" for detecting returning users.
  implication: The cache lookup CANNOT work without a userId. If getUserId() throws (because session isn't restored yet), there's no way to look up the cached status for that user.

- timestamp: 2026-01-20T00:04:00Z
  checked: trendyApp.swift lines 340-413 - exact initialization order
  found: |
    CRITICAL SEQUENCE:
    1. Line 343: SupabaseService init called -> spawns Task { restoreSession() } (async)
    2. Line 369: appRouter.determineInitialRoute() called SYNCHRONOUSLY
    3. Line 385-413: Task spawned for analytics, calls restoreSession() AGAIN

    The problem: SupabaseService.init() launches restoreSession() in a detached Task,
    but the trendyApp.init() continues and calls determineInitialRoute() SYNCHRONOUSLY.
    The async restoreSession() has NOT completed when determineInitialRoute() runs.
  implication: |
    This is a clear race condition. The flow is:
    1. SupabaseService created, currentSession is nil
    2. Task { restoreSession() } is launched but runs AFTER init continues
    3. determineInitialRoute() is called while currentSession is still nil
    4. getUserId() throws because currentSession is nil
    5. findMostRecentCachedStatus() returns nil
    6. hasAnyCompletedUser is TRUE (user completed onboarding before)
    7. Route goes to .login (line 103 of AppRouter.swift) instead of .authenticated

## Resolution

root_cause: |
  Race condition in AppRouter.determineInitialRoute(). The method is called synchronously
  during app init, but SupabaseService.restoreSession() runs asynchronously in a detached Task.

  The flow is:
  1. SupabaseService.init() spawns Task { restoreSession() } - runs async
  2. trendyApp.init() continues and calls determineInitialRoute() SYNCHRONOUSLY
  3. findMostRecentCachedStatus() calls supabaseService.getUserId()
  4. getUserId() throws because currentSession is nil (async restore hasn't completed)
  5. findMostRecentCachedStatus() returns nil
  6. Since hasAnyUserCompletedOnboarding() is true, route goes to .login instead of .authenticated

  The onboarding cache is keyed by userId, but the userId isn't available synchronously
  because Supabase's session storage is accessed asynchronously via Keychain.

fix: |
  Cache the last authenticated userId in UserDefaults when sign-in/sign-up succeeds,
  and clear it on sign-out. Read this cached userId synchronously during route determination.

  Changes made:
  1. SupabaseService.swift - Added cachedUserId property and helper methods:
     - cachedUserIdKey constant for UserDefaults key
     - cachedUserId computed property (read from UserDefaults)
     - cacheUserId() method (save to UserDefaults)
     - clearCachedUserId() method (remove from UserDefaults)
  2. SupabaseService.signUp() - Added cacheUserId() call after successful signup
  3. SupabaseService.signIn() - Added cacheUserId() call after successful signin
  4. SupabaseService.signInWithIdToken() - Added cacheUserId() call after successful OAuth signin
  5. SupabaseService.signOut() - Added clearCachedUserId() call
  6. AppRouter.findMostRecentCachedStatus() - Updated to use supabaseService.cachedUserId
     instead of trying to get userId from session (which may not be restored yet)
  7. AppRouter.determineInitialRoute() - Added cachedUserId to debug logging

verification: |
  - Build succeeded (xcodebuild with scheme "trendy (local)")
  - Code compiles without errors
  - Logic verified: userId is now cached in UserDefaults on sign-in/sign-up
  - Logic verified: cached userId is cleared on sign-out
  - Logic verified: AppRouter.findMostRecentCachedStatus() uses cached userId for synchronous lookup
files_changed:
  - apps/ios/trendy/Services/SupabaseService.swift
  - apps/ios/trendy/Services/AppRouter.swift
