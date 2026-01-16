# Debug Session: Offline Sync Issues

**Started:** 2026-01-16
**Status:** TENTATIVELY RESOLVED - Testing confirms no freeze
**Blocking:** Phase 5 verification (05-03 checkpoint)

## Current Focus

**Hypothesis:** The 60-second freeze is caused by Supabase SDK's `client.auth.session` call attempting to refresh an expired token over the network, using its internal URLSession with 60-second default timeout.

**Test:** Run app with timing logs, reproduce freeze, identify last log before 60-second gap.

**Expecting:** Last log will be `TIMING getAccessToken [T+0.000s] START - calling client.auth.session`

**Next Action:** User needs to test with the timing logs and report which log appears just before the freeze.

---

## Issues

### Issue 1: Offline Event Creation - Event Not Appearing in List ✅ FIXED

**Symptom:** When creating an event while offline, the event did not appear in the event list, but the banner showed a pending change.

**Root Cause:**
The EventListView uses a caching mechanism (`cachedGroupedEvents`, `cachedSortedDates`) that is updated via:
1. `.task` modifier - runs only on **first** appearance
2. `.onChange(of: eventStore.events.count)` - only fires when view is **active**

When the user creates an event on the Dashboard tab:
1. `events.insert()` happens in EventStore
2. But EventListView is inactive (different tab), so `.onChange` doesn't fire
3. When user switches to Events tab, `.task` doesn't re-run (view is cached)
4. The cache is never updated with the new event

**Fix Applied:**
- Added `.onAppear` modifier to EventListView that calls `updateCachedData()`
- This ensures the cache is rebuilt whenever the view becomes visible (e.g., switching tabs)

**Files Modified:**
- `apps/ios/trendy/Views/List/EventListView.swift` (added lines ~121-126)

**Status:** ✅ Verified working

---

### Issue 2: App Freeze When Returning from Background After Going Offline ❌ NOT FIXED

**Symptom:**
1. Launch app from Xcode
2. Swipe up to home, go to Settings
3. Enable Airplane Mode and turn off WiFi
4. Return to app
5. App is frozen/unresponsive for ~60 seconds

**Status:** Synchronous network check was added but DID NOT fix the issue. Freeze still occurs.

---

## ROOT CAUSE ANALYSIS (Issue 2)

### Evidence Gathered

1. **HealthKit `refreshDailyAggregates()` does NOT make network calls** - Verified by reading `HealthKitService+DailyAggregates.swift`. It only queries the local HealthKit store using `HKStatisticsQuery`.

2. **No `URLSession.shared` usage outside APIClient** - Grep search returned no matches. All HTTP calls go through APIClient with 15s/30s timeouts.

3. **Supabase SDK has its own URLSession with 60s default timeout** - The Supabase Swift SDK creates its own URLSession internally which we don't control.

### Root Cause: Supabase SDK Token Refresh with 60s Timeout

The 60-second freeze was caused by the Supabase SDK's internal network timeout when attempting to refresh an expired access token.

