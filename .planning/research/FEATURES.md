# Feature Research: iOS Background Data Infrastructure

**Domain:** iOS background data infrastructure (HealthKit, geofences, sync engine)
**Researched:** 2026-01-15
**Confidence:** MEDIUM (WebSearch-based with Apple documentation verification)

## Feature Landscape

### Table Stakes (Users Expect These)

Features that users expect from a reliable background data capture system. Missing these creates friction and distrust.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **HealthKit background delivery** | Workout apps auto-import data without manual refresh | HIGH | iOS controls timing; requires observer queries per data type |
| **Geofence persistence across app lifecycle** | Location triggers work even after app restart | MEDIUM | Must re-register on launch; iOS manages regions |
| **Offline data creation** | Users can log events without network | LOW | Standard local-first pattern |
| **Automatic sync when online** | No manual "sync" button required | MEDIUM | Network monitoring + automatic queue processing |
| **Data never lost** | Offline changes eventually sync successfully | MEDIUM | Persistent queue with retry logic |
| **Geofence enter/exit notifications** | User knows location trigger fired | LOW | Standard iOS notification |
| **HealthKit permission transparency** | User sees what data is being accessed | LOW | Standard iOS permission UI |
| **Background App Refresh support** | App can sync while backgrounded | MEDIUM | User can disable; must handle gracefully |
| **Re-registration after iOS eviction** | Geofences restored after iOS terminates app | MEDIUM | Check on launch, re-add missing regions |
| **Duplicate prevention** | Same workout/event not imported twice | MEDIUM | Track processed sample IDs; anchor-based queries |

### Differentiators (Better Than Typical)

Features that go beyond basic expectations. These create trust and delight.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Sync state visibility** | User knows what's pending, what's synced | MEDIUM | "3 events pending sync" indicator |
| **Last sync timestamp** | User knows data freshness | LOW | Simple timestamp display |
| **Sync error surfacing** | User knows if something is stuck | MEDIUM | Show error state, offer retry |
| **Deterministic progress indicators** | "Syncing 3 of 5" vs spinner | LOW | Track queue size, show progress |
| **Automatic retry with backoff** | Failed syncs retry intelligently | MEDIUM | Exponential backoff + jitter; max 5 attempts |
| **HealthKit data freshness indicator** | User knows last HealthKit update time | LOW | Track last observer callback |
| **Geofence health monitoring** | User sees which geofences are actually registered | MEDIUM | Compare saved vs CLLocationManager.monitoredRegions |
| **Offline mode indicator** | User knows app is offline but functional | LOW | Network status badge |
| **Smart geofence rotation** | Handle >20 geofences via proximity-based monitoring | HIGH | Monitor nearest 20, update on significant location change |
| **Background delivery verification** | Confirm HealthKit observer queries are running | MEDIUM | Debug view showing active queries |
| **Conflict resolution transparency** | User knows when local change was overwritten | HIGH | Show "updated from server" indicator |
| **Charging-aware sync** | More aggressive sync when charging | LOW | Check battery state, adjust strategy |

### Anti-Features (Avoid These)

Features that seem useful but create problems in background systems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Manual "Sync Now" button** | User control | Creates expectation iOS can't meet; BGTaskScheduler timing not controllable | Show sync state; auto-sync handles it |
| **Real-time HealthKit updates** | Instant workout appearance | iOS delivers background updates on its own schedule; promising real-time creates frustration | Set expectation: "within 1 hour" |
| **Guaranteed background execution times** | Predictable sync schedule | iOS has full discretion on background task timing | Design for eventual consistency |
| **Force-quitting warning dismissal** | User finds warnings annoying | User needs to know force-quit breaks geofences | Keep warning, make it contextual |
| **Unlimited geofences** | User wants many locations | iOS hard limit is 20; workarounds add complexity and battery drain | Clear UI showing limit, proximity rotation if needed |
| **Continuous location tracking** | More accurate geofences | Massive battery drain; user backlash | Event-driven monitoring only |
| **Automatic conflict resolution (silent)** | "Just make it work" | User loses changes without knowing | Show conflicts, let user choose |
| **Retry forever** | Never give up on sync | Drains battery; fills queue with impossible operations | Max 5 attempts, then surface error |
| **Fine-grained sync preferences** | User tunes sync behavior | Adds complexity; most users won't touch; creates support burden | Smart defaults, one "sync less often" toggle at most |
| **Background HealthKit polling** | Get data faster than observer callbacks | Apple explicitly discourages; may cause background delivery to stop | Trust observer query system |

