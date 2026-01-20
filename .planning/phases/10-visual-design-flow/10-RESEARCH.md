# Phase 10: Visual Design & Flow - Research

**Researched:** 2026-01-20
**Domain:** SwiftUI animations, onboarding UX, iOS permission handling
**Confidence:** HIGH

## Summary

This phase redesigns the existing onboarding flow with modern visual design, polished animations, and proper permission priming screens. The existing codebase already has a functional 6-step onboarding (welcome -> auth -> createEventType -> logFirstEvent -> permissions -> finish), but lacks visual polish and proper flow ordering per requirements.

The recommended approach uses iOS 17+ animation APIs (PhaseAnimator for multi-step transitions, spring animations for snappy feel), a horizontal slide navigation pattern with swipe gestures, and a progress bar indicator. For celebration, ConfettiSwiftUI provides a mature, customizable solution with built-in haptic feedback.

**Primary recommendation:** Refactor OnboardingContainerView to use a horizontal scroll/page pattern with PhaseAnimator-driven transitions, replacing the current switch-based navigation with animated horizontal slides and swipe gestures.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 17+ | UI framework | Native, required for PhaseAnimator/KeyframeAnimator |
| PhaseAnimator | iOS 17+ | Multi-step transitions | Apple's official solution for complex animations |
| Spring animation | iOS 17+ | Bouncy transitions | Native, snappy iOS feel |
| sensoryFeedback | iOS 17+ | Haptic feedback | Native modifier, clean API |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ConfettiSwiftUI | 2.0.3 | Celebration animation | Onboarding completion |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ConfettiSwiftUI | SPConfetti | SPConfetti has delegate callbacks but more UIKit-based |
| ConfettiSwiftUI | Lottie | Lottie more flexible but requires JSON asset creation |
| PhaseAnimator | KeyframeAnimator | KeyframeAnimator better for precise timing, PhaseAnimator simpler for discrete states |

**Installation:**
```bash
# Add via Swift Package Manager
# https://github.com/simibac/ConfettiSwiftUI
```

## Architecture Patterns

### Current File Structure
```
apps/ios/trendy/
├── Models/Onboarding/
│   ├── OnboardingStep.swift           # Enum state machine (6 steps)
│   ├── OnboardingAnalytics.swift      # Analytics events
│   ├── EventTypeTemplate.swift        # Predefined templates
│   └── API/APIOnboardingStatus.swift
├── Services/
│   ├── OnboardingCache.swift          # UserDefaults caching
│   ├── OnboardingStatusService.swift  # Backend sync
│   └── AppRouter.swift                # Route state machine
├── ViewModels/
│   └── OnboardingViewModel.swift      # Flow coordinator
└── Views/Onboarding/
    ├── OnboardingContainerView.swift  # Container + navigation
    ├── WelcomeView.swift              # Step 1
    ├── OnboardingAuthView.swift       # Step 2
    ├── CreateEventTypeView.swift      # Step 3
    ├── LogFirstEventView.swift        # Step 4
    ├── PermissionsView.swift          # Step 5
    └── OnboardingFinishView.swift     # Step 6
```

### Recommended Redesign Structure
```
apps/ios/trendy/Views/Onboarding/
├── OnboardingContainerView.swift     # REDESIGN: horizontal page navigation
├── Components/
│   ├── OnboardingProgressBar.swift   # NEW: progress bar indicator
│   ├── OnboardingHeroView.swift      # NEW: reusable hero layout
│   └── PermissionPrimingCard.swift   # NEW: permission priming full screen
├── Screens/
│   ├── WelcomeScreen.swift           # REDESIGN: hero layout
│   ├── AuthScreen.swift              # REDESIGN: hero layout
│   ├── NotificationPrimingScreen.swift  # NEW: dedicated priming
│   ├── LocationPrimingScreen.swift      # NEW: dedicated priming
│   └── CompletionScreen.swift        # REDESIGN: confetti celebration
└── OnboardingFinishView.swift        # Keep for backward compat or remove
```

