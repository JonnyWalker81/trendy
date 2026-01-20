---
status: resolved
trigger: "Workout duplicates created when endDiff=1.000 exactly"
created: 2026-01-19T00:00:00Z
updated: 2026-01-19T00:05:00Z
---

## Current Focus

hypothesis: Tolerance comparison uses strict less-than (<) instead of less-than-or-equal (<=), causing 1.0 second differences to fail matching
test: Found exact line in code - lines 134, 139, 215 use `< tolerance`
expecting: Changing to `<= tolerance` will fix the boundary condition
next_action: COMPLETE - fix applied and verified

## Symptoms

expected: Workouts with timestamps differing by exactly 1 second should be deduplicated
actual: Workouts with endDiff=1.000 create duplicates
errors: None - logic error in comparison
reproduction: Import workout from HealthKit where server-stored endDate has 1-second truncation difference
started: Always broken - boundary condition never handled

## Eliminated

(none - first hypothesis confirmed)

## Evidence

- timestamp: 2026-01-19T00:00:00Z
  checked: eventExistsWithMatchingWorkoutTimestamp() in HealthKitService+EventFactory.swift
  found: Line 134 uses `startDiff < tolerance`, Line 139 uses `endDiff! < tolerance`
  implication: When diff equals exactly 1.0 (the tolerance), comparison fails

- timestamp: 2026-01-19T00:00:01Z
  checked: eventExistsWithMatchingHealthKitContent() same file
  found: Line 215 uses `abs(event.timestamp.timeIntervalSince(timestamp)) < tolerance`
  implication: Same boundary condition bug exists in content-based deduplication

- timestamp: 2026-01-19T00:00:02Z
  checked: User-provided diagnostic logs
  found: All failures have endDiff=1.000, all passes have endDiff=0.000
  implication: 1-second boundary is exact failure point

- timestamp: 2026-01-19T00:03:00Z
  checked: Grep for remaining `< tolerance` patterns
  found: No remaining instances after fix - all now use `<= tolerance`
  implication: Fix is complete and consistent

- timestamp: 2026-01-19T00:04:00Z
  checked: iOS build compilation
  found: BUILD SUCCEEDED
  implication: Fix compiles without errors

## Resolution

root_cause: Tolerance comparison uses `<` instead of `<=`. When timestamp difference equals exactly the tolerance value (1.0 seconds), the comparison `1.0 < 1.0` returns false, causing deduplication to fail.

fix: Changed `< tolerance` to `<= tolerance` at three locations:
- Line 134: startDiff comparison in eventExistsWithMatchingWorkoutTimestamp()
- Line 139: endDiff comparison in eventExistsWithMatchingWorkoutTimestamp()
- Line 215: timestamp comparison in eventExistsWithMatchingHealthKitContent()

verification:
- iOS project builds successfully (BUILD SUCCEEDED)
- All tolerance comparisons now use <= instead of <
- Test support file already used <= (consistency confirmed)

files_changed:
- apps/ios/trendy/Services/HealthKit/HealthKitService+EventFactory.swift
