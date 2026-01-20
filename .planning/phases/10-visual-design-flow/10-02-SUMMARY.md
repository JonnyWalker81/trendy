---
phase: 10-visual-design-flow
plan: 02
subsystem: ui
tags: [swiftui, onboarding, hero-layout, progress-bar, design-system]

# Dependency graph
requires:
  - phase: 10-visual-design-flow
    plan: 01
    provides: OnboardingProgressBar, OnboardingHeroView components
provides:
  - Redesigned WelcomeView with hero layout and progress bar
  - Redesigned OnboardingAuthView with hero layout and dynamic icon
affects: [10-03, 10-04, 10-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [hero-layout-pattern, computed-progress]

key-files:
  created: []
  modified:
    - apps/ios/trendy/Views/Onboarding/WelcomeView.swift
    - apps/ios/trendy/Views/Onboarding/OnboardingAuthView.swift

key-decisions:
  - "Hero height for WelcomeView: 280pt (default from OnboardingHeroView)"
  - "Hero height for OnboardingAuthView: 200pt (reduced to accommodate form)"
  - "Progress at welcome: 0.0 (step 1 of flow)"
  - "Progress at auth: 1/6 (step 2 of 6 total steps)"
  - "Auth hero icon dynamic: person.crop.circle.fill (sign-in) or person.crop.circle.fill.badge.plus (sign-up)"
  - "Feature highlights reduced from 3 to 2 rows for minimal text density per CONTEXT.md"
  - "Haptic feedback on WelcomeView primary button using sensoryFeedback modifier"

patterns-established:
  - "Hero layout: progress bar -> hero view -> spacer -> content -> spacer -> action buttons"
  - "Computed progress using OnboardingStep.allCases.count for consistency"
  - "ScrollView wrapping form content for keyboard handling"

# Metrics
duration: 4min
completed: 2026-01-20
---

# Phase 10 Plan 02: Container + Navigation Summary

**Redesigned WelcomeView and OnboardingAuthView with modern hero layouts using OnboardingHeroView and OnboardingProgressBar components**

## Performance

- **Duration:** 4 min
- **Started:** 2026-01-20T21:48:03Z
- **Completed:** 2026-01-20T21:51:45Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Redesigned WelcomeView with hero layout (progress bar at top, hero area with gradient/SF Symbol, content, buttons pinned at bottom)
- Added haptic feedback to WelcomeView primary button using iOS 17+ sensoryFeedback modifier
- Simplified feature highlights from 3 to 2 rows for minimal text density per CONTEXT.md
- Redesigned OnboardingAuthView with hero layout (reduced height to 200pt for form space)
- Added dynamic hero icon that changes based on sign-in vs sign-up mode
- Added computed progress property that calculates step based on OnboardingStep count
- Preserved all existing authentication functionality (email/password, Google Sign-In, validation)

## Task Commits

Each task was committed atomically:

1. **Task 1: Redesign WelcomeView with Hero Layout** - `50cce3f` (feat)
2. **Task 2: Redesign OnboardingAuthView with Hero Layout** - `96902ad` (feat)

## Files Modified

- `apps/ios/trendy/Views/Onboarding/WelcomeView.swift` - Hero layout with progress bar, haptic feedback
- `apps/ios/trendy/Views/Onboarding/OnboardingAuthView.swift` - Hero layout with dynamic icon, ScrollView for form

## Decisions Made

- **Hero heights:** WelcomeView uses default 280pt, OnboardingAuthView uses 200pt to fit form
- **Progress calculation:** Uses OnboardingStep.allCases.count for future-proof consistency
- **Feature highlights:** Reduced to 2 rows (Quick Logging, Smart Insights) - removed Reminders row for less clutter
- **Haptic feedback:** Applied to WelcomeView "Get Started" button only per CONTEXT.md decision

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Build database lock required killing stale xcodebuild process (resolved)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- WelcomeView and OnboardingAuthView now use consistent hero layout pattern
- Both screens show progress bar at top
- Foundation established for remaining onboarding screen redesigns (CreateEventType, LogFirstEvent, Permissions, Finish)
- All auth functionality preserved and tested via build verification

---
*Phase: 10-visual-design-flow*
*Completed: 2026-01-20*
