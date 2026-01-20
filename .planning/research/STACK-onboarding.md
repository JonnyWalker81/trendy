# Technology Stack: iOS Onboarding Improvements

**Project:** Trendy iOS Onboarding Polish
**Researched:** 2026-01-19
**Overall Confidence:** HIGH (native SwiftUI patterns, existing codebase analysis)

## Executive Summary

The existing Trendy iOS app already has a solid onboarding foundation with proper state management via `UserDefaults` and a well-structured `OnboardingViewModel` state machine. The improvements needed are primarily **refinements to existing patterns**, not wholesale replacements. This research recommends staying with native SwiftUI animations rather than adding third-party dependencies.

## Recommended Stack

### State Management (Existing - Enhance)

| Technology | Version | Purpose | Recommendation |
|------------|---------|---------|----------------|
| `UserDefaults` | Native | Onboarding completion flag, step persistence | **KEEP** - Already implemented correctly |
| `@AppStorage` | iOS 14+ | Reactive state binding for simple values | **ADD** for view-level reactivity |
| `@Observable` (Observation) | iOS 17+ | ViewModel state | **KEEP** - Already using correctly |

**Rationale:**

The current implementation uses `UserDefaults` directly in the `OnboardingViewModel` with three keys:
- `onboarding_current_step` - Step persistence
- `onboarding_start_time` - Analytics timing
- `onboarding_complete` - Completion flag

This is the correct pattern for onboarding state. `@AppStorage` would add value for simple view-level bindings but shouldn't replace the ViewModel's direct `UserDefaults` access since the ViewModel needs to coordinate writes with backend profile updates.

**What NOT to change:**
- Do NOT move to Keychain for onboarding state - Keychain is for secrets, not app state
- Do NOT use SwiftData for onboarding flags - overkill for simple boolean state
- Do NOT use `@SceneStorage` - persists per-scene, not per-app

### Animation (Native SwiftUI - Enhance)

| Technology | Version | Purpose | Recommendation |
|------------|---------|---------|----------------|
| SwiftUI Animations | Native | Basic transitions | **ENHANCE** with modern APIs |
| `PhaseAnimator` | iOS 17+ | Multi-phase sequential animations | **ADD** for onboarding step transitions |
| `KeyframeAnimator` | iOS 17+ | Complex keyframe-based animations | **ADD** for attention-seeking elements |
| `.spring()` animations | Native | Physics-based motion | **KEEP** - Already used well |

**Rationale:**

Current animations use basic `.animation()` and `withAnimation()` which work but feel dated. iOS 17 introduced `PhaseAnimator` and `KeyframeAnimator` which are perfect for onboarding:

- **PhaseAnimator**: Ideal for step-by-step animations like permission cards cycling through states, or welcome screen feature highlights appearing sequentially
- **KeyframeAnimator**: Perfect for hero animations like the checkmark celebration on the finish screen

**What NOT to add:**
- **Lottie** - Adds ~2MB to binary, requires After Effects workflow, native SwiftUI animations are sufficient for onboarding
- **Rive** - More powerful but excessive for simple onboarding animations
- **Spring (library)** - Redundant with native SwiftUI springs

**Trade-off acknowledged:** Lottie would enable more complex designer-driven animations, but:
1. Trendy's onboarding doesn't require designer-authored vector animations
2. Native SwiftUI `PhaseAnimator` + `KeyframeAnimator` can achieve polished results
3. Avoiding dependencies reduces app size and maintenance burden

### Permission Flow (Native - Restructure)

| Technology | Version | Purpose | Recommendation |
|------------|---------|---------|----------------|
| `UNUserNotificationCenter` | Native | Notification permission | **KEEP** |
| `CoreLocation` | Native | Location permission | **KEEP** |
| `HealthKit` | Native | Health data permission | **KEEP** |
| Custom Pre-Permission UI | SwiftUI | Context before system prompt | **ADD** - Enhance existing cards |

**Rationale:**

The current `PermissionsView` already implements pre-permission "cards" before system prompts, which is best practice. However, the UX can be enhanced:

1. **Contextual timing**: Currently all permissions are requested in sequence during onboarding. Consider moving non-critical permissions (HealthKit) to first-use-of-feature.
2. **Permission priming**: The current cards explain "what" but could better explain "why" with concrete benefit examples.
3. **Progressive disclosure**: Consider showing "Not Now" more prominently and deferring to settings.

