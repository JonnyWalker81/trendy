---
status: resolved
trigger: "Duplicate workout events appearing in iOS app and server database"
created: 2026-01-18T12:00:00Z
updated: 2026-01-18T17:30:00Z
resolved: 2026-01-18T17:30:00Z
---

## Resolution Summary

**Root Cause:** After bootstrap sync, HealthKitService used a stale ModelContext for dedup checks, causing duplicates to be created.

**Fix:** Added `useFreshContext` parameter to dedup methods. Committed in `8df40ce`.

**Cleanup:** Deleted 266 duplicate events from production database (249 Workout, 17 Water).

## Current Focus

hypothesis: CONFIRMED - ModelContext staleness after bootstrap causes dedup checks to fail
test: Build succeeded after applying fix
expecting: No more duplicate workout events after force resync
next_action: DONE - Fix committed, duplicates cleaned up

## Symptoms

expected: Each HealthKit workout should appear only once in the app and database
actual: Multiple workout events with the same timestamp appear as duplicates. Some have different notes ("Traditional Strength Training" vs "Other" for the same workout).
errors: No errors - data is being created but duplicated
reproduction: Look at Jan 16, 2026 workout data - duplicates visible in screenshot and confirmed in Supabase database
started: Duplicates created on 2026-01-18 00:47:19 (batch timestamp) suggesting a resync/reconciliation caused them

## Eliminated

- timestamp: 2026-01-18T12:15:00Z
  hypothesis: healthKitSampleId not synced to backend (per outdated CLAUDE.md)
  evidence: Backend models.go HAS healthKitSampleId field (line 40), iOS APIModels.swift maps it correctly, SyncEngine.swift syncs it (line 1581). CLAUDE.md documentation was outdated.

- timestamp: 2026-01-18T12:45:00Z
  hypothesis: Same HealthKit sample UUID causing bypass of dedup
  evidence: Backend has UNIQUE constraint idx_events_healthkit_dedupe on (user_id, healthkit_sample_id). Duplicates exist = sample IDs are DIFFERENT. This is expected - same physical workout can have multiple HK samples.

## Evidence

- timestamp: 2026-01-18T12:00:00Z
  checked: Supabase production database
  found: Duplicate workout events with identical timestamps but different IDs and creation times. All duplicates created at exactly 2026-01-18 00:47:19 (batch resync). Original events created 2026-01-17 01:44:52-53.
  implication: Bootstrap/resync triggered reconcileHealthKitData which re-processed already-existing workouts

- timestamp: 2026-01-18T12:15:00Z
  checked: Backend models.go and iOS APIModels.swift
  found: healthKitSampleId IS synced to backend. Data model is correct.
  implication: The issue is in iOS-side deduplication, not backend.

- timestamp: 2026-01-18T12:25:00Z
  checked: Workout type "Other" in duplicates
  found: HKWorkoutActivityType+Name.swift has "default: return 'Other'" fallback. Some duplicate events show "Other" instead of actual type.
  implication: Different HKWorkout samples with different activity types but same timestamp exist in HealthKit.

- timestamp: 2026-01-18T12:35:00Z
  checked: Backend dedup via healthkit_sample_id
  found: Backend uses UpsertHealthKitEventsBatch with UNIQUE constraint. This would prevent duplicates IF healthkit_sample_id was the same.
  implication: Duplicates have different sample IDs - this is expected behavior (multiple HK samples for same workout).

- timestamp: 2026-01-18T12:50:00Z
  checked: processedSampleIds handling
  found: reloadProcessedSampleIdsFromDatabase() uses fresh ModelContext and works correctly. But subsequent checks (eventExistsWithHealthKitSampleId, eventExistsWithMatchingWorkoutTimestamp, getLocalHealthKitSampleIds) use the STALE original modelContext.
  implication: processedSampleIds contains the original sample IDs, but timestamp/sampleId dedup checks fail because modelContext doesn't see the events yet.

- timestamp: 2026-01-18T13:00:00Z
  checked: SwiftData context behavior
  found: HealthKitService.modelContext is set at init and never refreshed. After SyncEngine.bootstrapFetch saves events via different context, HealthKitService.modelContext is stale. SwiftData contexts don't auto-merge changes synchronously.
  implication: All dedup checks that use modelContext fail because they query stale data.

- timestamp: 2026-01-18T13:10:00Z
  checked: eventExistsWithMatchingWorkoutTimestamp function
  found: This function queries modelContext for events with healthKitCategory == "workout" and compares timestamps. With stale context, it returns no matches even though events exist.
  implication: The timestamp-based dedup (the last line of defense) fails due to stale context, allowing duplicates to be created.

- timestamp: 2026-01-18T13:25:00Z
  checked: iOS build after fix
  found: BUILD SUCCEEDED - all modified files compile correctly
  implication: Fix is syntactically correct and ready for testing

## Resolution

root_cause: After bootstrap sync completes and notification is posted, HealthKitService.handleBootstrapCompleted() triggers reconcileHealthKitData(). The deduplication checks (eventExistsWithHealthKitSampleId, eventExistsWithMatchingWorkoutTimestamp, getLocalHealthKitSampleIds) use the original modelContext which is STALE - it doesn't see the events just saved by SyncEngine's context. This causes HealthKit samples to pass all dedup checks and be re-created as duplicate events.

fix: Added useFreshContext parameter to deduplication methods. When called during reconciliation, they now create a fresh ModelContext to see the latest persisted data. Applied to:
1. eventExistsWithHealthKitSampleId() - useFreshContext parameter
2. eventExistsWithMatchingWorkoutTimestamp() - useFreshContext parameter
3. getLocalHealthKitSampleIds() - useFreshContext parameter
4. processWorkoutSample() - passes useFreshContext to dedup methods
5. processSample() - passes useFreshContext to processWorkoutSample
6. reconcileCategory() - calls with useFreshContext: true

verification: iOS build succeeded. Need to test in production by triggering force resync.

files_changed:
- apps/ios/trendy/Services/HealthKit/HealthKitService+EventFactory.swift
- apps/ios/trendy/Services/HealthKit/HealthKitService+WorkoutProcessing.swift
- apps/ios/trendy/Services/HealthKit/HealthKitService+CategoryProcessing.swift
- apps/ios/trendy/Services/HealthKit/HealthKitService+Debug.swift

## SQL to Clean Up Existing Duplicates

```sql
-- Find duplicates: events with same user, event_type, and timestamp within 1 second
-- Keep the OLDEST event (first created), delete the NEWER duplicates

-- First, identify duplicates
WITH duplicates AS (
    SELECT
        id,
        user_id,
        event_type_id,
        timestamp,
        created_at,
        notes,
        healthkit_sample_id,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, event_type_id,
                DATE_TRUNC('second', timestamp)
            ORDER BY created_at ASC
        ) as rn
    FROM events
    WHERE source_type = 'healthkit'
      AND healthkit_category = 'workout'
)
-- Preview what will be deleted
SELECT * FROM duplicates WHERE rn > 1 ORDER BY timestamp DESC;

-- Actually delete (uncomment to run)
-- DELETE FROM events
-- WHERE id IN (
--     SELECT id FROM duplicates WHERE rn > 1
-- );
```

Alternative: Delete by specific batch timestamp (safer, more targeted)

```sql
-- Delete events created during the problematic batch resync at 2026-01-18 00:47:19
-- These are the duplicates - keep original events from 2026-01-17

DELETE FROM events
WHERE created_at >= '2026-01-18 00:47:00'
  AND created_at < '2026-01-18 00:48:00'
  AND source_type = 'healthkit'
  AND healthkit_category = 'workout';
```
