# Phase 9: iOS State Architecture - Research

**Researched:** 2026-01-20
**Domain:** iOS SwiftUI App State Management, Backend Sync, Launch State Routing
**Confidence:** HIGH

## Summary

This research investigates the current iOS app architecture to inform planning for Phase 9: iOS State Architecture. The phase requires implementing a local cache of onboarding status and an Observable-based routing system that ensures returning users never see onboarding screens flash.

The current implementation uses:
- `ContentView.swift` as the root router with `@State` for onboarding status
- `NotificationCenter` posts for routing transitions (`.onboardingCompleted`)
- `UserDefaults` for local onboarding state (single boolean)
- `ProfileService` direct Supabase calls for backend onboarding status (old `profiles` table)
- Async state determination causing loading screen flash

The new system will leverage:
- Phase 8's dedicated `onboarding_status` API endpoints with per-step granularity
- `SyncEngine` patterns for offline-capable syncing
- `@Observable` pattern already established in the codebase
- Per-user caching (keyed by user ID) for multi-account support

**Primary recommendation:** Create an `AppRouter` Observable that synchronously reads cached onboarding status before any UI renders, eliminating the loading flash for returning users.

## Current Architecture Analysis

### Routing Flow (Current)

```
trendyApp.swift
    └── ContentView
            ├── LoadingStateView (while checking)
            ├── MainTabView (authenticated + onboarding complete)
            └── OnboardingContainerView (not authenticated OR onboarding incomplete)
```

**Critical Issue:** `ContentView.checkOnboardingStatus()` is async, causing a loading screen flash for returning users:
```swift
// ContentView.swift lines 74-101
private func checkOnboardingStatus() async {
    // Check local storage first (fast path)
    if UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey) {
        onboardingComplete = true
        hasCheckedOnboarding = true
        return
    }
    // If authenticated, check profile in backend...
}
```

The current "fast path" only checks a boolean - it doesn't distinguish between users or store step-level progress.

### NotificationCenter Usage (To Be Removed)

Found 3 routing-related NotificationCenter usages:

| Location | Usage | Will Replace With |
|----------|-------|-------------------|
| `ContentView.swift:51` | `.onReceive(.onboardingCompleted)` | AppRouter state change |
| `OnboardingContainerView.swift:60,109` | Posts `.onboardingCompleted` | AppRouter method call |
| `OnboardingViewModel.swift:647` | Posts `.onboardingCompleted` | AppRouter method call |

Non-routing NotificationCenter usages (will NOT be removed):
- `SyncEngine.swift:1725` - `.syncEngineBootstrapCompleted` for HealthKit
- `GeofenceManager.swift` - System notifications (app lifecycle)
- `HealthKitService.swift` - Bootstrap notification listener
- `AppDelegate.swift` - Background launch notifications

### Current State Storage

| Data | Storage | Per-User? | Survives Reinstall? |
|------|---------|-----------|---------------------|
| Onboarding complete (boolean) | UserDefaults | No | No |
| Onboarding step | UserDefaults | No | No |
| Onboarding start time | UserDefaults | No | No |
| Sync cursor | UserDefaults (env-keyed) | No | No |
| Auth session | Supabase Keychain | Yes | Yes |

**Problem:** Current onboarding storage is NOT per-user. If User A logs out and User B logs in, User B might see User A's onboarding status.

### Backend Onboarding API (Phase 8)

Endpoints available from Phase 8:

```
GET    /api/v1/users/onboarding   - GetOrCreate (returns defaults for new users)
PATCH  /api/v1/users/onboarding   - Update status
DELETE /api/v1/users/onboarding   - Soft reset (clears step timestamps, keeps permissions)
```

**OnboardingStatus model (backend):**
```go
type OnboardingStatus struct {
    UserID                   string     `json:"user_id"`
    Completed                bool       `json:"completed"`
    WelcomeCompletedAt       *time.Time `json:"welcome_completed_at"`
    AuthCompletedAt          *time.Time `json:"auth_completed_at"`
    PermissionsCompletedAt   *time.Time `json:"permissions_completed_at"`
    NotificationsStatus      *string    `json:"notifications_status"`
    NotificationsCompletedAt *time.Time `json:"notifications_completed_at"`
    HealthkitStatus          *string    `json:"healthkit_status"`
    HealthkitCompletedAt     *time.Time `json:"healthkit_completed_at"`
    LocationStatus           *string    `json:"location_status"`
    LocationCompletedAt      *time.Time `json:"location_completed_at"`
    CreatedAt                time.Time  `json:"created_at"`
    UpdatedAt                time.Time  `json:"updated_at"`
}
```

