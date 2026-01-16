# Phase 3: Geofence Reliability - Research

**Researched:** 2026-01-16
**Domain:** iOS CoreLocation region monitoring / geofencing
**Confidence:** HIGH for CLLocationManager approach, LOW for CLMonitor (unstable)

## Summary

Geofence reliability on iOS requires understanding a fundamental truth: **iOS region monitoring is designed for persistence but has significant caveats**. The system tracks registered regions even when the app is terminated and will relaunch the app to deliver events. However, several factors can cause regions to be lost or events to be missed: device restarts, iOS eviction, authorization changes, and iOS version bugs.

The current Trendy codebase already has solid foundations: `GeofenceManager.swift` uses `CLLocationManager` (the correct choice), implements region reconciliation, and handles delegate callbacks properly. The main gaps are: **no AppDelegate for background launch handling**, **no proactive re-registration on app lifecycle events**, and **limited health monitoring visibility**.

**Primary recommendation:** Stick with CLLocationManager for region monitoring. Do NOT migrate to CLMonitor - it has significant reliability issues in iOS 17/18. Add an AppDelegate to handle background launches, implement aggressive re-registration on all lifecycle events, and expand the debug view to show full health status.

## Standard Stack

The established APIs for persistent geofence monitoring on iOS:

### Core (Use These)

| API | Availability | Purpose | Why Standard |
|-----|--------------|---------|--------------|
| CLLocationManager | iOS 2+ | Region monitoring, authorization | Battle-tested, reliable, extensive documentation |
| CLCircularRegion | iOS 7+ | Define circular geofence boundaries | Only supported shape on iOS, well-understood behavior |
| CLLocationManagerDelegate | iOS 2+ | Receive region enter/exit events | Standard callback pattern, works with background launch |
| UIApplicationDelegateAdaptor | SwiftUI | Handle background launches in SwiftUI apps | Required for location-based background launch handling |

### Supporting

| API | Availability | Purpose | When to Use |
|-----|--------------|---------|-------------|
| UIApplication.LaunchOptionsKey.location | iOS 4+ | Detect location-triggered launch | Check in didFinishLaunchingWithOptions to reinitialize location manager |
| requestState(for:) | iOS 7+ | Query current state of a region | On registration to detect already-inside scenario |
| monitoredRegions | iOS 4+ | Get currently registered regions | Reconciliation, health checks, debugging |

### Avoid These

| Instead of | Could Use | Why Avoid |
|------------|-----------|-----------|
| CLMonitor | CLLocationManager | CLMonitor is unreliable in iOS 17/18, known bugs with event delivery, crashes with name reuse |
| CLServiceSession | Not needed for regions | Only required for CLMonitor/CLLocationUpdate, adds complexity |
| CLBackgroundActivitySession | Not needed for regions | Region monitoring has built-in background support |
| Significant Location Changes | Region Monitoring | Different use case, less precise, higher battery for continuous updates |

## Architecture Patterns

### Recommended Project Structure

Current structure is appropriate. Key additions needed:

```
apps/ios/trendy/
├── trendyApp.swift              # ADD: UIApplicationDelegateAdaptor for AppDelegate
├── AppDelegate.swift            # NEW: Handle location-triggered background launches
├── Services/
│   └── GeofenceManager.swift    # ENHANCE: Add lifecycle hooks, health monitoring
├── Views/
│   └── Geofence/
│       └── GeofenceDebugView.swift  # ENHANCE: Full health dashboard
└── Models/
    └── Geofence.swift           # No changes needed
```

### Pattern 1: AppDelegate for Background Location Launch

**What:** Use UIApplicationDelegateAdaptor to integrate an AppDelegate with SwiftUI lifecycle.
**When to use:** Any app using region monitoring that needs to handle background launches.
**Why:** SwiftUI's ScenePhase cannot handle the critical `didFinishLaunchingWithOptions` with location key.

```swift
// Source: Apple Developer Documentation + community best practices
// In trendyApp.swift
@main
struct trendyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // ...
}

// In AppDelegate.swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Check if launched due to location event
        if launchOptions?[.location] != nil {
            Log.geofence.info("App launched due to location event")
            // Create CLLocationManager immediately to receive pending events
            initializeLocationManagerForBackgroundLaunch()
        }
        return true
    }

    private func initializeLocationManagerForBackgroundLaunch() {
        // Must create a CLLocationManager instance to receive pending callbacks
        // The delegate methods will be called after this returns
    }
}
```

