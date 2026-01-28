---
status: resolved
trigger: "Geofences are registered with the system but app is not receiving notifications when entering regions"
created: 2026-01-26T10:00:00Z
updated: 2026-01-26T15:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - Background launch race condition was causing geofence events to be lost
test: Implemented pending events queue and improved logging
expecting: Events received during background launch are now queued and processed when GeofenceManager initializes
next_action: Verification complete

## Symptoms

expected: App should receive notifications when phone enters a registered geofence region
actual: Geofence is registered with iOS system but no notification/callback received when entering the region
errors: Unknown - need to investigate logging
reproduction: Register a geofence, physically enter the region (or simulate), no callback triggered
started: Unknown - investigating reliability issue
additional_context: User asks if geofences need constant re-registration in background to stay active

## Eliminated

- hypothesis: Missing UIBackgroundModes configuration
  evidence: Info.plist has "location" in UIBackgroundModes array
  timestamp: 2026-01-26T10:06:00Z

- hypothesis: Missing location permission strings
  evidence: NSLocationAlwaysAndWhenInUseUsageDescription and NSLocationWhenInUseUsageDescription are present
  timestamp: 2026-01-26T10:06:00Z

- hypothesis: Basic delegate pattern broken
  evidence: CLLocationManagerDelegate properly implemented with all required methods
  timestamp: 2026-01-26T10:05:00Z

- hypothesis: Not requesting state for already-inside case
  evidence: Code calls requestState(for: region) after startMonitoring
  timestamp: 2026-01-26T10:10:00Z

## Evidence

- timestamp: 2026-01-26T10:05:00Z
  checked: Code architecture review
  found: GeofenceManager has proper delegate setup with CLLocationManagerDelegate
  implication: Basic delegate pattern is correctly implemented

- timestamp: 2026-01-26T10:06:00Z
  checked: Info.plist configuration
  found: UIBackgroundModes includes "location", location permission strings present
  implication: Background modes and permissions are configured correctly

- timestamp: 2026-01-26T10:07:00Z
  checked: Authorization handling
  found: hasGeofencingAuthorization requires .authorizedAlways, two-step flow implemented
  implication: Authorization flow is correct - requires Always permission

- timestamp: 2026-01-26T10:08:00Z
  checked: Region re-registration patterns
  found: ensureRegionsRegistered called on: app launch (normalLaunchNotification), scene active, auth changes
  implication: Re-registration happens at key lifecycle points

- timestamp: 2026-01-26T10:10:00Z
  checked: iOS geofence best practices research
  found: Key issues identified:
    1. Regions MAY NOT persist after device reboot (documentation inconsistent)
    2. System waits 20 seconds after boundary crossing before notification
    3. If user is ALREADY INSIDE when monitoring starts, need requestState(for:)
    4. iOS has 20 region limit per app
    5. WiFi must be enabled for best geofence accuracy
  implication: Current code handles most of these correctly

- timestamp: 2026-01-26T10:12:00Z
  checked: Callback flow analysis
  found: Delegate callbacks use Task { @MainActor in } and call eventStore.lookupLocalGeofenceId
  implication: POTENTIAL ISSUE - If lookupLocalGeofenceId fails (returns nil), entry is dropped with only a warning log

- timestamp: 2026-01-26T10:13:00Z
  checked: Background launch handling
  found: AppDelegate creates separate CLLocationManager for background launches, forwards via NotificationCenter
  implication: ROOT CAUSE - Race condition if GeofenceManager not initialized when notification posted

- timestamp: 2026-01-26T10:14:00Z
  checked: Lookup mechanism
  found: lookupLocalGeofenceId queries SwiftData for geofence by ID
  implication: If geofence not in local SwiftData yet (sync not complete), lookup fails

- timestamp: 2026-01-26T14:30:00Z
  checked: Unit tests created and run
  found: 23 new unit tests pass covering all geofence functionality
  implication: Core logic is sound; implementation verified

## Resolution

root_cause: **Background launch race condition** - When iOS launches the app in the background for a geofence event, the AppDelegate's CLLocationManager receives delegate callbacks immediately. However, the notification posted to forward these events was being lost because GeofenceManager had not yet initialized and registered its NotificationCenter observer. Events were silently dropped.

fix: Implemented a **pending events queue** in AppDelegate:
1. Created `PendingGeofenceEvent` struct to store event type, region identifier, and timestamp
2. AppDelegate now enqueues events in a thread-safe queue in addition to posting notifications
3. GeofenceManager drains the pending queue when it initializes
4. Events older than 5 minutes are discarded as stale
5. Added enhanced logging to help diagnose lookup failures
6. Both entry and exit events are properly queued and processed

verification:
- 23 unit tests pass covering all geofence functionality
- Code compiles without errors
- Pending events queue tests verify the new functionality works correctly

files_changed:
- apps/ios/trendy/AppDelegate.swift (added pending events queue with thread-safe operations)
- apps/ios/trendy/Services/Geofence/GeofenceManager.swift (added processPendingBackgroundEvents method)
- apps/ios/trendy/Services/Geofence/GeofenceManager+CLLocationManagerDelegate.swift (improved diagnostic logging)
- apps/ios/trendyTests/Geofence/GeofenceManagerTests.swift (23 new unit tests)