Valid permission status values: `granted`, `denied`, `skipped`, `not_requested`

### Existing Patterns to Leverage

#### @Observable Pattern
The codebase extensively uses Swift's `@Observable` macro:
- `AuthViewModel` - auth state management
- `EventStore` - data layer with sync state
- `OnboardingViewModel` - onboarding flow state
- `SyncStatusViewModel` - sync progress display
- `ThemeManager` - theme state

**Pattern:** Services are created in `trendyApp.swift` and injected via `.environment()`:
```swift
@State private var authViewModel: AuthViewModel
// ...
ContentView()
    .environment(authViewModel)
    .environment(themeManager)
```

#### SyncEngine Pattern
`SyncEngine` demonstrates the offline-capable sync pattern:
- Queues mutations locally (PendingMutation model)
- Flushes to backend when online
- Uses cursor-based incremental sync
- Environment-specific storage keys

**Key insight for onboarding:** Use the same pattern - queue onboarding status updates locally, sync to backend when online.

#### Per-User Storage Pattern
`SyncEngine` uses environment-keyed storage:
```swift
private var cursorKey: String {
    "sync_engine_cursor_\(AppEnvironment.current.rawValue)"
}
```

For onboarding, extend this to be user-keyed:
```swift
private func cacheKey(for userId: String) -> String {
    "onboarding_status_\(userId)"
}
```

### ProfileService (Old Pattern - Being Replaced)

`ProfileService.swift` currently uses direct Supabase queries to the `profiles` table:
```swift
func fetchProfile() async throws -> Profile?
func completeOnboarding() async throws
func updateOnboardingStep(_ step: OnboardingStep) async throws
```

**This will be replaced** by API calls to the new `/api/v1/users/onboarding` endpoints via `APIClient`.

### Environment Keys

Existing environment key pattern for services:
```swift
struct SupabaseServiceKey: EnvironmentKey {
    static let defaultValue: SupabaseService? = nil
}

extension EnvironmentValues {
    var supabaseService: SupabaseService? {
        get { self[SupabaseServiceKey.self] }
        set { self[SupabaseServiceKey.self] = newValue }
    }
}
```

## Standard Stack

### Core Components

| Component | Pattern | Purpose |
|-----------|---------|---------|
| `AppRouter` | `@Observable` | Central routing state machine |
| `OnboardingStatusCache` | `UserDefaults` (per-user keyed) | Local cache for fast launch |
| `OnboardingStatusService` | Service class | API calls + cache management |

### Storage Decision: UserDefaults vs Keychain

**Recommendation: UserDefaults** (per-user keyed)

| Factor | UserDefaults | Keychain |
|--------|-------------|----------|
| Reinstall survival | No | Yes |
| Multi-user support | Easy (key per user) | Complex |
| Sync complexity | Simple | Need wrapper |
| Backend source of truth? | Yes (sync on login) | Yes |
| Performance | Synchronous | Async |

Since backend is source of truth and we sync on login, reinstall survival is not critical. UserDefaults allows synchronous reads for instant route determination.

**Key pattern:**
```swift
// Store by user ID
let key = "onboarding_status_\(userId)"
UserDefaults.standard.set(encodedData, forKey: key)

// On logout: Keep cache (user might re-login)
// On login as different user: Check their key (no conflict)
```

### Route State Enum

```swift
enum AppRoute: Equatable {
    case loading           // Initial state, checking cache
    case onboarding(step: OnboardingStep)  // In onboarding flow
    case authenticated     // Main app
    case login            // Unauthenticated returning user
}
```

**Note:** Per CONTEXT.md, explicit `loading` case is preferred. Cache hit = instant route, no loading for returning users.

## Architecture Patterns

### Recommended Flow