### Pattern 2: Defensive Re-registration Strategy

**What:** Always re-register geofences at multiple lifecycle points.
**When to use:** Every geofence-based app.
**Why:** Regions can be lost due to many factors: iOS eviction, device restart, authorization changes, app updates.

```swift
// Re-registration points:
// 1. App launch (didFinishLaunchingWithOptions)
// 2. App becomes active (scenePhase == .active)
// 3. Authorization granted/restored (locationManagerDidChangeAuthorization)
// 4. After backend sync (to pick up server-side changes)

func reconcileRegions(desired: [GeofenceDefinition]) {
    let currentIds = Set(locationManager.monitoredRegions.map { $0.identifier })
    let desiredIds = Set(desired.map { $0.identifier })

    // Remove stale
    for region in locationManager.monitoredRegions {
        if !desiredIds.contains(region.identifier) {
            locationManager.stopMonitoring(for: region)
        }
    }

    // Add missing
    for definition in desired where !currentIds.contains(definition.identifier) {
        let region = CLCircularRegion(/* ... */)
        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region)  // Critical: detect if already inside
    }
}
```

### Pattern 3: Event Logging with Local Fallback

**What:** Always persist geofence events locally first, then sync to backend.
**When to use:** Ensuring no events are lost even if sync fails.
**Why:** Background execution time is limited (~10 seconds), network may fail.

```swift
// Source: Existing pattern in GeofenceManager.swift (already implemented correctly)
func handleGeofenceEntry(geofenceId: String) {
    // 1. Create Event in SwiftData (local-first)
    let event = Event(/* ... */)
    modelContext.insert(event)
    try modelContext.save()

    // 2. Queue for backend sync (async, can fail gracefully)
    Task {
        await eventStore.syncEventToBackend(event)
    }

    // 3. Optionally send notification (nice-to-have, not critical path)
}
```

### Anti-Patterns to Avoid

- **Recreating CLLocationManager on every event:** The manager should be long-lived; recreating loses monitored regions state.
- **Using CLMonitor on iOS 17/18:** Known bugs cause missed events, crashes, and unreliable behavior.
- **Blocking main thread in delegate callbacks:** Location callbacks must return quickly; use Task for async work.
- **Relying solely on ScenePhase:** SwiftUI's ScenePhase does not fire for background location launches.
- **Not requesting state after registration:** Without `requestState(for:)`, you won't know if user is already inside.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Region persistence | Custom persistence layer | CLLocationManager's built-in persistence | iOS maintains regions across app lifecycle; just re-initialize manager on launch |
| Background wake | Custom background task | Region monitoring's built-in wake | iOS automatically wakes app for region events |
| 20 region limit workaround | Custom proximity tracking | Accept limit for v1 | Smart rotation requires significant location changes, adds battery drain and complexity |
| Circular region math | Custom distance calculations | CLCircularRegion | Apple handles GPS accuracy, boundary hysteresis, etc. |
| Entry detection on registration | Manual location check | `requestState(for:)` | Built-in API handles this correctly |

**Key insight:** CoreLocation's region monitoring is designed to be persistent and low-power. The complexity is in lifecycle management, not the monitoring itself.

## Common Pitfalls

### Pitfall 1: Missed Events After Background Launch

**What goes wrong:** App is terminated, region event occurs, app relaunches but doesn't receive the event.
**Why it happens:** No AppDelegate to handle `didFinishLaunchingWithOptions`, or CLLocationManager not created early enough.
**How to avoid:** Add AppDelegate with UIApplicationDelegateAdaptor, create CLLocationManager immediately when `.location` key is present.
**Warning signs:** Users report missed events but debug shows regions are registered; events work when app is foregrounded.

### Pitfall 2: Regions Lost After Device Restart

**What goes wrong:** After device restart, geofences stop working until user opens app.
**Why it happens:** iOS needs ~5-10 minutes after restart to restore region monitoring. If app is launched via region event during this window, manager may show empty monitoredRegions.
**How to avoid:** Always re-register regions on app launch, don't assume monitoredRegions is authoritative immediately after restart.
**Warning signs:** `monitoredRegions.isEmpty` returns true even though regions were registered.

### Pitfall 3: 20-Second Boundary Delay

**What goes wrong:** Events don't trigger exactly at boundary crossing.
**Why it happens:** iOS waits for user to cross boundary AND remain on other side for 20+ seconds to prevent spurious events.
**How to avoid:** Document this for users, don't promise instant detection. Use minimum 100m radius (Apple recommendation).
**Warning signs:** Users report delays or missed events when quickly crossing boundaries.

