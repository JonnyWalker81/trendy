# Debug Session: SyncEngine Test Failures

**Status:** IN PROGRESS - Investigation complete, fixes needed
**Created:** 2026-01-29
**Files investigated:** All read and analyzed

## Failing Tests (19 total)

### Category 1: Circuit Breaker Tests (8 failures)
**File:** `apps/ios/trendyTests/SyncEngine/CircuitBreakerTests.swift`

| Test | Failure Reason |
|------|---------------|
| `circuitBreakerTripsAfter3RateLimits` | Circuit breaker not tripping |
| `circuitBreakerTripsOnExactly3` | Circuit breaker not tripping |
| `backoffTimeInExpectedRange` | Depends on trip working |
| `circuitBreakerResetsAfterManualReset` | Depends on trip working |
| `syncBlockedWhileTripped` | Depends on trip working |
| `syncAllowedAfterReset` | Depends on trip working |
| `backoffFollowsExponentialProgression` | Depends on trip working |
| `backoffMultiplierStartsAt1AfterFullReset` | Depends on trip working |

### Category 2: Deduplication / Conflict Tests (5 failures)
**File:** `apps/ios/trendyTests/SyncEngine/DeduplicationTests.swift`

| Test | Failure Reason |
|------|---------------|
| `conflict409DeletesLocalDuplicate` | Flush path uses batch API, not idempotency API |
| `non409ErrorsDoNotDeduplicate` | Same - wrong flush path |
| `server500DoesNotDeduplicate` | Same - wrong flush path |
| `retryReusesSameIdempotencyKey` | Same - wrong flush path |
| `sameEventNotCreatedTwiceWithSameKey` | Same - wrong flush path |

### Category 3: Single Flight Tests (2 failures)
**File:** `apps/ios/trendyTests/SyncEngine/SingleFlightTests.swift`

| Test | Failure Reason |
|------|---------------|
| `testSYNC01_ConcurrentSyncCallsCoalesce` | Health check counted >1 time (race in concurrent test) |
| `testSyncBlockedReturnsImmediately` | Health check counted >1 time |

### Category 4: Health Check Tests (2 failures)
**File:** `apps/ios/trendyTests/SyncEngine/HealthCheckTests.swift`

| Test | Failure Reason |
|------|---------------|
| `testHealthCheckPassesWithValidResponse` | Test expects `createEventWithIdempotencyCalls` but SyncEngine uses batch API path |
| `testHealthCheckCalledBeforeEverySync` | Likely mock response queue exhausted on 2nd sync |

### Category 5: Bootstrap Notification Tests (1 failure)
**File:** `apps/ios/trendyTests/SyncEngine/BootstrapNotificationTimingTests.swift`

| Test | Failure Reason |
|------|---------------|
| `notificationPostedOnlyDuringBootstrap` | Mock setup may be incomplete for bootstrap path |

### Category 6: Resurrection Prevention Tests (1 failure)
**File:** `apps/ios/trendyTests/SyncEngine/ResurrectionPreventionTests.swift`

| Test | Failure Reason |
|------|---------------|
| `pendingDeleteIdsClearedAfterSuccessfulSync` | Second sync mock setup doesn't re-set cursor key after reset() clears it |

---

## Root Cause Analysis

### Primary Issue: Batch API vs Individual Idempotency API Mismatch

The SyncEngine's `flushPendingMutations()` method (line 748) separates mutations into:
1. **Event CREATE mutations** → processed via `syncEventCreateBatches()` → calls `createEventsBatch()` (batch API)
2. **Other mutations** (updates, deletes, non-event creates) → processed individually via `flushMutation()` → calls `createEventWithIdempotency()` (individual API)

**Many tests configure `createEventWithIdempotencyResponses` but seed event CREATE mutations.** These mutations go through the batch path (`createEventsBatch`), never hitting the idempotency endpoint. The mock's `createEventWithIdempotencyResponses` queue is never consumed.

This affects: All deduplication tests, health check "passes with valid response" test, retry behavior tests.

### Secondary Issue: Circuit Breaker Tests - Batch Processing Logic

The circuit breaker tests seed 3 mutations and configure 3 `createEventsBatchResponses`. But:
- All 3 event CREATEs are batched into a **single** batch call (batch size = 50, 3 < 50)
- So only **1** batch response is consumed, not 3
- Only **1** rate limit error is recorded, not 3
- Circuit breaker threshold is 3, so it never trips

The tests assume 1 mutation = 1 API call, but batching means N mutations = ceil(N/50) API calls.

### Tertiary Issue: UserDefaults Pollution Between Tests

Tests use `UserDefaults.standard` for cursor keys (`sync_engine_cursor_<env>`). Since Swift Testing runs tests in parallel by default, and tests don't clean up UserDefaults, state leaks between tests. The `configureForFlush` and `configureForPullChanges` helpers set cursor to 1000, but `mockStore.reset()` doesn't reset UserDefaults.

### Quaternary Issue: Single Flight Race Condition

`testSYNC01_ConcurrentSyncCallsCoalesce` launches 5 concurrent `performSync()` calls and expects only 1 health check. But SyncEngine's `isSyncing` flag is set AFTER `performHealthCheck()` completes (line 227). Multiple concurrent calls can pass the `!isSyncing` guard and reach health check before the first one sets `isSyncing = true`.