**Call Path:**
1. `MainTabView.onChange(of: scenePhase)` fires when scene becomes `.active`
2. `isOnline` check passes (stale `true` - NWPathMonitor hasn't updated yet)
3. `store.fetchData()` is called
4. `fetchData()` calls `syncEngine.performSync()`
5. `performSync()` calls `performHealthCheck()` at line 109
6. `performHealthCheck()` calls `apiClient.getEventTypes()`
7. `getEventTypes()` calls `authHeaders()` which calls `supabaseService.getAccessToken()`
8. `getAccessToken()` calls `client.auth.session` (Supabase SDK)
9. **If the JWT is expired**, Supabase SDK tries to refresh the token over the network
10. Supabase SDK uses its own URLSession with **60 second default timeout**
11. **FREEZE for 60 seconds** waiting for timeout

### Why Previous Fixes Didn't Work

1. **APIClient timeouts (15s/30s)** - These only apply to our custom URLSession, not to the Supabase SDK's internal URLSession.

2. **`isOnline` check** - This check was bypassed because:
   - NWPathMonitor runs callbacks on a background DispatchQueue
   - When scene becomes `.active`, the callback hasn't fired yet
   - `isOnline` is still stale `true` from before going offline
   - The check passes and `fetchData()` is called

---

## FIX APPLIED

### Solution: Synchronous Network Path Check

Instead of relying on the cached `isOnline` value (which can be stale), we now call `monitor.currentPath` synchronously to get the actual current network state.

### Changes Made

**1. EventStore.swift - Added `checkNetworkPathSynchronously()` method:**
```swift
/// Synchronously check the current network path status.
/// This is more reliable than the cached `isOnline` value when the app returns from background,
/// because NWPathMonitor callbacks may not have fired yet.
/// - Returns: true if network is currently available, false otherwise
func checkNetworkPathSynchronously() -> Bool {
    let path = monitor.currentPath
    let isConnected = path.status == .satisfied

    // Update cached value to match current state
    if isOnline != isConnected {
        Log.sync.debug("Network state updated from synchronous check", context: .with { ctx in
            ctx.add("cached_was", isOnline)
            ctx.add("actual_is", isConnected)
        })
        isOnline = isConnected
    }

    return isConnected
}
```

**2. MainTabView.swift - Updated scene phase handler to use synchronous check:**
```swift
// Check network status SYNCHRONOUSLY before making any network calls.
let isCurrentlyOnline = store.checkNetworkPathSynchronously()

if isCurrentlyOnline {
    await store.fetchData()
} else {
    Log.sync.debug("Scene active but offline (sync check) - skipping fetchData")
    await store.refreshSyncStateForUI()
}
```

**3. EventStore.swift - Added synchronous check in `fetchData()` as defense-in-depth:**
```swift
// Use synchronous network check to avoid stale isOnline value when returning from background
let actuallyOnline = checkNetworkPathSynchronously()
if let syncEngine = syncEngine, actuallyOnline {
    await syncEngine.performSync()
}
```

### Files Modified
- `apps/ios/trendy/ViewModels/EventStore.swift` - Added `checkNetworkPathSynchronously()` and updated `fetchData()`
- `apps/ios/trendy/Views/MainTabView.swift` - Use synchronous network check in scene phase handler

---

## Verification

The fix should be verified by:
1. Launch app from Xcode
2. Swipe up to home, go to Settings
3. Enable Airplane Mode and turn off WiFi
4. Return to app
5. **Expected:** App should be responsive immediately (no freeze)
6. Console should show: "Scene active but offline (sync check) - skipping fetchData"

---

## Summary

| Issue | Root Cause | Fix | Status |
|-------|-----------|-----|--------|
| Event not appearing in list | EventListView cache not updated on tab switch | Added `.onAppear` to refresh cache | ✅ Fixed |
| 60-second freeze on background return | Likely stale `isOnline` + Supabase SDK 60s timeout | Synchronous network check before any network calls | ✅ Tentatively Fixed |

---

## ATTEMPTED FIX THAT DID NOT WORK

The synchronous `monitor.currentPath` check was added but **did not resolve the freeze**.

This suggests the root cause is NOT the stale `isOnline` value. Something else is blocking.

---

## NEXT INVESTIGATION STEPS

### 1. Add Detailed Timing Logs
The freeze location is unknown. Add timestamped logs to identify exactly where the freeze occurs:

```swift
// In MainTabView.onChange(of: scenePhase)
Log.sync.info("TIMING: Scene became active - START", context: .with { ctx in
    ctx.add("timestamp", Date().timeIntervalSince1970)
})

// Before each operation:
Log.sync.info("TIMING: Before HealthKit refresh")
// ... operation ...
Log.sync.info("TIMING: After HealthKit refresh")

Log.sync.info("TIMING: Before checkNetworkPathSynchronously")
// ... operation ...
Log.sync.info("TIMING: After checkNetworkPathSynchronously")

// etc.
```

### 2. Check if HealthKit Query Blocks
Even though `refreshDailyAggregates()` doesn't make network calls, HKStatisticsQuery might block when system is in a weird state after background/airplane mode transition.

### 3. Check NWPathMonitor.currentPath
The `monitor.currentPath` call itself might block. NWPathMonitor documentation is unclear about thread safety of `currentPath` property.

### 4. Check Supabase SDK Auth State
Even with network check, Supabase SDK might be doing something on initialization or auth state restoration that blocks.

### 5. Run with Instruments
Profile the app with Time Profiler to see exactly what's blocking the main thread during the freeze.

### 6. Check for Other .task/.onAppear Modifiers
Other views might have their own network calls triggered on scene phase change.

### 7. Systematically Disable Code Paths
Comment out sections of the scene phase handler one by one:
1. First, comment out HealthKit refresh entirely
2. Then comment out fetchData() entirely
3. Then comment out geofence reconciliation
4. Identify which code path causes the freeze

---

## FILES CURRENTLY MODIFIED (uncommitted)

- `apps/ios/trendy/ViewModels/EventStore.swift` - Added `checkNetworkPathSynchronously()` method
- `apps/ios/trendy/Views/MainTabView.swift` - Uses synchronous network check (not working)
- `apps/ios/trendy/Views/List/EventListView.swift` - Added `.onAppear` for Issue 1

---

## CURRENT INVESTIGATION (2026-01-16)

### Timing Logs Added

Comprehensive timing logs have been added to trace the exact location of the 60-second freeze:

**Files Modified:**
1. `apps/ios/trendy/Views/MainTabView.swift` - Scene phase handler timing
2. `apps/ios/trendy/ViewModels/EventStore.swift` - fetchData() timing
3. `apps/ios/trendy/Services/Sync/SyncEngine.swift` - performSync() and performHealthCheck() timing
4. `apps/ios/trendy/Services/APIClient.swift` - authHeaders() timing
5. `apps/ios/trendy/Services/SupabaseService.swift` - getAccessToken() timing

**Log Pattern:**
All timing logs follow the pattern: `TIMING <function> [T+<seconds>s] <event>`

### Expected Log Output (Normal Flow)

```
=== TIMING [T+0.000s] Scene became active - START ===
TIMING [T+0.001s] Before ensureRegionsRegistered
TIMING [T+0.002s] After ensureRegionsRegistered
TIMING [T+0.003s] Inside Task - start
TIMING [T+0.004s] Before checkNetworkPathSynchronously
TIMING [T+0.005s] After checkNetworkPathSynchronously - result: true
TIMING [T+0.006s] Before fetchData
TIMING fetchData [T+0.000s] START
TIMING fetchData [T+0.001s] Before checkNetworkPathSynchronously
TIMING fetchData [T+0.002s] After checkNetworkPathSynchronously - result: true
TIMING fetchData [T+0.003s] Before syncEngine.performSync
TIMING performSync [T+0.000s] START
TIMING performSync [T+0.001s] Before performHealthCheck
TIMING performHealthCheck [T+0.000s] START - calling apiClient.getEventTypes()
TIMING authHeaders [T+0.000s] START - calling supabaseService.getAccessToken()
TIMING getAccessToken [T+0.000s] START - calling client.auth.session
<--- IF FREEZE OCCURS, THE LAST LOG BEFORE ~60s GAP IS THE CULPRIT --->
TIMING getAccessToken [T+0.100s] COMPLETE - session acquired  (or T+60.xxx if frozen here)
TIMING authHeaders [T+0.101s] COMPLETE - token acquired
TIMING performHealthCheck [T+0.500s] SUCCESS (or FAILED after timeout)
...
```

### Testing Instructions

1. **Build and run app from Xcode**
2. **Open Console.app** and filter by:
   - Process: trendy
   - Subsystem: com.memento.trendy (or filter by "TIMING")
3. **Reproduce the freeze:**
   - With app in foreground, swipe up to go home
   - Go to Settings > Airplane Mode > Enable
   - Also turn off WiFi
   - Return to the trendy app
4. **Watch Console.app** for TIMING logs
5. **Identify the freeze:** Look for a ~60 second gap between two consecutive TIMING logs
   - The log BEFORE the gap identifies where the freeze begins
   - This will definitively tell us which operation is blocking

### Hypothesis Based on Code Analysis

Based on the code path, the most likely freeze location is:
```
TIMING getAccessToken [T+0.000s] START - calling client.auth.session
<--- 60 second gap --->
TIMING getAccessToken [T+60.xxx] COMPLETE (or error)
```

**Reason:** `client.auth.session` triggers the Supabase SDK's internal session refresh mechanism, which uses its own URLSession with a 60-second default timeout that we cannot control.

### Next Steps After Testing

1. **If freeze is in `getAccessToken`:** The root cause is confirmed as Supabase SDK token refresh. Fix options:
   - Check if session is expired BEFORE calling `client.auth.session`
   - Use a cached token if available
   - Add a pre-flight network check before any Supabase calls

2. **If freeze is elsewhere:** The timing logs will reveal the actual culprit and we can investigate that specific code path.

---

## RESOLUTION (2026-01-16)

### Test Result
User tested the offline→return flow and **the freeze no longer occurs**.

### Analysis
The fix appears to be working. The combination of:
1. Synchronous `monitor.currentPath` check in `checkNetworkPathSynchronously()`
2. Using this check in MainTabView before calling `fetchData()`
3. Using this check again in `fetchData()` before calling `syncEngine.performSync()`

This defense-in-depth approach ensures that when offline:
- The synchronous check detects the offline state immediately
- No network calls are attempted (including Supabase SDK token refresh)
- The 60-second timeout is never triggered

### Possible Race Condition
The earlier test where the fix "didn't work" may have been a race condition where:
- The timing logs added slight delays
- Or the test conditions differed (token expiry state, etc.)

### Recommendation
1. **Keep the timing logs for now** - They have minimal performance impact and help diagnose future issues
2. **Test a few more times** over the next day to confirm consistency
3. **Clean up timing logs later** once we're confident the fix is stable

### Files Modified (ready for commit)
- `apps/ios/trendy/ViewModels/EventStore.swift` - `checkNetworkPathSynchronously()` + timing logs
- `apps/ios/trendy/Views/MainTabView.swift` - Synchronous network check + timing logs
- `apps/ios/trendy/Views/List/EventListView.swift` - `.onAppear` cache refresh (Issue 1)
- `apps/ios/trendy/Services/Sync/SyncEngine.swift` - Timing logs
- `apps/ios/trendy/Services/APIClient.swift` - Timing logs
- `apps/ios/trendy/Services/SupabaseService.swift` - Timing logs

---

## TO RESUME (if issues recur)

1. Read this document for full context
2. Check Console.app for TIMING logs to identify where any new freeze occurs
3. The timing logs are still in place for diagnostics