**Permission Request Order (if kept in onboarding):**
1. **Notifications** (FIRST) - Lowest friction, highest grant rate, immediate value
2. **Location** - Higher friction but core to geofencing feature
3. **HealthKit** - CONSIDER DEFERRING to first HealthKit feature use (optional)

### Auth Integration (Existing - No Changes)

| Technology | Version | Purpose | Recommendation |
|------------|---------|---------|----------------|
| Supabase Swift SDK | 2.0+ | Authentication | **KEEP** - Working well |
| `SupabaseService` | Custom | Auth wrapper | **KEEP** - Clean abstraction |
| Google Sign-In | Latest | Social auth | **KEEP** - Already integrated |

**No changes needed.** The auth flow is already well-integrated with onboarding via `OnboardingViewModel.signUp()`, `signIn()`, and `signInWithGoogle()`.

## Patterns to Implement

### 1. First-Run Detection Pattern

**Current (Good):**
```swift
// In ContentView
if UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey) {
    onboardingComplete = true
}
```

**Enhanced (Better View Reactivity):**
```swift
// For view-level reactivity to state changes
@AppStorage("onboarding_complete") private var onboardingComplete = false

// Keep UserDefaults direct access in ViewModel for write coordination
UserDefaults.standard.set(true, forKey: Self.localCompleteKey)
```

**Why:** `@AppStorage` provides automatic SwiftUI view updates when the value changes, eliminating the need for manual state synchronization via `NotificationCenter.default.post(name: .onboardingCompleted, ...)`.

### 2. Step Transition Animation Pattern

**Current:**
```swift
.animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
```

**Enhanced with PhaseAnimator:**
```swift
enum TransitionPhase: CaseIterable {
    case initial, active, complete
}

PhaseAnimator(TransitionPhase.allCases, trigger: viewModel.currentStep) { phase in
    StepContent(viewModel: viewModel)
        .opacity(phase == .initial ? 0 : 1)
        .offset(x: phase == .initial ? 50 : 0)
        .scaleEffect(phase == .complete ? 1.0 : 0.95)
} animation: { phase in
    switch phase {
    case .initial: .easeOut(duration: 0.1)
    case .active: .spring(response: 0.4, dampingFraction: 0.8)
    case .complete: .spring(response: 0.3, dampingFraction: 0.9)
    }
}
```

### 3. Celebration Animation Pattern (Finish Screen)

**Current:**
```swift
.scaleEffect(showCheckmark ? 1.0 : 0.5)
.animation(.spring(response: 0.6, dampingFraction: 0.7), value: showCheckmark)
```

**Enhanced with KeyframeAnimator:**
```swift
struct CelebrationKeyframes {
    var scale: Double = 0.3
    var rotation: Double = -30
    var opacity: Double = 0
}

KeyframeAnimator(initialValue: CelebrationKeyframes(), trigger: showCheckmark) { value in
    CheckmarkCircle()
        .scaleEffect(value.scale)
        .rotationEffect(.degrees(value.rotation))
        .opacity(value.opacity)
} keyframes: { _ in
    KeyframeTrack(\.scale) {
        SpringKeyframe(1.2, duration: 0.4, spring: .bouncy)
        SpringKeyframe(1.0, duration: 0.2, spring: .smooth)
    }
    KeyframeTrack(\.rotation) {
        LinearKeyframe(0, duration: 0.3)
    }
    KeyframeTrack(\.opacity) {
        LinearKeyframe(1.0, duration: 0.2)
    }
}
```

### 4. Permission Pre-Prompt Pattern

