# iOS Onboarding Pitfalls

**Domain:** iOS SwiftUI Onboarding Flow
**Researched:** 2026-01-19
**Confidence:** HIGH (verified against current Trendy codebase and SwiftUI documentation)
**Context:** Fixing existing onboarding that flashes for returning users, has wrong flow order, and needs visual refresh

---

## Executive Summary

This research documents common mistakes when building iOS onboarding flows, with specific focus on the issues currently affecting Trendy:

1. **UI Flash for Returning Users** - The core bug being fixed
2. **State Management Fragmentation** - Root cause of the flash issue
3. **Permission Request Timing** - Opportunity for improvement
4. **Animation and Transition Glitches** - Visual polish concerns

**Current Trendy Issues Mapped to Pitfalls:**
- Onboarding screens flash for returning users (Pitfalls 1, 2, 7)
- Multiple loading screens in sequence (Pitfall 2)
- State stored in multiple places with sync issues (Pitfall 6)
- NotificationCenter used for view routing (Pitfall 7)
- All permissions requested at once (Pitfall 4)

---

## Critical Pitfalls

Mistakes causing the problems you are currently experiencing or that would cause rewrites.

### Pitfall 1: Async State Check Causing UI Flash

**What goes wrong:** The onboarding screen briefly appears before the app determines the user has already completed onboarding. Users see a "flash" of the welcome/auth screen before being routed to the main app.

**Why it happens:** The current implementation in `ContentView.swift` uses a pattern where:
1. `hasCheckedOnboarding` starts as `false`
2. A `LoadingStateView` shows while checking
3. An async `.task` checks UserDefaults and/or backend profile
4. BUT the auth state (`authViewModel.isAuthenticated`) may update BEFORE `hasCheckedOnboarding` is set to `true`

The race condition occurs in this code pattern:
```swift
// Current problematic pattern in ContentView.swift:
if !hasCheckedOnboarding {
    LoadingStateView()  // Shows first
} else if authViewModel.isAuthenticated && onboardingComplete {
    MainTabView()
} else {
    OnboardingContainerView()  // FLASH: May show briefly
}
```

When `authViewModel.isAuthenticated` becomes `true` (from session restore in trendyApp.swift) but `hasCheckedOnboarding` is still `false`, the loading view shows. But if there is ANY render cycle where both conditions flip at different times, users see onboarding flash.

**Consequences:**
- Users see onboarding screens flash on every app launch
- Creates perception of buggy, unpolished app
- May confuse users about whether they need to re-authenticate
- "onboarding_started" analytics events fire incorrectly for returning users

**Prevention:**

1. **Single Source of Truth for Route State:**
   Use an enum-based routing state that encapsulates ALL conditions:
   ```swift
   enum AppRoute {
       case loading           // Checking state
       case onboarding(OnboardingStep)  // Needs onboarding
       case authenticated     // Ready for main app
   }

   @State private var route: AppRoute = .loading
   ```
   The route should ONLY change after ALL async checks complete in a single atomic operation.

2. **Synchronous Fast Path Check:**
   Check UserDefaults synchronously BEFORE any view renders:
   ```swift
   init() {
       // Synchronous check - no async needed for cached state
       let localComplete = UserDefaults.standard.bool(forKey: "onboarding_complete")
       let hasSession = // synchronous session check if possible
       if localComplete && hasSession {
           _route = State(initialValue: .authenticated)
       } else {
           _route = State(initialValue: .loading)
       }
   }
   ```

3. **Never Separate Auth and Onboarding Checks:**
   The current code checks `authViewModel.isAuthenticated` and `onboardingComplete` as separate conditions in separate state variables. These must be combined into a single state determination that only updates once.

4. **Atomic State Updates:**
   ```swift
   func determineRoute() async {
       // Gather ALL state
       let isAuthenticated = await checkAuth()
       let isOnboardingComplete = await checkOnboarding()

       // Single atomic update
       if isAuthenticated && isOnboardingComplete {
           route = .authenticated
       } else if isAuthenticated {
           route = .onboarding(.createEventType)  // Resume after auth
       } else {
           route = .onboarding(.welcome)
       }
   }
   ```

**Detection (warning signs you have this bug):**
- Users report seeing login screen briefly on app launch
- Onboarding analytics show "started" events for returning users
- UI tests capture screenshots of wrong screens
- QA reports intermittent flash on launch

