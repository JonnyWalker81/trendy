---
status: resolved
trigger: "HealthKit events are duplicated locally on iOS but the backend has content-based deduplication. Need to implement similar deduplication on iOS."
created: 2026-01-19T10:00:00Z
updated: 2026-01-19T10:58:00Z
---

## Current Focus

hypothesis: iOS water processing lacks content-based deduplication - it only checks sample ID, not (eventTypeId, timestamp, healthKitCategory) tuple
test: Verify water processing code has no content-based dedup
expecting: Confirm processWaterSample only checks sampleId
next_action: Implement content-based dedup in iOS matching backend logic

## Symptoms

expected: HealthKit events should be deduplicated locally on iOS the same way the backend does content-based deduplication
actual: Events are duplicated locally on iOS. Server has some duplicates too (17 groups of "0 ml water" entries that predated the backend dedup)
errors: No errors - just duplicate data appearing
reproduction: Import HealthKit data, duplicates appear in the local iOS database
started: Backend deduplication was recently added (commit 65b91be). iOS never had this logic.

## Eliminated

## Evidence

- timestamp: 2026-01-19T10:05:00Z
  checked: Backend deduplication logic in event.go and repository/event.go
  found: Backend uses TWO deduplication strategies for HealthKit:
    1. Sample ID deduplication (healthkit_sample_id match)
    2. Content-based deduplication (event_type_id, timestamp, healthkit_category) match
  implication: Backend handles case where HealthKit sample IDs change (restore, migration) but content is identical

- timestamp: 2026-01-19T10:06:00Z
  checked: Backend healthKitContentKey function in repository/event.go:865
  found: Key format is "{userID}|{eventTypeID}|{timestamp truncated to seconds}|{healthKitCategory}"
  implication: This is the deduplication signature to match on iOS

- timestamp: 2026-01-19T10:07:00Z
  checked: iOS HealthKitService+EventFactory.swift - eventExistsWithHealthKitSampleId
  found: Only checks by healthKitSampleId (sample ID dedup only)
  implication: iOS lacks content-based dedup entirely

- timestamp: 2026-01-19T10:08:00Z
  checked: iOS HealthKitService+CategoryProcessing.swift - processWaterSample
  found: Only uses processedSampleIds (in-memory) and eventExistsWithHealthKitSampleId (database) checks
    - Line 338: guard !processedSampleIds.contains(sampleId)
    - Line 344: if await eventExistsWithHealthKitSampleId(sampleId)
  implication: No content-based dedup - if sample ID changes, duplicate is created

- timestamp: 2026-01-19T10:09:00Z
  checked: iOS HealthKitService+WorkoutProcessing.swift - processWorkoutSample
  found: HAS timestamp-based dedup for workouts! (lines 51-64)
    - eventExistsWithMatchingWorkoutTimestamp() checks start/end timestamp match
  implication: Workout has content-based dedup but water/mindfulness/sleep do NOT

## Resolution

root_cause: iOS HealthKit processing only has sample ID deduplication for water, mindfulness categories (not content-based like backend). When HealthKit sample IDs change (iOS restore, device migration, or HealthKit database reset), the same data gets reimported as duplicates because iOS doesn't check if an event with matching (eventTypeId, timestamp, healthKitCategory) already exists. Workouts have partial protection via timestamp matching but other categories do not.
fix: Added content-based deduplication matching backend logic:
  1. Added eventExistsWithMatchingHealthKitContent() to HealthKitService+EventFactory.swift
     - Checks for existing event with same (eventTypeId, timestamp within 1s, healthKitCategory)
  2. Updated processWaterSample() to call content-based dedup after sample ID check
  3. Updated processMindfulnessSample() to call content-based dedup after sample ID check
  4. Both methods now accept useFreshContext parameter for reconciliation flows
verification: Build succeeded (xcodebuild "trendy (local)" scheme)
files_changed:
  - apps/ios/trendy/Services/HealthKit/HealthKitService+EventFactory.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+CategoryProcessing.swift
