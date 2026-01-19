---
status: verifying
trigger: "Sync history view never shows any entries despite sync operations working correctly"
created: 2026-01-18T12:00:00Z
updated: 2026-01-18T12:15:00Z
---

## Current Focus

hypothesis: CONFIRMED - SyncHistoryStore methods were never called from sync code path
test: Build passed, fix implemented
expecting: Sync history should now populate after sync operations
next_action: User verification - trigger sync and check history view

## Symptoms

expected: Sync history should display records of sync operations (when syncs happen, what synced, etc.)
actual: Sync history view is always empty - has never shown any history since the feature was implemented
errors: No visible errors in UI or console
reproduction: Open sync history view after performing sync operations - always empty
timeline: Never worked since feature was implemented

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-01-18T12:01:00Z
  checked: SyncHistoryStore.swift implementation
  found: Store has proper methods: recordSuccess(events:eventTypes:durationMs:), recordFailure(errorMessage:durationMs:), stores in UserDefaults with key "sync_history"
  implication: The storage mechanism is implemented correctly

- timestamp: 2026-01-18T12:02:00Z
  checked: Grep for calls to SyncHistoryStore.recordSuccess/recordFailure
  found: Only calls found are in Preview code (SyncSettingsView.swift lines 256-259) and a DIFFERENT recordSuccess() in SyncStatusViewModel.swift (line 210) which clears error state, NOT records history
  implication: NO production code actually calls SyncHistoryStore.recordSuccess() or recordFailure()

- timestamp: 2026-01-18T12:03:00Z
  checked: SyncEngine.swift performSync() method
  found: Sync completes with log "Sync completed successfully" but never calls syncHistoryStore.recordSuccess()
  implication: SyncEngine has no reference to SyncHistoryStore - it cannot record history

- timestamp: 2026-01-18T12:04:00Z
  checked: trendyApp.swift for how SyncHistoryStore is wired
  found: SyncHistoryStore is created (line 47) and passed to environment (line 422), but NOT passed to SyncEngine or EventStore
  implication: SyncHistoryStore is isolated - only the view can read it, but nothing writes to it

## Resolution

root_cause: SyncHistoryStore.recordSuccess() and recordFailure() are never called from the actual sync code path. The SyncEngine completes sync operations but has no reference to SyncHistoryStore to record the history. The store exists and the UI reads from it, but no code writes sync results to it.

fix:
1. Added syncHistoryStore property to SyncEngine (optional, passed via init)
2. Track sync start time and calculate duration in performSync()
3. Count pending mutations before/after to track items synced
4. Added recordSyncHistory() helper method that dispatches to MainActor
5. Call recordSuccess/recordFailure on sync completion
6. Updated EventStore.setModelContext() to accept and pass syncHistoryStore to SyncEngine
7. Updated MainTabView and OnboardingContainerView to pass syncHistoryStore from environment

verification: Build succeeded. Needs manual testing to verify sync history entries appear.
files_changed:
- apps/ios/trendy/Services/Sync/SyncEngine.swift (added syncHistoryStore, timing, recording)
- apps/ios/trendy/ViewModels/EventStore.swift (pass syncHistoryStore through)
- apps/ios/trendy/Views/MainTabView.swift (get syncHistoryStore from environment)
- apps/ios/trendy/Views/Onboarding/OnboardingContainerView.swift (get syncHistoryStore from environment)
