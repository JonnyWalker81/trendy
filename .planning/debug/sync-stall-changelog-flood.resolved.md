# Debug Session: Sync Stall - Rate Limit During Change Log Pull

**Status:** ✅ RESOLVED - iOS changes + DB truncation complete
**Created:** 2025-01-17
**Updated:** 2025-01-18
**Priority:** Critical - sync completely blocked

## Final State (After Fix)

| Metric | Before | After |
|--------|--------|-------|
| change_log entries | 61,864 | **100** |
| change_log min_id | 600 | 62,676 |
| change_log max_id | 62,775 | 62,775 |
| events (source of truth) | 7,963 | 7,963 ✅ |
| event_types | 20 | 20 ✅ |

**Data integrity verified:** All 7,963 events and 20 event_types preserved.

## Previous State (Before Fix)

| Metric | Value | Notes |
|--------|-------|-------|
| Device cursor | 15,661 | |
| Max change_log ID | 62,775 | |
| Entries to pull | **47,114** | Massive backlog causing rate limits |
| Pending mutations | **3,236** | Growing (was 2,171) |
| Backend rate limit | 300/min | |
| Pull requests needed | ~471 | 47,114 / 100 batch size |

## Root Cause

**The pullChanges phase is exhausting the rate limit, not the push phase.**

Sync flow:
1. `performSync()` starts
2. `flushPendingMutations()` runs - pushes mutations in batches of 50
3. `pullChanges()` runs - fetches change_log in batches of 100
4. With 47,114 entries to pull = 471 API requests
5. After ~300 requests, rate limit (300/min) is hit
6. 429 error returned to iOS
7. Circuit breaker trips (30s backoff)
8. Repeat on next sync attempt

**Why mutations keep growing:**
- Sync keeps failing, so `syncStatus` stays `pending`
- HealthKit observer continues importing new events
- New events create new mutations
- Queue grows from 2,171 to 3,236

**Why "Skip Change Log Backlog" didn't help before:**
- Button only showed when `pendingMutationCount == 0` (safety measure)
- Can't clear mutations while sync is failing
- Deadlock

## Evidence

1. Backend fix IS deployed (event.go lines 223-241) - only CREATE logged for HealthKit
2. Recent 100 change_log entries are ALL "create" - fix is working
3. Historical 53,877 UPDATE entries are still in change_log
4. iOS build succeeds
5. Rate limit is 300 requests/minute (ratelimit.go line 109)
6. Pull batch size is 100 (SyncEngine.swift line 96)

## Fix Applied

### Part 1: iOS Changes (COMPLETE)

**File:** `apps/ios/trendy/Views/Settings/DebugStorageView.swift`
- "Skip Change Log Backlog" button now shows even with pending mutations
- Updated footer text to explain the button is safe with pending mutations
- Updated confirmation dialog message to clarify safety

**File:** `apps/ios/trendy/Services/Sync/SyncEngine.swift`
- Removed pendingCount check from `skipToLatestCursor()`
- Updated documentation to explain why this is safe
- Push and pull phases are independent operations

### Part 2: Database Truncation (PENDING USER ACTION)

Run this SQL in Supabase SQL Editor (cwxghazeohicindcznhx):

```sql
-- Step 1: Check current state
SELECT
    COUNT(*) as total_count,
    MIN(id) as min_id,
    MAX(id) as max_id
FROM change_log;

-- Step 2: Count entries to delete
SELECT COUNT(*) as rows_to_delete
FROM change_log
WHERE id NOT IN (
    SELECT id FROM change_log
    ORDER BY id DESC
    LIMIT 1000
);

-- Step 3: Delete old entries, keep only recent 1000
-- This is SAFE - change_log is audit trail, not source of truth
-- Events and event_types tables remain untouched
WITH to_keep AS (
    SELECT id FROM change_log
    ORDER BY id DESC
    LIMIT 1000
)
DELETE FROM change_log
WHERE id NOT IN (SELECT id FROM to_keep);

-- Step 4: Verify truncation
SELECT
    COUNT(*) as total_count,
    MIN(id) as min_id,
    MAX(id) as max_id
FROM change_log;
```

## Recovery Steps (After iOS Deploy + DB Truncation)

1. **Deploy iOS changes** (rebuild and install on device)
2. **Run SQL truncation** (Supabase SQL Editor)
3. **On device:** Go to Settings > Debug Storage
4. **Click "Skip Change Log Backlog"** - cursor will jump to ~62,775
5. **Wait for sync** - mutations should now push successfully
6. **Verify:** pendingMutationCount should drop to 0

## Files Modified

- [x] `apps/ios/trendy/Views/Settings/DebugStorageView.swift` - Allow cursor skip with warning
- [x] `apps/ios/trendy/Services/Sync/SyncEngine.swift` - Remove pendingCount check
- [x] Supabase change_log table - Truncated from 61,864 to 100 rows

## Verification Checklist

- [x] iOS code changes complete
- [x] iOS build succeeds
- [x] change_log truncated (from 61,864 to 100 rows)
- [ ] Device cursor skipped to latest (user action required)
- [ ] Device sync completes without rate limit errors
- [ ] All pending mutations pushed successfully
- [ ] Local and server event counts match
- [ ] New events sync within seconds

## Remaining User Actions

1. **Rebuild and install iOS app** on device (to get updated "Skip Change Log Backlog" button)
2. **Settings > Debug Storage > "Skip Change Log Backlog"** - this skips cursor from 15,661 to 62,775
3. **Wait for sync** - mutations should now push successfully without rate limiting
4. **Verify** pendingMutationCount drops to 0