### Pitfall 4: Authorization Downgrade

**What goes wrong:** User changes permission from "Always" to "When In Use" or "Never", regions silently stop working.
**Why it happens:** Region monitoring requires "Always" authorization, but iOS doesn't notify you when it's revoked.
**How to avoid:** Check `authorizationStatus` on every app activation, show warning UI if not `.authorizedAlways`.
**Warning signs:** `hasGeofencingAuthorization` suddenly returns false, no delegate callbacks received.

### Pitfall 5: CLMonitor Reliability (iOS 17/18)

**What goes wrong:** CLMonitor-based apps stop receiving events reliably, especially after first few events.
**Why it happens:** Known iOS 17/18 bugs with CLMonitor's event stream, name reuse crashes, and background behavior.
**How to avoid:** Use CLLocationManager instead. If you must use CLMonitor, pair with CLServiceSession on iOS 18+.
**Warning signs:** First 1-2 events work, then stops; duplicate events with wrong timestamps after foregrounding.

### Pitfall 6: Small Radius Unreliability

**What goes wrong:** Geofences with small radius (<100m) trigger inconsistently.
**Why it happens:** GPS accuracy varies (especially indoors, urban canyons); iOS uses WiFi/cellular for region monitoring.
**How to avoid:** Enforce minimum 100m radius (Apple recommendation), consider 150m as default.
**Warning signs:** Users in same location get inconsistent entry/exit events.

## Code Examples

Verified patterns from official sources and community best practices:

### AppDelegate Integration with SwiftUI

```swift
// Source: Apple Developer Documentation + Jesse Squires blog
// In trendyApp.swift
@main
struct trendyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// In AppDelegate.swift
class AppDelegate: NSObject, UIApplicationDelegate, CLLocationManagerDelegate {
    private var locationManager: CLLocationManager?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if launchOptions?[.location] != nil {
            Log.geofence.info("Background launch due to location event")
            // Must create manager immediately to receive pending events
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            // The pending region events will be delivered to delegate methods
        }
        return true
    }

    // Delegate receives pending events from background launch
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Log.geofence.info("Background: Entered region", context: .with { ctx in
            ctx.add("identifier", region.identifier)
        })
        // Forward to main GeofenceManager or handle directly
    }
}
```

### Region Reconciliation

```swift
// Source: Existing GeofenceManager.swift pattern (enhanced)
func reconcileRegions(desired: [GeofenceDefinition]) {
    guard hasGeofencingAuthorization else {
        Log.geofence.warning("Cannot reconcile: insufficient authorization")
        return
    }

    let desiredLimited = Array(desired.prefix(20))  // iOS limit
    let desiredIds = Set(desiredLimited.map { $0.identifier })
    let currentIds = Set(locationManager.monitoredRegions.map { $0.identifier })

    // 1. Stop stale regions
    for region in locationManager.monitoredRegions {
        if !desiredIds.contains(region.identifier) {
            locationManager.stopMonitoring(for: region)
            Log.geofence.debug("Stopped stale region", context: .with { ctx in
                ctx.add("identifier", region.identifier)
            })
        }
    }

    // 2. Start missing regions
    for def in desiredLimited where !currentIds.contains(def.identifier) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: def.latitude, longitude: def.longitude),
            radius: max(def.radius, 100),  // Enforce minimum
            identifier: def.identifier
        )
        region.notifyOnEntry = def.notifyOnEntry
        region.notifyOnExit = def.notifyOnExit

        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region)  // Critical!

        Log.geofence.debug("Started region", context: .with { ctx in
            ctx.add("identifier", def.identifier)
        })
    }
}
```

### Health Status Model