**Which phase should address:** Phase 1 (State Management Foundation)

---

### Pitfall 2: Multiple Loading States Creating Disjointed Experience

**What goes wrong:** The app shows multiple different loading screens in sequence (iOS Launch Screen -> Loading View -> Onboarding Loading View -> Main Tab Loading View), creating a jarring, slow-feeling experience.

**Why it happens:** Looking at the current Trendy codebase:
- iOS shows the Launch Screen (configured in xcconfig/Info.plist)
- `ContentView` shows `LoadingStateView` while checking onboarding
- `OnboardingContainerView` shows `OnboardingLoadingView` while initializing
- `MainTabView` shows `LoadingView` while setting up EventStore/GeofenceManager

Each view manages its own loading state independently, leading to visible transitions between them.

**Consequences:**
- Users see 2-4 different loading screens in sequence
- Jarring visual experience with different loading indicators
- Perception of slow app startup
- Breaks the "instant launch" feel iOS users expect

**Prevention:**

1. **Match Launch Screen with Initial SwiftUI View:**
   Create a SwiftUI view that visually matches your Launch Screen EXACTLY. Keep showing this single view until ALL initialization is complete:
   ```swift
   struct RootView: View {
       @State private var isReady = false

       var body: some View {
           ZStack {
               // Main content (hidden until ready)
               mainContent
                   .opacity(isReady ? 1 : 0)

               // Launch screen replica (always on top until ready)
               if !isReady {
                   LaunchScreenReplica()
                       .transition(.opacity)
               }
           }
           .animation(.easeOut(duration: 0.3), value: isReady)
       }
   }
   ```

2. **Centralized Initialization:**
   Have a single coordinator that completes ALL setup before revealing UI:
   ```swift
   @Observable
   class AppCoordinator {
       var isReady = false
       var route: AppRoute = .loading

       func initialize() async {
           // 1. Restore auth session
           // 2. Check onboarding status
           // 3. Pre-fetch critical data
           // 4. Determine route
           // 5. Signal ready
           isReady = true
       }
   }
   ```

3. **No Nested Loading States:**
   Child views should NEVER show their own loading state during initial app launch. Loading states are only for user-initiated refreshes.

**Detection:**
- Screen recordings show multiple loading spinners/screens
- Users complain app "takes forever to load"
- Analytics show abnormal time-to-first-interaction
- Visual jarring during app launch

**Which phase should address:** Phase 1 (State Management Foundation)

---

### Pitfall 3: `task` and `onAppear` Running Multiple Times

**What goes wrong:** Initialization code runs multiple times, causing duplicate API calls, analytics events, or state inconsistencies.

**Why it happens:** SwiftUI's `task` and `onAppear` modifiers can trigger multiple times due to:
- View recreation from `@ObservedObject` or `@Observable` changes
- Navigation stack push/pop
- TabView tab switching
- Views in lazy containers scrolling in/out
- Parent view state changes causing child recreation

From the Trendy codebase, `OnboardingContainerView` uses:
```swift
.task {
    await initializeOnboarding()
}
```

This will re-run if the view is recreated for any reason.

**Consequences:**
- Duplicate "onboarding_started" analytics events (PostHog)
- Multiple network requests to check profile
- Race conditions between duplicate operations
- Memory leaks from uncancelled tasks
- State corruption from overlapping initializations

**Prevention:**

1. **Use `@State` Guard for One-Time Execution:**
   ```swift
   @State private var hasInitialized = false

   .task {
       guard !hasInitialized else { return }
       hasInitialized = true
       await initializeOnboarding()
   }
   ```

2. **Create Custom `onFirstAppear` Modifier:**
   ```swift
   extension View {
       func onFirstAppear(perform action: @escaping () async -> Void) -> some View {
           modifier(OnFirstAppearModifier(action: action))
       }
   }

   struct OnFirstAppearModifier: ViewModifier {
       @State private var hasAppeared = false
       let action: () async -> Void

       func body(content: Content) -> some View {
           content.task {
               guard !hasAppeared else { return }
               hasAppeared = true
               await action()
           }
       }
   }
   ```

