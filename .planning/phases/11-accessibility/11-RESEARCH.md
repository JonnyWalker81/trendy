# Phase 11: Accessibility - Research

**Researched:** 2026-01-20
**Domain:** iOS SwiftUI Accessibility (VoiceOver, Reduce Motion)
**Confidence:** HIGH

## Summary

This phase adds accessibility support to the existing onboarding flow built in Phase 10. The codebase already uses `accessibilityReduceMotion` and accessibility labels in other views (SyncErrorView, RelativeTimestampView), providing established patterns to follow.

SwiftUI provides comprehensive accessibility modifiers for VoiceOver support. Key requirements are:
1. **VoiceOver labels/hints** - contextual descriptions for all interactive elements
2. **AccessibilityFocusState** - programmatic focus management when transitioning between steps
3. **accessibilityHidden** - hide decorative hero images and icons from VoiceOver
4. **accessibilityReduceMotion** - respect user's motion preference for all animations

**Primary recommendation:** Follow the existing pattern in SyncErrorView for accessibility labels and reduceMotion handling. Use `@AccessibilityFocusState` with an enum to move focus to step titles on transitions.

## Standard Stack

SwiftUI's built-in accessibility system is the standard. No third-party libraries needed.

### Core Modifiers
| Modifier | Purpose | When to Use |
|----------|---------|-------------|
| `.accessibilityLabel(_:)` | Primary description read by VoiceOver | Buttons, images without text, custom controls |
| `.accessibilityHint(_:)` | Explains action result (read after pause) | Buttons where outcome isn't obvious |
| `.accessibilityValue(_:)` | Current state for dynamic elements | Progress bars, sliders |
| `.accessibilityHidden(true)` | Hide from VoiceOver | Decorative images, hero graphics |
| `.accessibilityFocused(_:)` | Bind focus state | Elements that need programmatic focus |
| `.accessibilityElement(children:)` | Group or ignore children | Combine related elements, hide containers |
| `.accessibilitySortPriority(_:)` | Control focus order | When visual order differs from logical order |
| `.accessibilityAddTraits(_:)` | Add semantic traits | Headers, buttons not using Button type |

### Environment Values
| Value | Purpose |
|-------|---------|
| `@Environment(\.accessibilityReduceMotion)` | Check if user prefers reduced motion |
| `UIAccessibility.prefersCrossFadeTransitions` | Check if user prefers crossfade (not in SwiftUI env) |

### Property Wrappers
| Wrapper | Purpose |
|---------|---------|
| `@AccessibilityFocusState` | Track and control VoiceOver focus programmatically |

## Architecture Patterns

### Pattern 1: Contextual Button Labels

**What:** Buttons get descriptive labels including context about destination/action.
**When to use:** All onboarding buttons (Continue, Skip, Enable permissions).

```swift
// Source: CONTEXT.md decision + Apple HIG
Button("Get Started") {
    // action
}
.accessibilityLabel("Get started with Trendy setup")
.accessibilityHint("Opens account creation")
```

### Pattern 2: AccessibilityFocusState for Step Transitions

**What:** Use enum-based focus state to move VoiceOver to step heading on navigation.
**When to use:** When onboarding step changes.

```swift
// Source: https://swiftwithmajid.com/2021/09/23/accessibility-focus-in-swiftui/
enum OnboardingFocusField: Hashable {
    case welcomeTitle
    case authTitle
    case createEventTitle
    case logEventTitle
    case permissionTitle
    case finishTitle
}

@AccessibilityFocusState private var focusedField: OnboardingFocusField?

Text("Welcome to Trendy")
    .accessibilityFocused($focusedField, equals: .welcomeTitle)
    .accessibilityAddTraits(.isHeader)

// On step change:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    focusedField = .authTitle
}
```

### Pattern 3: Reduce Motion with Conditional Animation

**What:** Check `accessibilityReduceMotion` and provide alternative (nil or crossfade).
**When to use:** All animations - transitions, pulse effects, confetti.

```swift
// Source: Existing pattern in apps/ios/trendy/Views/MainTabView.swift line 207
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// For transitions
.transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
.animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: step)

// For withAnimation calls
if reduceMotion {
    showDetails.toggle()
} else {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showDetails.toggle()
    }
}
```

