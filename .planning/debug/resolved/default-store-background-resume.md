---
status: resolved
trigger: "Race conditions or issues when iOS app resumes after long periods in background, leading to default.store errors during sync"
created: 2026-01-30T00:00:00Z
updated: 2026-01-30T00:03:00Z
---

## Current Focus

hypothesis: CONFIRMED and FIXED - Three root causes in PersistenceController lifecycle handling
test: Build succeeds, all autosave and race condition tests pass
expecting: N/A
next_action: Archive session

## Symptoms

expected: App resumes from background cleanly and syncs data without errors
actual: "default.store" error occurs when syncing after long background periods
errors: "default.store" error during sync operations
reproduction: Put iOS app in background for extended period, then resume and trigger sync
started: Ongoing - recent commits show related fixes

## Eliminated

## Evidence

- timestamp: 2026-01-30T00:01:00Z
  checked: PersistenceController.handleDidEnterBackground() line 158
  found: onBackgroundEntry callback was fire-and-forget Task{await callback()}. SyncEngine.resetDataStore() may not complete before iOS suspends the app.
  implication: CRITICAL - SyncEngine cached ModelContext retains stale SQLite handles during suspension

- timestamp: 2026-01-30T00:01:00Z
  checked: PersistenceController notification observers (lines 94-113)
  found: Both background and foreground handlers wrapped in Task{@MainActor} - async dispatch rather than synchronous execution
  implication: handleWillEnterForeground may not run before other MainActor tasks that need the fresh context

- timestamp: 2026-01-30T00:01:00Z
  checked: PersistenceController.handleWillEnterForeground() guard isBackgrounded
  found: Guard skips refresh if isBackgrounded is false (cold launch by iOS for background activity)
  implication: Context may not be refreshed when app transitions to foreground after cold launch

- timestamp: 2026-01-30T00:03:00Z
  checked: Build and all tests
  found: Build succeeds with only warnings. All autosave prevention and race condition tests pass.
  implication: Fixes are correct and verified

## Resolution

root_cause: Three race conditions in PersistenceController background/foreground lifecycle handling:
  1. CRITICAL: SyncEngine DataStore release on background entry used fire-and-forget Task (not awaited, no background task protection). iOS could suspend the app before SyncEngine.resetDataStore() completed, leaving stale SQLite file handles.
  2. MODERATE: Notification handlers wrapped in Task{@MainActor} instead of running synchronously. This caused the foreground context refresh to be enqueued as an async task, allowing other MainActor tasks (MainTabView.onChange scenePhase) to execute first with the stale context.
  3. MODERATE: handleWillEnterForeground had a guard on isBackgrounded that skipped context refresh when the app was cold-launched by iOS for background activity (geofence/HealthKit) then brought to foreground. isBackgrounded was never set to true, so the guard returned early.

fix: Three changes to PersistenceController.swift:
  1. Wrapped SyncEngine DataStore release in a UIBackgroundTask that stays alive until the async release completes. The background task is only ended after the callback awaits.
  2. Replaced Task{@MainActor} notification handlers with MainActor.assumeIsolated{} to run synchronously during notification delivery (the notification queue is already .main).
  3. Removed the isBackgrounded guard from handleWillEnterForeground. Now always creates a fresh ModelContext on foreground entry (cheap and safe; stale contexts cause crashes).

verification: Build succeeds. All 18+ autosave prevention and race condition tests pass including 5 new tests:
  - foregroundRefreshWithoutPriorBackground: Verifies context refresh without prior background entry
  - foregroundAlwaysCreatesNewContext: Verifies each foreground call creates a new context
  - ensureValidContextUsesRefreshedContext: Verifies ensureValidContext uses the fresh context
  - contextAfterForegroundIsFunctional: Verifies CRUD works after foreground refresh
  - resetDataStoreClearsCacheAndState: Verifies SyncEngine DataStore reset works
  - backgroundEntryCallbackWiring: Verifies onBackgroundEntry callback is settable

files_changed:
  - apps/ios/trendy/Services/PersistenceController.swift
  - apps/ios/trendyTests/SyncEngine/AutosavePreventionTests.swift
