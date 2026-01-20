# iOS Onboarding Architecture

**Domain:** iOS app onboarding state management
**Researched:** 2026-01-19
**Focus:** Preventing flash for returning users, proper state machine, integration with existing SupabaseService

## Problem Analysis

### Current Architecture Issues

The existing implementation has a **flash problem** where onboarding screens briefly appear for returning users. This happens because:

1. **Async state checking in `.task`**: `ContentView` uses `.task { await checkOnboardingStatus() }` which runs AFTER the initial view render
2. **Default state shows loading then wrong view**: While `hasCheckedOnboarding` is false, loading view shows, but then the check completes and the wrong view may flash
3. **Multiple async hops**: Auth check -> Profile fetch -> State update creates race conditions
4. **State split across locations**: `UserDefaults`, `SupabaseService.isAuthenticated`, `ProfileService.onboardingComplete` all need to be in sync

### Root Cause

```
Current Flow (Problematic):
1. App launches -> ContentView body evaluates
2. hasCheckedOnboarding = false -> LoadingStateView shows
3. .task runs checkOnboardingStatus() [ASYNC]
4. During async: authViewModel.isAuthenticated may update
5. View re-renders mid-check -> potential flash
6. Finally: onboardingComplete updates -> final state
```

The problem is that SwiftUI's body is computed synchronously, but the state determination is async with multiple intermediate states.

## Recommended Architecture

### Pattern: Synchronous Launch State with Deferred Async Verification

The key insight is to **read cached state synchronously** at app launch, then **verify/update asynchronously** without intermediate view changes.

### Component 1: AppLaunchState Enum

A single source of truth for what the app should display:

```swift
enum AppLaunchState: Equatable {
    case loading           // Initial state, checking auth
    case onboarding        // Show onboarding flow
    case authenticated     // Show main app
}
```

**Why this works:** The enum has no intermediate states. The app is either checking, showing onboarding, or showing the main app. No flash-inducing transitions.

### Component 2: LaunchStateCoordinator (ObservableObject/@Observable)

A coordinator that manages launch state determination:

```swift
@Observable
@MainActor
class LaunchStateCoordinator {
    private(set) var launchState: AppLaunchState = .loading

    private let supabaseService: SupabaseService

    // UserDefaults keys for cached state
    private static let onboardingCompleteKey = "onboarding_complete"

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService

        // SYNCHRONOUS: Check cached state immediately in init
        // This prevents flash because we know the answer before body renders
        let cachedComplete = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)

        if cachedComplete && supabaseService.isAuthenticated {
            // Fast path: cached as complete and has auth -> go directly to authenticated
            launchState = .authenticated
        } else {
            // Need to verify with backend
            launchState = .loading
        }
    }

    func verifyLaunchState() async {
        // If already determined authenticated, verify it's still valid
        if launchState == .authenticated {
            // Just verify session is still valid
            await supabaseService.restoreSession()
            if !supabaseService.isAuthenticated {
                // Session expired, need to re-auth
                launchState = .onboarding
            }
            return
        }

        // If loading, determine actual state
        await supabaseService.restoreSession()

        if supabaseService.isAuthenticated {
            // Check profile for onboarding status
            let profileService = ProfileService(supabaseService: supabaseService)
            do {
                if let profile = try await profileService.fetchProfile(),
                   profile.onboardingComplete {
                    // Cache for next launch
                    UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
                    launchState = .authenticated
                } else {
                    launchState = .onboarding
                }
            } catch {
                // Error fetching profile - show onboarding to be safe
                launchState = .onboarding
            }
        } else {
            launchState = .onboarding
        }
    }
}
```

### Component 3: Root View Structure

```swift
@main
struct TrendyApp: App {
    // ... existing services ...

    @State private var launchCoordinator: LaunchStateCoordinator

    init() {
        // Initialize services first
        let supabaseService = SupabaseService(configuration: appConfiguration.supabaseConfiguration)
        self.supabaseService = supabaseService

        // Initialize launch coordinator synchronously
        // This determines initial state BEFORE body is computed
        _launchCoordinator = State(initialValue: LaunchStateCoordinator(supabaseService: supabaseService))
    }

    var body: some Scene {
        WindowGroup {
            RootView(launchCoordinator: launchCoordinator)
                .environment(authViewModel)
                // ... other environments ...
        }
    }
}

struct RootView: View {
    @Bindable var launchCoordinator: LaunchStateCoordinator

    var body: some View {
        // SWITCH on launch state - no intermediate views
        switch launchCoordinator.launchState {
        case .loading:
            LaunchLoadingView()
                .task {
                    await launchCoordinator.verifyLaunchState()
                }
        case .onboarding:
            OnboardingContainerView()
        case .authenticated:
            MainTabView()
        }
    }
}
```

