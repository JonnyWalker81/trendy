---
status: diagnosed
trigger: "iOS sync blocking UI - large data sync causes loading screen to hang forever. Batch syncing is broken."
created: 2026-01-17T00:00:00Z
updated: 2026-01-17T01:30:00Z
---

## Current Focus

hypothesis: CONFIRMED - MainTabView.initializeNormally() awaits fetchData() which awaits syncEngine.performSync(), blocking the entire UI initialization until sync completes
test: Traced initialization flow in MainTabView.swift
expecting: Find blocking await on sync
next_action: Document root cause and design fix

## Symptoms

expected: |
  1. App launches immediately without blocking on sync
  2. All syncing happens asynchronously in background
  3. UI never blocks or freezes during sync
  4. Sync status is visible somewhere (debug view, settings, or event list)
  5. Batch syncing works to prevent rate limiting

actual: |
  1. Loading screen hangs forever during large syncs
  2. Batch syncing is broken
  3. Sync blocks the UI
  4. No visibility into sync status during the hang

errors: |
  - Loading screen never completes (infinite hang)
  - App appears frozen during sync

reproduction: Launch iOS app with large amount of pending data to sync (e.g., 5000+ HealthKit events)

started: Current behavior - sync has never been fully async/non-blocking

## Eliminated

## Evidence

- timestamp: 2026-01-17T01:00:00Z
  checked: MainTabView.swift initialization flow
  found: |
    Line 49-57: LoadingView shown when `isLoading || eventStore == nil || geofenceManager == nil`
    Line 72-80: .task { await initializeNormally() }
    Line 208-275: initializeNormally() calls `await store.fetchData()` at line 259
    Line 271-274: `isLoading = false` only AFTER fetchData completes

    BLOCKING CHAIN:
    1. MainTabView shows LoadingView while isLoading=true
    2. initializeNormally() starts
    3. await store.fetchData() called
    4. fetchData() calls await syncEngine.performSync() at line 531
    5. performSync() flushes ALL pending mutations sequentially (5000+ events = hours)
    6. Only after ALL syncing completes does isLoading become false
    7. LoadingView shows the ENTIRE time - user sees infinite loading
  implication: The root cause is the BLOCKING architecture - sync runs inline with initialization

- timestamp: 2026-01-17T01:00:00Z
  checked: EventStore.fetchData() method
  found: |
    Line 504-553: fetchData() synchronously awaits syncEngine.performSync()
    Line 521: `if let syncEngine = syncEngine, actuallyOnline { await syncEngine.performSync() }`
    Line 540: Only after sync completes does it call fetchFromLocal()

    The polling task (lines 524-528) updates UI state, but doesn't help because
    the caller (initializeNormally) is still blocked waiting for fetchData() to return.
  implication: fetchData() is a synchronous barrier - nothing after it runs until sync completes

- timestamp: 2026-01-17T01:00:00Z
  checked: SyncEngine.performSync() and flushPendingMutations()
  found: |
    Line 156-289: performSync() is single-flight protected (isSyncing guard)
    Line 511: batchSize = 500 (correct batch size for backend)
    Line 513-742: flushPendingMutations() processes mutations

    Line 543-545: Separates event CREATEs (for batch) from other mutations
    Line 556-612: Batch processes event CREATEs in batches of 500
    Line 584: Actually calls flushEventCreateBatch() which uses apiClient.createEventsBatch()

    BATCH SYNC IS WORKING - processes 500 events per API call

    The issue is NOT broken batching - it's that the ENTIRE batch process
    (potentially 10+ batches for 5000 events) must complete before UI shows.
  implication: Batch sync works correctly, but the blocking architecture means ALL batches must complete

