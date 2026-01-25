---
status: resolved
trigger: "HealthKit workout events are being duplicated - two Workout entries at 1:38 PM with identical Auto-logged: Traditional Strength Training text"
created: 2026-01-25T00:00:00Z
updated: 2026-01-25T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED - Race condition between concurrent processWorkoutSample calls for same workout with different sample IDs
test: Implemented fix and comprehensive unit tests
expecting: Tests pass, duplicates no longer created
next_action: Archive session

## Symptoms

expected: Each HealthKit workout should appear only once in the events list
actual: Duplicate workout entries appear - two workouts at 1:38 PM (Traditional Strength Training)
errors: No error messages - duplicates silently appear
reproduction: HealthKit workouts are being duplicated
started: Currently happening (Jan 23, 2026 visible in screenshot)

## Eliminated

- hypothesis: processedSampleIds race condition
  evidence: The in-memory set uses early claim pattern correctly, but uses sample ID which differs between devices
  timestamp: 2026-01-25T00:02:00Z

- hypothesis: Backend sync creating duplicates
  evidence: Backend has content-based dedup, but duplicates are created locally BEFORE sync
  timestamp: 2026-01-25T00:03:00Z

## Evidence

- timestamp: 2026-01-25T00:00:30Z
  checked: HealthKitService+WorkoutProcessing.swift deduplication flow
  found: 3-layer deduplication exists: (1) processedSampleIds in-memory, (2) eventExistsWithHealthKitSampleId db check, (3) eventExistsWithMatchingWorkoutTimestamp
  implication: All three checks must fail for duplicate to be created

- timestamp: 2026-01-25T00:00:45Z
  checked: eventExistsWithMatchingWorkoutTimestamp tolerance
  found: Uses 1.0 second tolerance for both start and end timestamps
  implication: Different sample IDs for same workout should be caught by timestamp check

- timestamp: 2026-01-25T00:01:00Z
  checked: Backend deduplication in repository/event.go
  found: healthKitContentKey uses (eventTypeId, timestamp truncated to seconds, healthKitCategory)
  implication: Backend has better deduplication, but iOS creates duplicate locally first

- timestamp: 2026-01-25T00:04:00Z
  checked: Async interleaving in processWorkoutSample
  found: RACE CONDITION - When two workouts with different sample IDs but same timestamps are processed concurrently:
    1. Both pass processedSampleIds check (different IDs)
    2. Both pass eventExistsWithHealthKitSampleId (different IDs)
    3. Both start eventExistsWithMatchingWorkoutTimestamp check
    4. Due to async interleaving at await points, BOTH queries run BEFORE either createEvent
    5. Both timestamp checks return false (no event exists yet)
    6. Both create events -> DUPLICATE
  implication: Need mutex/lock at workout timestamp level, not sample ID level

- timestamp: 2026-01-25T00:05:00Z
  checked: Why same workout has different sample IDs
  found: HKWorkout objects can have different UUIDs when:
    - Recorded on Apple Watch and synced to iPhone
    - Multiple apps recording same workout
    - HealthKit mirroring between devices
  implication: Sample ID is NOT sufficient for deduplication of the same physical workout

## Resolution

root_cause: Race condition in processWorkoutSample - async interleaving allows multiple concurrent calls for the same workout (with different sample IDs) to both pass the timestamp check before either creates an event. The processedSampleIds mutex uses sample ID as key, but different devices can report the same workout with different sample IDs.

fix: Added workout-level mutex using normalized workout timestamp as the key. The fix:
  1. Added processingWorkoutTimestamps Set<String> to HealthKitService (HealthKitService.swift line 129)
  2. Added workoutTimestampKey() helper function to generate unique keys from start/end timestamps
  3. Added synchronous early claim of timestamp key BEFORE any async operations
  4. Used defer pattern to release the lock after processing completes (success or failure)
  5. The key uses truncated-to-second timestamps to handle sub-second variations

verification: Created comprehensive unit tests in WorkoutDeduplicationTests.swift:
  - WorkoutTimestampKeyTests: 6 tests for key generation logic
  - ProcessingWorkoutTimestampsMutexTests: 4 tests for mutex behavior
  - ConcurrentProcessingPreventionTests: 4 tests for race condition prevention
  All 14 tests pass.

files_changed:
  - apps/ios/trendy/Services/HealthKit/HealthKitService.swift (added processingWorkoutTimestamps property)
  - apps/ios/trendy/Services/HealthKit/HealthKitService+WorkoutProcessing.swift (added workoutTimestampKey() and mutex logic)
  - apps/ios/trendyTests/HealthKit/WorkoutDeduplicationTests.swift (new test file)
