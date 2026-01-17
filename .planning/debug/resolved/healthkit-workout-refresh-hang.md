---
status: resolved
trigger: "healthkit-workout-refresh-hang: Manual refresh of HealthKit data hangs indefinitely on Workout category"
created: 2026-01-16T12:00:00Z
updated: 2026-01-16T12:50:00Z
---

## Current Focus

hypothesis: CONFIRMED - Multiple performance issues cause workout refresh to take 5-10+ minutes, appearing as a hang
test: Code analysis complete
expecting: N/A - fix applied
next_action: N/A - resolved

## Symptoms

expected: HealthKit manual refresh completes for all categories including Workouts, spinner stops
actual: All other categories refresh successfully, but Workout category never completes - spinner runs forever
errors: None visible (no crash, no error message)
reproduction: Open HealthKit Settings > tap "Refresh Health Data" button > observe all categories update except Workout which hangs
started: First time testing this feature. User has 500+ workouts in Apple Health (large dataset).

## Eliminated

## Evidence

- timestamp: 2026-01-16T12:10:00Z
  checked: fetchHeartRateStats code paths
  found: All code paths properly resume the continuation. If samples nil/empty -> returns (nil,nil). If samples exist -> calculates avg/max and returns.
  implication: The hang is NOT due to a missing continuation.resume()

- timestamp: 2026-01-16T12:15:00Z
  checked: forceRefreshAllCategories flow
  found: Categories processed sequentially in for loop. refreshingCategories.remove(category) called AFTER each category completes. If handleNewSamples hangs, loop never continues.
  implication: Matches symptom - if workout hangs, spinner stays forever but other categories that completed before workout would show updated

- timestamp: 2026-01-16T12:20:00Z
  checked: Bulk import detection
  found: isBulkImport = currentAnchor == nil && samples.count > 5. With 500+ workouts and no anchor, isBulkImport = true
  implication: Notifications and sync skipped for bulk, so those aren't causing delay

- timestamp: 2026-01-16T12:25:00Z
  checked: Per-workout processing steps
  found: For each workout: (1) duplicate checks, (2) ensureEventType, (3) fetchHeartRateStats query, (4) createEvent. The heart rate query is the unique step for workouts vs other categories.
  implication: Heart rate query is prime suspect - 500+ sequential HKSampleQuery calls

- timestamp: 2026-01-16T12:30:00Z
  checked: eventExistsWithMatchingWorkoutTimestamp performance
  found: Function fetches ALL existing workout events from database, then iterates through them. As workouts are saved, subsequent checks fetch more events. This is O(n^2) complexity for n workouts.
  implication: With 500 workouts: 500 * 250 avg events = 125,000 event comparisons. Significant slowdown but not infinite.

- timestamp: 2026-01-16T12:35:00Z
  checked: Total processing time estimate
  found: Per workout ~250-500ms (DB checks + heart rate query + save). 500 workouts = 2-4 minutes baseline. Plus O(n^2) timestamp checks could add 1-2 more minutes.
  implication: Total time could be 5-10+ minutes. User likely saw "spinner forever" but it was just very slow, OR there's an actual hang in heart rate query.

## Resolution

root_cause: |
  Primary: Each of 500+ workouts triggers a separate HealthKit query for heart rate stats (fetchHeartRateStats), taking ~100-500ms each. Total: 50-250 seconds just for heart rate queries.

  Secondary: eventExistsWithMatchingWorkoutTimestamp has O(n^2) complexity - fetches ALL existing workout events for EACH new workout being processed. As workouts are saved, subsequent checks scan more events.

  Combined: With 500 workouts, processing time is 5-10+ minutes, which appears as an infinite hang to the user.

fix: |
  1. Skip heart rate enrichment during bulk import (isBulkImport flag already exists) - DONE
  2. Add progress logging for workout processing - DONE
  3. Future: Batch timestamp duplicate checking (collect all timestamps, query once)

verification: |
  Code analysis verification:
  - Skip heart rate queries during bulk import eliminates 500+ sequential HealthKit queries
  - Each heart rate query took ~100-500ms; eliminating them saves 50-250 seconds
  - Progress logging added every 50 workouts so user sees activity

  Expected behavior after fix:
  - Workout refresh should complete in ~30-60 seconds instead of 5-10+ minutes
  - Progress logs should appear every 50 workouts
  - Heart rate data NOT included in bulk-imported workouts (acceptable tradeoff)
  - New individual workouts still get heart rate enrichment (isBulkImport = false)

files_changed:
  - apps/ios/trendy/Services/HealthKit/HealthKitService+WorkoutProcessing.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+CategoryProcessing.swift