- timestamp: 2026-01-17T01:00:00Z
  checked: LoadingView.swift sync status display
  found: |
    Line 10-14: LoadingView accepts optional syncState and pendingCount parameters
    Line 50-66: MainTabView DOES pass syncState to LoadingView
    Line 56-88: LoadingView displays sync progress when state is .syncing

    The sync status IS visible on the loading screen - shows "Synced X of Y (Z%)"

    However, this only helps if you wait - the problem is the INDEFINITE wait.
  implication: Sync status UI exists and works, but doesn't solve the blocking problem

- timestamp: 2026-01-17T01:00:00Z
  checked: SyncStatusBanner.swift and EventListView.swift
  found: |
    SyncStatusBanner: Full-featured sync status component with progress, rate limit info, retry button
    EventListView lines 54-67: SyncStatusBanner is shown at top of event list

    These components work correctly AFTER the app loads - user can see sync status
    in the event list. The problem is they're unreachable during the blocking load.
  implication: Post-load sync status works; need to make sync non-blocking so user reaches this UI

## Resolution

root_cause: |
  THREE INTERRELATED ISSUES:

  1. BLOCKING INITIALIZATION (Primary Issue)
     MainTabView.initializeNormally() blocks on `await fetchData()` which blocks on
     `await syncEngine.performSync()`. The UI cannot show main content until ALL
     pending mutations are synced. With 5000+ events, this takes hours.

     Code path:
     - MainTabView.task { await initializeNormally() }
     - initializeNormally() calls await store.fetchData() [line 259]
     - fetchData() calls await syncEngine.performSync() [line 531]
     - isLoading = false only after fetchData returns [line 273]
     - LoadingView shown entire time isLoading is true

  2. BATCH SYNC IS NOT BROKEN
     Contrary to the bug report, batch sync IS implemented and working:
     - SyncEngine.batchSize = 500 [line 511]
     - flushPendingMutations() separates event CREATEs for batching [line 543-545]
     - flushEventCreateBatch() calls apiClient.createEventsBatch() [line 792]

     The perceived "broken batch sync" is actually the blocking architecture -
     even with batching, processing 10+ batches takes a long time, and the
     UI is blocked the entire duration.

  3. SYNC STATUS VISIBILITY EXISTS BUT UNREACHABLE
     - LoadingView DOES display sync progress (line 56-88)
     - SyncStatusBanner in EventListView shows detailed sync status
     - But user cannot see EventListView until sync completes (catch-22)

fix: |
  DESIGN FIX - Make sync fully async and non-blocking:

  1. DECOUPLE FETCH FROM SYNC
     - fetchData() should load local cache FIRST (instant UI)
     - THEN trigger sync in background (fire-and-forget)
     - UI shows immediately with cached data

  2. CHANGE initializeNormally() FLOW
     ```swift
     // BEFORE (blocking):
     await store.fetchData()       // Blocks until sync completes
     isLoading = false             // UI finally shows

     // AFTER (non-blocking):
     try? await store.fetchFromLocal()  // Load cached data (fast)
     isLoading = false                  // UI shows immediately
     Task { await store.performSync() } // Sync in background
     ```

  3. UPDATE fetchData() SEMANTICS
     - Rename or split into two methods:
       a) loadLocalData() - Load from SwiftData cache (fast, synchronous)
       b) syncWithBackend() - Background sync (async, fire-and-forget)
     - Current callers that need both can call: loadLocalData(); Task { syncWithBackend() }

  4. ENSURE UI UPDATES DURING SYNC
     - SyncStatusBanner already shows in EventListView
     - Add banner to other views (Dashboard, Calendar) for visibility
     - Polling in EventListView already refreshes sync state

  5. HANDLE SYNC COMPLETION
     - When sync completes, update local store
     - SwiftUI @Observable will auto-update UI with new data
     - No explicit refresh needed - data binding handles it

verification: |
  To verify fix works:
  1. Launch app with 5000+ pending events
  2. App should show main UI within 2-3 seconds (loading cached data)
  3. SyncStatusBanner should appear showing "Syncing X of Y"
  4. User can navigate app while sync runs in background
  5. New events appear in list as batches complete
  6. No UI freezes or hangs during sync

files_changed: []