```
App Launch
    │
    ▼
┌─────────────────┐
│ Read Auth State │ (Supabase session restore - sync)
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
Has Session  No Session
    │             │
    ▼             ▼
┌──────────┐  ┌──────────────────┐
│Read Cache│  │Check Cache       │
│(sync)    │  │(any user ever?)  │
└────┬─────┘  └────────┬─────────┘
     │                  │
┌────┴────┐       ┌────┴────┐
│         │       │         │
▼         ▼       ▼         ▼
Complete  Not    Has Cache  No Cache
   │      Complete (returning) (fresh)
   │         │        │         │
   ▼         ▼        ▼         ▼
MainApp  Onboarding  Login   Onboarding
```

### AppRouter Design

```swift
@Observable
@MainActor
class AppRouter {
    private(set) var currentRoute: AppRoute = .loading

    private let supabaseService: SupabaseService
    private let onboardingService: OnboardingStatusService

    /// Called ONCE at app launch - synchronous determination
    func determineInitialRoute() {
        // 1. Check auth state (synchronous from cached session)
        guard let userId = supabaseService.currentSession?.user.id else {
            // No session - check if ANY user has completed onboarding before
            if hasAnyUserCompletedOnboarding() {
                currentRoute = .login  // Returning user, show login
            } else {
                currentRoute = .onboarding(step: .welcome)  // Fresh install
            }
            return
        }

        // 2. Has session - read cached onboarding status (synchronous)
        if let status = readCachedStatus(userId: userId), status.completed {
            currentRoute = .authenticated  // Instant main app
        } else {
            currentRoute = .loading  // Need to check backend
            Task { await fetchAndRoute(userId: userId) }
        }
    }

    private func readCachedStatus(userId: String) -> CachedOnboardingStatus? {
        // Synchronous UserDefaults read - no flash
    }

    private func hasAnyUserCompletedOnboarding() -> Bool {
        // Check for existence of any onboarding_status_* keys
    }
}
```

### Sync Strategy

Per CONTEXT.md decisions:
1. **Push to backend after each onboarding step** - enables cross-device resume
2. **Offline completion allowed** - queue sync for later
3. **Use existing SyncQueue** - same pattern as events

However, onboarding status is simpler than events - no UUIDv7, no idempotency needed:
- Single row per user (user_id is primary key)
- PATCH is idempotent (same fields = no conflict)
- No complex reconciliation

**Recommendation:** Direct API calls with offline queue fallback, not full SyncEngine integration.

### Cache Structure

```swift
struct CachedOnboardingStatus: Codable {
    let userId: String
    let completed: Bool
    let currentStep: String?  // Resume step if incomplete
    let welcomeCompletedAt: Date?
    let authCompletedAt: Date?
    let permissionsCompletedAt: Date?
    let lastSyncedAt: Date?
    let lastUpdatedAt: Date
}
```

**Key behaviors:**
- On logout: Keep cache (user might re-login)
- On login: Sync from backend, update cache
- On step complete: Update cache immediately, queue backend push
- On cache miss + offline: Treat as incomplete (show onboarding)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-user keyed storage | Custom file storage | UserDefaults with `userId` in key | Atomic, thread-safe, synchronous |
| Session restore | Manual token storage | Supabase SDK Keychain | Already handles refresh |
| Backend sync queue | Custom queue system | Adapt existing SyncEngine pattern | Proven offline-capable |
| Date encoding | Manual ISO8601 | JSONEncoder with `.iso8601` | Consistent with existing code |

## Common Pitfalls

### Pitfall 1: Async State Determination Causing Flash
**What goes wrong:** Loading screen appears briefly for returning users
**Why it happens:** Route determination requires async operations
**How to avoid:**
- Read cached status synchronously at launch
- Only go async for cache miss scenarios
- Use `currentSession` (synchronous) not `auth.session` (async)
**Warning signs:** `await` in the immediate launch path

### Pitfall 2: Multi-User Cache Conflicts
**What goes wrong:** User B sees User A's onboarding status
**Why it happens:** Single-key storage without user scoping
**How to avoid:** Always include `userId` in cache keys
**Warning signs:** Cache read without user ID parameter

### Pitfall 3: NotificationCenter Routing Leaks
**What goes wrong:** Routing happens from multiple places, inconsistent state
**Why it happens:** NotificationCenter is loosely coupled, any code can post
**How to avoid:**
- Remove all `.onboardingCompleted` posts
- Route changes ONLY through AppRouter methods
**Warning signs:** `NotificationCenter.default.post` for routing