### Pattern 1: PhaseAnimator for Screen Transitions
**What:** Use PhaseAnimator to coordinate multi-element animations during transitions
**When to use:** When transitioning between onboarding screens with staggered element animations
**Example:**
```swift
// Source: https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-multi-step-animations-using-phase-animators
enum OnboardingTransitionPhase: CaseIterable {
    case hidden, appearing, visible
}

.phaseAnimator(OnboardingTransitionPhase.allCases, trigger: screenIndex) { content, phase in
    content
        .opacity(phase == .hidden ? 0 : 1)
        .offset(y: phase == .hidden ? 20 : 0)
} animation: { phase in
    switch phase {
    case .hidden: .easeOut(duration: 0.1)
    case .appearing: .spring(response: 0.3, dampingFraction: 0.7)
    case .visible: .easeOut
    }
}
```

### Pattern 2: Horizontal Swipe Navigation
**What:** TabView with page style or ScrollView with scrollPosition for swipe navigation
**When to use:** Navigation between onboarding screens
**Example:**
```swift
// Source: https://www.riveralabs.com/blog/swiftui-onboarding/
@State private var currentPage: OnboardingStep = .welcome

ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack(spacing: 0) {
        ForEach(OnboardingStep.allCases, id: \.self) { step in
            stepView(for: step)
                .frame(width: UIScreen.main.bounds.width)
                .id(step)
        }
    }
}
.scrollPosition(id: $currentPage)
.scrollTargetBehavior(.paging)
.scrollDisabled(!allowSwipeNavigation) // Control when swipe is enabled
```

### Pattern 3: Spring Animation for Snappy Transitions
**What:** Use spring animations with low response time for iOS-native feel
**When to use:** Button taps, screen transitions
**Example:**
```swift
// Per CONTEXT.md: 0.2-0.3s duration, spring animation curve
// Source: https://github.com/GetStream/swiftui-spring-animations
.animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentStep)

// iOS 17+ alternative syntax:
.animation(.spring(duration: 0.25, bounce: 0.3), value: currentStep)
```

### Pattern 4: Progress Bar Component
**What:** Animated progress bar at top of screen
**When to use:** All onboarding screens to show progress
**Example:**
```swift
// Source: https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/1-animate-a-progress-bar-in-swiftui
struct OnboardingProgressBar: View {
    let progress: Double // 0.0 to 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track (unfilled)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.dsBorder)

                // Fill (progress)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.dsPrimary)
                    .frame(width: geometry.size.width * progress)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 4) // Thin bar per CONTEXT.md
    }
}
```

### Pattern 5: Hero Layout with SF Symbols
**What:** Full-bleed hero with large SF Symbol and gradient background
**When to use:** Every onboarding screen per CONTEXT.md decision
**Example:**
```swift
struct OnboardingHeroView: View {
    let symbolName: String
    let gradientColors: [Color]

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // SF Symbol with glow effect
            Image(systemName: symbolName)
                .font(.system(size: 80, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.5), radius: 20)
        }
        .frame(height: 280)
    }
}
```

### Anti-Patterns to Avoid
- **Instant cuts between screens:** Always animate transitions, never use instant state changes
- **Tab-based navigation without swipe control:** TabView alone doesn't give enough control over when swipes are allowed
- **Multiple permission requests on one screen:** Each permission should have its own priming screen
- **Manipulative permission UI:** Apple forbids rewards, misleading visuals, or psychological nudges

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Confetti celebration | Custom particle system | ConfettiSwiftUI | Physics, performance, haptics all handled |
| Haptic feedback | UIFeedbackGenerator manually | .sensoryFeedback modifier | iOS 17+ native, cleaner API |
| Progress indicator animation | Manual frame/offset tweening | .animation with spring | Spring physics built-in |
| Multi-step animations | Chained withAnimation blocks | PhaseAnimator | Apple's solution, handles phase coordination |

**Key insight:** iOS 17 introduced PhaseAnimator and sensoryFeedback specifically to replace complex manual animation code. Use them.

## Common Pitfalls

### Pitfall 1: Gesture Conflicts in iOS 18
**What goes wrong:** Horizontal swipe gestures conflict with navigation back gesture or ScrollView
**Why it happens:** iOS 18 changed gesture priority behavior
**How to avoid:** Use `.simultaneousGesture` instead of `.gesture`, or use SwiftUIIntrospect to manage UIKit gesture recognizers
**Warning signs:** Swipe navigation stops working intermittently, back gesture doesn't work

