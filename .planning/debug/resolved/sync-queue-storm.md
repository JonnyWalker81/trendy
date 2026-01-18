---
status: resolved
trigger: "Sync engine retry storm causing app unresponsiveness. ~1000 events queued, all hitting 429 rate limits, retries pile up."
created: 2026-01-15T00:00:00Z
updated: 2026-01-15T00:03:00Z
---

## Current Focus

hypothesis: Fix verified - build succeeded
test: iOS build completed successfully
expecting: App compiles and user can test clearing mutation queue
next_action: Archive session

## Symptoms

expected: App remains responsive when HealthKit data syncs to backend
actual: App becomes unresponsive. Continuous 429 errors, retry storm, "System gesture gate timed out" in logs
errors: |
  - status=429, "rate limit exceeded"
  - "Mutation will retry [attempts_after=1]"
  - "Rate limited, retrying [endpoint=/events, retry_count=1, delay_seconds=1.0]"
  - "System gesture gate timed out"
  - PostHog queue depth growing (30+)
reproduction: |
  1. Enable HealthKit categories
  2. App fetches historical data (1000+ samples)
  3. Each sample creates event and queues for sync
  4. Backend rate limits at 429
  5. Retry storm ensues
timeline: Started when Phase 2 HealthKit work added bulk historical import. isBulkImport fix added to skip sync for NEW events, but existing queue (~1000 events) persists and keeps retrying.

## Eliminated

## Evidence

- timestamp: 2026-01-15T00:01:00Z
  checked: PendingMutation model (apps/ios/trendy/Models/PendingMutation.swift)
  found: |
    - Stored in SwiftData (@Model class)
    - Max 5 retry attempts per mutation (hasExceededRetryLimit at attempts >= 5)
    - No backoff between mutations in the same sync cycle
    - recordFailure() increments attempts but doesn't track 429 specifically
  implication: Mutations retry up to 5 times, but all ~1000 mutations get processed in same sync loop

- timestamp: 2026-01-15T00:01:00Z
  checked: SyncEngine.flushPendingMutations() (apps/ios/trendy/Services/Sync/SyncEngine.swift:320-411)
  found: |
    - Fetches ALL pending mutations and processes them in a tight loop
    - No delay between mutations
    - Each mutation that fails with 429 gets recordFailure() but loop continues immediately
    - Only stops processing when hasExceededRetryLimit (5 attempts)
    - No circuit breaker - if one mutation gets 429, all will likely get 429
  implication: With 1000 mutations, each getting 429, app hammers backend continuously

- timestamp: 2026-01-15T00:01:00Z
  checked: APIClient.requestWithIdempotency() (apps/ios/trendy/Services/APIClient.swift:452-524)
  found: |
    - Has built-in retry for 429: maxRetries=3, exponential backoff starting at 1 second
    - Delays are: 1s, 2s, 4s for retries 1-3
    - BUT: After 3 retries, throws error which SyncEngine catches
  implication: Each mutation does 4 attempts (1 initial + 3 retries) with delays, then fails

- timestamp: 2026-01-15T00:01:00Z
  checked: Combined retry behavior
  found: |
    DOUBLE RETRY STORM:
    1. APIClient retries each request up to 3 times with backoff (per request)
    2. SyncEngine retries each mutation up to 5 times (per sync cycle)

    With 1000 mutations:
    - First sync: 1000 mutations * 4 API attempts each = 4000 API calls
    - If all fail: 1000 mutations stay in queue with attempts=1
    - Second sync: another 4000 API calls
    - ...continues until attempts=5 for each mutation

    Total potential: 1000 mutations * 5 SyncEngine retries * 4 API attempts = 20,000 API calls!
  implication: This is the retry storm - multiplicative retries across two layers

- timestamp: 2026-01-15T00:01:00Z
  checked: Sync trigger points (EventStore.swift)
  found: |
    - performSync() called on:
      - Network restored (handleNetworkRestored)
      - fetchData() if online
      - After each CRUD operation (recordEvent, updateEvent, deleteEvent, etc.)
      - After queueMutationsForUnsyncedEvents
    - Multiple code paths trigger performSync, potentially overlapping
  implication: Multiple sync triggers can pile up, each processing the full mutation queue