3. **Move Initialization to Coordinator:**
   Don't initialize in views at all. Have a coordinator/router that initializes once:
   ```swift
   // In RootView, not OnboardingContainerView
   .task {
       await coordinator.initialize()  // Only called once at app launch
   }
   ```

4. **Use `@Observable` Instead of `@ObservedObject`:**
   The `@Observable` macro (iOS 17+) tracks changes at property level, reducing unnecessary view recreations that trigger `task`/`onAppear`.

**Detection:**
- Analytics show duplicate events for same user/session
- Network logs show repeated API calls on same screen
- Console logs show initialization code running multiple times
- PostHog shows multiple "onboarding_started" for single session

**Which phase should address:** Phase 1 (State Management Foundation)

---

### Pitfall 4: Permission Priming Timing Mistakes

**What goes wrong:** Asking for permissions (notifications, location, HealthKit) at the wrong time leads to high denial rates. Once denied, the user must navigate to iOS Settings to re-enable.

**Why it happens:** Common mistakes:
- Asking for ALL permissions upfront during onboarding
- No context about WHY the permission is needed
- Asking before user understands app value
- Showing iOS system dialog without a custom explanation first

The current `PermissionsView` asks for notifications, location, and HealthKit in one screen, even though these features have very different use cases.

**Consequences:**
- 60-80% permission denial rates (vs 89% acceptance with proper priming)
- Core features disabled for users who denied
- No second chance without Settings navigation
- Lost engagement (no push notifications, no geofence events, no HealthKit sync)
- Users don't understand why features "don't work"

**Prevention:**

1. **Two-Step Opt-In Pattern:**
   Show a custom pre-permission screen explaining the value BEFORE triggering the iOS system dialog:
   ```swift
   // Step 1: Custom explanation screen (YOUR UI)
   VStack {
       Image(systemName: "bell.badge")
       Text("Get reminders to log your daily coffee")
       Text("We'll notify you at the times that matter most to you.")

       Button("Enable Notifications") {
           // Only NOW show iOS dialog
           showSystemDialog = true
       }

       Button("Not Now") {
           skipPermission()
       }
   }

   // Step 2: Only if user taps Enable, show iOS dialog
   .task(id: showSystemDialog) {
       guard showSystemDialog else { return }
       await UNUserNotificationCenter.current().requestAuthorization(...)
   }
   ```

2. **Contextual Permission Requests (Preferred):**
   Ask for permissions when the user tries to use the feature, not during onboarding:
   ```swift
   // In geofence creation flow, not onboarding
   func createGeofence() async {
       if !hasLocationPermission {
           let granted = await showLocationExplanationAndRequest()
           guard granted else { return }
       }
       // Proceed with geofence creation
   }
   ```

3. **Remove Non-Essential Permissions from Onboarding:**
   The current `PermissionsView` is skippable (`isSkippable: true`). Consider removing it entirely and prompting contextually instead.

4. **Use iOS Provisional Push (iOS 12+):**
   For notifications, use provisional authorization to deliver quiet notifications first:
   ```swift
   try await center.requestAuthorization(options: [.alert, .badge, .sound, .provisional])
   ```
   Users experience value before deciding on full permission.

5. **Prioritize Based on Feature Usage:**
   - Notifications: Prompt when user creates reminder or enables a feature that uses them
   - Location: Prompt when user tries to create a geofence
   - HealthKit: Prompt when user taps to enable HealthKit integration in settings

**Detection:**
- Low permission grant rates in PostHog analytics
- Users complain core features "don't work"
- High rate of "Don't Allow" taps in permission dialogs
- Support tickets about missing notifications/location events

**Which phase should address:** Phase 3 (Permissions Polish) - or move permissions out of onboarding entirely

---

## Moderate Pitfalls

Mistakes that cause delays, technical debt, or poor UX but are recoverable.

### Pitfall 5: ZStack Animation Glitches

**What goes wrong:** Transitions between onboarding steps show visual glitches - views flash, overlap incorrectly, or animate in wrong directions.

**Why it happens:** SwiftUI's ZStack reorders views when state changes. The `zIndex` is calculated automatically and can change unexpectedly during transitions.

Current code pattern:
```swift
Group {
    switch viewModel.currentStep {
    case .welcome: WelcomeView(...)
    case .auth: OnboardingAuthView(...)
    // ...
    }
}
.animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
```