## Feature Dependencies

```
Offline data creation
    |
    v
Persistent mutation queue
    |
    v
Network monitoring -----------> Automatic sync when online
    |
    v
Retry with backoff
    |
    v
Sync state visibility <-------- Error surfacing
```

```
HealthKit authorization
    |
    v
Observer query per data type
    |
    v
Background delivery entitlement
    |
    v
HealthKit background callbacks
    |
    v
Duplicate prevention ----------> Event creation
```

```
Location "Always" authorization
    |
    v
Geofence registration
    |
    v
Re-registration on launch <---- iOS eviction handling
    |
    v
Enter/exit callbacks
    |
    v
Event creation
```

## Expected Behavior Specifications

### HealthKit Background Delivery

**Timeliness expectations (what users should expect):**

| Scenario | Expected Timing | Notes |
|----------|-----------------|-------|
| Workout ends while app backgrounded | 1-60 minutes | iOS controls timing; faster when charging |
| Workout ends while app terminated | Next app launch or up to 4 hours | System may batch deliveries |
| Sleep data (overnight) | Within 1 hour of waking | Often delivered when phone starts charging |
| Daily steps/energy | Aggregated, not real-time | Process once per day or on app open |

**Reliability requirements:**

- Observer queries MUST be set up in `application(_:didFinishLaunchingWithOptions:)` before HealthKit delivers updates
- Completion handler MUST be called after processing, or HealthKit will retry with exponential backoff and eventually stop delivering
- Maximum 3 missed completion handlers before HealthKit stops trying
- Must handle case where callback fires but no new data exists (spurious callbacks)

**iOS constraints that cannot be worked around:**

- iOS has full discretion on delivery timing based on battery, CPU, user patterns
- Background delivery may be delayed until device is charging
- Low Power Mode pauses most background delivery
- User can disable Background App Refresh entirely

### Geofence Monitoring

**Reliability expectations:**

| Scenario | Expected Behavior | Notes |
|----------|-------------------|-------|
| User crosses boundary | Event within 20 seconds of crossing | iOS intentional delay to prevent spurious triggers |
| App force-quit by user | Geofences still monitored; app relaunched silently | Only if Background App Refresh enabled |
| Device restart | App must be launched once to re-register | Geofences not automatically restored |
| iOS memory pressure | Regions may be evicted | Must verify on app launch |
| User in region at registration | Immediate state callback | Use `requestState(for:)` after registering |

**Recovery requirements:**

- On every app launch: compare saved geofences vs `locationManager.monitoredRegions`
- Re-register any missing regions
- Handle case where iOS silently removed regions
- Log when regions are re-added vs already present

**iOS constraints:**

- Maximum 20 simultaneous regions per app (hard limit)
- Circular regions only (no polygons)
- Accuracy varies: 5-50 meters depending on environment (GPS, Wi-Fi, cellular)
- Dense urban or indoor: degraded accuracy
- Background App Refresh must be enabled for terminated app relaunch

### Sync Engine

**Offline behavior requirements:**

| Operation | Expected Behavior | Recovery |
|-----------|-------------------|----------|
| Create event offline | Saved locally, queued for sync | Sync when online |
| Edit event offline | Updated locally, queued for sync | Sync when online; handle conflicts |
| Delete event offline | Marked deleted locally, queued for sync | Sync when online |
| Network restored | Automatic queue processing | No user action required |
| Sync fails | Retry with exponential backoff | Max 5 attempts, then surface error |
| Conflict detected | Preserve both versions or last-write-wins with notification | User should know if their change was overwritten |

**Retry strategy:**

```
Attempt 1: Immediate
Attempt 2: 2 seconds + jitter
Attempt 3: 4 seconds + jitter
Attempt 4: 8 seconds + jitter
Attempt 5: 16 seconds + jitter
After 5 failures: Mark as failed, surface error to user
```

Maximum delay capped at 30 seconds. Jitter: +/- 10% of delay.

