# Feature Landscape: iOS Onboarding

**Domain:** iOS app onboarding for event tracking application
**Researched:** 2026-01-19
**Confidence:** HIGH (verified with Apple HIG and multiple UX research sources)

## Table Stakes

Features users expect from any modern iOS app onboarding. Missing = product feels incomplete or unprofessional.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Never show to returning users** | Fundamental UX expectation. Users should never see onboarding screens flash. | Low | Use `@AppStorage` check BEFORE view hierarchy loads. Current bug in Trendy shows screens flashing. |
| **Skip button on optional steps** | Users should always be able to exit onboarding. 77% of users abandon apps in first 3 days - friction matters. | Low | Permissions and personalization should be skippable. Auth may require completion. |
| **Progress indicator** | Users need to know how many steps remain. Increases completion by showing end in sight. | Low | Dot indicators (PageTabViewStyle) are iOS standard. Duolingo uses "X more questions" text. |
| **Value proposition before signup** | Users need to understand app value before committing. Best apps let users explore before requiring auth. | Medium | Trendy currently shows feature highlights on welcome screen - good. |
| **Smooth transitions** | Jarring screen changes feel broken. SwiftUI animation between steps expected. | Low | Use `.animation()` modifier. Already implemented in OnboardingContainerView. |
| **Clear CTAs** | Primary action should be obvious. "Get Started" vs "I have an account" distinction. | Low | Already implemented in WelcomeView. |
| **Pre-permission priming screens** | Explain WHY before system dialog. iOS only allows ONE system prompt per permission ever. | Medium | Critical for HealthKit, Location, Notifications. If user denies at system level, recovery requires Settings app. |
| **Error handling with recovery** | Auth failures, network errors should have clear messages and retry options. | Low | Already implemented with `mapAuthError()` in OnboardingViewModel. |
| **Keyboard handling** | Keyboard should not obscure inputs. Scroll to focused field. | Low | SwiftUI handles most cases. Test on small devices. |

## Differentiators

Features that set the product apart. Not expected, but valued. These make onboarding memorable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Value-first, signup-later flow** | Let users create their first event type and log an event BEFORE requiring signup. Duolingo does this - users complete a lesson before account creation. Increases commitment through completion bias. | High | Would require significant architecture change. Current flow: welcome > auth > create event. Ideal: welcome > create event > auth. |
| **Personalization questions** | Ask "What do you want to track?" upfront and pre-populate with relevant event type templates. LinkedIn asks about goals, Duolingo asks language goals. | Medium | Could present category choices (health, habits, work, mood) and customize templates. |
| **Quick wins / first success celebration** | Celebrate first event logged with animation/confetti. Psychological reward wires users to seek more. | Low | Simple animation when first event is created in onboarding. |
| **Contextual permission requests** | Ask for HealthKit only when user selects health-related event types. Ask for location only when user enables geofencing. | Medium | More complex state management but dramatically improves permission acceptance rates (46% recovery rate with pre-permissions). |
| **Interactive tutorials** | Instead of static screens, let users tap to "try" features. Learning by doing beats reading. | High | Trendy already does this with "create event type" and "log first event" steps. Enhance with guided highlights. |
| **Social proof** | Show user count or testimonials. "Join 50,000 trackers" builds trust. | Low | Requires having real numbers. Add to welcome screen when applicable. |
| **Animated mascot/branding** | Duolingo's Duo owl creates emotional connection. Subtle animations during loading/transitions. | Medium | Trendy could animate the chart icon during transitions. Not essential but memorable. |
| **Smart defaults** | Pre-select sensible defaults for event types based on time of day or device capabilities. | Low | If HealthKit available, show workout templates first. Morning = coffee/exercise. |

## Anti-Features

Features to explicitly NOT build. Common mistakes in this domain that hurt UX.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Mandatory email verification before access** | 27% of users never verify. Loses users before they see value. | Allow app access immediately. Verify email later or make it optional for basic use. |
| **5+ static intro screens** | Boring. Users swipe through without reading. No retention improvement. | Maximum 3 value-prop screens OR use progressive/interactive onboarding. |
| **Permissions on first screen** | Requesting camera/location/health before context destroys trust. Users decline. | Ask permissions in context when the feature is first used, not during onboarding. |
| **Forced account creation before any value** | Major friction. DoorDash allows guest checkout. Many apps allow exploration first. | For Trendy: Consider allowing local-only use before requiring auth for sync. |
| **Long forms during onboarding** | Every field is friction. Users abandon. | Collect only email/password. Defer profile completion to later. |
| **Tutorial videos** | Nobody watches them. Skip rates near 100%. | Use interactive walkthroughs or tooltips instead. |
| **Feature tours on first launch** | Users don't care about features they haven't needed yet. | Progressive disclosure - show feature tips when user first encounters the feature area. |
| **Dark patterns to get permissions** | Misleading users into accepting permissions backfires. Reviews and trust destroyed. | Be transparent about what each permission enables. Let users skip. |
| **Onboarding that looks different from app** | Jarring transition. Users feel tricked. | Use same design system, colors, and components in onboarding as main app. |
| **No way to revisit onboarding** | Some users want to re-learn features. | Provide "How to use" in Settings that replays key tips. Not the full onboarding. |
| **Auth before exploring content** | Users can't evaluate if app is worth signing up for. | Trendy could show sample data or let user create local events before requiring sync account. |

## Feature Dependencies

