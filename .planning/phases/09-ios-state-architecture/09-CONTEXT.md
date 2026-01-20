# Phase 9: iOS State Architecture - Context

**Gathered:** 2026-01-20
**Status:** Ready for planning

<domain>
## Phase Boundary

App launch routing that reads cached state synchronously, ensuring returning users never see onboarding screens flash. This phase delivers:
- Local cache of onboarding status (per-user, full step granularity)
- Synchronous state determination before UI renders
- Single enum-based route state (`loading`, `onboarding`, `authenticated`)
- Observable-based routing (replacing NotificationCenter)
- Backend sync on login and step completion

Creating or designing onboarding screens is Phase 10. Accessibility is Phase 11.

</domain>

<decisions>
## Implementation Decisions

### Cache behavior
- Fresh install (no cache): Check backend if online, assume new user if offline
- Backend is source of truth — backend status always wins over local
- Corrupted/unreadable cache: Treat as missing (same as fresh install)
- Cache stores full status (which steps completed), not just boolean — enables resuming mid-onboarding
- Cache is per-user (keyed by user ID) — multiple users on same device have separate status
- On logout: Keep onboarding cache — if user completed onboarding, don't show again on re-login
- If user A logs out and new user B logs in: User B sees onboarding (no cache for them)

### Loading state
- Loading screen matches Launch Screen aesthetic (seamless transition)
- Timeout fallback: Show onboarding if backend check fails or times out

### Sync timing
- Push to backend after each onboarding step — enables resuming on other devices
- Offline completion: Auto-sync when connection returns (use existing SyncQueue)
- Use existing SyncQueue for onboarding status (same pattern as events/event types)
- Reset onboarding option in settings — user can manually trigger onboarding again

### Edge cases
- Force-quit mid-onboarding: Resume from where they left off (cached step)
- Account loss (deletion/password reset): Clear local onboarding cache
- Device migration: Rely on backend sync, not iCloud transfer
- Mid-onboarding network drop: Allow offline continuation, queue sync for later
- NotificationCenter routing: Remove completely in this phase (no deprecation period)

### Claude's Discretion
- Cache storage location (Keychain vs UserDefaults) based on iOS best practices and reinstall survival
- Backend check timeout duration
- Retry behavior on backend push failure (silent queue likely)
- Backend sync frequency (on login vs every launch)
- Whether silent or notify user when syncing from another device
- Reset behavior: Clear local + backend, or local only
- App update handling: Skip new steps or show only new steps for existing users
- Loading screen activity indicator behavior
- Explicit loading case in route enum vs invisible loading
- Cache hit = instant route (no loading) for returning users
- Auto-fallback vs retry button on timeout
- Observable router injection pattern (environment vs singleton)
- Biometric auth timing relative to route determination

</decisions>

<specifics>
## Specific Ideas

- "I don't want users who already completed onboarding to see it flash, even for a millisecond"
- Resume from exact step on force-quit — treat onboarding like a progress-saved flow
- Backend sync per-step enables cross-device continuity (start on iPad, finish on iPhone)
- Offline-first: Never block user from continuing onboarding due to network

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-ios-state-architecture*
*Context gathered: 2026-01-20*