- timestamp: 2026-01-15T00:02:00Z
  checked: Fix implementation
  found: |
    Implemented multi-pronged fix in:
    1. APIClient.swift - Added isRateLimitError property to APIError
    2. SyncEngine.swift - Added circuit breaker with:
       - consecutiveRateLimitErrors counter
       - rateLimitCircuitBreakerThreshold = 3
       - rateLimitBackoffUntil timestamp
       - Exponential backoff (30s base, 5min max)
       - clearPendingMutations() method
       - 429 errors don't count against mutation retry limit
    3. EventStore.swift - Added clearPendingMutations() wrapper
    4. DebugStorageView.swift - Added "Clear Mutation Queue" button
  implication: Circuit breaker should stop retry storm after 3 consecutive 429s, user can manually clear queue

- timestamp: 2026-01-15T00:03:00Z
  checked: Build verification
  found: |
    xcodebuild succeeded with "** BUILD SUCCEEDED **"
    All Swift files compiled without errors
    App signed successfully
  implication: Fix is syntactically correct and compiles

## Resolution

root_cause: |
  Multiple compounding issues cause exponential retry behavior:

  1. NO CIRCUIT BREAKER: SyncEngine processes ALL mutations in a tight loop without stopping when rate limited. If backend returns 429 for one request, all subsequent requests will also fail.

  2. DOUBLE RETRY LAYER: APIClient retries 3x with backoff, then SyncEngine retries 5x per mutation. This multiplies retries exponentially (4 * 5 = 20 attempts per mutation).

  3. NO QUEUE PAUSE ON 429: When 429 is encountered, the queue should pause/backoff, not continue processing remaining mutations.

  4. EXISTING QUEUE PERSISTS: The isBulkImport fix prevents NEW events from queuing during bulk import, but existing ~1000 queued mutations remain and keep retrying.

  5. NO WAY TO CLEAR QUEUE: There's no UI or mechanism to clear the mutation queue when it gets into this state.

fix: |
  Implemented multi-pronged fix:

  1. ADDED CIRCUIT BREAKER to SyncEngine.flushPendingMutations():
     - Tracks consecutive 429 errors (consecutiveRateLimitErrors)
     - After 3 consecutive 429s (rateLimitCircuitBreakerThreshold), trips circuit breaker
     - Enters backoff state (30s base, exponential up to 5min max)
     - Skips mutation flush entirely while in backoff (rateLimitBackoffUntil)
     - tripCircuitBreaker() method handles the state transition

  2. ADDED RATE LIMIT DETECTION:
     - Added isRateLimitError property to APIError enum
     - 429 errors don't increment mutation.attempts (not the mutation's fault)
     - Only non-rate-limit errors count against retry limit
     - Successful mutations reset consecutiveRateLimitErrors to 0

  3. ADDED QUEUE CLEARING:
     - SyncEngine.clearPendingMutations(markEntitiesFailed:) method
     - EventStore.clearPendingMutations() wrapper for UI
     - Clears all PendingMutation records from SwiftData
     - Resets circuit breaker state when queue is cleared
     - Returns count of cleared mutations

  4. ADDED UI FOR MANUAL RECOVERY:
     - "Clear Mutation Queue (N)" button in DebugStorageView
     - Only visible when pendingMutationCount > 0
     - Confirmation dialog warns about data loss
     - Success alert shows count cleared

verification: |
  BUILD VERIFIED: xcodebuild succeeded with "** BUILD SUCCEEDED **"

  To test the fix in the app:
  1. Open app with existing retry storm
  2. Go to Settings > Debug Storage
  3. Observe "Pending Mutations" count (should be ~1000)
  4. Click "Clear Mutation Queue" button
  5. Confirm action in dialog
  6. Verify mutations cleared (count goes to 0)
  7. App should become responsive

files_changed:
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/Services/APIClient.swift
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/Services/Sync/SyncEngine.swift
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/ViewModels/EventStore.swift
  - /Users/cipher/Repositories/trendy/apps/ios/trendy/Views/Settings/DebugStorageView.swift
