---
status: resolved
trigger: "healthkit-duplicates-production - Production database has duplicate events from HealthKit syncs"
created: 2026-01-19T00:00:00Z
updated: 2026-01-19T15:30:00Z
---

## Current Focus

hypothesis: RESOLVED - All duplicates cleaned up, current code prevents future duplicates
test: Verified 0 duplicates remain after cleanup
expecting: N/A - issue resolved
next_action: Archive debug session

## Symptoms

expected: No duplicate events in production database - each HealthKit sync should only create unique entries based on healthkit_sample_id, content/timestamp combination, and external_id
actual: Duplicate events exist from past HealthKit syncs - duplicates by HealthKit sample ID, same content/timestamp, and same external_id
errors: No error messages - duplicates silently exist in database
reproduction: Duplicates already exist in production from past syncs
started: Past HealthKit syncs created duplicates, recent code changes (commit 65b91be) added content-based deduplication

## Eliminated

## Evidence

- timestamp: 2026-01-19T00:01:00Z
  checked: Backend deduplication code in apps/backend/internal/repository/event.go
  found: Current implementation has TWO deduplication strategies for HealthKit events:
    1. Sample ID deduplication via GetByHealthKitSampleIDs() - checks healthkit_sample_id uniqueness
    2. Content-based deduplication via GetByHealthKitContent() - checks (user_id, event_type_id, timestamp, healthkit_category) combination
  implication: Current code should prevent new duplicates; need to clean up existing duplicates created before commit 65b91be

- timestamp: 2026-01-19T00:02:00Z
  checked: Production database for duplicate healthkit_sample_id
  found: 0 duplicates by healthkit_sample_id - unique index is working correctly
  implication: No duplicates where the same sample ID was inserted twice

- timestamp: 2026-01-19T00:03:00Z
  checked: Production database for content-based duplicates (user_id, event_type_id, timestamp)
  found: 28 duplicate sets (56 total events, 28 extras to delete)
  implication: HealthKit database was restored/reset at some point, causing new sample IDs for same workouts

- timestamp: 2026-01-19T00:04:00Z
  checked: Example duplicate pair (019bd751-33c2-72de-9f1f-8f66d571336f, 019bc99f-8f2a-7c57-8812-f093f00834d5)
  found: Same user/event_type/timestamp/category but DIFFERENT healthkit_sample_id
    - First created: 2026-01-17 01:44:41 (sample ID: 479AB605-6BEA-424F-875C-A5B37BC85EAD)
    - Second created: 2026-01-19 18:41:42 (sample ID: FC22BE95-B4AE-4B4C-A528-2F84F7AA7499)
  implication: iOS HealthKit database was reset between Jan 17-19, new sample IDs assigned to same workouts

- timestamp: 2026-01-19T00:05:00Z
  checked: Production database for duplicate external_id
  found: 0 duplicates by external_id
  implication: Calendar imports are not creating duplicates

## Resolution

root_cause: HealthKit database was restored/reset between Jan 17-19, 2026, causing Apple HealthKit to assign new sample IDs to existing workouts. When the iOS app synced with these new sample IDs, the backend (before commit 65b91be added content-based deduplication) created new events because the sample IDs didn't match any existing records. This resulted in 28 duplicate workout events.

fix:
  1. Deleted 28 duplicate events from production database using SQL:
     ```sql
     WITH duplicates AS (
         SELECT id, ROW_NUMBER() OVER (
             PARTITION BY user_id, event_type_id, timestamp
             ORDER BY created_at ASC
         ) as row_num
         FROM events WHERE source_type = 'healthkit'
     )
     DELETE FROM events WHERE id IN (SELECT id FROM duplicates WHERE row_num > 1);
     ```
  2. Kept the older record from each duplicate pair (preserved original healthkit_sample_id)

verification:
  - Verified 0 content-based duplicates remain in production
  - Verified 0 sample_id-based duplicates (unique index working)
  - Verified 0 external_id duplicates (calendar imports clean)
  - Verified 0 non-HealthKit duplicates (manual/imported/geofence clean)
  - Commit 65b91be already in production to prevent future duplicates

files_changed: []

deleted_event_ids:
  - 019bd751-23f6-74f0-ba3d-5b4d83fb9fec
  - 019bd751-25c4-7bdc-b419-4633ed342a1b
  - 019bd751-0796-77d4-ae72-42fe300aa37c
  - 019bd751-090d-7177-8e2d-ddae7ebcd971
  - 019bd751-09c8-76bb-ac62-5cd854df1d8c
  - 019bd751-0cc5-7ea3-884e-dc5687448ad9
  - 019bd751-0e85-762b-b48b-cfbb74d5994e
  - 019bd751-0f3c-7b55-9c65-1893bb0c1eec
  - 019bd751-13d5-7264-bfc1-027b31ed92b7
  - 019bd751-15c8-73a1-98b5-cd3f9f674a8d
  - 019bd751-1682-74ba-8f1a-668816c6a020
  - 019bd751-1953-7a89-a59c-29361be33c39
  - 019bd751-1cb4-7b64-9d66-06c0c6784b50
  - 019bd751-1d6f-767d-8c38-6c8d1504f966
  - 019bd751-1e2b-711e-90cb-ec37c373ef40
  - 019bd751-22a2-7d4b-9b92-2d2c26124d43
  - 019bd751-273f-7041-983c-2276905641f9
  - 019bd751-27ff-73f7-a1d5-0a3b9733231c
  - 019bd751-2949-75eb-8d49-6c2df5c21035
  - 019bd751-2a0d-7e67-852b-b0372968f375
  - 019bd751-2acc-7fe6-9720-6e80b4430e1b
  - 019bd751-2b8c-7b7f-9bd4-bc416931c3ea
  - 019bd751-2de9-75d4-9fe9-ec1b47fab0cf
  - 019bd751-2fe3-758e-94f8-acc81fcb8e83
  - 019bd751-30a0-70e9-8c8d-574d91a9ae0f
  - 019bd751-32fd-7b85-9ecc-04f3425f80af
  - 019bd751-33c2-72de-9f1f-8f66d571336f
  - 019bd7be-8afa-7a66-bb28-cfa2bf0d4e17