### Pitfall 4: Supabase Session Restore Race
**What goes wrong:** App checks auth before session is restored
**Why it happens:** Supabase session restore is async
**How to avoid:**
- Use `currentSession` for synchronous check (may be nil)
- Don't await session restore in hot path
- Handle "no session" = unauthenticated OR session restoring
**Warning signs:** `try await client.auth.session` in launch path

### Pitfall 5: Offline User Blocked from Onboarding
**What goes wrong:** New user can't complete onboarding without network
**Why it happens:** Waiting for backend status check
**How to avoid:**
- Cache miss + offline = assume new user, allow onboarding
- Queue backend sync for later
**Warning signs:** Network check gating onboarding entry

### Pitfall 6: Step Completion Not Persisted on Force Quit
**What goes wrong:** User force quits mid-onboarding, restarts from beginning
**Why it happens:** Status only in memory, not persisted
**How to avoid:**
- Update cache immediately on step completion
- Queue backend push (fire-and-forget)
**Warning signs:** `await` before cache update

## Code Examples

### Synchronous Route Determination
```swift
// Source: Adapted from SupabaseService.swift patterns
@Observable
@MainActor
class AppRouter {
    private(set) var currentRoute: AppRoute = .loading

    func determineInitialRoute() {
        // SYNCHRONOUS - uses cached session, not async restore
        let hasSession = supabaseService.currentSession != nil
        let userId = supabaseService.currentSession?.user.id.uuidString

        if hasSession, let userId = userId {
            // Check per-user cache synchronously
            if let cached = readCache(userId: userId), cached.completed {
                currentRoute = .authenticated  // No flash!
            } else if let cached = readCache(userId: userId), let step = cached.currentStep {
                currentRoute = .onboarding(step: OnboardingStep(rawValue: step) ?? .welcome)
            } else {
                // Cache miss - need to check backend
                currentRoute = .loading
                Task { await syncAndRoute(userId: userId) }
            }
        } else {
            // No session - but might be returning user
            if hasAnyCompletedOnboardingCache() {
                currentRoute = .login  // Show login, not onboarding
            } else {
                currentRoute = .onboarding(step: .welcome)
            }
        }
    }
}
```

### Per-User Cache Read/Write
```swift
// Source: Adapted from SyncEngine.swift environment-keyed pattern
struct OnboardingCache {
    private static func key(for userId: String) -> String {
        "onboarding_status_\(userId)"
    }

    static func read(userId: String) -> CachedOnboardingStatus? {
        guard let data = UserDefaults.standard.data(forKey: key(for: userId)) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedOnboardingStatus.self, from: data)
    }

    static func write(_ status: CachedOnboardingStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: key(for: status.userId))
    }

    static func hasAnyCompletedCache() -> Bool {
        // Check if any onboarding_status_* key has completed = true
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("onboarding_status_") {
            if let data = UserDefaults.standard.data(forKey: key),
               let status = try? JSONDecoder().decode(CachedOnboardingStatus.self, from: data),
               status.completed {
                return true
            }
        }
        return false
    }
}
```

### Observable Router in App Entry Point
```swift
// Source: Adapted from trendyApp.swift patterns
@main
struct trendyApp: App {
    @State private var appRouter: AppRouter

    init() {
        // Create router with dependencies
        let supabaseService = SupabaseService(configuration: appConfiguration.supabaseConfiguration)
        let apiClient = APIClient(configuration: appConfiguration.apiConfiguration, supabaseService: supabaseService)
        let onboardingService = OnboardingStatusService(apiClient: apiClient)

        _appRouter = State(initialValue: AppRouter(
            supabaseService: supabaseService,
            onboardingService: onboardingService
        ))

        // Determine route SYNCHRONOUSLY before body is called
        // This is the key to no-flash routing
        appRouter.determineInitialRoute()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appRouter)
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        switch router.currentRoute {
        case .loading:
            LaunchScreenView()  // Matches launch screen aesthetic
        case .onboarding(let step):
            OnboardingContainerView(startingStep: step)
        case .login:
            LoginView()  // Returning unauthenticated user
        case .authenticated:
            MainTabView()
        }
    }
}
```