```
Returning User Detection (must be FIRST)
    |
    +--> If returning: Skip to main app (no flash!)
    |
    +--> If new user: Welcome Screen
            |
            v
        [Value Proposition - 1-3 screens max]
            |
            v
        Authentication (email/Google)
            |
            v
        Create First Event Type
            |
            v
        Log First Event (with created type)
            |
            v
        Permissions (OPTIONAL, skippable)
            |-- HealthKit (if health event types selected)
            |-- Location (if geofencing enabled)
            |-- Notifications (for reminders)
            |
            v
        Completion / Celebration
```

**Critical Dependency:** Returning user detection MUST happen before ANY view loads. Current implementation has a race condition where OnboardingContainerView loads and shows loading state before `determineInitialState()` completes.

## MVP Recommendation

For polishing the existing onboarding, prioritize:

### Must Fix (Table Stakes)
1. **Fix returning user flash** - Check `onboarding_complete` flag BEFORE loading OnboardingContainerView. Do this at the App level, not inside the container.
2. **Pre-permission priming screens** - Add explanation screens before each system permission request. Currently jumps straight to system dialogs.
3. **Proper flow order** - Ensure welcome > auth > create > log > permissions > finish sequence never breaks.

### Should Add (Quick Wins)
4. **Celebrate first event** - Simple animation when user logs their first event during onboarding.
5. **Better progress indicator** - Current `stepNumber` grouping is confusing (steps 1-1, 2, 3, 4-4). Use clear dots or "Step X of Y".
6. **Skip confirmation** - When skipping permissions, briefly explain what they'll miss.

### Defer to Post-MVP
- Value-first flow (significant architecture change)
- Deep personalization questions
- Animated mascot/branding
- Contextual permission requests

## Real-World Exemplars

Apps with exceptional iOS onboarding to reference:

| App | What They Do Well | Applicable to Trendy |
|-----|-------------------|---------------------|
| **Duolingo** | Value-first (complete lesson before signup), progress transparency ("7 more questions"), mascot creates emotional connection, gamification | Value-first approach, progress text |
| **Strava** | Permission priming for location/HealthKit, explains benefits clearly, lets you explore before full commitment | Permission priming screens essential |
| **Calm** | Personalization ("Why are you here?"), beautiful animations, optional signup | Personalization questions for event type suggestions |
| **DoorDash** | Guest browsing before signup, signup at point of commitment (checkout) | Consider allowing local tracking before requiring account |
| **Headspace** | Goal setting upfront, clean progress indicator, celebration of completion | Goal framing for tracking habits |

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Table stakes features | HIGH | Verified across Apple HIG, Nielsen Norman Group, multiple 2025-2026 UX research sources |
| Anti-features | HIGH | Documented in multiple "mistakes to avoid" articles with supporting data |
| Differentiators | MEDIUM | Based on app examples and UX research, but specific implementation for event tracking app is less documented |
| Dependencies | HIGH | Based on code review of current OnboardingViewModel and standard iOS patterns |

## Sources

### Official Guidelines
- [Apple Human Interface Guidelines - Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Apple Developer - Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

### UX Research
- [Mobile Onboarding UX: 11 Best Practices for Retention (2026)](https://www.designstudiouiux.com/blog/mobile-app-onboarding-best-practices/)
- [The Ultimate Mobile App Onboarding Guide (2026) - VWO](https://vwo.com/blog/mobile-app-onboarding-guide/)
- [App Onboarding Best Practices for iOS Developers 2025 - Medium](https://ravi6997.medium.com/app-onboarding-best-practices-for-ios-developers-f65e29327a58)
- [3 Design Considerations for Effective Mobile-App Permission Requests - NN/G](https://www.nngroup.com/articles/permission-requests/)
- [Mobile UX Design: The Right Ways to Ask Users for Permissions](https://uxplanet.org/mobile-ux-design-the-right-ways-to-ask-users-for-permissions-6cdd9ab25c27)

### App Examples
- [Duolingo - an in-depth UX and user onboarding breakdown](https://userguiding.com/blog/duolingo-onboarding-ux)
- [UX Design: A Neuromarketing Study of Duolingo's Onboarding Flow](https://www.braingineers.com/post/user-experience-design-a-neuromarketing-evaluation-of-duolingos-onboarding-flow)
- [iOS Onboarding Screen - Medium](https://medium.com/@NikolaStanchev/ios-onboarding-screen-7d28d4a5fff4)
- [App Onboarding Guide - Top 10 Examples 2025 - UXCam](https://uxcam.com/blog/10-apps-with-great-user-onboarding/)

### Anti-Patterns
- [6 Most Common App Onboarding Mistakes to Avoid - DECODE](https://decode.agency/article/app-onboarding-mistakes/)
- [7 Onboarding Mistakes That Are Killing Your App's Success](https://thisisglance.com/blog/7-onboarding-mistakes-that-are-killing-your-apps-success)
- [Bad Onboarding Experiences - Best Practices, Examples & How to Avoid](https://userguiding.com/blog/bad-onboarding-experience)

### SwiftUI Implementation
- [SwiftUI onboarding screen using UserDefaults - Medium](https://medium.com/@deanirafd/swiftui-onboarding-screen-using-userdefaults-29ea1ad63fa1)
- [How to Build an Onboarding Flow in SwiftUI - Medium](https://medium.com/@jpmtech/how-to-build-an-onboarding-flow-in-swiftui-dfacdde2dded)
- [The Right Way to Ask Users for iOS Permissions - Medium/Cluster](https://medium.com/launch-kit/the-right-way-to-ask-users-for-ios-permissions-96fa4eb54f2c)
