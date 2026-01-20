# Project Research Summary

**Project:** Trendy iOS v1.1 Onboarding Overhaul
**Domain:** iOS SwiftUI onboarding flow improvement
**Researched:** 2026-01-19
**Confidence:** HIGH

## Executive Summary

The Trendy iOS onboarding system has three well-defined problems: returning users see onboarding screens flash (a race condition in state management), the flow order creates friction, and the visual design feels dated. Research confirms these are solvable with native SwiftUI patterns requiring no new dependencies.

The recommended approach is a three-phase refactor: First, fix the flash issue by introducing a `LaunchStateCoordinator` that reads cached state synchronously before any view renders, replacing the current scattered async checks and NotificationCenter-based routing. Second, apply modern iOS 17 animation APIs (`PhaseAnimator`, `KeyframeAnimator`) to polish transitions and celebrations. Third, either remove permissions from onboarding entirely (deferring to first feature use) or enhance with proper two-step priming screens.

The primary risk is the state management refactor touching multiple files (ContentView, trendyApp, OnboardingViewModel, OnboardingContainerView). Mitigation: Phase 1 focuses exclusively on the routing architecture without changing onboarding content views. The existing state machine (`OnboardingStep` enum) and authentication flow are solid and should be preserved.

## Key Findings

### Recommended Stack

The existing stack is sound - this is an enhancement exercise, not a rebuild. No new third-party dependencies are needed. The research explicitly recommends against adding Lottie or Rive animation libraries; native SwiftUI iOS 17+ APIs are sufficient for the scope.

**Core technologies:**
- **UserDefaults + @AppStorage**: State persistence - UserDefaults for ViewModel writes, @AppStorage for view-level reactivity
- **PhaseAnimator (iOS 17+)**: Multi-phase sequential animations for step transitions
- **KeyframeAnimator (iOS 17+)**: Complex keyframe-based animations for celebration effects on finish screen
- **@Observable**: ViewModel state management - already correctly implemented, no changes needed
- **Supabase Swift SDK**: Authentication - working well, no changes needed

**What to avoid:**
- Lottie (adds 2MB, After Effects dependency, overkill)
- SwiftData for onboarding flags (overkill for boolean state)
- Keychain for onboarding state (Keychain is for secrets, not app state)

### Expected Features

**Must have (table stakes):**
- Never show onboarding to returning users (current bug - screens flash)
- Progress indicator showing remaining steps
- Pre-permission priming screens before system dialogs
- Skip button on optional steps
- Smooth transitions between steps
- Clear CTAs with obvious primary action

**Should have (quick wins):**
- Celebrate first event with animation
- Better progress indicator (current step grouping is confusing)
- Skip confirmation explaining what user will miss
- Enhanced permission cards with benefit messaging

**Defer (v2+):**
- Value-first flow (significant architecture change - let users create events before auth)
- Deep personalization questions
- Animated mascot/branding
- Fully contextual permission requests (prompt at feature use, not during onboarding)

### Architecture Approach

The core fix requires introducing a `LaunchStateCoordinator` that determines app routing state synchronously in `init()` by reading cached UserDefaults, before SwiftUI renders any view body. This eliminates the race condition where auth state, onboarding completion, and "has checked" flags update at different times causing the flash.

**Major components:**
1. **AppLaunchState enum** - Single source of truth: `.loading`, `.onboarding`, `.authenticated`
2. **LaunchStateCoordinator** - Reads cached state synchronously in init, verifies async without intermediate view changes
3. **RootView** - Single point of branching that switches on launch state (replaces scattered checks in ContentView)
4. **OnboardingViewModel** - Keep as-is for onboarding flow management, add completion callback to coordinator

**Key principles:**
- Single point of branching (RootView only decides onboarding vs main app)
- Synchronous fast path for returning users (no loading screen needed)
- Async verification without state changes unless truly different
- Replace NotificationCenter routing with shared @Observable state

### Critical Pitfalls

1. **Async state check causing UI flash** - Check UserDefaults synchronously in init BEFORE body renders. Never separate auth and onboarding checks into independent state variables. Use atomic state updates.

2. **Multiple loading states** - Match Launch Screen with initial SwiftUI view visually. Single centralized initialization. No nested loading states in child views.

3. **task/onAppear running multiple times** - Use `@State` guard for one-time execution or custom `onFirstAppear` modifier. Move initialization to coordinator, not views.

4. **NotificationCenter for view routing** - Replace with shared @Observable state. Notifications can be missed, cause race conditions, and are hard to debug.

5. **Permission priming timing** - Never request permissions without context. Use two-step opt-in (custom explanation then system dialog). Consider deferring to first feature use.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: State Management Foundation
**Rationale:** The flash issue is the highest priority bug and blocks other improvements. All research sources agree this must be fixed first. Architecture refactor provides foundation for subsequent phases.
**Delivers:** No flash for returning users. Clean single loading screen. Atomic routing state.
**Addresses:** Never show to returning users (table stakes), progress indicator foundation
**Avoids:** Pitfalls 1 (async flash), 2 (multiple loading), 3 (duplicate initialization), 6 (state sync), 7 (NotificationCenter routing)
**Scope:**
- Create AppLaunchState enum
- Create LaunchStateCoordinator with synchronous init
- Create RootView as single branching point
- Update trendyApp to wire coordinator
- Update OnboardingContainerView to remove redundant state checks
- Connect completion callback from OnboardingViewModel to coordinator
- Update sign-out flow to use coordinator