### Pattern 4: Progress Bar Accessibility

**What:** Progress bar announces current step name and position.
**When to use:** OnboardingProgressBar component.

```swift
// Source: Apple accessibility docs + CONTEXT.md decision
OnboardingProgressBar(progress: 0.5)
    .accessibilityLabel("Onboarding progress")
    .accessibilityValue("Permissions, step 5 of 6")
```

### Pattern 5: Hide Decorative Elements

**What:** Mark decorative images as hidden from VoiceOver.
**When to use:** Hero images, background graphics, decorative icons.

```swift
// Source: https://www.hackingwithswift.com/books/ios-swiftui/hiding-and-grouping-accessibility-data
OnboardingHeroView(...)
    .accessibilityHidden(true)

// Or for SF Symbols in hero:
Image(systemName: "sparkles")
    .accessibilityHidden(true)
```

### Pattern 6: Grouped Accessibility Elements

**What:** Combine related elements into single VoiceOver focus point.
**When to use:** Feature highlights, benefit bullets, error messages.

```swift
// Source: Apple docs + existing pattern in SyncErrorView
VStack {
    Image(systemName: "checkmark.circle.fill")
    Text("Quick Logging")
    Text("Tap to track any event instantly")
}
.accessibilityElement(children: .combine)
// VoiceOver reads: "Quick Logging, Tap to track any event instantly"
```

### Anti-Patterns to Avoid

- **Generic labels:** "Button" or "Continue" without context - use "Continue to permissions"
- **Redundant announcements:** Hero icon + title both being read - hide decorative
- **Changing focus unexpectedly:** Only move focus on user-initiated navigation
- **Removing all animation for reduceMotion:** Use crossfade/opacity instead of nothing

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Focus management | Custom focus tracking | `@AccessibilityFocusState` | Built-in, works with all assistive tech |
| Motion detection | Custom settings observer | `@Environment(\.accessibilityReduceMotion)` | Automatic updates, SwiftUI native |
| VoiceOver announcements | Custom notification posting | `.accessibilityLabel/.accessibilityHint` | Standard patterns, localizable |
| Button traits | Manual trait management | SwiftUI's Button type | Automatic button traits |

**Key insight:** SwiftUI's accessibility modifiers handle VoiceOver, Switch Control, and Full Keyboard Access simultaneously. Using them correctly means supporting all assistive technologies.

## Common Pitfalls

### Pitfall 1: Focus Not Moving on Step Change
**What goes wrong:** VoiceOver stays on previous screen content after transition.
**Why it happens:** `accessibilityFocused` binding not updated, or updated too early.
**How to avoid:** Use `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` after animation starts.
**Warning signs:** VoiceOver reads old content after visual change.

### Pitfall 2: Confetti Triggering Multiple Haptics
**What goes wrong:** Confetti library fires haptic on each "explosion", overwhelming in Reduce Motion mode.
**Why it happens:** ConfettiSwiftUI has built-in hapticFeedback that doesn't check reduceMotion.
**How to avoid:** Conditionally hide confetti entirely or replace with static success indicator.
**Warning signs:** Multiple vibrations on finish screen.

### Pitfall 3: Progress Bar Animation Ignored
**What goes wrong:** Progress bar still animates even with Reduce Motion on.
**Why it happens:** `.animation()` modifier doesn't automatically check accessibilityReduceMotion.
**How to avoid:** Conditionally apply animation: `.animation(reduceMotion ? nil : .spring(...), value: progress)`.
**Warning signs:** Progress fill slides with spring animation when Reduce Motion is enabled.

### Pitfall 4: Hero Pulse Animation in Reduce Motion
**What goes wrong:** Pulsing SF Symbol in hero continues with Reduce Motion enabled.
**Why it happens:** `OnboardingHeroView.symbolAnimation` is a separate parameter, not tied to reduceMotion.
**How to avoid:** Pass `symbolAnimation: !reduceMotion` or check internally.
**Warning signs:** Symbol scales up/down repeatedly when Reduce Motion is on.

### Pitfall 5: Skip Explanation Delay with VoiceOver
**What goes wrong:** "Skipping..." text appears but VoiceOver doesn't announce it before advancing.
**Why it happens:** Auto-advance after 1.5 seconds happens before VoiceOver finishes reading.
**How to avoid:** Check `UIAccessibility.isVoiceOverRunning` and extend delay, or use `.accessibilityAnnouncement()`.
**Warning signs:** VoiceOver user hears nothing about skip consequences.