---

## Fix Strategy

### Fix 1: Circuit Breaker Tests
Need to seed enough mutations to create **multiple batches** (>50 per batch) OR reduce the circuit breaker threshold in tests OR modify the helper `tripCircuitBreaker()` to seed mutations across multiple batch cycles.

**Simplest fix:** Change `tripCircuitBreaker()` to call `performSync()` 3 times (one rate limit per sync cycle) instead of trying to get 3 rate limits in a single sync.

### Fix 2: Deduplication Tests
Tests that check `createEventWithIdempotencyCalls` need to either:
- a) Use **non-event** entity types (eventType/geofence CREATEs go through individual path), OR
- b) Configure `createEventsBatchResponses` instead and check `createEventsBatchCalls`, OR
- c) Seed event UPDATE/DELETE mutations instead of CREATEs (these go through individual path)

### Fix 3: Health Check Tests
- `testHealthCheckPassesWithValidResponse`: Configure `createEventsBatchResponses` (not `createEventWithIdempotencyResponses`) and check `createEventsBatchCalls`
- `testHealthCheckCalledBeforeEverySync`: Add `changeFeedResponseToReturn` for second sync cycle

### Fix 4: Single Flight Tests
- Accept that health check happens before `isSyncing` is set, so concurrent calls may do >1 health check
- OR check a broader assertion (e.g., at most 2 health checks instead of exactly 1)
- OR move the `isSyncing` guard to BEFORE health check in SyncEngine

### Fix 5: Bootstrap Notification Test
- Ensure mock has all required responses for bootstrap path (eventTypes, geofences, events, latestCursor)
- May need `changeFeedResponseToReturn` for the non-bootstrap second sync

### Fix 6: Resurrection Prevention Cursor Test
- After `mockStore.reset()`, re-set the cursor key in UserDefaults since reset clears the mock but not UserDefaults

### Fix 7: Test Isolation (All tests)
- Add `UserDefaults.standard.removeObject(forKey:)` cleanup in test setup/teardown for cursor keys
- Consider using a unique cursor key per test to prevent cross-test pollution

---

## Key Source Files

| File | Purpose | Lines of Interest |
|------|---------|-------------------|
| `apps/ios/trendy/Services/Sync/SyncEngine.swift` | Main sync logic | L211 `performSync()`, L748 `flushPendingMutations()`, L685-708 circuit breaker, L819 `syncEventCreateBatches()` |
| `apps/ios/trendyTests/SyncEngine/CircuitBreakerTests.swift` | CB tests | L51 `tripCircuitBreaker()` helper |
| `apps/ios/trendyTests/SyncEngine/DeduplicationTests.swift` | Dedup tests | L155 `sameEventNotCreatedTwiceWithSameKey` |
| `apps/ios/trendyTests/SyncEngine/SingleFlightTests.swift` | Concurrency tests | L53 coalesce test |
| `apps/ios/trendyTests/SyncEngine/HealthCheckTests.swift` | Health check tests | L87 valid response test |
| `apps/ios/trendyTests/SyncEngine/BootstrapNotificationTimingTests.swift` | Bootstrap timing | L104 notification test |
| `apps/ios/trendyTests/SyncEngine/ResurrectionPreventionTests.swift` | Resurrection prevention | L277 cursor cleanup test |
| `apps/ios/trendyTests/Mocks/MockNetworkClient.swift` | Network mock | L505 `createEventsBatch`, L461 `createEventWithIdempotency` |
| `apps/ios/trendyTests/Mocks/MockDataStore.swift` | Data store mock | Full file |
| `apps/ios/trendyTests/Mocks/MockDataStoreFactory.swift` | Factory mock | Full file |

## Mock Architecture Summary

- `MockNetworkClient`: Spy pattern with response queues. Key distinction: `createEventsBatch()` (batch path) vs `createEventWithIdempotency()` (individual path)
- `MockDataStore`: In-memory SwiftData with spy pattern. `storedPendingMutations` is the key array for verifying flush behavior.
- `MockDataStoreFactory`: Returns same mock instance for all `makeDataStore()` calls (unlike production which creates fresh contexts)

## SyncEngine Flush Flow (Critical for Understanding Failures)

```
flushPendingMutations()
  ├── Separate mutations by type:
  │   ├── Event CREATEs → syncEventCreateBatches()
  │   │   └── Batches of 50 → createEventsBatch() ← BATCH API
  │   └── Everything else → syncOtherMutations()
  │       └── One by one → flushMutation()
  │           ├── CREATE → flushCreate() → createEventWithIdempotency() ← INDIVIDUAL API
  │           ├── UPDATE → flushUpdate() → updateEvent/updateEventType/etc
  │           └── DELETE → flushDelete() → deleteEvent/deleteEventType/etc
  └── Check circuit breaker between batches
```

**The batch path calls `createEventsBatch()`. The individual path calls `createEventWithIdempotency()`.**
**Tests that seed event CREATEs but configure `createEventWithIdempotencyResponses` will fail.**