### Pitfall 2: Permission Priming Rejection
**What goes wrong:** App Store rejection for manipulative permission screens
**Why it happens:** Apple forbids UI that manipulates users into granting permissions
**How to avoid:**
- Use subtle "Skip" option (not hidden but not prominent)
- Don't use rewards language ("Get 10% off by enabling...")
- Explain benefit honestly, not manipulatively
- Button text should be explicit: "Enable Notifications" not "Continue"
**Warning signs:** Using "Continue" button that actually triggers permission, hiding skip option

### Pitfall 3: Animation Chaining Without Coordination
**What goes wrong:** Elements animate out of sync, visual jank
**Why it happens:** Multiple independent .animation modifiers don't coordinate
**How to avoid:** Use PhaseAnimator for multi-element coordination, or use explicit withAnimation blocks with shared completion
**Warning signs:** Hero image starts moving before text fades out

### Pitfall 4: Progress Bar Not Matching Step Count
**What goes wrong:** Progress bar shows 6 steps but flow has been reordered
**Why it happens:** Hardcoded step count doesn't match OnboardingStep enum
**How to avoid:** Derive step count from OnboardingStep.allCases.count, map step to progress dynamically
**Warning signs:** Progress bar shows 4/6 when user is on last screen

### Pitfall 5: Flash of Loading State on Cache Hit
**What goes wrong:** User sees brief loading spinner before content
**Why it happens:** determineInitialRoute() not called before body renders
**How to avoid:** Per existing CONTEXT.md design, route determination is synchronous and cache-first. Maintain this pattern in onboarding container.
**Warning signs:** Loading view visible for 100-200ms on app launch

## Code Examples

Verified patterns from official sources:

### Haptic Feedback on Button Tap
```swift
// Source: https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-haptic-effects-using-sensory-feedback
@State private var stepAdvanced = 0

Button("Continue") {
    stepAdvanced += 1
    advanceToNextStep()
}
.sensoryFeedback(.impact(weight: .medium), trigger: stepAdvanced)
```

### ConfettiSwiftUI Integration
```swift
// Source: https://github.com/simibac/ConfettiSwiftUI
import ConfettiSwiftUI

@State private var confettiTrigger = 0

VStack {
    // Content...
}
.confettiCannon(
    trigger: $confettiTrigger,
    num: 50,
    colors: [.dsChart1, .dsChart2, .dsChart3, .dsChart4],
    confettiSize: 10,
    radius: 300,
    hapticFeedback: true
)
.onAppear {
    confettiTrigger += 1
}
```