When the switch changes, SwiftUI may reorder the ZStack, causing the wrong view to appear on top momentarily.

**Consequences:**
- Views briefly overlap during transitions
- Animation direction feels wrong (new view comes from wrong side)
- Professional polish is undermined
- Users notice something is "off"

**Prevention:**

1. **Explicit zIndex Assignment:**
   ```swift
   ZStack {
       WelcomeView()
           .opacity(currentStep == .welcome ? 1 : 0)
           .zIndex(currentStep == .welcome ? 1 : 0)

       AuthView()
           .opacity(currentStep == .auth ? 1 : 0)
           .zIndex(currentStep == .auth ? 1 : 0)
   }
   ```

2. **Use Matched Geometry Effect:**
   For smooth hero transitions between steps sharing common elements.

3. **Consider NavigationStack for Linear Flows:**
   If onboarding is strictly linear, NavigationStack provides built-in transitions:
   ```swift
   NavigationStack(path: $onboardingPath) {
       WelcomeView()
           .navigationDestination(for: OnboardingStep.self) { step in
               stepView(for: step)
           }
   }
   ```

4. **Use `id()` Modifier for Clean Transitions:**
   ```swift
   currentStepView
       .id(viewModel.currentStep)
       .transition(.slide)
   ```

5. **Test Transitions Explicitly:**
   Add UI tests that capture screenshots during transitions.

**Detection:**
- Visual glitches visible during step changes
- Views briefly overlap during animation
- Animation direction feels wrong or inconsistent
- QA reports "flickering" between screens

**Which phase should address:** Phase 2 (Visual Design and Animations)

---

### Pitfall 6: State Persistence Inconsistency

**What goes wrong:** Onboarding state stored in multiple places (UserDefaults, backend profile) gets out of sync. User completes onboarding but sees it again, or partially completes but is shown as complete.

**Why it happens:** The current implementation stores state in:
- `UserDefaults` (local): `onboarding_complete`, `onboarding_current_step`, `onboarding_start_time`
- Backend `profiles` table: `onboarding_complete`, `onboarding_step`

Sync failures, offline usage, or timing issues can cause divergence:
- Network error when updating backend, but local updated
- New device with no local state but backend says complete
- Backend updated but local cache not cleared

**Consequences:**
- Users see onboarding after completing it
- Users skip onboarding on new device (local empty, backend complete)
- Analytics show same user completing onboarding multiple times
- Inconsistent experience across devices

**Prevention:**

1. **Single Source of Truth with Local Cache:**
   Backend is the authoritative source. Local is ONLY a fast-path cache:
   ```swift
   // Read: Check local cache first for speed
   func isOnboardingComplete() -> Bool {
       // Fast path: local cache
       if UserDefaults.standard.bool(forKey: "onboarding_complete") {
           return true
       }
       return false  // Will verify with backend async
   }

   // Write: Backend first, then update local on success
   func completeOnboarding() async throws {
       try await profileService.completeOnboarding()  // Backend first
       UserDefaults.standard.set(true, forKey: "onboarding_complete")  // Cache after success
   }
   ```

2. **Clear Local Cache on Sign In:**
   When a user signs in (especially on new device), fetch fresh state from backend:
   ```swift
   func handleSignIn() async {
       // Always fetch fresh profile on sign in
       let profile = try await profileService.fetchProfile()
       UserDefaults.standard.set(profile.onboardingComplete, forKey: "onboarding_complete")
   }
   ```

3. **Idempotent Completion:**
   Backend should accept duplicate completion calls gracefully:
   ```swift
   // Backend: Update if not already complete, no error if already complete
   func completeOnboarding() async {
       // This should be safe to call multiple times
       try await profileService.completeOnboarding()
       UserDefaults.standard.set(true, forKey: "onboarding_complete")
   }
   ```

4. **Clear All Local State on Sign Out:**
   The current `handleSignOut()` in OnboardingViewModel does this correctly.

**Detection:**
- Users see onboarding after completing it previously
- Analytics show same user completing onboarding multiple times
- Support tickets about "stuck in onboarding"
- Inconsistent state between devices logged into same account

**Which phase should address:** Phase 1 (State Management Foundation)

---

### Pitfall 7: NotificationCenter for View Routing

