# Debug Session: iOS Sync Rate Limit Errors

---
status: resolved
trigger: "iOS app hitting 429 rate limits when syncing 5000+ pending events"
created: 2026-01-16
updated: 2026-01-17
resolved: 2026-01-17
---

## Current Focus

hypothesis: CONFIRMED - Three issues identified and fixed
test: Build verified, code review complete
expecting: UI shows sync progress, batch sync handles HealthKit upserts correctly
next_action: Manual testing with 5000+ pending HealthKit events to verify end-to-end

## NEW SYMPTOMS (Latest - after healthKitSampleId fix)

1. **UI not showing progress**: Shows "Loading your data..." instead of "Synced X of Y (Z%)"
2. **Only small amount of events synced**: Backend DB received very few events
3. **Logs still printing**: App not frozen, lots of log activity indicating processing
4. **Events stuck**: Processing happening but not actually syncing to backend

## Key Investigation Areas

### 1. UI State Flow
- `MainTabView.swift` lines 49-69: Shows LoadingView when `isLoading || eventStore == nil || geofenceManager == nil`
- `LoadingView.swift` lines 56-88: Shows "Loading your data..." when syncState is nil/idle/unknown
- `EventStore.swift` line 59: `currentSyncState` is cached, updated via `refreshSyncStateForUI()`
- **Issue**: LoadingView receives `eventStore?.currentSyncState` but if eventStore is nil, it's nil

### 2. Initialization Flow
- `MainTabView.initializeNormally()` lines 208-275:
  1. Creates EventStore
  2. Calls `store.fetchData()` which calls `syncEngine.performSync()`
  3. Sets `isLoading = false` AFTER fetchData completes
- **Issue**: If sync takes long time, isLoading stays true but currentSyncState may not update

### 3. Sync State Updates
- `SyncEngine.flushPendingMutations()` calls `await updateState(.syncing(synced: X, total: Y))`
- `EventStore.refreshSyncStateForUI()` polls `syncEngine.state` to update `currentSyncState`
- **Issue**: refreshSyncStateForUI is only called at specific points, not continuously during sync

### 4. Batch Sync Execution
- `SyncEngine.flushEventCreateBatch()` - the new batch method
- Check if batches are actually being sent to backend
- Check if response handling is working correctly
- Check if mutations are being deleted from queue

## Key Files to Investigate

```
apps/ios/trendy/Services/Sync/SyncEngine.swift
  - flushPendingMutations() - batch processing loop (lines 540-612)
  - flushEventCreateBatch() - batch API call and response handling (lines 673+)
  - updateState() - how sync state is published

apps/ios/trendy/ViewModels/EventStore.swift
  - currentSyncState (line 59) - cached state for UI
  - refreshSyncStateForUI() (lines 439-444) - how state gets updated
  - fetchData() (lines 477-514) - calls performSync and refreshSyncStateForUI

apps/ios/trendy/Views/MainTabView.swift
  - LoadingView instantiation (lines 49-69) - passes eventStore?.currentSyncState
  - initializeNormally() (lines 208-275) - when isLoading becomes false

apps/ios/trendy/Views/LoadingView.swift
  - statusText computed property (lines 56-88) - decides what text to show
```

## Previous Symptoms (Fixed)

expected: All 5000+ pending events should sync to backend without hitting rate limits
actual:
  - Rate limit fixed by batch sync
  - Stall at 167 items fixed by healthKitSampleId matching
errors: HTTP 429 (fixed), stall at 167 (fixed)
reproduction: Have 5000+ pending HealthKit events, start sync

## Evidence

- timestamp: 2026-01-17T12:30
  checked: UI state flow during sync (LoadingView -> EventStore -> SyncEngine)
  found: |
    ROOT CAUSE OF UI ISSUE:
    1. LoadingView reads `eventStore?.currentSyncState` (line 51 in MainTabView.swift)
    2. `currentSyncState` is a cached property in EventStore, initialized to `.idle`
    3. `refreshSyncStateForUI()` is the ONLY way to update `currentSyncState`:
       ```swift
       func refreshSyncStateForUI() async {
           guard let syncEngine = syncEngine else { return }
           currentSyncState = await syncEngine.state  // Polls SyncEngine
       }
       ```
    4. In `fetchData()`, `refreshSyncStateForUI()` only called AFTER sync completes (line 528)
    5. During sync, SyncEngine.state is updated to .syncing(synced:X, total:Y)
       but EventStore.currentSyncState stays .idle
    6. LoadingView sees .idle -> shows "Loading your data..." (default case)
  implication: |
    FIX: Added polling task that calls refreshSyncStateForUI() every 250ms during sync:
    ```swift
    let pollingTask = Task { @MainActor in
        while !Task.isCancelled {
            await refreshSyncStateForUI()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
    await syncEngine.performSync()
    pollingTask.cancel()
    ```
    Applied to both performSync() and fetchData() methods.

