---
status: resolved
trigger: "Workout HealthKit events are duplicated locally after sync/resync"
created: 2026-01-19T00:00:00Z
updated: 2026-01-19T00:10:00Z
---

## Current Focus

hypothesis: reconcileHealthKitData() runs after bootstrap sync and re-processes HealthKit samples, but the workout dedup check fails to see bootstrap data because it uses a stale ModelContext
test: Examine code flow from bootstrap notification through reconciliation to workout processing
expecting: Find where useFreshContext is not being passed or where context is stale
next_action: Read bootstrap notification handler and reconciliation code

## Symptoms

expected: After clearing local data and resyncing, workout events should match the server (no duplicates)
actual: Duplicate workout events appear locally (e.g., two "Running" at 3:43 PM, two "Traditional Strength Training" at 2:55 PM)
errors: No errors - just duplicate data appearing in the UI
reproduction:
  1. Clear all local data in iOS app
  2. Force resync from server
  3. Duplicates appear in the event list
started: Happens on every resync. Server confirmed to have NO duplicates.

## Eliminated

## Evidence

- timestamp: 2026-01-19T00:01:00Z
  checked: reconcileCategory() code flow
  found: At line 305 in HealthKitService+Debug.swift, reconcileCategory calls processSample with useFreshContext: true
  implication: The useFreshContext flag IS being passed correctly to processSample

- timestamp: 2026-01-19T00:02:00Z
  checked: processSample() dispatch to processWorkoutSample
  found: At line 245 in HealthKitService+CategoryProcessing.swift, processSample passes useFreshContext to processWorkoutSample
  implication: The flag is propagated correctly through the call chain

- timestamp: 2026-01-19T00:03:00Z
  checked: processWorkoutSample dedup checks
  found: processWorkoutSample does TWO dedup checks with useFreshContext: eventExistsWithHealthKitSampleId (line 40) and eventExistsWithMatchingWorkoutTimestamp (line 51-55)
  implication: Both workout dedup checks honor the useFreshContext flag

- timestamp: 2026-01-19T00:04:00Z
  checked: eventExistsWithMatchingWorkoutTimestamp implementation
  found: At line 120 in EventFactory.swift, it creates fresh context when useFreshContext=true and queries all workout events
  implication: The dedup logic appears correct, so why are duplicates appearing?

- timestamp: 2026-01-19T00:05:00Z
  checked: reconcileCategory() logic at lines 296-300 in HealthKitService+Debug.swift
  found: BUG FOUND! The code checks if sampleId is in processedSampleIds, removes it if found, but DOES NOT SKIP processing. It falls through to processSample().
  implication: This is the ROOT CAUSE. After bootstrap, processedSampleIds contains the HealthKit sample IDs from downloaded events. When reconcileCategory runs, it finds samples in processedSampleIds but not in localSampleIds (because localSampleIds is category-specific). The code removes from processedSampleIds but CONTINUES to process, creating duplicates.

## Resolution

root_cause: In reconcileCategory() at lines 296-300 of HealthKitService+Debug.swift, the code checks if sampleId is in processedSampleIds, and if so, removes it from the set - but does NOT return/continue to skip processing. The sample then falls through to processSample() which creates a duplicate event.

fix: Changed the logic at lines 296-300 in reconcileCategory() to simply continue (skip processing) when a sample is found in processedSampleIds. The old logic removed the sample from processedSampleIds but didn't skip, causing the sample to be processed and creating duplicates.

verification: Manual testing required - clear local data, force resync, verify no duplicate workouts appear.
files_changed:
  - apps/ios/trendy/Services/HealthKit/HealthKitService+Debug.swift