**What goes wrong:** Using `NotificationCenter` to communicate between views creates implicit dependencies, race conditions, and makes debugging difficult.

**Why it happens:** Current code posts `Notification.Name.onboardingCompleted`:
```swift
// In OnboardingContainerView and OnboardingViewModel
NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
```

And observes it:
```swift
// In ContentView
.onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
    withAnimation {
        onboardingComplete = true
    }
}
```

**Consequences:**
- Notifications can be missed if observer not attached yet
- Multiple observers can cause duplicate handling
- Hard to debug timing issues (no call stack, no types)
- No type safety (notification could carry wrong data)
- Difficult to trace code flow during debugging
- Race conditions if notification fires before view is ready

**Prevention:**

1. **Use Shared Observable State:**
   ```swift
   @Observable
   class AppRouter {
       var route: AppRoute = .loading

       func completeOnboarding() {
           route = .authenticated
       }
   }

   // Inject via Environment
   struct ContentView: View {
       @Environment(AppRouter.self) var router

       var body: some View {
           switch router.route {
           case .loading: LoadingView()
           case .onboarding(let step): OnboardingView(step: step)
           case .authenticated: MainTabView()
           }
       }
   }
   ```

2. **Callback Pattern for Parent-Child Communication:**
   Pass completion handlers explicitly:
   ```swift
   OnboardingContainerView(onComplete: {
       withAnimation {
           route = .authenticated
       }
   })
   ```

3. **If NotificationCenter Must Be Used:**
   Use typed notifications with Combine:
   ```swift
   // Typed notification
   extension Notification.Name {
       static let onboardingCompleted = Notification.Name("onboardingCompleted")
   }

   // With type safety
   struct OnboardingCompletedNotification {
       let userId: String
   }
   ```

**Detection:**
- Intermittent failures where onboarding completion not detected
- Debug logs show notification posted but not received
- Race conditions on app launch
- Hard to trace why view state changed

**Which phase should address:** Phase 1 (State Management Foundation)

---

### Pitfall 8: Missing Accessibility Support

**What goes wrong:** Onboarding is unusable or frustrating for users with VoiceOver, Dynamic Type, or Reduce Motion settings.

**Why it happens:** Focus on visual design without accessibility testing. Assuming onboarding is "simple enough" to not need accessibility work.

**Consequences:**
- VoiceOver users cannot complete onboarding
- Text clips or overlaps with large text sizes
- Animations cause motion sickness for sensitive users
- App Store rejection possible for accessibility violations
- Legal liability in some jurisdictions

**Prevention:**

1. **VoiceOver Labels:**
   ```swift
   Button("Continue") { }
       .accessibilityLabel("Continue to next step")
       .accessibilityHint("Double tap to proceed to account creation")
   ```

2. **Respect Reduce Motion:**
   ```swift
   @Environment(\.accessibilityReduceMotion) var reduceMotion

   .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: step)
   ```

3. **Support Dynamic Type:**
   Use `@ScaledMetric` for custom sizes:
   ```swift
   @ScaledMetric(relativeTo: .title) var iconSize = 60.0

   Image(systemName: "star")
       .font(.system(size: iconSize))
   ```

4. **Test with Accessibility Inspector:**
   Run Accessibility Inspector during development. Test with VoiceOver enabled.

5. **Ensure Sufficient Color Contrast:**
   Use Apple's Color Contrast Calculator or built-in accessibility audit.

**Detection:**
- Accessibility audit in Xcode fails
- VoiceOver users cannot complete onboarding
- Text clips or overlaps with large text sizes
- App Store review mentions accessibility issues

**Which phase should address:** Phase 2 (Visual Design and Animations) - accessibility is integral to polish

---

## Minor Pitfalls

Mistakes that cause annoyance but are quickly fixable.

### Pitfall 9: Hardcoded Strings

**What goes wrong:** UI strings are hardcoded, making localization difficult, terminology inconsistent, and updates tedious.

**Prevention:**
Use String Catalog from the start:
```swift
Text("Welcome to Trendy", comment: "Onboarding welcome screen title")
// or
Text(String(localized: "welcome_title"))
```

**Which phase should address:** Phase 2 (Visual Design)

---

### Pitfall 10: Missing Loading State on Buttons

**What goes wrong:** User taps "Continue" or "Sign Up" but nothing visibly happens during async operations. User taps again, causing duplicate submissions.

