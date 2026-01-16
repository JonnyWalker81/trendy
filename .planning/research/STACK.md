# Stack Research: iOS Background Data Infrastructure

**Domain:** iOS background data infrastructure (HealthKit, CoreLocation, SwiftData sync, BGTaskScheduler)
**Researched:** 2026-01-15
**Confidence:** MEDIUM (patterns from official docs verified, but iOS background behavior is notoriously implementation-dependent)

---

## Executive Summary

iOS background processing remains one of the most challenging aspects of iOS development. The system is designed to aggressively preserve battery life and protect user privacy, which means background work is heavily restricted and can behave unpredictably. This research covers four key areas for the Trendy iOS app overhaul:

1. **HealthKit Background Delivery** - Observer queries with anchored object queries for change tracking
2. **CoreLocation Geofencing** - CLMonitor (iOS 17+) vs legacy CLLocationManager approaches
3. **SwiftData Sync Engine** - Actor-based offline-first patterns with ModelActor
4. **BGTaskScheduler** - BGContinuedProcessingTask (iOS 26+) and proper task scheduling

**Primary recommendation:** Adopt a layered approach: Local SwiftData as source of truth, with HKAnchoredObjectQuery for change tracking, CLMonitor for modern geofencing, and BGProcessingTask for batch sync operations.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **HKAnchoredObjectQuery** | iOS 15+ | Change tracking for HealthKit | Returns only new/deleted samples since last anchor; persists across app launches |
| **HKObserverQuery** | iOS 8+ | Background delivery trigger | Required for background delivery; notifies app of HealthKit changes |
| **CLMonitor** | iOS 17+ | Modern geofence monitoring | Swift actor with async/await; cleaner than delegate-based CLLocationManager |
| **@ModelActor** | iOS 17+ | Thread-safe SwiftData background ops | Guarantees thread safety via DefaultSerialModelExecutor |
| **NWPathMonitor** | iOS 12+ | Network reachability | Apple's official replacement for Reachability; supports connection type detection |
| **BGProcessingTask** | iOS 13+ | Background sync | For intensive work requiring network; runs during device charging/idle |
| **BGAppRefreshTask** | iOS 13+ | Periodic background refresh | For quick updates (<30s); system-scheduled based on app usage patterns |

### Supporting Technologies

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| **BGContinuedProcessingTask** | iOS 26+ | Foreground-started background work | Tasks started in foreground that need to complete in background (video export, large syncs) |
| **CLBackgroundActivitySession** | iOS 17+ | Background location authorization | Enables CLMonitor events when app is backgrounded |
| **HKStatisticsQuery** | iOS 8+ | Daily aggregations | Steps, active energy, and other cumulative metrics |
| **PersistentIdentifier** | iOS 17+ | Cross-context SwiftData references | Pass IDs (not models) between actors/contexts |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Xcode Instruments - Energy Log** | Battery impact analysis | Essential for debugging background behavior |
| **Console.app** | System log monitoring | Filter by subsystem to see HealthKit/CoreLocation events |
| **Background Task Debugger** | BGTaskScheduler testing | Xcode menu: Debug > Simulate Background Fetch |

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| CLMonitor | CLLocationManager | Legacy codebases on iOS < 17; CLMonitor requires async/await |
| @ModelActor | Manual ModelContext | Simple one-off operations; @ModelActor overhead not justified |
| NWPathMonitor | URLSession waitsForConnectivity | When you only need to know if a specific request succeeded |
| BGProcessingTask | Silent Push Notifications | When you need server-triggered background work (not time-based) |
| HKAnchoredObjectQuery | HKSampleQuery | When you need ALL samples, not just changes since last sync |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **Reachability (3rd party)** | Outdated; NWPathMonitor is official Apple solution | NWPathMonitor |
| **HKObserverQuery alone** | Only notifies of changes, doesn't tell WHAT changed | Combine with HKAnchoredObjectQuery |
| **CLLocationManager.monitoredRegions for state** | Documented bug: may return empty set after app restart | Persist regions in UserDefaults/SwiftData and re-register on launch |
| **BGAppRefreshTask for sync** | 30-second limit too short for meaningful sync | BGProcessingTask with requiresNetworkConnectivity |
| **Passing @Model objects between contexts** | Not Sendable; will crash or corrupt data | Pass PersistentIdentifier, fetch in target context |
| **Polling for HealthKit changes** | Battery drain; HealthKit Observer API is designed for this | HKObserverQuery with background delivery |
| **Assuming background delivery is reliable** | iOS frequently skips or delays background delivery | Design for eventual consistency; sync on foreground return |

