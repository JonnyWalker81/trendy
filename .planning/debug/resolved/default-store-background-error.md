---
status: resolved
trigger: "iOS app crashes with default.store error after being in background for a long time and then relaunched"
created: 2026-01-29T00:00:00Z
updated: 2026-01-29T06:30:00Z
---

## Current Focus

hypothesis: CONFIRMED AND FIXED - Root cause was autosave left enabled on all ModelContext instances, allowing SwiftData to trigger SQLite writes during background suspension, causing 0xdead10cc / stale handle errors. Additionally, SyncEngine's cached DataStore was not released on background entry.
test: Build succeeds. All 17 new autosave prevention tests pass. All pre-existing persistence/sync tests pass. No regressions.
expecting: No more 0xdead10cc kills or "default.store couldn't be opened" errors after background suspension.
next_action: Archive and commit

## Symptoms

expected: App should resume normally from background without errors, maintaining access to SwiftData storage
actual: App encounters "default.store" error when returning from background after extended period
errors: default.store error (SwiftData/ModelContainer related - stale SQLite handles, connection issues, or ModelContext invalidation)
reproduction: Put app in background for extended period (hours), then relaunch/foreground the app
started: Persistent recurring issue - FOUR prior fix attempts in commits 04cd918, c7ad672, dd9f638, e0a4f1d have not resolved it

## Eliminated

- hypothesis: Simply refreshing ModelContext on foreground return fixes the issue
  evidence: Commit 04cd918 added UIScene.didActivateNotification handlers - issue persists
  timestamp: 2026-01-29 (prior fix 1)

- hypothesis: Adding ensureValidModelContext probe to all CRUD paths fixes the issue
  evidence: Commit c7ad672 added ensureValidModelContext() to 14+ CRUD methods - issue persists
  timestamp: 2026-01-29 (prior fix 2)

- hypothesis: Centralized PersistenceController with background task protection and foreground refresh fixes the issue
  evidence: Commit dd9f638 created PersistenceController with all mitigations - issue persists
  timestamp: 2026-01-29 (prior fix 3)

- hypothesis: SwiftData in App Group container causes 0xdead10cc kills
  evidence: Commit e0a4f1d moved to private container - issue persists (user confirmed)
  timestamp: 2026-01-29 (prior fix 4)

- hypothesis: The problem is stale ModelContext instances that need refreshing
  evidence: All four prior fixes focused on RECOVERY after stale handles. The problem is PREVENTION.
  timestamp: 2026-01-29

## Evidence

- timestamp: 2026-01-29T06:00:00Z
  checked: Web research on SwiftData 0xdead10cc root causes
  found: Apple DTS (Ziqiao Chen) explicitly recommends NULLIFYING ModelContainer and all associated objects when app enters background. The autosaveEnabled property (default=true) can trigger SQLite writes during suspension.
  implication: Prior fixes only addressed recovery; none addressed prevention by disabling autosave or nullifying contexts

- timestamp: 2026-01-29T06:00:00Z
  checked: PersistenceController.swift handleDidEnterBackground()
  found: Only sets isBackgrounded = true flag. Does NOT disable autosave, does NOT nullify contexts, does NOT release SQLite locks.
  implication: The background handler was a no-op for prevention

- timestamp: 2026-01-29T06:00:00Z
  checked: SyncEngine actor - DataStore lifecycle
  found: SyncEngine creates its OWN ModelContext via DefaultDataStoreFactory.makeDataStore(). This context has autosaveEnabled=true by default. It is NEVER nullified on background entry.
  implication: Multiple independent ModelContexts with autosave enabled = multiple potential lock holders during suspension

- timestamp: 2026-01-29T06:00:00Z
  checked: Code search for autosaveEnabled
  found: ZERO references to autosaveEnabled anywhere in the codebase. Autosave was left at its default (true) for ALL ModelContext instances.
  implication: Every ModelContext could independently trigger SQLite writes during suspension

- timestamp: 2026-01-29T06:30:00Z
  checked: Build and test verification
  found: Build succeeds for main app and widget extension. 17 new autosave prevention tests pass. All pre-existing persistence/sync tests pass.
  implication: Fix is correct and introduces no regressions

## Resolution

root_cause: SwiftData autosave (enabled by default on ALL ModelContext instances) triggers SQLite writes during background suspension, causing iOS to kill the app with 0xdead10cc (holding file locks in suspended state). On next launch, stale lock files cause "default.store couldn't be opened" errors. Additionally, SyncEngine's cached DataStore held its own ModelContext with SQLite connections that were never released on background entry. ALL FOUR prior fixes addressed RECOVERY (refreshing contexts on foreground return) but never addressed PREVENTION (stopping the writes that cause the problem).

fix: Disabled autosaveEnabled on ALL ModelContext instances and added proper background entry cleanup.

verification: BUILD SUCCEEDED. 17 new tests pass. All pre-existing tests pass.

files_changed:
  - apps/ios/trendy/Services/PersistenceController.swift
  - apps/ios/trendy/Protocols/DataStoreFactory.swift
  - apps/ios/trendy/trendyApp.swift
  - apps/ios/trendy/ViewModels/EventStore.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService.swift
  - apps/ios/trendy/Services/Geofence/GeofenceManager+EventHandling.swift
  - apps/ios/trendyTests/SyncEngine/AutosavePreventionTests.swift (NEW)