**Prevention:**
Always show loading state and disable during async operations:
```swift
Button {
    await action()
} label: {
    if isLoading {
        ProgressView()
            .tint(.white)
    } else {
        Text("Continue")
    }
}
.disabled(isLoading)
```

The current Trendy implementation does this correctly in most places (verified in `OnboardingAuthView`, `CreateEventTypeView`, `LogFirstEventView`).

**Which phase should address:** Already implemented - verify during Phase 2

---

### Pitfall 11: Keyboard Handling in Auth Forms

**What goes wrong:** Keyboard covers input fields, submit button not visible, no way to dismiss keyboard, Enter key doesn't submit form.

**Prevention:**
```swift
Form {
    TextField("Email", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .submitLabel(.next)

    SecureField("Password", text: $password)
        .textContentType(.password)
        .submitLabel(.done)
}
.scrollDismissesKeyboard(.interactively)
.onSubmit {
    if isFormValid {
        await submit()
    }
}
```

**Which phase should address:** Phase 2 (Visual Design)

---

### Pitfall 12: Back Button Inconsistency

**What goes wrong:** Back navigation behavior is inconsistent - sometimes goes back a step, sometimes not available, sometimes exits onboarding entirely.

**Prevention:**
Define clear back navigation rules in `OnboardingStep`:
```swift
var canGoBack: Bool {
    previous != nil
}

var previous: OnboardingStep? {
    switch self {
    case .welcome: return nil
    case .auth: return .welcome
    case .createEventType: return nil  // Can't go back after auth
    case .logFirstEvent: return .createEventType
    case .permissions: return .logFirstEvent
    case .finish: return nil
    }
}
```

The current implementation has this, but the `previous` logic might need review for the new flow order.

**Which phase should address:** Phase 1 (if flow order changes) or Phase 2 (visual consistency)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| State Management | UI Flash (Pitfall 1) | Implement enum-based routing with synchronous fast-path |
| State Management | Multiple Loading (Pitfall 2) | Single loading screen matching Launch Screen |
| State Management | Duplicate Initialization (Pitfall 3) | Use `@State` guard or custom `onFirstAppear` |
| State Management | NotificationCenter Race (Pitfall 7) | Replace with shared Observable state |
| State Management | State Sync (Pitfall 6) | Backend as source of truth, local as cache only |
| Visual Design | ZStack Glitches (Pitfall 5) | Use explicit zIndex or NavigationStack |
| Visual Design | Missing Accessibility (Pitfall 8) | Test with VoiceOver throughout development |
| Visual Design | Keyboard Handling (Pitfall 11) | Add scroll dismiss and submit handling |
| Permissions | High Denial Rates (Pitfall 4) | Two-step opt-in, contextual requests |

---

## Specific Recommendations for Trendy

Based on analysis of the current codebase:

### Immediate Fix for Flash Issue

The flash occurs because `ContentView` uses separate state variables that can update independently:
- `onboardingComplete` (async check from UserDefaults/backend)
- `hasCheckedOnboarding` (set after async check)
- `authViewModel.isAuthenticated` (from SupabaseService session restore)

**Root Cause:** In `trendyApp.init()`, session restore happens in a detached Task:
```swift
Task {
    await supabase.restoreSession()
    // ...
}
```

This can complete DURING or AFTER `ContentView.checkOnboardingStatus()`, causing the race.

**Solution:** Consolidate into single `AppRouter` with atomic state:

```swift
@Observable
class AppRouter {
    enum Route: Equatable {
        case loading
        case onboarding(step: OnboardingStep)
        case authenticated
    }

    private(set) var currentRoute: Route = .loading

    func determineRoute(supabaseService: SupabaseService) async {
        // 1. Restore session first (if not already done)
        await supabaseService.restoreSession()

        // 2. Synchronous fast path
        if UserDefaults.standard.bool(forKey: "onboarding_complete")
           && supabaseService.isAuthenticated {
            currentRoute = .authenticated
            return
        }

        // 3. Full async check if fast path failed
        if supabaseService.isAuthenticated {
            // Fetch profile from backend
            let profileService = ProfileService(supabaseService: supabaseService)
            if let profile = try? await profileService.fetchProfile(),
               profile.onboardingComplete {
                UserDefaults.standard.set(true, forKey: "onboarding_complete")
                currentRoute = .authenticated
                return
            }
            // Authenticated but onboarding incomplete
            currentRoute = .onboarding(step: .createEventType)
        } else {
            // Not authenticated
            currentRoute = .onboarding(step: .welcome)
        }
    }
}
```