---

## iOS Background Processing Patterns

### HealthKit Background Delivery Architecture

**The Three-Query Pattern (Recommended)**

HealthKit background delivery requires combining three query types for reliable data tracking:

```
1. HKAnchoredObjectQuery (initial fetch)
   - Run on app launch
   - Use persisted anchor from last run
   - Returns all samples since anchor

2. HKAnchoredObjectQuery (foreground updates)
   - Long-running query while app is active
   - Receives live updates

3. HKObserverQuery (background trigger)
   - Notifies app of HealthKit store changes
   - App launched in background to handle
   - MUST call completionHandler within 15 seconds
   - Run HKAnchoredObjectQuery inside to get actual data
```

**Critical Implementation Requirements:**

1. **Entitlement Required (iOS 15+)**: `com.apple.developer.healthkit.background-delivery`
   - Without this, background delivery silently fails
   - Add to both .entitlements file AND provisioning profile

2. **Setup in AppDelegate (NOT SceneDelegate)**:
   - Observer queries must be created in `application(_:didFinishLaunchingWithOptions:)`
   - System re-instantiates observers when launching app for background delivery

3. **Call `enableBackgroundDelivery` Every Launch**:
   - Not just once during setup
   - Required for system to know you want background updates

4. **Always Call Completion Handler**:
   - Within 15 seconds of observer query firing
   - If you don't, HealthKit uses exponential backoff
   - After 3 failures, stops delivering updates entirely

5. **Persist Anchors Using NSKeyedArchiver**:
   - HKQueryAnchor conforms to NSSecureCoding
   - Store in UserDefaults or App Group container
   - Restore on app launch before querying

**Known Limitations (HIGH confidence - multiple sources):**

- Background delivery may only trigger when device is charging
- Updates may be batched (several hours delay)
- Observer query updateHandler doesn't work in background; must use completion handler pattern
- Device lock blocks HealthKit access (empty results if device is locked)

**Workout-Specific Issues (Current Trendy Problem):**

The current implementation uses `HKSampleQuery` to fetch workouts after observer fires. This is correct but has issues:

1. The query fetches last 24 hours, which may miss workouts if background delivery was delayed
2. No anchor persistence means re-processing all recent workouts on each launch
3. Processed sample IDs stored in memory Set, but not tied to anchor

**Recommended Fix:**
- Use HKAnchoredObjectQuery instead of HKSampleQuery
- Persist anchor per sample type (workout, sleep, etc.)
- Let anchor handle "what's new" instead of custom date filtering

---

### CoreLocation Geofencing Patterns

**CLMonitor (iOS 17+ Recommended Approach)**

CLMonitor is a Swift actor introduced in iOS 17 that modernizes geofencing:

```swift
// Create monitor (persists state by name)
let monitor = await CLMonitor("myGeofences")

// Add geofence condition
let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
let condition = CLMonitor.CircularGeographicCondition(center: center, radius: 100)
await monitor.add(condition, identifier: "work")

// Consume events with async/await
Task {
    for try await event in await monitor.events {
        switch event.state {
        case .satisfied:
            // Inside geofence
        case .unsatisfied:
            // Outside geofence
        case .unknown:
            // State unknown
        }
    }
}
```

