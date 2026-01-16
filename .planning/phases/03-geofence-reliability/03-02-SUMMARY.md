---
phase: 03-geofence-reliability
plan: 02
subsystem: ios
tags: [corelocation, geofencing, lifecycle, swiftui, scene-phase]

# Dependency graph
requires:
  - phase: 03-geofence-reliability
    plan: 01
    provides: AppDelegate with normalLaunchNotification, background event handling
provides:
  - ensureRegionsRegistered method for lifecycle-aware re-registration
  - Multiple lifecycle trigger points for geofence re-registration
  - Idempotent region reconciliation on app activation
affects: [03-03, 03-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Lifecycle-triggered re-registration pattern for geofences
    - ScenePhase observer for app activation detection
    - NotificationCenter-based launch triggers

key-files:
  created: []
  modified:
    - apps/ios/trendy/Services/GeofenceManager.swift
    - apps/ios/trendy/AppDelegate.swift
    - apps/ios/trendy/Views/MainTabView.swift

key-decisions:
  - "ensureRegionsRegistered fetches from SwiftData and calls reconcileRegions - single source of truth"
  - "Normal launch notification posted for ALL app launches (background and foreground)"
  - "Scene activation triggers ensureRegionsRegistered immediately, then reconciles again after backend sync"
  - "Authorization gain calls ensureRegionsRegistered instead of refreshMonitoredGeofences"

patterns-established:
  - "Lifecycle re-registration: ensureRegionsRegistered called on launch, activation, and auth restoration"
  - "App launch notification: AppDelegate.normalLaunchNotification for triggering registration"
  - "Idempotent region management: reconcileRegions handles add/remove safely"

# Metrics
duration: 6min
completed: 2026-01-16
---

# Phase 3 Plan 2: Lifecycle Re-registration Summary

**Defensive re-registration at multiple lifecycle points to ensure geofences survive iOS lifecycle events**

## Performance

- **Duration:** 6 min
- **Started:** 2026-01-16T18:08:00Z
- **Completed:** 2026-01-16T18:14:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Added ensureRegionsRegistered() method to GeofenceManager for idempotent region re-registration
- Added normalLaunchNotification to AppDelegate, posted on every app launch
- GeofenceManager observes and handles normal launch notification
- MainTabView calls ensureRegionsRegistered when scenePhase becomes .active
- Updated locationManagerDidChangeAuthorization to use ensureRegionsRegistered on auth gain
- Build verified successful with no compilation errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Add ensureRegionsRegistered method** - `e04f28c` (feat)
2. **Task 2: Call ensureRegionsRegistered on normal app launch** - `84b82de` (feat)
3. **Task 3: Call ensureRegionsRegistered when app becomes active** - `427464b` (feat)

## Files Modified
- `apps/ios/trendy/Services/GeofenceManager.swift` - Added ensureRegionsRegistered(), handleNormalLaunch handler, updated auth delegate to use ensureRegionsRegistered
- `apps/ios/trendy/AppDelegate.swift` - Added normalLaunchNotification constant, posts notification in didFinishLaunchingWithOptions
- `apps/ios/trendy/Views/MainTabView.swift` - Added ensureRegionsRegistered call in scenePhase observer when app becomes active

## Decisions Made
- ensureRegionsRegistered() fetches active geofences from SwiftData and creates GeofenceDefinition array, then calls reconcileRegions - this keeps SwiftData as single source of truth
- Normal launch notification is posted for ALL launches (background location and normal) to ensure regions are always checked
- MainTabView calls ensureRegionsRegistered immediately on scene activation (synchronous), then reconcileRegions again after async backend sync to pick up server-side changes
- Authorization delegate now uses ensureRegionsRegistered instead of refreshMonitoredGeofences when previousStatus != .authorizedAlways

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed GeofenceDefinition initializer call**
- **Found during:** Build verification after Task 1
- **Issue:** Plan specified positional initializer that didn't exist. GeofenceDefinition has `init(from geofence: Geofence)` initializer.
- **Fix:** Linter automatically changed to `GeofenceDefinition(from: $0)`
- **Files modified:** GeofenceManager.swift
- **Commit:** Fixed in subsequent user commit `3e5ec81`

## Issues Encountered
- Build database lock on first verification attempt - resolved by waiting and retrying
- Scheme name is "trendy (local)" not "Trendy (Local)" as documented in plan

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Lifecycle re-registration is now in place at all key points
- Ready for 03-03: Debug UI for monitoring geofence health (user already started adding GeofenceHealthStatus)
- ensureRegionsRegistered is a public method ready for use by other components

---
*Phase: 03-geofence-reliability*
*Completed: 2026-01-16*
