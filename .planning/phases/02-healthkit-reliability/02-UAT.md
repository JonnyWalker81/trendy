---
status: diagnosed
phase: 02-healthkit-reliability
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md]
started: 2026-01-15T10:00:00Z
updated: 2026-01-16T21:40:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Debug View Anchor State
expected: In HealthKit Debug view, you see anchor count and a list of categories with anchors stored.
result: pass

### 2. Clear All Anchors Button
expected: Debug view has "Clear All Anchors" button. Tapping it clears all stored anchors.
result: pass

### 3. Settings Freshness Display
expected: In HealthKit Settings, each enabled category shows "Updated X ago" (e.g., "Updated 5 min ago") below the toggle.
result: pass

### 4. Settings Not Yet Updated State
expected: Categories with no data yet show "Not yet updated" in orange text.
result: skipped
reason: All categories already have data

### 5. Debug View Timestamps
expected: Debug view has "Last Update Times" section showing exact timestamps (date and time) per category.
result: pass

### 6. Debug View Clear Update Times
expected: Debug view has "Clear Update Times" button in Actions section.
result: pass

### 7. Settings Manual Refresh Button
expected: HealthKit Settings has "Refresh Health Data" button. Tapping shows loading indicator, button disables during refresh.
result: issue
reported: "pressing the button starts the loading indicator, all the categories are updated except the Workout category and the spinner is not going away, either its stuck or its taking a very very very long time to update the Workout health info"
severity: major

### 8. Dashboard HealthKit Summary
expected: Dashboard shows HealthKit summary section with enabled category count and oldest update time (e.g., "3 categories, oldest: 5 min ago").
result: pass

### 9. Dashboard Inline Refresh
expected: Dashboard HealthKit summary has inline refresh button. Tapping shows loading indicator during refresh.
result: pass

## Summary

total: 9
passed: 7
issues: 1
pending: 0
skipped: 1

## Gaps

- truth: "Manual refresh completes for all categories including Workouts in reasonable time"
  status: failed
  reason: "User reported: pressing the button starts the loading indicator, all the categories are updated except the Workout category and the spinner is not going away, either its stuck or its taking a very very very long time to update the Workout health info"
  severity: major
  test: 7
  root_cause: "Initial sync attempts to import ALL historical HealthKit data (500+ workouts). Each workout triggers heart rate query (~100-500ms). No time-bound predicate limits scope."
  artifacts:
    - path: "apps/ios/trendy/Services/HealthKit/HealthKitService+CategoryProcessing.swift"
      issue: "HKAnchoredObjectQuery has no date predicate - fetches entire history"
    - path: "apps/ios/trendy/Services/HealthKit/HealthKitService+WorkoutProcessing.swift"
      issue: "Heart rate enrichment runs for every workout including bulk imports"
  missing:
    - "Default date predicate: last 30 days for initial sync"
    - "User setting to control historical import depth"
    - "UI to trigger extended historical import on demand"
  debug_session: ".planning/debug/resolved/healthkit-workout-refresh-hang.md"
  fix_approach: |
    1. Add 30-day date predicate to anchored queries for initial sync (no anchor exists)
    2. Add "Import Historical Data" option in HealthKit Settings
    3. Historical import shows progress and estimated time
    4. Skip heart rate enrichment for bulk historical imports