**Key CLMonitor Benefits:**
- Actor isolation handles thread safety
- Persists monitored conditions across app launches (by monitor name)
- Clean async/await API
- State persistence - lastEvent property shows most recent known state

**CLMonitor Critical Requirements:**

1. **Always await events on launch**: Events can arrive unpredictably; your app needs a Task awaiting `monitor.events` whenever running
2. **Re-initialize monitor on each launch**: System launches app in background for events; must call init and await events in `didFinishLaunchingWithOptions`
3. **One monitor instance per name**: Don't create multiple monitors with same name simultaneously
4. **Don't use in widgets**: Explicitly not supported

**Legacy CLLocationManager Issues (Why Current Trendy Has Problems):**

1. **monitoredRegions can be empty after restart**: Known iOS bug; regions may "silently unregister"
2. **20 region limit**: Hard iOS limit, shared across all apps
3. **Delegate callbacks require app to be alive**: Must handle app launch case in AppDelegate
4. **No built-in persistence**: App must track which regions it expects to be monitoring

**Recommended Migration Path:**

1. Keep CLLocationManager for iOS 16 compatibility (if needed)
2. Add CLMonitor for iOS 17+
3. Persist geofence definitions in SwiftData (current approach is good)
4. On app launch: reconcile CLMonitor/CLLocationManager state with SwiftData

**Geofence Reliability Tips:**

1. **Request state after registration**: Call `requestState(for:)` to check if user is already inside
2. **Handle "Already Inside"**: If state is `.inside` on registration, trigger entry event manually
3. **Persist active events**: Current Trendy approach of storing activeGeofenceEvents in UserDefaults is correct
4. **Requires "Always" authorization**: "When In Use" is insufficient for background geofence monitoring

---

### SwiftData Background Operations

**@ModelActor Pattern (iOS 17+)**

SwiftData models are NOT Sendable. To safely work with SwiftData in background:

```swift
@ModelActor
actor BackgroundSyncActor {
    // modelContainer and modelContext are auto-synthesized

    func performSync() async throws {
        // Safe to use modelContext here
        let events = try modelContext.fetch(FetchDescriptor<Event>())
        // ... process events ...
        try modelContext.save()
    }
}

// Usage
let syncActor = BackgroundSyncActor(modelContainer: container)
try await syncActor.performSync()
```

**Critical Rules:**

1. **Never pass @Model objects between contexts**: Will crash or corrupt data
2. **Pass PersistentIdentifier instead**: Fetch the model in the target context
3. **One ModelContext per actor/thread**: DefaultSerialModelExecutor ensures this
4. **ModelContainer IS Sendable**: Safe to pass to actors

**Swift 6.2 Changes (iOS 26+):**

- `nonisolated` async methods now inherit caller's isolation
- Use `@concurrent` annotation to force background execution
- Xcode 26 template uses MainActor default isolation for @Model

**Current Trendy SyncEngine Analysis:**

The existing SyncEngine is a Swift actor (good) that creates ModelContext per operation (good). Key improvements:

1. **Consider @ModelActor macro**: Simplifies boilerplate
2. **Batch operations**: Current approach processes one mutation at a time; could batch
3. **Conflict resolution**: Last-write-wins is simple but risky for multi-device

---

### Background Task Scheduling

**BGTaskScheduler Task Types:**

| Type | Duration | When Runs | Use Case |
|------|----------|-----------|----------|
| BGAppRefreshTask | ~30 seconds | System-determined (based on app usage) | Quick content updates |
| BGProcessingTask | Up to 10 minutes | Device idle, often charging | Database maintenance, ML training, large syncs |
| BGContinuedProcessingTask (iOS 26+) | Until complete | Foreground-started, continues in background | Export, upload, processing started by user |

**Registration Requirements:**

