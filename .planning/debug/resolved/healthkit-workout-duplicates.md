---
status: investigating
trigger: "healthkit-workout-duplicates: Duplicate workout events appearing in iOS app after sync/clear local data"
created: 2026-01-19T10:00:00Z
updated: 2026-01-19T10:05:00Z
---

## Current Focus

hypothesis: Two possible causes: (1) Backend already has duplicate events from before content-based dedup was implemented - bootstrap downloads these duplicates directly. (2) Timestamp-based dedup on iOS failing for some reason during reconciliation.
test: Run app with diagnostic logging to trace dedup checks, also check backend for existing duplicates
expecting: Logs will reveal if duplicates come from backend (candidateCount > expected) or are created locally (all dedup checks fail)
next_action: Build in Xcode (xcodebuild SPM issue - use Xcode GUI), run app, trigger Force Full Resync, then share logs with [DEDUP-*] prefix

## Symptoms

expected: Each workout from HealthKit should appear exactly once in the Trendy iOS app event list.
actual: Multiple workouts at the same time appear duplicated (e.g., two "Traditional Strength Training" at 4:19 PM, two "Running" at 3:43 PM).
errors: No explicit errors shown. Duplicates appear after "Force Full Resync" or clearing local data.
reproduction: 1) Clear local data or force full resync. 2) Wait for sync. 3) Navigate to Events - duplicates visible.
started: Duplicates reappear immediately after sync when local data was cleared.

## Eliminated

## Evidence

- timestamp: 2026-01-19T10:00:00Z
  checked: iOS dedup flow in processWorkoutSample()
  found: Three-layer dedup: (1) in-memory processedSampleIds set, (2) eventExistsWithHealthKitSampleId DB check, (3) eventExistsWithMatchingWorkoutTimestamp DB check
  implication: If all three fail, duplicate is created

- timestamp: 2026-01-19T10:02:00Z
  checked: handleBootstrapCompleted() in HealthKitService
  found: After bootstrap: (1) clears all anchors, (2) clears daily aggregate timestamps, (3) calls reloadProcessedSampleIdsFromDatabase() which replaces processedSampleIds with DB values, (4) calls reconcileHealthKitData(days: 30)
  implication: After bootstrap, processedSampleIds contains server-side sample IDs. If HealthKit has different sample IDs for same workouts, layer 1 and 2 dedup fail - only layer 3 (timestamp matching) can prevent duplicates

- timestamp: 2026-01-19T10:03:00Z
  checked: eventExistsWithMatchingWorkoutTimestamp() in HealthKitService+EventFactory.swift
  found: Matches events where BOTH startDate and endDate match within 1.0 second tolerance, AND healthKitCategory == "workout"
  implication: If endDate precision is lost during server round-trip (e.g., truncated to seconds), the endDate check may fail

- timestamp: 2026-01-19T10:04:00Z
  checked: Backend content-based dedup in event.go
  found: Backend uses healthKitContentKey() = userID|eventTypeID|timestamp.Truncate(time.Second)|category - NO endDate in the key!
  implication: Backend dedup doesn't consider endDate, but iOS dedup DOES. This means backend could accept event as "not duplicate" while iOS sees it as duplicate later

- timestamp: 2026-01-19T10:05:00Z
  checked: reconcileCategory() in HealthKitService+Debug.swift line 287-307
  found: For each sample NOT in localSampleIds or processedSampleIds, calls processSample() with useFreshContext=true. The processSample() calls processWorkoutSample() which has all three dedup layers.
  implication: The useFreshContext=true should make dedup checks see fresh data. Need to verify if the issue is in timestamp precision or EventType matching.

- timestamp: 2026-01-19T10:30:00Z
  checked: Added diagnostic logging to three key functions
  found: Added [DEDUP-WORKOUT], [DEDUP-TIMESTAMP], [DEDUP-RELOAD] log prefixes to:
    - processWorkoutSample(): Logs all three dedup checks with pass/fail status
    - eventExistsWithMatchingWorkoutTimestamp(): Logs candidate count, timestamp diffs, close matches
    - reloadProcessedSampleIdsFromDatabase(): Logs workout events found after bootstrap
  implication: Next run will produce detailed logs showing exactly why dedup fails

- timestamp: 2026-01-19T10:45:00Z
  checked: Full data flow from backend to iOS
  found: Backend GetByUserID uses SELECT * which includes healthkit_category. iOS APIEvent properly maps the field. Bootstrap saves it to local Event. The eventExistsWithMatchingWorkoutTimestamp query filters by healthKitCategory == "workout".
  implication: If healthkit_category is null in backend, iOS events won't match the dedup query predicate

## Resolution

root_cause:
fix:
verification:
files_changed: []