### Pitfall 6: TextField Focus Conflict
**What goes wrong:** Setting `@AccessibilityFocusState` conflicts with `@FocusState` for keyboard.
**Why it happens:** Two different focus systems can compete.
**How to avoid:** Set accessibility focus BEFORE or AFTER keyboard focus, not simultaneously.
**Warning signs:** Keyboard doesn't appear, or VoiceOver reads wrong element.

## Code Examples

### Example 1: OnboardingProgressBar with Accessibility

```swift
// Current progress bar needs accessibility value
struct OnboardingProgressBar: View {
    let progress: Double
    let stepName: String  // NEW: Pass step name
    let stepNumber: Int   // NEW: Pass step number
    let totalSteps: Int   // NEW: Pass total steps

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.dsBorder)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.dsPrimary)
                    .frame(width: max(0, geometry.size.width * CGFloat(clampedProgress)))
                    // Conditional animation for reduce motion
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(stepName), step \(stepNumber) of \(totalSteps)")
    }
}
```

### Example 2: Hero View Hidden from VoiceOver

```swift
// Hero view is decorative - hide entirely
OnboardingHeroView(
    symbolName: "chart.line.uptrend.xyaxis",
    gradientColors: [Color.dsPrimary, Color.dsAccent],
    symbolAnimation: !reduceMotion  // Disable pulse when reduce motion
)
.accessibilityHidden(true)
```

### Example 3: Focus Management on Step Change

```swift
struct OnboardingNavigationView: View {
    @Bindable var viewModel: OnboardingViewModel

    enum FocusField: Hashable {
        case welcome, auth, createEvent, logEvent, permissions, finish
    }

    @AccessibilityFocusState private var focusedField: FocusField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeView(viewModel: viewModel, focusedField: $focusedField)
            // ... other cases
            }
        }
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: viewModel.currentStep)
        .onChange(of: viewModel.currentStep) { _, newStep in
            // Move focus after animation starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = focusField(for: newStep)
            }
        }
    }

    private func focusField(for step: OnboardingStep) -> FocusField {
        switch step {
        case .welcome: return .welcome
        case .auth: return .auth
        case .createEventType: return .createEvent
        case .logFirstEvent: return .logEvent
        case .permissions: return .permissions
        case .finish: return .finish
        }
    }
}
```

### Example 4: Contextual Button Labels

```swift
// WelcomeView buttons
Button("Get Started") {
    // action
}
.accessibilityLabel("Get started")
.accessibilityHint("Creates your account to begin tracking")

Button("I already have an account") {
    // action
}
.accessibilityLabel("Sign in to existing account")
.accessibilityHint("Opens sign in form")
```

### Example 5: Permission Priming with Accessibility

```swift
// Enable button with context
Button {
    // request permission
} label: {
    Text("Enable Notifications")
}
.accessibilityLabel("Enable notifications")
.accessibilityHint("Shows iOS permission dialog. Allows reminders to track your events.")

// Skip button with warning
Button("Skip for now") {
    // skip
}
.accessibilityLabel("Skip notification setup")
.accessibilityHint("You can enable notifications later in Settings. App will remind you less frequently.")
```

### Example 6: Reduce Motion Confetti Alternative

