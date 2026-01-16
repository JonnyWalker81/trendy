---
phase: "02"
plan: "02"
subsystem: ios-healthkit
tags: [healthkit, ios, ui, observability, timestamps]

dependency-graph:
  requires:
    - 02-01 (anchor persistence for category tracking)
  provides:
    - Per-category last update timestamps
    - Freshness indicators in Settings and Dashboard
    - Manual refresh capability
    - Global refresh state tracking
  affects:
    - 02-03 (background task scheduling may use freshness)
    - Future monitoring/alerting features

tech-stack:
  added: []
  patterns:
    - RelativeDateTimeFormatter for user-friendly time display
    - Observable refresh state with Set-based category tracking
    - Conditional UI sections based on authorization state

key-files:
  created: []
  modified:
    - apps/ios/trendy/Services/HealthKitService.swift
    - apps/ios/trendy/Views/HealthKit/HealthKitSettingsView.swift
    - apps/ios/trendy/Views/HealthKit/HealthKitDebugView.swift
    - apps/ios/trendy/Views/Dashboard/BubblesView.swift

decisions:
  - decision: "Use RelativeDateTimeFormatter for relative time display"
    rationale: "Native iOS API, automatically localizes, handles edge cases"
    timestamp: 2026-01-16

  - decision: "Show oldest category update in Dashboard for overall freshness"
    rationale: "Gives quick at-a-glance view of HealthKit sync status"
    timestamp: 2026-01-16

  - decision: "Track refreshing state with Set<HealthDataCategory>"
    rationale: "Allows concurrent category refreshes while maintaining accurate isRefreshing state"
    timestamp: 2026-01-16

metrics:
  duration: "~15 minutes"
  completed: 2026-01-16
---

# Phase 2 Plan 2: Timestamp Visibility Summary

Per-category update timestamps with user-facing freshness indicators in Settings, Debug, and Dashboard views.

## What Was Built

### 1. Timestamp Tracking Infrastructure (HealthKitService)
- Added `lastUpdateTimes: [HealthDataCategory: Date]` dictionary
- Added `lastUpdateTimeKeyPrefix` constant for UserDefaults persistence
- Added `recordCategoryUpdate(for:)` to capture timestamps on new samples
- Added `loadAllUpdateTimes()` to restore timestamps on init
- Added `lastUpdateTime(for:)` public accessor
- Added `clearUpdateTime(for:)` for debug/reset

### 2. Freshness Display in Settings (HealthKitCategoryRow)
- Added `@Environment(HealthKitService.self)` to access service
- Added `formatRelativeTime()` helper using RelativeDateTimeFormatter
- Shows "Updated X ago" for categories with data
- Shows "Not yet updated" in orange for categories without data

### 3. Debug View Enhancements (HealthKitDebugView)
- Added "Last Update Times" section showing exact timestamps per category
- Displays time and date for categories with data
- Shows "Never" in orange for categories without data
- Added "Clear Update Times" button in Actions section

### 4. Global Refresh State (HealthKitService)
- Added `isRefreshing: Bool` property for global refresh state
- Added `refreshingCategories: Set<HealthDataCategory>` for granular tracking
- Updated `forceSleepCheck()`, `forceStepsCheck()`, `forceActiveEnergyCheck()` to set state
- Updated `forceRefreshAllCategories()` to track all categories

### 5. Manual Refresh Button (HealthKitSettingsView)
- Added `isManuallyRefreshing` state variable
- Added "Refresh Health Data" button with inline loading indicator
- Button disabled during refresh
- Calls `forceRefreshAllCategories()` and toggles refresh trigger

### 6. Dashboard Summary (BubblesView)
- Added `healthKitSummarySection` showing active tracking status
- Displays enabled category count and oldest update time
- Inline refresh button with loading indicator
- Shows section only when HealthKit is authorized

## Commits

| Commit | Description |
|--------|-------------|
| 655580c | feat(02-02): add per-category update timestamp tracking |
| dfbdede | feat(02-02): display freshness indicators in settings |
| 3233692 | feat(02-02): add detailed timestamps to debug view |
| 4d8f26a | feat(02-02): add global refresh indicator properties |
| 8f1fc05 | feat(02-02): add manual refresh button to settings |
| ba84951 | feat(02-02): add HealthKit summary section to Dashboard |

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

### Dependencies Satisfied
- Timestamp tracking infrastructure ready for background task scheduling
- Freshness indicators available for staleness detection

### Recommended Next Steps
1. Proceed to 02-03 (Background Task Scheduling) to use freshness for smart refresh timing
2. Consider adding staleness alerts when data is too old
3. Could add notification when HealthKit data hasn't updated in X hours

### Blockers
None identified.