1. Add task identifiers to Info.plist under `BGTaskSchedulerPermittedIdentifiers`
2. Register handlers in `application(_:didFinishLaunchingWithOptions:)` before app finishes launching
3. Schedule tasks when entering background (in sceneDidEnterBackground or applicationDidEnterBackground)

**BGProcessingTask for Sync (Recommended):**

```swift
// Registration (in AppDelegate)
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.trendy.sync",
    using: nil
) { task in
    self.handleSync(task: task as! BGProcessingTask)
}

// Scheduling (when entering background)
let request = BGProcessingTaskRequest(identifier: "com.trendy.sync")
request.requiresNetworkConnectivity = true
request.requiresExternalPower = false // true = more likely to run, but only when charging
request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
try? BGTaskScheduler.shared.submit(request)

// Handler
func handleSync(task: BGProcessingTask) {
    task.expirationHandler = {
        // Clean up, save state
        self.syncTask?.cancel()
    }

    let syncTask = Task {
        do {
            try await syncEngine.performSync()
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }
    self.syncTask = syncTask
}
```

**Testing Background Tasks:**

Xcode provides debugging commands (requires device attached):

```bash
# Trigger app refresh
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.trendy.sync"]

# Or via Debug menu: Debug > Simulate Background Fetch
```

**BGContinuedProcessingTask (iOS 26+ - Future Enhancement):**

For user-initiated work that should complete if app backgrounds:

```swift
let request = BGContinuedProcessingTaskRequest(identifier: "com.trendy.export")
request.title = "Exporting Data"
request.subtitle = "Please wait..."
request.requiredResources = [.network]
request.strategy = .queueOnResourceContention // or .fail

BGTaskScheduler.shared.submit(request) { task in
    task.progress.totalUnitCount = 100

    for i in 0..<100 {
        // ... do work ...
        task.progress.completedUnitCount = Int64(i)
    }

    task.setTaskCompleted(success: true)
}
```

---

## Network Monitoring Pattern

**NWPathMonitor for Sync Engine:**

```swift
import Network

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType = .other

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type ?? .other
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
```

**Important:** NWPathMonitor tells you if a network is reachable, NOT if internet is accessible. A WiFi network may be connected but have no internet. For true connectivity, use URLSession with `waitsForConnectivity`.

---

## Offline-First Sync Architecture

**Recommended Three-Layer Model:**

```
Layer 1: Local Store (SwiftData)
├── Source of truth when offline
├── All user actions write here first
├── Immediate UI feedback
└── No waiting for network

Layer 2: Sync Manager (Actor)
├── Detects network changes
├── Queues offline mutations
├── Handles conflict resolution
└── Processes in FIFO order

Layer 3: Remote API
├── Backend source of truth
├── Returns server timestamps
├── Supports cursor-based sync
└── Idempotent operations
```

**Conflict Resolution (Current: Last-Write-Wins):**

The current Trendy SyncEngine uses timestamp-based last-write-wins. This is acceptable for single-user scenarios but has risks:

1. **Clock skew**: Device clocks may differ
2. **Silent overwrites**: User may not know their change was discarded

**Alternative: Operation-Based CRDTs (Future Enhancement)**

For multi-device sync, consider:
- Store individual field changes, not entire objects
- Merge changes rather than replacing
- More complex but preserves all edits

---

## Implementation Priorities

Based on current Trendy issues, recommended order:

### Priority 1: HealthKit Reliability (Workout Background Delivery)

1. Add `com.apple.developer.healthkit.background-delivery` entitlement if missing
2. Replace HKSampleQuery with HKAnchoredObjectQuery for workouts
3. Persist anchor per sample type in App Group UserDefaults
4. Move observer query setup to AppDelegate
5. Add logging to track background delivery events

### Priority 2: Geofence Persistence

1. Add reconciliation check on app launch (compare CLLocationManager.monitoredRegions with SwiftData)
2. Re-register missing regions automatically
3. Consider CLMonitor migration for iOS 17+ devices
4. Add health check that logs monitored region count