**Queue management:**

- Operations processed in FIFO order
- Track: operation type, payload, attempt count, first attempt timestamp, last attempt timestamp
- Maximum queue age: 72 hours (3 days) before marking stale
- Stale operations surfaced as errors, not silently dropped

### UX Indicators

**What users should see:**

| State | Indicator | Location |
|-------|-----------|----------|
| Online, synced | Subtle checkmark or no indicator | Settings or debug view |
| Online, syncing | Spinner + "Syncing..." | Navigation bar or settings |
| Online, pending | Badge "3 pending" | Navigation bar or settings |
| Offline | "Offline" badge or banner | Visible but not intrusive |
| Sync error | Error badge + explanation | Settings; tappable for details |
| Last sync time | "Last synced: 5 min ago" | Settings or pull-to-refresh header |

**What users should NOT see:**

- Constant spinners for background operations
- "Syncing" that never completes
- Technical error messages (HTTP codes, etc.)
- Multiple overlapping indicators

## Complexity Assessment

| Feature Area | Implementation Complexity | Testing Complexity | Risk |
|--------------|--------------------------|-------------------|------|
| HealthKit observer queries | MEDIUM | HIGH (needs real device, manual workout creation) | iOS timing unpredictable |
| Geofence registration | LOW | HIGH (needs physical movement or simulator) | iOS eviction unpredictable |
| Geofence recovery | MEDIUM | HIGH (hard to simulate iOS eviction) | May miss edge cases |
| Offline queue | MEDIUM | MEDIUM (network simulation) | Queue corruption risk |
| Retry with backoff | LOW | LOW (unit testable) | Low risk |
| Sync state UI | LOW | LOW (pure UI) | Low risk |
| Conflict resolution | HIGH | MEDIUM | User confusion risk |
| >20 geofence handling | HIGH | HIGH (needs many locations) | Battery drain risk |

## Sources

### Primary (HIGH confidence)
- [Apple: enableBackgroundDelivery(for:frequency:withCompletion:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)) - HealthKit background delivery API
- [Apple: Monitoring the user's proximity to geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions) - Geofence monitoring
- [Apple: BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler) - Background task scheduling
- [Apple: HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery) - Observer query documentation

### Secondary (MEDIUM confidence)
- [Radar: Geofencing iOS limitations](https://radar.com/blog/limitations-of-ios-geofencing) - 20 region limit workarounds
- [Radar: How accurate is geofencing](https://radar.com/blog/how-accurate-is-geofencing) - Accuracy expectations (5-50m)
- [Dev.to: Offline-First iOS Apps](https://dev.to/vijaya_saimunduru_c9579b/architecting-offline-first-ios-apps-with-idle-aware-background-sync-1dhh) - Sync engine architecture
- [Medium: iOS Background Processing Best Practices](https://uynguyen.github.io/2020/09/26/Best-practice-iOS-background-processing-Background-App-Refresh-Task/) - BGTaskScheduler patterns
- [Junction: Apple HealthKit](https://docs.junction.com/wearables/guides/apple-healthkit) - Background delivery timing realities

### Tertiary (LOW confidence, needs validation)
- [Apple Developer Forums: HKObserverQuery background delivery](https://developer.apple.com/forums/thread/690974) - Charging requirement observations
- [Apple Developer Forums: Region monitoring stops](https://developer.apple.com/forums/thread/92605) - iOS 15+ issues
- [Medium: Exponential backoff patterns](https://harish-bhattbhatt.medium.com/best-practices-for-retry-pattern-f29d47cd5117) - Retry strategy patterns

## Open Questions

1. **HealthKit charging requirement:** Multiple sources suggest background delivery only works reliably when charging. This may be iOS version specific. Needs validation on target iOS versions.

2. **iOS 15+ geofence issues:** Reports of region monitoring stopping after 1-2 days on iOS 15+. May be resolved in later versions. Needs testing on iOS 17+.

3. **CLMonitor (iOS 17+):** New API for condition monitoring. May offer better reliability than CLLocationManager for geofences. Needs investigation.

4. **Conflict resolution strategy:** Last-write-wins vs merge vs user choice. Depends on data model complexity. Recommend starting with last-write-wins + notification.
