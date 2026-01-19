---
status: investigating
trigger: "Active energy for January 12th is not showing after reconciliation, but workouts work"
created: 2026-01-18T18:00:00Z
updated: 2026-01-18T18:00:00Z
---

## Current Focus

hypothesis: Either findEventByHealthKitSampleId finds existing event OR HealthKit statistics query returns no/zero data for Jan 12
test: Build app with debug logging, trigger reconciliation, check logs for Jan 12 specifically
expecting: Logs will show: 1) [RECONCILE] Checking date for 2026-01-12, 2) [ACTIVE_ENERGY] aggregateDailyActiveEnergyForDate called, 3) HealthKit query result
next_action: User needs to run app and check logs for [RECONCILE] and [ACTIVE_ENERGY] tags

## Symptoms

expected: Active energy for January 12th should show after reconciliation
actual: Active energy for today shows, workouts reconcile correctly, but Jan 12 active energy missing
errors: None observed - silent failure
reproduction: Run reconcileHealthKitData, check Jan 12 active energy
started: Discovered during debugging - workouts fixed, daily aggregates partially broken

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-01-18T18:00:00Z
  checked: reconcileDailyAggregates code flow
  found: |
    1. Iterates from startDate to today
    2. For each day, builds sampleId like "activeEnergy-2026-01-12"
    3. Calls findEventByHealthKitSampleId(sampleId)
    4. If nil, removes from processedSampleIds and calls aggregateDailyActiveEnergyForDate
    5. aggregateDailyActiveEnergyForDate queries HealthKit statistics for that day
  implication: Need to trace where Jan 12 fails - either event exists OR HK returns no data

- timestamp: 2026-01-18T18:05:00Z
  checked: Code structure analysis
  found: |
    - dateOnlyFormatter uses UTC timezone
    - reconcileDailyAggregates uses Calendar.current (local timezone) for date iteration
    - HealthKit query uses local timezone startOfDay/endOfDay
    - There is a SECOND findEventByHealthKitSampleId call inside aggregateDailyActiveEnergyForDate
  implication: Added detailed [ACTIVE_ENERGY] and [RECONCILE] tagged logging to trace exact flow

- timestamp: 2026-01-18T18:15:00Z
  checked: processSample flow for activeEnergy
  found: |
    - processSample for activeEnergy calls aggregateDailyActiveEnergy() with NO date argument
    - aggregateDailyActiveEnergy() always processes TODAY (Date())
    - This means individual historical samples all trigger TODAY's aggregation (wasteful but not harmful)
    - reconcileDailyAggregates IS called afterward and iterates through historical days
    - activeEnergy events use synthetic sampleIds like "activeEnergy-2026-01-12"
    - Individual HK samples have different UUIDs, so they're always "new" to the sample loop
  implication: The historical processing is correct - need logs to see why Jan 12 specifically fails

## Resolution

root_cause:
fix:
verification:
files_changed: []