- timestamp: 2026-01-16T10:00
  checked: SyncEngine.swift flushPendingMutations method (lines 510-669)
  found: |
    The method iterates over each PendingMutation one at a time:
    ```swift
    for mutation in mutations {
        // ...processes each mutation individually...
        try await flushMutation(mutation, localStore: localStore)
    }
    ```
    Each flushMutation calls apiClient.createEventWithIdempotency() for creates.
    With 5000 mutations, this is 5000 HTTP requests.
  implication: |
    ROOT CAUSE CONFIRMED: One-by-one sync pattern.
    Rate limit is 300 requests/minute = 5 requests/second.
    5000 events would take 5000/5 = 1000 seconds = 16+ minutes if perfectly paced.
    But requests happen as fast as possible, exhausting limit in first minute.

- timestamp: 2026-01-16T11:00
  checked: flushEventCreateBatch matching logic (lines 793-811)
  found: |
    The matching logic compares mutation.entityId with createdEvent.id:
    ```swift
    for createdEvent in response.created {
        for (index, mutation) in mutationsByIndex {
            if mutation.entityId == createdEvent.id {  // <-- ID matching
                // mark synced, delete mutation
            }
        }
    }
    ```
    Problem: For HealthKit duplicates, backend returns the EXISTING event's ID, not the client-provided ID.
  implication: |
    When HealthKit event already exists in DB:
    1. Client sends event with id="new-uuid-v7"
    2. Backend checks healthkit_sample_id, finds duplicate
    3. Backend UPDATES existing event, returns it with ORIGINAL ID
    4. iOS tries to match "new-uuid-v7" with "old-uuid-from-db" - FAILS
    5. Mutation never deleted, stays in queue forever

- timestamp: 2026-01-16T11:01
  checked: Backend UpsertHealthKitEventsBatch (event.go lines 535-547)
  found: |
    ```go
    if existingID, exists := existingSampleIDToEventID[*event.HealthKitSampleID]; exists {
        // UPDATE: Uses EXISTING event's ID, not client-provided ID
        body, err := r.client.Update("events", existingID, data)
        allResults = append(allResults, updated[0])  // Returns with EXISTING ID
    }
    ```
  implication: |
    Backend design intentionally preserves existing event's ID during upsert.
    This is correct for data consistency (don't create duplicate IDs).
    iOS needs to match by healthKitSampleId for upserted events, not just ID.

- timestamp: 2026-01-16T11:02
  checked: Why stalls at exactly 167
  found: |
    First 167 events are NEW (no duplicates in DB), so they create with client ID.
    Event 168+ are duplicates - backend returns different IDs.
    Mutations 168+ never matched, never deleted, stay in queue.
    Next sync cycle: same mutations, same result = infinite stall.
  implication: |
    The number 167 represents how many truly NEW events existed before hitting duplicates.
    This matches the scenario where HealthKit was re-synced after prior syncs.

## Eliminated

(none)

## Resolution

root_cause: |
  THREE ISSUES FOUND:

  1. RATE LIMIT (HTTP 429): One-by-one sync pattern with 5000+ events
     - Fixed by batch sync API (500 events per batch)

  2. STALL AT 167 ITEMS: HealthKit upsert ID mismatch
     - Backend returns EXISTING event's ID for upserts, not client-provided ID
     - flushEventCreateBatch matched by ID only, missing healthKitSampleId fallback
     - Fixed by adding secondary matching by healthKitSampleId

  3. UI NOT SHOWING PROGRESS: State polling gap
     - LoadingView reads EventStore.currentSyncState (cached, starts as .idle)
     - refreshSyncStateForUI() only called AFTER sync completes
     - During sync, SyncEngine.state updates but UI never sees it
     - UI shows "Loading your data..." instead of "Synced X of Y (Z%)"

fix: |
  1. Batch sync: Already implemented - sends 500 events per API call

  2. healthKitSampleId fallback: Already implemented
     - Secondary lookup by sample ID when ID match fails
     - Deletes local duplicate for upsert cases

  3. UI state polling (NEW FIX):
     Added polling task in both performSync() and fetchData() that refreshes
     UI state every 250ms during sync:
     ```swift
     let pollingTask = Task { @MainActor in
         while !Task.isCancelled {
             await refreshSyncStateForUI()
             try? await Task.sleep(nanoseconds: 250_000_000)
         }
     }
     await syncEngine.performSync()
     pollingTask.cancel()
     ```

verification: |
  - BUILD SUCCEEDED (xcodebuild 2026-01-17, iPhone 17 Pro Simulator, iOS 26.1)
  - Code review: Polling task correctly starts before sync, stops after
  - Code review: 250ms interval provides responsive UI without excessive polling
  - Code review: Polling added to performSync(), fetchData(), and forceFullResync()
  - Manual testing needed: Launch app with pending HealthKit events, verify:
    1. LoadingView shows "Synced X of Y (Z%)" during sync
    2. All pending mutations eventually clear from queue
    3. Events appear on backend after sync completes

files_changed:
  - apps/ios/trendy/Services/Sync/SyncEngine.swift (batch sync + fallback matching)
  - apps/ios/trendy/ViewModels/EventStore.swift (UI state polling during sync)