```swift
struct OnboardingFinishView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confettiTrigger = 0

    var body: some View {
        VStack {
            // ... content
        }
        .background(Color.dsBackground)
        .overlay {
            // Only show confetti if reduce motion is off
            if !reduceMotion {
                // Confetti overlay (using ConfettiSwiftUI library)
            }
        }
        .confettiCannon(
            trigger: $confettiTrigger,
            num: reduceMotion ? 0 : 50,  // No confetti particles
            hapticFeedback: !reduceMotion  // No haptic with reduce motion
            // ... other params
        )
        .onAppear {
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    confettiTrigger += 1
                }
            }
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `AccessibilityChildBehavior` enum | `.accessibilityElement(children:)` modifier | iOS 14+ | Cleaner API |
| `UIAccessibility.post(notification:)` for focus | `@AccessibilityFocusState` | iOS 15/SwiftUI 3 | Native SwiftUI focus management |
| `ContentSizeCategory` | `DynamicTypeSize` | iOS 15 | Better naming, more sizes |
| Manual trait management | Automatic from SwiftUI controls | Always | Use native Button, not Image+onTapGesture |

**Deprecated/outdated:**
- `.accessibility(label:)` - Use `.accessibilityLabel(_:)` (same functionality, better naming)
- `.accessibility(hidden:)` - Use `.accessibilityHidden(_:)`
- Manual focus tracking - Use `@AccessibilityFocusState`

## Open Questions

### 1. Confetti Library Reduce Motion Handling
**What we know:** ConfettiSwiftUI has `hapticFeedback` parameter but no built-in reduceMotion check.
**What's unclear:** Whether setting `num: 0` completely prevents animation or just shows zero particles.
**Recommendation:** Test with `num: 0` and `hapticFeedback: false`. If animation still runs, wrap entire `.confettiCannon` in `if !reduceMotion` check.

### 2. Skip Explanation Auto-Advance Timing
**What we know:** Current implementation advances after 1.5 seconds.
**What's unclear:** Whether VoiceOver users need more time to hear skip explanation.
**Recommendation:** Check `UIAccessibility.isVoiceOverRunning` and extend to 3 seconds if VoiceOver active.

### 3. Dynamic Type in Onboarding
**What we know:** SwiftUI text styles auto-scale. Custom sizes may not.
**What's unclear:** Whether current onboarding layouts break at largest accessibility sizes.
**Recommendation:** Test with "Accessibility Size" Dynamic Type (5 extra large sizes). Flag as future work if layouts break.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: Accessibility modifiers
- Existing codebase pattern: `apps/ios/trendy/Views/Components/SyncIndicator/SyncErrorView.swift`
- Existing codebase pattern: `apps/ios/trendy/Views/MainTabView.swift` (lines 17, 207, 210, 223)

### Secondary (MEDIUM confidence)
- [Hacking with Swift - Hiding and grouping accessibility data](https://www.hackingwithswift.com/books/ios-swiftui/hiding-and-grouping-accessibility-data)
- [Swift with Majid - Accessibility focus in SwiftUI](https://swiftwithmajid.com/2021/09/23/accessibility-focus-in-swiftui/)
- [Create with Swift - Reduce Motion Support](https://www.createwithswift.com/ensure-visual-accessibility-supporting-reduced-motion-preferences-in-swiftui/)
- [CVS Health iOS Accessibility Techniques](https://github.com/cvs-health/ios-swiftui-accessibility-techniques)
- [Apple HIG - Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Apple Developer - Reduced Motion Evaluation](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria/)

### Tertiary (LOW confidence)
- Various Medium articles on SwiftUI accessibility patterns (verified against official docs)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using only SwiftUI built-in accessibility modifiers
- Architecture patterns: HIGH - Based on existing codebase patterns + Apple docs
- Pitfalls: MEDIUM - Based on community experience and testing guidance

**Research date:** 2026-01-20
**Valid until:** 90 days (accessibility APIs are stable, rarely change)

## Implementation Checklist for Planner

Views requiring accessibility work:
1. **OnboardingContainerView/OnboardingNavigationView** - Add focus state management
2. **OnboardingProgressBar** - Add accessibility value with step name and position
3. **OnboardingHeroView** - Add accessibilityHidden, conditional symbolAnimation
4. **WelcomeView** - Contextual button labels, hide hero, focus on title
5. **OnboardingAuthView** - Labels for form fields, hide hero, focus on title
6. **CreateEventTypeView** - Labels for template cards, color picker, icon picker
7. **LogFirstEventView** - Labels for log button, focus on title
8. **NotificationPrimingScreen** - Contextual enable/skip labels, focus on title
9. **LocationPrimingScreen** - Contextual enable/skip labels, focus on title
10. **HealthKitPrimingScreen** - Contextual enable/skip labels, focus on title
11. **OnboardingFinishView** - Reduce motion confetti handling, focus on success message

Shared components to update:
- OnboardingProgressBar (add stepName, stepNumber, totalSteps parameters)
- OnboardingHeroView (respect reduceMotion for symbolAnimation)
