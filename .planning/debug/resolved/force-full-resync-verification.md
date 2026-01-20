---
status: diagnosed
trigger: "Verify Force Full Resync function in iOS app - check if it properly deletes ALL local data and fetches ALL from server"
created: 2026-01-19T00:00:00Z
updated: 2026-01-19T00:00:00Z
---

## Current Focus

hypothesis: Force Full Resync correctly deletes ALL local data and fetches ALL from server - confirmed by code analysis
test: Traced complete flow from UI to data layer
expecting: Complete deletion + complete fetch
next_action: Document findings

## Symptoms

expected: Force Full Resync should delete all local Events and EventTypes, then fetch everything fresh from the backend
actual: Duplicates appear after resync, suggesting either data isn't fully cleared or sync logic has issues
errors: None explicit - verification task
reproduction: Settings > Sync > Force Full Resync
started: N/A - verification task

## Eliminated

## Evidence

- timestamp: 2026-01-19
  checked: UI entry point in DebugStorageView.swift
  found: Line 305-309 shows "Force Full Resync" button triggers showingForceResyncConfirmation, then line 611-617 forceResync() calls eventStore.forceFullResync()
  implication: UI correctly triggers the resync flow

- timestamp: 2026-01-19
  checked: EventStore.forceFullResync() in EventStore.swift line 402-429
  found: Calls syncEngine.forceFullResync() then fetchFromLocal() to refresh UI
  implication: EventStore is a thin wrapper, real logic is in SyncEngine

- timestamp: 2026-01-19
  checked: SyncEngine.forceFullResync() in SyncEngine.swift line 360-377
  found: (1) Waits for any in-progress sync, (2) Resets lastSyncCursor to 0, (3) Sets forceBootstrapOnNextSync = true, (4) Calls performSync()
  implication: Uses cursor reset + flag to trigger bootstrap fetch

- timestamp: 2026-01-19
  checked: performSync() bootstrap logic in SyncEngine.swift line 226-278
  found: When shouldBootstrap is true (cursor=0 OR forceBootstrapOnNextSync), it calls bootstrapFetch() instead of incremental pullChanges()
  implication: Force resync correctly triggers full bootstrap path

- timestamp: 2026-01-19
  checked: bootstrapFetch() "nuclear cleanup" in SyncEngine.swift line 1501-1727
  found: Lines 1509-1556 implement "NUCLEAR CLEANUP" - deletes ALL Events, ALL Geofences, ALL PropertyDefinitions, ALL EventTypes BEFORE fetching from backend
  implication: Delete phase is comprehensive - deletes EVERYTHING for current user

- timestamp: 2026-01-19
  checked: bootstrapFetch() fetch phase in SyncEngine.swift
  found: (1) Fetches ALL EventTypes via getEventTypes(), (2) Fetches ALL Geofences via getGeofences(), (3) Fetches ALL Events via getAllEvents() with batched pagination, (4) Fetches PropertyDefinitions for each EventType
  implication: Fetch phase retrieves ALL data without filters

- timestamp: 2026-01-19
  checked: getAllEvents() in APIClient.swift line 268-293
  found: Uses pagination with batchSize=500, offset incrementing, fetches until batch.count < batchSize
  implication: Correctly fetches ALL events without arbitrary limits

- timestamp: 2026-01-19
  checked: Cursor update after bootstrap in SyncEngine.swift line 252-278
  found: After bootstrap, gets latestCursor from backend and sets cursor high to skip all existing change_log entries
  implication: Prevents stale change_log entries from recreating deleted events

## Resolution

root_cause: The Force Full Resync implementation is CORRECT. It properly:
1. Deletes ALL local Events, EventTypes, Geofences, and PropertyDefinitions
2. Fetches ALL data from the backend using proper pagination
3. Updates cursor to skip stale change_log entries

The duplicates appearing after resync are NOT caused by incomplete deletion or fetch logic. Possible causes for duplicates include:
- HealthKit observer firing after bootstrap, creating events for samples that already exist on backend
- queueMutationsForUnsyncedEvents() running after bootstrap and re-syncing already-synced events
- Post-bootstrap notification triggering HealthKitService.reloadProcessedSampleIds() but timing race

fix: N/A - implementation is correct
verification: Code analysis verified complete flow
files_changed: []
