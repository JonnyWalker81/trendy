# Debug: Sync Progress UI Not Updating During Batch Operations

**Status:** Active
**Created:** 2026-01-17
**Phase:** 05-sync-engine (blocking 05-03 verification checkpoint)

## Problem

During historical HealthKit import (4500+ events), the sync progress banner shows "Synced 0 of 5000 (0%)" and never updates, even though batches are being processed.

## Symptoms

1. Progress banner shows total count but processed count stays at 0
2. Percentage never changes
3. Backend batch API times out (`NSURLErrorDomain Code=-1001 "The request timed out."`)
4. Logs show batches ARE progressing: `Processing event batch [batch_start=4000, batch_size=500]`

## Root Cause

In `SyncEngine.swift`, the progress update only happens AFTER successful batch completion:

```swift
// Line 584-590 in flushPendingMutations()
do {
    let batchSyncedCount = try await flushEventCreateBatch(...)
    syncedCount += batchSyncedCount  // <-- Only reached on success
    await updateState(.syncing(synced: syncedCount, total: totalPending))
    // ...
} catch {
    // Error logged but syncedCount NOT updated
    // State NOT updated
    // Loop continues to next batch
}
```

When batches timeout:
1. `flushEventCreateBatch()` throws before returning
2. `syncedCount += batchSyncedCount` is never reached
3. `updateState()` is never called
4. UI shows stale "0 of N" forever

## Secondary Issue: Backend Timeout

The batch API endpoint times out with 500 events per batch:
- Endpoint: `https://trendy-api-prod-541486728137.us-central1.run.app/api/v1/events/batch`
- Cloud Run default timeout may be too short for 500-event batches

## Fix Approach

### Option A: Show Batch Progress (Recommended)

Update progress as batches are *attempted*, not just completed:

```swift
for batchStart in stride(from: 0, to: eventCreateMutations.count, by: batchSize) {
    let batchEnd = min(batchStart + batchSize, eventCreateMutations.count)
    let batchMutations = Array(eventCreateMutations[batchStart..<batchEnd])

    // NEW: Update state to show which batch we're on
    let attemptedCount = batchStart  // Events we've attempted so far
    await updateState(.syncing(synced: attemptedCount, total: totalPending))

    do {
        let batchSyncedCount = try await flushEventCreateBatch(...)
        syncedCount += batchSyncedCount
        // State will update on next iteration or after loop
    } catch {
        // Error handling unchanged
    }
}

// Final state update after all batches
await updateState(.syncing(synced: syncedCount, total: totalPending))
```

### Option B: Add "Processing" State

Add a new SyncState case for in-progress batches:

```swift
enum SyncState: Equatable {
    case idle
    case syncing(synced: Int, total: Int)
    case processing(batch: Int, totalBatches: Int, synced: Int, total: Int)  // NEW
    case rateLimited(retryAfter: TimeInterval, pending: Int)
    case error(String)
}
```

### Option C: Reduce Batch Size

Reduce from 500 to 100-200 to avoid timeouts:

```swift
private let batchSize = 200  // Was 500
```

## Files to Modify

1. `apps/ios/trendy/Services/Sync/SyncEngine.swift`
   - Lines 558-611: `flushPendingMutations()` batch loop
   - Add progress update before each batch attempt

2. (Optional) `apps/ios/trendy/Views/Components/SyncStatusBanner.swift`
   - If adding new SyncState case, update UI to display it

## Test Plan

1. Trigger historical HealthKit import (500+ events)
2. Watch sync progress banner
3. Expected: Progress updates as batches are attempted
4. Even if batches fail, progress should show "Attempted X of Y"

## Related Files

- `apps/ios/trendy/Services/Sync/SyncEngine.swift` - Main fix location
- `apps/ios/trendy/Views/Components/SyncStatusBanner.swift` - UI that displays state
- `.planning/phases/05-sync-engine/05-03-PLAN.md` - Blocked verification checkpoint

## Resume Command

```
/gsd:resume-work
```

Or manually:
1. Read this file
2. Implement Option A fix in SyncEngine.swift
3. Re-run 05-03 verification tests