**Enhanced Card with Contextual Benefits:**
```swift
struct PermissionCard: View {
    let permission: OnboardingPermissionType

    var body: some View {
        VStack(spacing: 20) {
            // Animated icon with PhaseAnimator for attention
            PhaseAnimator([false, true], trigger: true) { isHighlighted in
                Image(systemName: permission.iconName)
                    .symbolEffect(.bounce, options: .repeat(2), value: isHighlighted)
            }

            // Value proposition (new)
            Text(permission.benefitStatement)  // "Track workouts automatically"
                .font(.headline)

            // Existing description
            Text(permission.promptDescription)

            // Visual preview of feature (new)
            FeaturePreviewImage(for: permission)
        }
    }
}
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Animation | Native SwiftUI | Lottie | Binary size (+2MB), After Effects dependency, overkill for onboarding |
| Animation | Native SwiftUI | Rive | Complex tooling, not needed for simple onboarding flows |
| State | UserDefaults | SwiftData | Overkill for boolean flags |
| State | UserDefaults | Keychain | Keychain is for secrets, not app state |
| State | @Observable | Combine | @Observable is simpler, already iOS 17+ |

## Installation

No new dependencies required. All recommended technologies are native SwiftUI available in iOS 17+.

**Existing dependencies (unchanged):**
- Supabase Swift SDK (authentication)
- PostHog (analytics)
- GoogleSignIn (social auth)

## Integration Notes

### Compatibility with Existing Code

1. **OnboardingViewModel**: No structural changes needed - enhance animation output only
2. **OnboardingContainerView**: Add PhaseAnimator wrapper around step transitions
3. **PermissionsView**: Enhance card animations, consider deferring HealthKit
4. **OnboardingFinishView**: Replace manual animation state with KeyframeAnimator

### Migration Path

Since this is enhancement (not replacement), changes can be incremental:
1. Phase 1: Add `@AppStorage` for reactive state in views
2. Phase 2: Replace basic animations with PhaseAnimator/KeyframeAnimator
3. Phase 3: Enhance permission pre-prompts with benefit messaging
4. Phase 4: Consider contextual (deferred) permission requests

### Testing Considerations

- Test animation performance on older devices (iPhone 12, iPhone SE)
- Verify `@AppStorage` correctly syncs with `UserDefaults` writes from ViewModel
- Test returning user flow (onboarding already complete)
- Test permission denial flows and "Not Now" paths

## Sources

### SwiftUI Animation
- [Apple WWDC23: Wind your way through advanced animations in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10157/)
- [Apple Documentation: Controlling the timing and movements of your animations](https://developer.apple.com/documentation/SwiftUI/Controlling-the-timing-and-movements-of-your-animations)
- [AppCoda: Creating Advanced Animations with KeyframeAnimator](https://www.appcoda.com/keyframeanimator/)
- [SwiftUI Lab: PhaseAnimator](https://swiftui-lab.com/swiftui-animations-part7/)
- [Exyte: Keyframe Animations for iOS 17](https://exyte.com/blog/keyframes-ios17)

### State Management
- [Apple Documentation: AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)
- [Hacking with Swift: @AppStorage property wrapper](https://www.hackingwithswift.com/quick-start/swiftui/what-is-the-appstorage-property-wrapper)
- [Medium: Best Practices for @AppStorage](https://medium.com/@ramdhas/mastering-swiftui-best-practices-for-efficient-user-preference-management-with-appstorage-cf088f4ca90c)

### Permission UX
- [Apple HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [UserOnboard: Permission Priming](https://www.useronboard.com/onboarding-ux-patterns/permission-priming/)
- [Appcues: Mobile Permission Priming](https://www.appcues.com/blog/mobile-permission-priming)
- [DogTown Media: Mobile Permission Requests Guide](https://www.dogtownmedia.com/the-ask-when-and-how-to-request-mobile-app-permissions-camera-location-contacts/)

### Animation Libraries (Evaluated, Not Recommended)
- [Lottie iOS](https://github.com/airbnb/lottie-ios) - Evaluated but not recommended for this use case
- [Rive vs Lottie 2025](https://dev.to/uianimation/rive-vs-lottie-which-animation-tool-should-you-use-in-2025-p4m) - Comparison reference

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| State Management | HIGH | Existing implementation is correct, enhancements are minor |
| Animation Approach | HIGH | Apple's official APIs, verified with WWDC sessions |
| Permission Timing | MEDIUM | UX best practices well-documented, but specific order depends on analytics |
| Third-Party Avoidance | HIGH | Analyzed Lottie/Rive, native SwiftUI sufficient for scope |

## Summary

**Key recommendations:**
1. Stay native - no new third-party animation libraries needed
2. Adopt iOS 17 animation APIs (`PhaseAnimator`, `KeyframeAnimator`) for polish
3. Add `@AppStorage` for view-level state reactivity
4. Enhance permission cards with benefit messaging and visual previews
5. Consider deferring HealthKit permission to first feature use

**The existing stack is sound.** This is an enhancement exercise, not a rebuild.