```swift
// For GEO-04: Health monitoring visibility
struct GeofenceHealthStatus {
    let registeredWithiOS: Set<String>      // Identifiers in monitoredRegions
    let savedInApp: Set<String>             // Identifiers in SwiftData
    let authorizationStatus: CLAuthorizationStatus
    let locationServicesEnabled: Bool

    var missingFromiOS: Set<String> {
        savedInApp.subtracting(registeredWithiOS)
    }

    var orphanedIniOS: Set<String> {
        registeredWithiOS.subtracting(savedInApp)
    }

    var isHealthy: Bool {
        authorizationStatus == .authorizedAlways &&
        locationServicesEnabled &&
        missingFromiOS.isEmpty &&
        orphanedIniOS.isEmpty
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CLMonitor (iOS 17) | Stick with CLLocationManager | iOS 17.3+ bugs, iOS 18 regressions | CLMonitor unreliable for production; CLLocationManager remains stable |
| Manual location polling for geofence | Region monitoring only | Always | Battery drain, unnecessary complexity |
| CLServiceSession required | Not needed for region monitoring | iOS 18 | CLServiceSession only needed for CLMonitor/CLLocationUpdate |

**Deprecated/outdated:**
- **CLRegion subclassing:** Use CLCircularRegion directly, CLRegion is abstract.
- **requestAlwaysAuthorization() alone:** Must request When In Use first, then upgrade to Always (since iOS 13.4).
- **Trusting monitoredRegions immediately after launch:** May be empty; always re-register.

## Open Questions

Things that couldn't be fully resolved:

1. **iOS 18 CLMonitor fix timeline**
   - What we know: CLMonitor has significant bugs in iOS 17/18, Apple engineers have acknowledged the issues.
   - What's unclear: Whether iOS 18.x or iOS 19 will fix these issues.
   - Recommendation: Do not migrate to CLMonitor. Revisit in iOS 19 if Apple announces fixes.

2. **Exact region monitoring recovery time after device restart**
   - What we know: Takes 5-10 minutes after restart for region monitoring to fully restore.
   - What's unclear: Exact timing, whether it varies by device or iOS version.
   - Recommendation: Always re-register on app launch, don't rely on automatic restoration.

3. **WiFi requirement for reliable geofencing**
   - What we know: WiFi is critical for low-power location; turning it off can break geofencing.
   - What's unclear: How much reliability is lost without WiFi.
   - Recommendation: Document that WiFi should remain on for best geofence reliability.

## Sources

### Primary (HIGH confidence)

- [Apple Developer Documentation: Monitoring the user's proximity to geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions) - Official guide
- [Apple Developer Documentation: CLLocationManager](https://developer.apple.com/documentation/corelocation/cllocationmanager) - API reference
- [Apple Developer Documentation: UIApplication.LaunchOptionsKey](https://developer.apple.com/documentation/uikit/uiapplication/launchoptionskey) - Background launch handling
- [Apple Developer Forums: Region monitoring persistence](https://developer.apple.com/forums/thread/79465) - Apple engineers on background behavior

### Secondary (MEDIUM confidence)

- [Core Location Modern API Tips (twocentstudios.com, Dec 2024)](https://twocentstudios.com/2024/12/02/core-location-modern-api-tips/) - Detailed CLMonitor vs CLLocationManager comparison
- [Radar Blog: Limitations of iOS Geofencing](https://radar.com/blog/limitations-of-ios-geofencing) - Comprehensive limitations overview
- [Bugfender: iOS Geofencing Guide](https://bugfender.com/blog/ios-geofencing/) - Implementation patterns
- [Jesse Squires: SwiftUI scene phase issues](https://www.jessesquires.com/blog/2024/06/29/swiftui-scene-phase/) - AppDelegate necessity in SwiftUI

### Tertiary (LOW confidence)

- [Apple Developer Forums: CLMonitor issues iOS 17/18](https://developer.apple.com/forums/thread/768373) - Community bug reports
- Various Medium articles on geofencing - General patterns, not always current

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - CLLocationManager is well-documented, stable, extensively tested
- Architecture patterns: HIGH - Patterns are based on Apple documentation and stable APIs
- CLMonitor avoidance: HIGH - Multiple sources confirm iOS 17/18 reliability issues
- Lifecycle handling: MEDIUM - Based on community best practices, not all edge cases documented by Apple
- Pitfalls: MEDIUM - Based on community reports and Apple forums

**Research date:** 2026-01-16
**Valid until:** 2026-04-16 (stable domain, revisit if iOS 19 changes CLMonitor status)

## Alignment with Existing Codebase

The current `GeofenceManager.swift` (757 lines) already implements:
- CLLocationManager-based region monitoring (correct)
- Region reconciliation via `reconcileRegions(desired:)` (correct)
- Delegate callbacks for enter/exit events (correct)
- Active event tracking via UserDefaults (correct)
- Debug properties for health monitoring (partial)

**Gaps to address in planning:**
1. No AppDelegate for background launch handling
2. No re-registration on device restart (relying on MainTabView.onAppear only)
3. GeofenceDebugView shows basic status but not full health comparison
4. No handling of `.location` launch key
5. No proactive re-registration when authorization is restored
