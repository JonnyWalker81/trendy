# Pitfalls Research: iOS Background Data Infrastructure

**Domain:** iOS background data infrastructure (HealthKit, CoreLocation, SwiftData, Sync)
**Researched:** 2026-01-15
**Confidence:** HIGH (verified against Apple documentation and current codebase)

## Executive Summary

This research documents the most common and costly mistakes iOS developers make when building background data infrastructure. The Trendy app already exhibits several of these pitfalls in production, making this research directly actionable.

**Current Trendy Issues Mapped to Pitfalls:**
- HealthKit workouts/active energy not triggering background delivery (Pitfall 1, 2)
- Geofences silently unregistering after days/weeks (Pitfall 5, 6)
- Complex cursor logic in SyncEngine that's fragile (Pitfall 9, 10)
- 45+ print statements instead of structured logging (Pitfall 14)

---

## Critical Pitfalls

### Pitfall 1: Missing or Incomplete HealthKit Background Delivery Entitlement

**What goes wrong:**
App requests HealthKit authorization and sets up observer queries, but background delivery never fires. The app works in foreground but fails silently in background.

**Why it happens:**
iOS 15+ requires the `com.apple.developer.healthkit.background-delivery` entitlement in BOTH the entitlements file AND the provisioning profile. Many developers add it to one but not the other, or miss it entirely because older tutorials don't mention it.

**How to avoid:**
1. Add entitlement via Xcode: Signing & Capabilities > HealthKit > check "Background Delivery"
2. Verify the entitlement appears in your `.entitlements` file:
   ```xml
   <key>com.apple.developer.healthkit.background-delivery</key>
   <true/>
   ```
3. Regenerate provisioning profiles after adding the capability
4. Add a startup check that logs whether the entitlement is present

**Warning signs:**
- Observer queries fire once immediately, then never again
- Background delivery works on simulator but not device
- App Store rejection mentioning HealthKit entitlements
- `enableBackgroundDelivery` returns without error but delivery never happens

**Phase to address:** Phase 1 (Foundation) - Audit entitlements before any HealthKit refactoring

---

### Pitfall 2: Not Calling HKObserverQuery Completion Handler in All Code Paths

**What goes wrong:**
HealthKit background delivery works initially, then stops completely after a few deliveries. The system believes your app is still processing and stops sending updates.

**Why it happens:**
The `HKObserverQuery` update handler receives a completion handler that MUST be called. If any code path (especially error paths) exits without calling it, HealthKit uses exponential backoff and eventually stops delivery entirely after 3 failed attempts.

**Current Trendy status:** The codebase calls `completionHandler()` in the observer query, but the async Task inside does not guarantee the completion handler timing is correct:

```swift
// Current code (HealthKitService.swift line 394-414)
let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
    // ...
    Task {
        await self.handleNewSamples(for: category)  // This can take arbitrary time
    }
    completionHandler()  // Called before Task completes - this is correct
}
```

**How to avoid:**
1. Call completion handler BEFORE spawning async work (current code does this correctly)
2. Never let any code path exit the update handler without calling the completion handler
3. Add explicit logging when completion handler is called
4. Set up monitoring for "HealthKit stopped delivering updates"

**Warning signs:**
- Delivery works for first few updates, then stops
- Restarting the app temporarily fixes the issue
- Console shows "exhausting the 15-second time allowance" errors

**Phase to address:** Phase 2 (HealthKit Refactor) - Add comprehensive logging around completion handler calls

---

### Pitfall 3: Assuming All HealthKit Data Types Support Immediate Delivery Frequency

**What goes wrong:**
Developer sets `.immediate` frequency for all data types, expecting real-time updates. Some data types work, others never trigger or trigger only hourly.

**Why it happens:**
Apple doesn't document which data types support which frequencies. Some types (like `activeEnergyBurned`, `stepCount`) have a MAXIMUM frequency of `.hourly` regardless of what you request. Workouts support `.immediate`.

**Current Trendy status:** The codebase uses `category.backgroundDeliveryFrequency` which should be verified per data type.

**How to avoid:**
1. Test each data type empirically on a real device
2. Document the observed behavior per type:
   - `.workout` - immediate works
   - `.sleepAnalysis` - immediate works
   - `.stepCount` - hourly maximum
   - `.activeEnergyBurned` - hourly maximum