### Why This Prevents Flash

1. **Synchronous init**: `LaunchStateCoordinator` reads `UserDefaults` synchronously in `init()`
2. **Known state before body**: When `RootView.body` is first computed, `launchState` is already set
3. **No intermediate states**: Loading only shows when genuinely unknown, then transitions directly to final state
4. **Cached fast path**: Returning users with cached `onboarding_complete = true` skip loading entirely

## View Hierarchy Pattern

### Recommended Structure

```
trendyApp (App struct)
  |
  +-- RootView (state switch)
        |
        +-- LaunchLoadingView (when state = .loading)
        |
        +-- OnboardingContainerView (when state = .onboarding)
        |     |
        |     +-- OnboardingNavigationView
        |           |
        |           +-- WelcomeView
        |           +-- OnboardingAuthView
        |           +-- CreateEventTypeView
        |           +-- LogFirstEventView
        |           +-- PermissionsView
        |           +-- OnboardingFinishView
        |
        +-- MainTabView (when state = .authenticated)
```

### Key Principles

1. **Single point of branching**: `RootView` is the ONLY place that decides onboarding vs main app
2. **No onboarding checks in child views**: Child views assume they're in the right context
3. **State transitions handled by coordinator**: Views call coordinator methods, not UserDefaults directly
4. **Environment propagation**: Services passed via environment, not recreated per-view

## State Machine for Onboarding Flow

### Existing OnboardingStep Enum (Keep)

The existing `OnboardingStep` enum is well-designed:

```swift
enum OnboardingStep: String, Codable, CaseIterable {
    case welcome
    case auth
    case createEventType
    case logFirstEvent
    case permissions
    case finish
}
```

### Integration with LaunchStateCoordinator

```swift
extension LaunchStateCoordinator {
    func completeOnboarding() {
        // Update cached state immediately
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)

        // Transition to authenticated
        launchState = .authenticated
    }

    func handleSignOut() {
        // Clear cached state
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey)

        // Transition to onboarding
        launchState = .onboarding
    }
}
```

### Notification-Based Transition (Alternative)

Current code uses `NotificationCenter.default.post(name: .onboardingCompleted)`. This can be kept but the coordinator should listen:

```swift
init(supabaseService: SupabaseService) {
    // ... existing init ...

    NotificationCenter.default.addObserver(
        forName: .onboardingCompleted,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.completeOnboarding()
    }
}
```

## Integration Points with Existing Services

### SupabaseService

**Current Integration:** `SupabaseService.isAuthenticated` is checked throughout the app.

**Recommendation:** The `LaunchStateCoordinator` becomes the single consumer of `isAuthenticated` for routing decisions. Other views should assume auth is valid if they're rendered.

```swift
// Good: Coordinator checks once
if supabaseService.isAuthenticated {
    launchState = .authenticated
}

// Bad: Multiple views checking independently
// This causes race conditions and flash
```

### AuthViewModel

**Current Role:** Manages auth state and provides sign in/out methods.

**Recommendation:** Keep `AuthViewModel` for auth operations, but decouple from routing:

```swift
// AuthViewModel remains for:
- signIn(email:password:)
- signUp(email:password:)
- signOut()
- currentUserEmail

// LaunchStateCoordinator handles:
- Launch state determination
- Routing between onboarding/main
- Cache management
```

### OnboardingViewModel

**Current Role:** Manages onboarding step navigation and state persistence.

**Recommendation:** Keep as-is for onboarding flow management. Add explicit callback for completion:

```swift
// In OnboardingViewModel
var onComplete: (() -> Void)?

private func completeOnboarding() async {
    // ... existing completion logic ...
    onComplete?()
}

// In OnboardingContainerView
OnboardingNavigationView(viewModel: viewModel)
    .onAppear {
        viewModel.onComplete = {
            launchCoordinator.completeOnboarding()
        }
    }
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Checking Auth in Multiple Views

**Problem:**
```swift
// ContentView
if authViewModel.isAuthenticated { ... }

// OnboardingContainerView
if supabaseService.isAuthenticated { ... }

