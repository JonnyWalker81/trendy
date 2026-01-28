---
status: resolved
trigger: "User is prompted to login frequently on iOS app when they should stay logged in until explicit logout"
created: 2026-01-25T00:00:00Z
updated: 2026-01-25T00:00:00Z
---

## Current Focus

hypothesis: verifySessionInBackground() has 0.5s timeout that may fire login transition before session is restored
test: Trace the timing of session restore vs background verification
expecting: If session restore takes >0.5s, user is incorrectly transitioned to login
next_action: Check Supabase Swift SDK for auth state listener pattern

## Symptoms

expected: User stays logged in until they explicitly log out
actual: User gets randomly prompted to login again on the iOS app
errors: None specified - just unexpected login prompts
reproduction: Random occurrence on iOS app - no specific trigger identified
started: User is not sure if it ever worked correctly

## Eliminated

## Evidence

- timestamp: 2026-01-25T00:01:00Z
  checked: SupabaseService.swift - session management
  found: |
    - Session is restored in init via Task { await restoreSession() } - fire-and-forget
    - restoreSession() uses `client.auth.session` which throws if no session
    - isAuthenticated is only set to true on successful session restore
    - currentSession can be nil even when session exists in Keychain (due to async restore)
    - No auth state listener/observer to react to session changes
  implication: Race condition possible - app may check isAuthenticated before restoreSession completes

- timestamp: 2026-01-25T00:01:00Z
  checked: AuthViewModel.swift - auth state initialization
  found: |
    - AuthViewModel also calls checkAuthState() in init via Task (fire-and-forget)
    - checkAuthState() calls supabaseService.getCurrentUser() which needs valid session
    - If getCurrentUser() fails, isAuthenticated is set to false
    - Two separate async tasks racing: SupabaseService.restoreSession and AuthViewModel.checkAuthState
  implication: AuthViewModel.checkAuthState may run before SupabaseService has restored session, causing false logout state

- timestamp: 2026-01-25T00:02:00Z
  checked: AppRouter.swift - verifySessionInBackground()
  found: |
    - determineInitialRoute() uses cache-first strategy (good)
    - If cache has completed user, routes to .authenticated immediately
    - THEN kicks off Task { await verifySessionInBackground() }
    - verifySessionInBackground() waits only 0.5s then checks session
    - If supabaseService.currentSession is nil after 0.5s -> transitionToLogin()
    - This is the SMOKING GUN: 0.5s may not be enough for Keychain session restore
  implication: Session restore from Keychain can take variable time; 0.5s timeout causes premature logout

- timestamp: 2026-01-25T00:03:00Z
  checked: Supabase Swift SDK auth patterns (web search)
  found: |
    - SDK provides `client.auth.authStateChanges` async sequence
    - This emits .initialSession event after session restore attempt
    - Proper pattern: listen to authStateChanges instead of polling
    - Events: .signedIn, .signedOut, .initialSession, .tokenRefreshed
    - Current implementation does NOT use authStateChanges listener
    - Using arbitrary 0.5s timeout is fragile and unreliable
  implication: Should replace polling with authStateChanges listener for reliable session state

## Resolution

root_cause: |
  AppRouter.verifySessionInBackground() uses a fixed 0.5s timeout to check if session was restored.
  If Keychain access takes longer than 0.5s (common on device under load or cold start),
  supabaseService.currentSession is still nil, triggering transitionToLogin().

  The proper pattern is to use Supabase SDK's authStateChanges async sequence which emits
  an .initialSession event when session restore completes (success or failure).

  Additionally, SupabaseService does not listen to auth state changes, so it cannot react
  to session refresh events or token expiration properly.

fix: |
  Replaced arbitrary 0.5s timeout with Supabase SDK auth state change listener.

  1. Added AuthStateEvent enum and authStateChanges stream to SupabaseService
  2. SupabaseService now listens to client.auth.authStateChanges for reliable events
  3. AppRouter.verifySessionInBackground() now waits for .initialSession event
  4. Added AppRouter.startAuthStateListener() for ongoing auth state monitoring
  5. Updated trendyApp.swift to start auth listener and use events for PostHog

  Key insight: Supabase SDK emits .initialSession event when Keychain restore completes.
  This is reliable regardless of how long the restore takes (no arbitrary timeout).

verification: |
  - Build: SUCCESS (xcodebuild completed without errors)
  - Code review: Changes correctly implement Supabase auth state listener pattern
  - Manual testing recommended: User should verify they stay logged in across app restarts
files_changed:
  - apps/ios/trendy/Services/SupabaseService.swift
  - apps/ios/trendy/Services/AppRouter.swift
  - apps/ios/trendy/trendyApp.swift