### Permission Priming Screen Structure
```swift
// Source: Apple HIG + CONTEXT.md decisions
struct PermissionPrimingScreen: View {
    let permission: OnboardingPermissionType
    let onEnable: () async -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            OnboardingProgressBar(progress: progressForStep)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            // Hero area with SF Symbol
            OnboardingHeroView(
                symbolName: permission.iconName,
                gradientColors: [.dsPrimary, .dsAccent]
            )

            Spacer()

            // Content area
            VStack(spacing: 16) {
                Text(permission.promptTitle)
                    .font(.title)
                    .fontWeight(.bold)

                Text(permission.promptDescription)
                    .font(.body)
                    .foregroundStyle(Color.dsMutedForeground)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Actions pinned at bottom
            VStack(spacing: 16) {
                Button("Enable \(permission.displayName)") {
                    Task { await onEnable() }
                }
                .buttonStyle(.primary)

                // Subtle skip as text link per CONTEXT.md
                Button {
                    onSkip()
                } label: {
                    Text("Skip for now")
                        .font(.footnote)
                        .foregroundStyle(Color.dsMutedForeground)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color.dsBackground)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| withAnimation chaining | PhaseAnimator | iOS 17 (2023) | Simpler multi-step animations |
| UIFeedbackGenerator | .sensoryFeedback modifier | iOS 17 (2023) | Declarative haptics |
| spring(response:dampingFraction:) | spring(duration:bounce:) | iOS 17 (2023) | More intuitive parameters |
| TabView for onboarding | ScrollView + scrollPosition | iOS 17+ | Better control over flow |

**Deprecated/outdated:**
- **Dots-based progress indicator:** Per CONTEXT.md decision, use progress bar instead
- **Multiple permissions on one screen:** Should be separate screens with priming

## Open Questions

Things that couldn't be fully resolved:

1. **Swipe-to-go-back on Auth screen**
   - What we know: CONTEXT.md says "Swipe gestures enabled for navigation (both directions)"
   - What's unclear: Should user be able to swipe back from Auth to Welcome? OnboardingStep.previous returns nil for .auth after .createEventType
   - Recommendation: Allow swipe back from Auth to Welcome, prevent swipe back after auth completes (post-createEventType)

2. **CreateEventType and LogFirstEvent removal from flow**
   - What we know: CONTEXT.md specifies flow order "Welcome -> Auth -> Permissions"
   - What's unclear: Current flow has createEventType and logFirstEvent between Auth and Permissions
   - Recommendation: Clarify with stakeholder if these steps should be removed or just reordered. Research assumes they remain for now.

3. **Hero symbol animation style**
   - What we know: CONTEXT.md marks as "Claude's Discretion"
   - Options: Subtle pulse/glow, gentle floating motion, static with entrance animation
   - Recommendation: Subtle scale pulse (1.0 to 1.05) with slow timing (2-3s loop), gentle glow using shadow

## Files Requiring Modification

### Must Modify
| File | Change Required |
|------|-----------------|
| `/apps/ios/trendy/Views/Onboarding/OnboardingContainerView.swift` | Replace switch-based navigation with horizontal scroll pattern |
| `/apps/ios/trendy/Views/Onboarding/WelcomeView.swift` | Redesign with hero layout per CONTEXT.md |
| `/apps/ios/trendy/Views/Onboarding/OnboardingAuthView.swift` | Redesign with hero layout |
| `/apps/ios/trendy/Views/Onboarding/PermissionsView.swift` | Split into individual priming screens |
| `/apps/ios/trendy/Views/Onboarding/OnboardingFinishView.swift` | Add ConfettiSwiftUI celebration |
| `/apps/ios/trendy/Views/Onboarding/CreateEventTypeView.swift` | Update ProgressIndicatorView usage |
| `/apps/ios/trendy/Views/RootView.swift` | Update LaunchLoadingView to match new aesthetic |
| `/apps/ios/trendy/Models/Onboarding/OnboardingStep.swift` | May need to add permission-specific steps |

### New Files
| File | Purpose |
|------|---------|
| `/apps/ios/trendy/Views/Onboarding/Components/OnboardingProgressBar.swift` | Progress bar component |
| `/apps/ios/trendy/Views/Onboarding/Components/OnboardingHeroView.swift` | Reusable hero layout |
| `/apps/ios/trendy/Views/Onboarding/Screens/NotificationPrimingScreen.swift` | Notification priming |
| `/apps/ios/trendy/Views/Onboarding/Screens/LocationPrimingScreen.swift` | Location priming |

### Package.swift Update
Add ConfettiSwiftUI dependency:
```swift
.package(url: "https://github.com/simibac/ConfettiSwiftUI", from: "2.0.0")
```

## Sources

### Primary (HIGH confidence)
- [Apple Developer - PhaseAnimator](https://developer.apple.com/documentation/swiftui/phaseanimator) - Official API documentation
- [Apple HIG - Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) - Permission priming guidelines
- [Hacking with Swift - PhaseAnimator](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-multi-step-animations-using-phase-animators) - Usage patterns
- [AppCoda - KeyframeAnimator](https://www.appcoda.com/keyframeanimator/) - Keyframe animation patterns

### Secondary (MEDIUM confidence)
- [Rivera Labs - SwiftUI Onboarding](https://www.riveralabs.com/blog/swiftui-onboarding/) - ScrollView pattern for iOS 18+
- [GetStream - Spring Animations](https://github.com/GetStream/swiftui-spring-animations) - Spring parameter reference
- [ConfettiSwiftUI GitHub](https://github.com/simibac/ConfettiSwiftUI) - Celebration animation library
- [Hacking with Swift - sensoryFeedback](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-haptic-effects-using-sensory-feedback) - Haptic feedback

### Tertiary (LOW confidence)
- [Medium - iOS 18 Gesture Conflicts](https://medium.com/@rickeyboy0318/fixing-navigation-back-gesture-conflicts-in-swiftui-3bc4a6cf042b) - Gesture conflict solutions (needs validation in actual iOS 18 environment)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All native iOS 17+ APIs, well-documented
- Architecture: HIGH - Patterns from existing codebase analysis + official docs
- Pitfalls: MEDIUM - Gesture conflicts in iOS 18 need runtime validation
- Animation APIs: HIGH - Verified with official Apple documentation and tutorials

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (30 days - stable APIs, iOS 17+ patterns established)
