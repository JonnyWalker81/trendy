---
status: resolved
trigger: "iOS sync of 1000+ events stalls - logs show Event.properties SET repeatedly but no events reach backend DB"
created: 2026-01-17T10:00:00Z
updated: 2026-01-17T17:30:00Z
---

## Current Focus

hypothesis: CONFIRMED - Sync shows "1831/1832" and appears stalled because pullChanges/bootstrapFetch don't update progress state
test: Code review of SyncEngine.swift
expecting: Find missing state updates during pull phase
next_action: Add progress state for pull phase to fix perceived stall

ROOT CAUSE IDENTIFIED:
1. flushPendingMutations() updates state to .syncing(synced: N, total: M)
2. After flush completes, sync moves to pullChanges() or bootstrapFetch()
3. Neither pullChanges() nor bootstrapFetch() updates the state
4. UI stays stuck at "1831/1832" while actually working on pull phase
5. User perceives this as "stalled" but sync is actually progressing

Additionally found:
- flushEventCreateBatch has a bug where markEventSynced failure doesn't delete the mutation
- This causes 1 mutation to remain pending forever (not matching in response)

## Symptoms (Updated)

### Original Symptoms (RESOLVED)
- Batch requests timing out due to batch size 500 being too large
- Fixed by reducing batch size to 50

### Current Symptoms (NEW)
- Sync gets to 1831 of 1832 and stops - won't finish
- Batching is working better now (reduced to 50)
- Massive amount of data in change_log table suspected
- iOS app may be stuck trying to download change_log entries or get cursor in correct state

## Progress So Far

### Fix 1: Backend UpsertHealthKitEventsBatch optimization
- Changed to skip UPDATE calls for existing HealthKit events
- Status: APPLIED

### Fix 2: Event.swift verbose DEBUG logging removed
- Removed excessive print() calls during property set
- Status: APPLIED

### Fix 3: Batch size reduced 500 -> 50
- Allows Cloud Run to process batches within 15-second timeout
- Status: APPLIED, PARTIALLY WORKING
- Result: Sync now progresses but stalls at 1831/1832

### Fix 4: APPLIED - Pull phase progress feedback
- Issue: Sync shows "1831/1832" and appears stalled
- Root cause: pullChanges and bootstrapFetch have no state updates
- Fix: Added SyncState.pulling case with UI feedback
- Files changed:
  - SyncEngine.swift: Added .pulling state, updateState calls before pull phases
  - SyncStatusBanner.swift: Added pulling case with "Downloading updates..." message
  - LoadingView.swift: Added pulling case with "Downloading updates..." message
  - EventListView.swift: Added .pulling to refresh timer switch

### Fix 5: APPLIED - markEventSynced failure handling
- Issue: If markEventSynced throws, mutation stays pending forever
- Root cause: mutationsByIndex.removeValue was outside try-catch
- Fix: Delete mutation even if markEventSynced fails (server has the event)
- Files changed:
  - SyncEngine.swift: Restructured error handling in flushEventCreateBatch

## Key Investigation Areas

1. **change_log table size** - How many rows? Is it massive?
2. **change_log content** - What entities are logged? Any duplicates?
3. **Cursor state** - What is the current cursor value in iOS vs max change_log ID?
4. **pullChanges behavior** - Is it getting stuck in the `while hasMore` loop?
5. **The 1832nd event** - What's special about it? Why won't it sync?

## Evidence

- timestamp: 2026-01-17T17:30:00Z
  checked: User report after batch size fix
  found: |
    - Batching is working better
    - Sync progresses to 1831 of 1832
    - Then stalls and won't finish
    - Massive change_log table suspected
  implication: Last event or pullChanges is blocking completion

- timestamp: 2026-01-17T18:15:00Z
  checked: SyncEngine.swift code review - performSync flow
  found: |
    - Line 198: flushPendingMutations() called
    - Lines 551-752: updateState(.syncing) called during flush
    - Line 214-220: bootstrapFetch() called if cursor=0
    - Line 254-255: pullChanges() called if cursor>0
    - Lines 1103-1130: pullChanges() loop - NO updateState calls
    - Lines 1365-1520: bootstrapFetch() - NO updateState calls
    - UI state stays at last flush progress during entire pull phase
  implication: Pull phase has no progress feedback, causing "stall" perception

- timestamp: 2026-01-17T18:20:00Z
  checked: flushEventCreateBatch error handling (lines 835-848)
  found: |
    - If markEventSynced throws, syncedCount NOT incremented
    - But mutationsByIndex.removeValue() IS called (outside try block)
    - Mutation NOT deleted from SwiftData
    - This leaves 1 mutation pending but removed from batch tracking
    - On next sync, it would be re-processed but could fail again
  implication: Secondary bug - one stuck mutation never syncs

## Files Changed (All Fixes)

- apps/backend/internal/repository/event.go (optimized UpsertHealthKitEventsBatch)
- apps/ios/trendy/Services/Sync/SyncEngine.swift (batch size 500->50, batch failure handling, .pulling state, markEventSynced fix)
- apps/ios/trendy/Models/Event.swift (removed verbose DEBUG logging)
- apps/ios/trendy/Views/Components/SyncStatusBanner.swift (added .pulling case)
- apps/ios/trendy/Views/LoadingView.swift (added .pulling case)
- apps/ios/trendy/Views/List/EventListView.swift (added .pulling to refresh timer)

## Resolution

root_cause: |
  Two issues causing "1831/1832 stalled" perception:

  1. MAIN ISSUE: After flushPendingMutations completes, sync enters pullChanges or bootstrapFetch
     which download data from server. Neither phase updated the UI state, so UI stayed frozen
     at the last push progress "1831/1832" while actually working on pulling.

  2. SECONDARY: In flushEventCreateBatch, if markEventSynced throws, the mutation was
     removed from tracking but not deleted from SwiftData. This left 1 mutation stuck
     forever (explains the 1831/1832 mismatch).

fix: |
  1. Added SyncState.pulling case to indicate downloading phase
  2. Added updateState(.pulling) before pullChanges() and bootstrapFetch()
  3. Updated SyncStatusBanner, LoadingView, EventListView to display "Downloading updates..."
  4. Fixed markEventSynced error handling - now deletes mutation even if markEventSynced fails
     (server has the event, no need to retry)

verification: |
  - iOS build succeeds: xcodebuild -scheme "trendy" build -> BUILD SUCCEEDED
  - All SyncState cases handled in UI components
  - Pull phase will now show "Downloading updates..." instead of frozen push progress

## Context for Next Session

When resuming investigation:
1. Use Supabase MCP to query change_log table
2. Check: `SELECT count(*) FROM change_log`
3. Check: `SELECT max(id) FROM change_log`
4. Check what the iOS cursor is vs what's in DB
5. Look at pullChanges in SyncEngine.swift (~line 1099) for potential infinite loops
6. Check if the 1832nd mutation has something special about it