### Phase 2: Visual Design and Animations
**Rationale:** With routing fixed, the visual polish can be applied without risk of state bugs. Animation APIs are well-documented and low-risk.
**Delivers:** Modern transitions, celebration animations, accessibility support
**Uses:** PhaseAnimator, KeyframeAnimator (from STACK.md)
**Implements:** Step transition animations, finish screen celebration, permission card enhancements
**Avoids:** Pitfall 5 (ZStack glitches), Pitfall 8 (missing accessibility)
**Scope:**
- Replace basic `.animation()` with PhaseAnimator for step transitions
- Add KeyframeAnimator celebration on finish screen
- Use explicit zIndex or NavigationStack for transitions
- Add VoiceOver labels and hints
- Respect reduceMotion setting
- Support Dynamic Type with @ScaledMetric
- Polish keyboard handling in auth forms

### Phase 3: Permissions Polish
**Rationale:** Permissions are the lowest-priority improvement. The current flow works, just has suboptimal acceptance rates. This phase can be descoped if needed.
**Delivers:** Higher permission acceptance rates, better user understanding
**Addresses:** Pre-permission priming (table stakes), contextual permission timing (differentiator)
**Avoids:** Pitfall 4 (permission timing mistakes)
**Scope:**
- Add two-step priming screens (custom explanation before system dialog)
- Enhance cards with benefit statements and feature previews
- Add "Not Now" prominence with skip confirmation
- Consider: Move HealthKit to first feature use (contextual)
- Consider: Move Location to first geofence creation
- Consider: Remove permissions step entirely, use post-onboarding "Setup Checklist"

### Phase Ordering Rationale

- **Phase 1 first because:** Flash issue is user-facing bug on every app launch. State architecture must be solid before adding animation complexity. All other phases depend on clean state management.
- **Phase 2 second because:** Visual polish can only be properly tested once routing is stable. Animation code is isolated to individual views, low risk of regression.
- **Phase 3 last because:** Permissions changes are optional/deferrable. May involve product decisions about feature gating. Current implementation works, just not optimal.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3:** Product decision needed on whether to keep permissions in onboarding or defer to contextual. May need analytics data on current permission acceptance rates.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Patterns are well-documented (LaunchState enum, synchronous init). Apple WWDC sessions and multiple tutorials confirm approach.
- **Phase 2:** iOS 17 animation APIs are official and well-documented. Straightforward implementation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing implementation is correct, enhancements use native iOS 17 APIs with official Apple documentation |
| Features | HIGH | Verified across Apple HIG, NN/G, multiple 2025-2026 UX research sources |
| Architecture | HIGH | LaunchState pattern documented in multiple sources, verified against current codebase |
| Pitfalls | HIGH | All identified pitfalls map directly to issues in current Trendy codebase |

**Overall confidence:** HIGH

### Gaps to Address

- **Permission acceptance analytics:** Current acceptance rates unknown. Would inform whether Phase 3 is necessary or how aggressive to be with contextual deferral.
- **Session expiry handling:** Phase 1 should include handling for expired tokens routing to re-auth. May need Supabase-specific research during implementation.
- **Callback vs notification trade-offs:** Phase 1 recommends replacing NotificationCenter, but existing code uses it in multiple places. Exact refactor scope TBD during planning.

## Sources

### Primary (HIGH confidence)
- [Apple WWDC23: Wind your way through advanced animations in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10157/) - PhaseAnimator, KeyframeAnimator patterns
- [Apple HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) - Official design guidelines
- [Apple Documentation: AppStorage](https://developer.apple.com/documentation/swiftui/appstorage) - Property wrapper behavior
- [Swift by Sundell - Handling loading states](https://www.swiftbysundell.com/articles/handling-loading-states-in-swiftui/) - State management patterns
- [Fatbobman - Mastering SwiftUI task Modifier](https://fatbobman.com/en/posts/mastering_swiftui_task_modifier/) - Task lifecycle

### Secondary (MEDIUM confidence)
- [Scott Smith Dev - App Launch States](https://scottsmithdev.com/an-approach-to-handling-app-launch-states-in-swiftui) - LaunchState enum pattern
- [Rivera Labs - SwiftUI Onboarding iOS 18+](https://www.riveralabs.com/blog/swiftui-onboarding/) - Modern patterns
- [UserOnboard - Permission Priming](https://www.useronboard.com/onboarding-ux-patterns/permission-priming/) - UX best practices
- [NN/G - Design Considerations for Mobile Permission Requests](https://www.nngroup.com/articles/permission-requests/) - Research-backed guidance

### Tertiary (verified against codebase)
- `trendy/ContentView.swift` - Current routing logic with race condition
- `trendy/trendyApp.swift` - Session restore in detached Task
- `trendy/ViewModels/OnboardingViewModel.swift` - State management and NotificationCenter usage
- `trendy/Views/Onboarding/OnboardingContainerView.swift` - Nested loading state
- `trendy/Models/Onboarding/OnboardingStep.swift` - Flow definition

---
*Research completed: 2026-01-19*
*Ready for roadmap: yes*