### Remove NotificationCenter for Routing

Replace:
```swift
NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
```

With direct state update:
```swift
router.currentRoute = .authenticated
```

### Consider Moving Permissions Out of Onboarding

The permissions step has low value during onboarding because:
- Users don't yet understand why they need these permissions
- Denial rates are high for "cold" permission requests
- Each permission serves a different feature

Consider:
1. **Remove from onboarding flow entirely**
2. **Prompt contextually** when feature is first used:
   - Location: When creating first geofence
   - Notifications: When enabling any notification-based feature
   - HealthKit: When tapping to enable in Settings
3. **Use "Setup Checklist"** post-onboarding for optional enhancements

---

## Onboarding Quality Checklist

Before shipping, verify:

- [ ] **No flash for returning users** - Kill app, relaunch, verify no onboarding screens shown
- [ ] **Single loading screen** - No visible transitions between loading states
- [ ] **Analytics accurate** - Only one "onboarding_started" per new user
- [ ] **Back navigation consistent** - Every step with back button works correctly
- [ ] **VoiceOver works** - Complete onboarding with VoiceOver enabled
- [ ] **Dynamic Type works** - Test with largest text size
- [ ] **Reduce Motion respected** - Animations disabled when setting enabled
- [ ] **Keyboard handling** - Forms scroll, dismiss works, Enter submits
- [ ] **Offline handling** - Graceful behavior when network unavailable
- [ ] **State persisted** - Kill during onboarding, relaunch, resume from correct step

---

## Sources

### Primary (HIGH confidence - Official Documentation and Verified Patterns)
- [Swift by Sundell - Handling loading states within SwiftUI views](https://www.swiftbysundell.com/articles/handling-loading-states-in-swiftui/)
- [Apple Developer - Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Fatbobman - Mastering the SwiftUI task Modifier](https://fatbobman.com/en/posts/mastering_swiftui_task_modifier/)
- [SwiftLee - Launch screens in Xcode](https://www.avanderlee.com/xcode/launch-screen/)
- [SwiftLee - @AppStorage explained](https://www.avanderlee.com/swift/appstorage-explained/)

### Secondary (MEDIUM confidence - Community Best Practices)
- [DEV Community - SwiftUI App Lifecycle Mastery](https://dev.to/sebastienlato/swiftui-app-lifecycle-mastery-scene-phases-background-tasks-state-44ao)
- [Holy Swift - Triggering Actions Solely on First View Appearance](https://holyswift.app/triggering-an-action-only-first-time-a-view-appears-in-swiftui/)
- [Medium - Fix SwiftUI onAppear Firing Infinity](https://medium.com/apps-2-develop/fix-swiftui-onappear-firing-infinity-the-fast-ios-17-ios-16-fix-4e0758223333)
- [Medium - ZStack Transition Animation Problems](https://medium.com/@balzsorbn/swiftui-how-to-solve-transition-animation-problems-in-zstack-beb8eab5eb2)
- [Rivera Labs - Building a Better Onboarding Flow in SwiftUI for iOS 18+](https://www.riveralabs.com/blog/swiftui-onboarding/)

### Permission Priming Best Practices
- [UserOnboard - Permission Priming Patterns](https://www.useronboard.com/onboarding-ux-patterns/permission-priming/)
- [Appcues - Mobile Permission Priming Strategies](https://www.appcues.com/blog/mobile-permission-priming)
- [Hurree - iOS Push Notification Permissions Best Practices](https://blog.hurree.co/ios-push-notification-permissions-best-practises)

### Tertiary (Verified Against Trendy Codebase)
- `trendy/ContentView.swift` - Current routing logic with race condition
- `trendy/trendyApp.swift` - Session restore in detached Task
- `trendy/ViewModels/OnboardingViewModel.swift` - State management and NotificationCenter usage
- `trendy/Views/Onboarding/OnboardingContainerView.swift` - Nested loading state
- `trendy/Models/Onboarding/OnboardingStep.swift` - Flow definition
