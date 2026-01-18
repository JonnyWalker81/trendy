---
status: verifying
trigger: "HealthKit widget on dashboard shows stale/old data and doesn't update even after manual refresh"
created: 2026-01-15T00:00:00Z
updated: 2026-01-15T00:02:00Z
---

## Current Focus

hypothesis: Fix applied - forceRefreshAllCategories now uses direct aggregation for daily aggregate categories
test: Build succeeded, need to verify on device
expecting: Manual refresh now properly updates steps/sleep/activeEnergy with current HealthKit data
next_action: Verify fix with manual testing

## Symptoms

expected: Widget should show current HealthKit data and update when refresh button is pressed
actual: Widget shows stale/old data that doesn't match what's in the Health app
errors: No errors in logs - refresh appears to complete successfully
reproduction: Press manual refresh button - logs show success but UI data remains stale
started: Never worked - widget has always shown stale data

## Eliminated

## Evidence

- timestamp: 2026-01-15T00:00:30Z
  checked: forceRefreshAllCategories method (line 2066)
  found: Calls handleNewSamples for each category, which uses anchored queries
  implication: Only processes NEW samples since last anchor

- timestamp: 2026-01-15T00:00:45Z
  checked: handleNewSamples method (lines 519-575)
  found: Uses HKAnchoredObjectQuery with currentAnchor. Only calls processSample if samples array is non-empty.
  implication: If anchor is up-to-date, no new samples returned, nothing processes

- timestamp: 2026-01-15T00:00:55Z
  checked: processSample for steps (lines 596-600)
  found: Only calls aggregateDailySteps when a raw step sample is processed
  implication: aggregateDailySteps never runs if no new raw samples

- timestamp: 2026-01-15T00:01:00Z
  checked: aggregateDailySteps (lines 991-1102)
  found: Has 5-minute throttle (lines 997-1003), but also directly queries HealthKit with HKStatisticsQuery (not anchored)
  implication: If called, it WOULD get current data. Issue is it's never called during force refresh.

- timestamp: 2026-01-15T00:01:30Z
  checked: Existing forceStepsCheck/forceSleepCheck/forceActiveEnergyCheck methods
  found: These properly bypass throttles and call aggregation directly
  implication: The correct pattern exists, just not used by forceRefreshAllCategories

- timestamp: 2026-01-15T00:02:00Z
  checked: Build result after fix
  found: BUILD SUCCEEDED
  implication: Fix compiles correctly

## Resolution

root_cause: forceRefreshAllCategories uses anchored queries which only return NEW samples. For daily aggregate categories (steps, sleep, active energy), no new raw samples means no re-aggregation occurs. The aggregation functions themselves query HealthKit correctly - they're just never called during force refresh.

fix: Modified forceRefreshAllCategories to:
1. For daily aggregate categories (steps, sleep, activeEnergy): use existing forceXxxCheck methods that bypass throttles and call aggregation directly
2. For non-aggregate categories (workout, mindfulness, water): continue using anchored query (correct behavior for event-based data)
3. Always call recordCategoryUpdate after processing each category so the UI shows the refresh occurred

verification: Build succeeded. Pending device testing:
1. Open app with stale HealthKit data visible
2. Press manual refresh button
3. Verify steps/sleep/active energy update to match Health app values
4. Verify "Updated X ago" shows recent time

files_changed:
- /Users/cipher/Repositories/trendy/apps/ios/trendy/Services/HealthKitService.swift