### API Integration for Onboarding Status
```swift
// Source: Pattern from APIClient.swift
extension APIClient {
    func getOnboardingStatus() async throws -> APIOnboardingStatus {
        return try await request("GET", endpoint: "/users/onboarding")
    }

    func updateOnboardingStatus(_ request: UpdateOnboardingStatusRequest) async throws -> APIOnboardingStatus {
        return try await self.request("PATCH", endpoint: "/users/onboarding", body: request)
    }

    func resetOnboardingStatus() async throws -> APIOnboardingStatus {
        return try await request("DELETE", endpoint: "/users/onboarding")
    }
}

struct APIOnboardingStatus: Codable {
    let userId: String
    let completed: Bool
    let welcomeCompletedAt: Date?
    let authCompletedAt: Date?
    let permissionsCompletedAt: Date?
    let notificationsStatus: String?
    let notificationsCompletedAt: Date?
    let healthkitStatus: String?
    let healthkitCompletedAt: Date?
    let locationStatus: String?
    let locationCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case completed
        case welcomeCompletedAt = "welcome_completed_at"
        case authCompletedAt = "auth_completed_at"
        case permissionsCompletedAt = "permissions_completed_at"
        case notificationsStatus = "notifications_status"
        case notificationsCompletedAt = "notifications_completed_at"
        case healthkitStatus = "healthkit_status"
        case healthkitCompletedAt = "healthkit_completed_at"
        case locationStatus = "location_status"
        case locationCompletedAt = "location_completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single onboarding boolean | Per-step timestamps | Phase 8-9 | Cross-device resume |
| Global UserDefaults keys | Per-user keyed storage | Phase 9 | Multi-account support |
| NotificationCenter routing | Observable router | Phase 9 | Predictable state flow |
| Async state determination | Synchronous cache read | Phase 9 | No flash for returning users |
| ProfileService (direct Supabase) | APIClient endpoints | Phase 8-9 | Consistent API layer |

**Deprecated/outdated:**
- `ProfileService.fetchProfile()` - replaced by `/users/onboarding` API
- `onboarding_complete` key in UserDefaults - replaced by per-user keyed cache
- `NotificationCenter.post(.onboardingCompleted)` - replaced by AppRouter state

## Integration Points

### Files to Modify

| File | Changes |
|------|---------|
| `trendyApp.swift` | Add AppRouter, call determineInitialRoute() |
| `ContentView.swift` | Remove routing logic, delegate to RootView |
| `OnboardingViewModel.swift` | Remove NotificationCenter posts, call AppRouter |
| `OnboardingContainerView.swift` | Remove NotificationCenter posts, call AppRouter |
| `APIClient.swift` | Add onboarding status endpoints |

### Files to Create

| File | Purpose |
|------|---------|
| `AppRouter.swift` | Observable routing state machine |
| `OnboardingStatusService.swift` | API calls + cache management |
| `OnboardingCache.swift` | Per-user UserDefaults wrapper |
| `RootView.swift` | Top-level view that switches on route |
| `LaunchScreenView.swift` | Loading state matching launch screen |

### Files to Remove/Deprecate

| File | Action | Reason |
|------|--------|--------|
| `ProfileService.swift` | Deprecate | Replaced by OnboardingStatusService |

## Open Questions

### Question 1: Session Restore Timing
**What we know:** Supabase session restore is async, called in `trendyApp.init()`
**What's unclear:** Exact timing - is `currentSession` populated before `body` is called?
**Recommendation:** Test empirically. If race exists, use a brief "splash" state that immediately resolves once session is checked.

### Question 2: Backend Check Timeout
**What we know:** CONTEXT.md says "timeout fallback: show onboarding"
**What's unclear:** Optimal timeout duration
**Recommendation:** 3 seconds - long enough for slow networks, short enough to not frustrate

### Question 3: Loading Screen Design
**What we know:** Should match launch screen aesthetic
**What's unclear:** Exact visual design (activity indicator, progress?)
**Recommendation:** Use existing `LoadingView` component, enhance if needed

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `/apps/ios/trendy/` - existing patterns verified
- Phase 8 backend: `/apps/backend/internal/handlers/onboarding.go` - API contract
- Phase 9 CONTEXT.md - locked decisions

### Secondary (MEDIUM confidence)
- Apple SwiftUI documentation - @Observable patterns
- Supabase Swift SDK - session management

## Metadata

**Confidence breakdown:**
- Current architecture analysis: HIGH - direct codebase examination
- Architecture patterns: HIGH - adapts existing proven patterns
- Pitfalls: HIGH - based on actual code issues found
- Integration points: HIGH - specific files identified

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (30 days - stable architecture)