### Priority 3: Sync Engine Hardening

1. Add BGProcessingTask for background sync
2. Implement exponential backoff for failed mutations
3. Add sync health metrics (last sync time, pending count, error rate)
4. Consider @ModelActor migration for cleaner code

### Priority 4: Background Task Scheduling

1. Register BGProcessingTask for sync
2. Schedule when app enters background
3. Add BGAppRefreshTask for quick state refresh
4. Implement proper expiration handling

---

## Open Questions

1. **CLMonitor state persistence details**: Documentation is sparse on exactly how CLMonitor persists state. Need empirical testing.

2. **HealthKit background delivery on M-series Macs**: Unclear if behavior differs on macOS/Catalyst apps.

3. **BGContinuedProcessingTask adoption**: iOS 26 is future (released 2025); need to plan for when to adopt.

4. **SwiftData + CloudKit**: If future Trendy moves to CloudKit sync, SwiftData has built-in support but limited conflict resolution customization.

---

## Sources

### Primary (HIGH confidence)

- [Apple Developer Documentation: HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery) - Observer query API reference
- [Apple Developer Documentation: HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery) - Anchored query for change tracking
- [WWDC23: Meet Core Location Monitor](https://developer.apple.com/videos/play/wwdc2023/10147/) - CLMonitor introduction
- [WWDC23: Discover streamlined location updates](https://developer.apple.com/videos/play/wwdc2023/10180/) - Location API modernization
- [Apple Developer Documentation: Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) - BGTaskScheduler guidance
- [WWDC25: Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/) - BGContinuedProcessingTask introduction

### Secondary (MEDIUM confidence)

- [DevFright: How to Use HealthKit HKAnchoredObjectQuery](https://www.devfright.com/how-to-use-healthkit-hkanchoredobjectquery/) - Practical anchor persistence patterns (updated March 2025)
- [iTwenty: Read workouts using HealthKit](https://itwenty.me/posts/09-healthkit-workout-updates/) - Three-query pattern explanation
- [Fatbobman: Concurrent Programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/) - @ModelActor deep dive
- [Medium: Offline-First SwiftUI with SwiftData](https://medium.com/@ashitranpura27/offline-first-swiftui-with-swiftdata-clean-fast-and-sync-ready-9a4faefdeedb) - Sync architecture patterns
- [Radar Blog: Geofencing iOS Limitations](https://radar.com/blog/limitations-of-ios-geofencing) - Comprehensive geofencing limitations

### Tertiary (LOW confidence - needs validation)

- [Apple Developer Forums: HKObserverQuery stops delivering](https://developer.apple.com/forums/thread/801627) - Potential iOS 26 regression reports
- [Apple Developer Forums: monitoredRegions empty](https://developer.apple.com/forums/thread/78107) - Historical bug reports on region persistence
- [Medium: Default Actor Isolation Changes](https://fatbobman.com/en/posts/default-actor-isolation/) - Swift 6.2 behavior changes (Xcode 26+)

---

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| HealthKit Observer/Anchored Query | HIGH | Official Apple documentation + multiple verified community patterns |
| HealthKit Background Delivery | MEDIUM | Known to be unreliable; official docs don't acknowledge all limitations |
| CLMonitor (iOS 17+) | HIGH | Official WWDC session + Apple documentation |
| CLLocationManager geofencing | MEDIUM | Well-documented but known bugs in monitoredRegions |
| @ModelActor | HIGH | Official Apple pattern, well-documented |
| BGTaskScheduler | HIGH | Official documentation + WWDC sessions |
| BGContinuedProcessingTask | MEDIUM | iOS 26+, limited real-world validation |
| Offline-first sync patterns | MEDIUM | Community patterns, not Apple-prescribed |

**Research valid until:** 2026-03-15 (3 months - background APIs change infrequently, but new iOS versions may alter behavior)