// Some other view
guard authViewModel.isAuthenticated else { return }
```

**Why Bad:** Each check can resolve at different times, causing inconsistent UI.

**Instead:** Single coordinator checks once, routes definitively.

### Anti-Pattern 2: Async State Check in View Body

**Problem:**
```swift
var body: some View {
    Group {
        if !hasCheckedOnboarding {
            LoadingView()
        } else if /* condition */ {
            MainView()
        }
    }
    .task {
        await checkOnboardingStatus()
        hasCheckedOnboarding = true  // Causes re-render
    }
}
```

**Why Bad:** The `.task` runs after initial render, causing at least two renders.

**Instead:** Determine state in coordinator init, verify async without changing state unless truly different.

### Anti-Pattern 3: UserDefaults Without Caching Strategy

**Problem:**
```swift
// Writing in multiple places
UserDefaults.standard.set(true, forKey: "onboarding_complete")
// ... somewhere else ...
UserDefaults.standard.set(true, forKey: "onboarding_complete")
```

**Why Bad:** No single source of truth, hard to track state changes.

**Instead:** Coordinator owns cache keys, provides methods for state changes.

## Suggested Build Order

Based on dependencies and the goal of fixing the flash issue first:

### Phase 1: Launch State Foundation

1. **Create `AppLaunchState` enum** - Simple, no dependencies
2. **Create `LaunchStateCoordinator`** - Depends on SupabaseService (exists)
3. **Create `RootView`** - Depends on LaunchStateCoordinator
4. **Update `trendyApp`** - Wire everything together

**Outcome:** Flash issue fixed. Returning users see main app immediately.

### Phase 2: Onboarding Flow Polish

5. **Update `OnboardingContainerView`** - Remove redundant state checks
6. **Connect completion callback** - OnboardingViewModel -> LaunchStateCoordinator
7. **Update sign-out flow** - Ensure LaunchStateCoordinator.handleSignOut() is called

**Outcome:** Clean transitions between all states.

### Phase 3: Edge Cases and Polish

8. **Handle session expiry** - Detect expired tokens, route to re-auth
9. **Add transition animations** - Smooth fade between launch states
10. **Add analytics** - Track time in loading state, onboarding funnel

**Outcome:** Production-ready onboarding.

## Confidence Assessment

| Aspect | Confidence | Rationale |
|--------|------------|-----------|
| Synchronous init pattern | HIGH | Standard SwiftUI pattern, well-documented |
| UserDefaults caching | HIGH | Proven pattern for fast app launch |
| Single coordinator approach | HIGH | Follows Apple's recommendations for state management |
| Integration with existing services | MEDIUM | Requires careful refactoring of existing code |
| Notification-based completion | MEDIUM | Works but callback pattern may be cleaner |

## Sources

- [Hacking with Swift - @AppStorage](https://www.hackingwithswift.com/quick-start/swiftui/what-is-the-appstorage-property-wrapper) - Property wrapper behavior and timing
- [Scott Smith Dev - App Launch States](https://scottsmithdev.com/an-approach-to-handling-app-launch-states-in-swiftui) - LaunchState enum pattern
- [onmyway133 - User State Structure](https://onmyway133.com/posts/how-to-structure-user-state-for-app-in-swiftui/) - UserState enum with auth levels
- [Kodeco - SwiftUI Onboarding](https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/1-design-a-seamless-onboarding-experience-in-swiftui) - Modern iOS 18+ patterns
- [Holy Swift - Launch Screen State Machine](https://holyswift.app/animated-launch-screen-in-swiftui/) - State machine for launch transitions
- [Rivera Labs - SwiftUI Onboarding iOS 18+](https://www.riveralabs.com/blog/swiftui-onboarding/) - ScrollPosition-based modern approach
- [Medium - SwiftUI Onboarding with UserDefaults](https://medium.com/@deanirafd/swiftui-onboarding-screen-using-userdefaults-29ea1ad63fa1) - UserDefaults persistence patterns
- [Peter Friese - SwiftUI Application Lifecycle](https://peterfriese.dev/posts/ultimate-guide-to-swiftui2-application-lifecycle/) - App struct initialization timing

## Summary for Roadmap

**Key Architectural Decisions:**

1. **LaunchStateCoordinator** - New component that owns launch state determination
2. **Synchronous cache read in init** - Prevents flash by knowing state before body renders
3. **Single routing point (RootView)** - Eliminates inconsistent state checks
4. **Async verification, not determination** - Verify cached state is still valid, don't re-determine

**Build Order Rationale:**
- Phase 1 fixes the flash issue (highest priority, blocks user experience)
- Phase 2 connects existing onboarding flow to new coordinator
- Phase 3 handles edge cases that only matter after core flow works

**Research Flags:**
- Phase 1: Standard patterns, unlikely to need additional research
- Phase 2: May need to investigate callback vs notification trade-offs
- Phase 3: Session expiry handling may need Supabase-specific research