3. Set expectations in UI based on actual behavior
4. Don't rely solely on background delivery for cumulative types - poll on app foreground

**Warning signs:**
- Steps/active energy never update in background
- Works when charging but not on battery
- Hourly data arrives, per-workout data doesn't

**Phase to address:** Phase 2 (HealthKit Refactor) - Verify and document frequency support per data type

---

### Pitfall 4: HealthKit Background Delivery Only Works When Charging

**What goes wrong:**
Background delivery works perfectly during development (phone plugged in) but users report it doesn't work in real use.

**Why it happens:**
This is documented iOS behavior for some data types. The system aggressively limits background execution to preserve battery. When the device is not charging, HealthKit may batch updates or skip them entirely.

**How to avoid:**
1. Design for "best effort" background delivery, not guaranteed real-time
2. Use `.immediate` frequency but expect actual delivery to vary
3. Always refresh data when app comes to foreground
4. Communicate expectations to users in UI

**Warning signs:**
- Users report missing data
- QA says "it works for me" (they're testing while charging)
- Data appears in batches when user plugs in phone

**Phase to address:** Phase 2 (HealthKit Refactor) - Add foreground refresh, communicate expectations

---

### Pitfall 5: Geofences Silently Stop Working After App Termination

**What goes wrong:**
Geofences work initially, but after the app is terminated (force-quit or system termination), they stop triggering entirely. Users don't notice until they realize they missed multiple location events.

**Why it happens:**
iOS 15+ has a known behavior where `startMonitoringForRegion` doesn't reliably relaunch terminated apps. The regions are technically still monitored, but the app isn't relaunched to handle crossings. This is worse when:
- User force-quits the app
- Background App Refresh is disabled
- Device enters Low Power Mode

**Current Trendy status:** GeofenceManager re-registers regions on authorization change but doesn't verify regions are actually monitored after app restart.

**How to avoid:**
1. Re-register ALL regions in `application:didFinishLaunchingWithOptions:`
2. Verify `locationManager.monitoredRegions` matches expected state
3. Request state for all regions on startup to catch missed crossings
4. Consider using Significant Location Change as a backup trigger
5. Implement a "geofence health check" that notifies user if monitoring appears broken

**Warning signs:**
- Geofences work for hours/days, then stop
- Restarting app fixes the issue temporarily
- Works in simulator but not on device after kill/restart

**Phase to address:** Phase 3 (Geofence Refactor) - Add startup verification and recovery

---

### Pitfall 6: Not Handling iOS 20-Region Limit Gracefully

**What goes wrong:**
Developer adds more than 20 geofences, and iOS silently fails to monitor some of them. Or, the app monitors 20 regions, and a system app (Home, Reminders) evicts one of your regions without notification.

**Why it happens:**
iOS has a hard limit of 20 monitored regions per app. This limit is NOT just per-app - the total system limit means other apps can potentially evict your regions. There's no callback when a region is evicted.

**Current Trendy status:** GeofenceManager limits to first 20 geofences (line 167), but doesn't prioritize which 20 or handle eviction.

**How to avoid:**
1. Implement "closest 20" monitoring - re-calculate on significant location change
2. Periodically verify `monitoredRegions.count` matches expected count
3. Compare registered identifiers against expected identifiers
4. Log when region count drops unexpectedly
5. Consider server-side geofencing for unlimited regions

**Warning signs:**
- Some geofences work, others don't
- Users with many geofences report inconsistent behavior
- Region count is less than what you registered

**Phase to address:** Phase 3 (Geofence Refactor) - Implement dynamic region management

---

### Pitfall 7: SwiftData Model Objects Passed Across Threads

**What goes wrong:**
App crashes with "CoreData concurrency debugging" errors or silently corrupts data. Crashes are intermittent and hard to reproduce.

**Why it happens:**
SwiftData models are NOT thread-safe and NOT Sendable. Passing a model object from a background actor to the main thread (or vice versa) violates concurrency rules. The compiler doesn't always catch this in Swift 5.x.

**Current Trendy status:** The codebase uses `@MainActor` annotations and separate ModelContexts, but some patterns are risky:
- SyncEngine creates `ModelContext(modelContainer)` on actor isolation
- HealthKitService accesses `modelContext` from async Task blocks

**How to avoid:**
1. Never pass `PersistentModel` objects across actor boundaries
2. Pass `persistentModelID` instead, then fetch in the destination context
3. Use `@ModelActor` for background work with its own ModelContext
4. Map model data to plain structs before passing across boundaries
5. Enable Strict Concurrency checking (`-strict-concurrency=complete`)

**Warning signs:**
- Intermittent crashes with "context is missing" errors
- Data corruption that appears after multitasking
- Crashes only in release builds, not debug

**Phase to address:** Phase 4 (SwiftData Migration) - Audit all model access patterns

---

### Pitfall 8: Creating ModelActor on Main Thread Accidentally

**What goes wrong:**
Developer uses `@ModelActor` expecting background execution, but operations actually run on main thread, blocking UI.

**Why it happens:**
`@ModelActor` inherits the execution context from where it's created. If created from a SwiftUI view (MainActor), it runs on main thread. Must use `Task.detached { ... }` to create truly background actors.

**How to avoid:**
1. Create `@ModelActor` instances inside `Task.detached` blocks
2. Verify thread using `Thread.current.isMainThread` in debug builds
3. Use separate `ModelContainer` for background work
4. Test with large datasets to notice blocking

**Warning signs:**
- UI freezes during "background" operations
- Profile shows main thread blocking during SwiftData operations
- "Background" actor operations complete suspiciously fast

**Phase to address:** Phase 4 (SwiftData Migration) - Verify ModelActor execution context

---

### Pitfall 9: Sync Engine Race Conditions with Cursor Management

**What goes wrong:**
Sync runs, data appears, then data disappears or duplicates. The cursor advances incorrectly, causing the sync to skip changes or re-apply old changes.

**Why it happens:**
Cursor-based sync is fragile when:
- Multiple syncs run concurrently (missing single-flight lock)
- Cursor is updated before changes are successfully applied
- Network timeout causes partial sync but cursor still advances
- Bootstrap and incremental sync run simultaneously

**Current Trendy status:** SyncEngine has sophisticated cursor management but the complexity itself is a risk:
- `forceBootstrapOnNextSync` flag adds state
- Cursor saved to UserDefaults with environment-specific keys
- `pendingDeleteIds` tracking to prevent resurrection

**How to avoid:**
1. Implement proper single-flight pattern (current code has `isSyncing` flag - good)
2. Only advance cursor AFTER changes are successfully persisted
3. Use transactions for atomic cursor + data updates
4. Add comprehensive logging of cursor state changes
5. Implement cursor validation (never go backwards unexpectedly)

**Warning signs:**
- Data appears then disappears
- Same changes applied multiple times
- "Force resync" becomes a common user action
- Cursor logged as 0 unexpectedly

**Phase to address:** Phase 5 (Sync Engine) - Simplify cursor logic, add validation

---

### Pitfall 10: Last-Write-Wins Conflict Resolution Losing User Data

**What goes wrong:**
User edits on device A, edits on device B while offline, syncs B first, then A syncs and overwrites B's changes. User loses work without warning.

**Why it happens:**
LWW (Last-Write-Wins) is simple to implement but loses data when:
- Devices have clock skew
- Concurrent offline edits
- Slow networks cause sync delays

**Current Trendy status:** The sync engine uses implicit LWW - whoever syncs last wins. No conflict detection or user notification.

**How to avoid:**
1. For user-generated content: detect conflicts, prompt user
2. For system-generated data (HealthKit events): LWW is acceptable
3. Add `updatedAt` timestamp to all entities
4. Detect when local changes would be overwritten by older server data
5. Consider field-level merging for complex entities

**Warning signs:**
- Users report "my changes disappeared"
- Data reverts to old state after sync
- Issues correlate with multi-device usage

**Phase to address:** Phase 5 (Sync Engine) - Add conflict detection for user content

---

### Pitfall 11: Offline Queue Operations Applied Out of Order

**What goes wrong:**
User creates EventType, creates Event referencing it, then goes online. Event sync fails because EventType hasn't synced yet.

**Why it happens:**
Operations are queued in order, but dependencies between operations aren't tracked. Parent entities must exist on server before children can reference them.

**Current Trendy status:** SyncEngine flushes mutations in order, but doesn't explicitly handle dependencies.

**How to avoid:**
1. Sort pending mutations by entity type (EventTypes before Events)
2. Track dependencies explicitly in the queue
3. Retry failed operations after their dependencies succeed
4. Use batch operations that maintain referential integrity

**Warning signs:**
- Sync errors mentioning "foreign key" or "not found"
- Some entities sync, their children don't
- Order of operations matters for success

**Phase to address:** Phase 5 (Sync Engine) - Implement dependency-aware flush ordering

---

### Pitfall 12: BGTaskScheduler Tasks Not Registered Early Enough

**What goes wrong:**
Background tasks never run. No errors, just silence. The scheduler doesn't complain but also doesn't schedule.

**Why it happens:**
BGTaskScheduler requires tasks to be registered in `application:didFinishLaunchingWithOptions:` BEFORE the app finishes launching. Registering later causes silent failure.

**How to avoid:**
1. Register ALL task identifiers in AppDelegate's `didFinishLaunchingWithOptions`
2. Add all task identifiers to Info.plist `BGTaskSchedulerPermittedIdentifiers`
3. Log when registration succeeds/fails
4. Test on real device (simulator doesn't support BGTaskScheduler)

**Warning signs:**
- Background tasks work in development (triggered manually) but not in production
- No crashes, just no background execution
- Works after force-quit + relaunch

**Phase to address:** Phase 1 (Foundation) - Audit background task registration

---

### Pitfall 13: User Force-Quit Disables Background Execution

**What goes wrong:**
Users complain background features don't work. Investigation shows they force-quit the app from the app switcher.

**Why it happens:**
When a user force-quits an app, iOS disables ALL background execution until the user manually relaunches. This is by design but surprising. There's no way to detect this state or work around it.

**How to avoid:**
1. Educate users not to force-quit if they want background features
2. Show a "background health" indicator in the app
3. Detect "app was force-quit" on next launch (no clean termination callback)
4. Consider onboarding that explains background feature requirements

**Warning signs:**
- Background features work for some users, not others
- Issue correlates with users who "manage battery" by killing apps
- Reinstalling temporarily fixes the issue

**Phase to address:** Phase 6 (Polish) - Add user education about background execution

---

### Pitfall 14: Print Statements Instead of Structured Logging

**What goes wrong:**
Production issue occurs, but logs are useless. No timestamps, no severity levels, no context. Debugging requires reproducing the issue.

**Why it happens:**
During development, `print()` is easy. It becomes habit. When production issues arise, there's no way to enable verbose logging remotely or filter by component.

**Current Trendy status:** 45+ print statements in the codebase. The `Log` utility exists but isn't used consistently.

**How to avoid:**
1. Use structured logging (Log.category.level) everywhere
2. Include context: IDs, timestamps, counts
3. Use different log levels: debug for verbose, info for significant, error for failures
4. Enable log level configuration per-environment
5. Remove all `print()` calls in production code

**Warning signs:**
- Debugging requires attaching Xcode
- No way to get logs from user devices
- Can't tell when an issue started

**Phase to address:** Phase 1 (Foundation) - Replace all print statements with structured logging

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Print statements | Fast debugging | No production visibility | Never in production code |
| Force unwrapping optionals | Less code | Crashes on edge cases | Never for external data |
| Synchronous main thread DB access | Simple code | UI freezes | Only for tiny datasets |
| Global singletons | Easy access | Testing nightmares | For truly global state only |
| Ignoring completion handlers | Faster execution | Silent failures | Never for system callbacks |
| Hard-coded limits (magic numbers) | Quick fix | Maintenance burden | Never - use named constants |
| Skipping error handling | Faster shipping | Silent failures | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| HealthKit + Background | Not calling completion handler | Always call in all code paths |
| HealthKit + Authorization | Assuming read auth status is queryable | Track authorization request, not grant |
| CoreLocation + Background | Expecting immediate region events | Account for 3-5 minute delay minimum |
| CoreLocation + Termination | Assuming regions persist | Re-register on every app launch |
| SwiftData + Actors | Passing models across boundaries | Pass IDs, fetch in destination context |
| SwiftData + @Observable | Mixing actor isolation modes | Use consistent isolation strategy |
| URLSession + Background | Not handling session delegate | Implement all required delegate methods |
| UserDefaults + Sync | Relying on automatic sync | Call synchronize() for critical data |

---

## iOS Background Execution Traps

### Trap 1: Testing While Charging
Background execution behaves differently on battery vs charging. Always test on battery for realistic behavior.

### Trap 2: Simulator Background Testing
Simulators don't accurately simulate background execution limits. Test on real devices.

### Trap 3: Debug Build Background
Debug builds may have different background execution behavior. Test release builds periodically.

### Trap 4: Fresh Install vs Update
Background permissions and registrations may behave differently on fresh install vs app update. Test both paths.

### Trap 5: Low Power Mode
Low Power Mode disables most background execution. Test with and without.

### Trap 6: Background App Refresh Setting
Users can disable Background App Refresh globally or per-app. Detect and handle this gracefully.

### Trap 7: Memory Pressure
iOS terminates background apps aggressively under memory pressure. Don't assume your app stays resident.

### Trap 8: 30-Second Execution Limit
Standard background tasks have 30-second limit. Design tasks to complete quickly.

### Trap 9: Task Completion Handler
Not calling task completion handler causes iOS to penalize future background execution.

### Trap 10: Excessive Background Attempts
iOS tracks failed background attempts. Too many failures = reduced future background time.

---

## "Looks Done But Isn't" Checklist

- [ ] **HealthKit integration**: Often missing background delivery entitlement
- [ ] **HealthKit observer query**: Often missing completion handler in error paths
- [ ] **Geofence monitoring**: Often not re-registering on app launch
- [ ] **Geofence monitoring**: Often not handling 20-region limit
- [ ] **SwiftData background**: Often passing model objects across threads
- [ ] **Sync engine**: Often advancing cursor before persisting changes
- [ ] **Sync engine**: Often missing dependency ordering in queue
- [ ] **Background tasks**: Often registered too late in app lifecycle
- [ ] **Error handling**: Often logging error but not handling it
- [ ] **Offline support**: Often not testing airplane mode scenarios

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 - HealthKit entitlement | Phase 1 (Foundation) | Check entitlements file |
| 2 - Completion handler | Phase 2 (HealthKit) | Add logging, code review |
| 3 - Delivery frequency | Phase 2 (HealthKit) | Document per data type |
| 4 - Charging-only delivery | Phase 2 (HealthKit) | Test on battery |
| 5 - Geofence termination | Phase 3 (Geofence) | Test force-quit + region crossing |
| 6 - 20-region limit | Phase 3 (Geofence) | Test with 21+ geofences |
| 7 - SwiftData threading | Phase 4 (SwiftData) | Enable strict concurrency |
| 8 - ModelActor isolation | Phase 4 (SwiftData) | Verify execution thread |
| 9 - Cursor race conditions | Phase 5 (Sync) | Add cursor validation logging |
| 10 - LWW data loss | Phase 5 (Sync) | Test concurrent offline edits |
| 11 - Queue ordering | Phase 5 (Sync) | Test EventType + Event creation offline |
| 12 - BGTask registration | Phase 1 (Foundation) | Verify in didFinishLaunching |
| 13 - Force-quit | Phase 6 (Polish) | Add user education |
| 14 - Print statements | Phase 1 (Foundation) | Replace with structured logging |

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: [HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- Apple Developer Documentation: [enableBackgroundDelivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/1614175-enablebackgrounddelivery)
- Apple Developer Documentation: [Region Monitoring](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)
- Apple Developer Forums: [HealthKit background delivery issues](https://developer.apple.com/forums/thread/704685)
- Apple Developer Forums: [CoreLocation region monitoring](https://developer.apple.com/forums/thread/694081)
- BrightDigit: [Using ModelActor in SwiftData](https://brightdigit.com/tutorials/swiftdata-modelactor/)
- Fat Bob Man: [Concurrent Programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/)

### Secondary (MEDIUM confidence)
- Medium: [Challenges With HKObserverQuery](https://medium.com/@shemona/challenges-with-hkobserverquery-and-background-app-refresh-for-healthkit-data-handling-8f84a4617499)
- Medium: [SwiftData ModelActor pitfalls](https://killlilwinters.medium.com/taking-swiftdata-further-modelactor-swift-concurrency-and-avoiding-mainactor-pitfalls-3692f61f2fa1)
- Radar.com: [Limitations of iOS Geofencing](https://radar.com/blog/limitations-of-ios-geofencing)
- Medium: [Offline-First Architecture](https://medium.com/@jusuftopic/offline-first-architecture-designing-for-reality-not-just-the-cloud-e5fd18e50a79)
- Dev.to: [iOS 26 Background APIs](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5)

### Tertiary (verified against codebase)
- Trendy codebase: `HealthKitService.swift`, `GeofenceManager.swift`, `SyncEngine.swift`
