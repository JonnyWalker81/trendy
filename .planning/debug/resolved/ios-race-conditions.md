---
status: resolved
trigger: "Comprehensive investigation of race conditions in the iOS app"
created: 2026-01-28T00:00:00Z
updated: 2026-01-28T00:00:00Z
---

## Current Focus

hypothesis: Five @Observable classes lack @MainActor isolation, causing potential data races on UI-observed state
test: Add @MainActor to all @Observable classes missing it; fix delegate callback isolation
expecting: All race conditions resolved
next_action: Apply fixes to all identified files

## Symptoms

expected: All concurrent operations should be thread-safe with no data races
actual: Five @Observable classes can have their state mutated from non-main threads
errors: Potential crashes, UI corruption, or data corruption from unsynchronized access
reproduction: N/A - proactive investigation
started: Full codebase audit

## Eliminated

- hypothesis: SyncEngine has race conditions
  evidence: SyncEngine is an actor - all access serialized automatically. Well-designed.
  timestamp: 2026-01-28

- hypothesis: EventStore has race conditions
  evidence: EventStore is @Observable @MainActor. All state mutations properly isolated.
  timestamp: 2026-01-28

- hypothesis: SwiftData ModelContext accessed from wrong thread
  evidence: EventStore uses mainContext consistently. SyncEngine creates its own context via DataStoreFactory inside actor isolation. LocalStore properly manages its own context.
  timestamp: 2026-01-28

- hypothesis: HealthKitService has thread safety issues
  evidence: HealthKitService is @Observable @MainActor. processedSampleIds/processingWorkoutTimestamps mutations are all @MainActor. Observer query callbacks properly dispatch to MainActor via Task.
  timestamp: 2026-01-28

## Evidence

- timestamp: 2026-01-28
  checked: All @Observable classes for @MainActor isolation
  found: 5 classes use @Observable WITHOUT @MainActor: NotificationManager, GeofenceManager, SyncHistoryStore, ThemeManager, HealthKitSettings
  implication: Their state can be mutated from any thread, causing data races when SwiftUI observes them

- timestamp: 2026-01-28
  checked: NotificationManager delegate callbacks
  found: UNUserNotificationCenterDelegate callbacks run on arbitrary threads. authorizationStatus property mutated in init via Task without @MainActor guarantee on the class itself.
  implication: Race between UI reads and background delegate writes

- timestamp: 2026-01-28
  checked: GeofenceManager delegate callbacks
  found: CLLocationManagerDelegate callbacks (locationManagerDidChangeAuthorization, didEnterRegion, etc.) run on arbitrary threads. These mutate authorizationStatus, pendingAlwaysAuthorizationRequest, and activeGeofenceEvents directly.
  implication: Race between UI reads and CLLocationManager delegate writes

- timestamp: 2026-01-28
  checked: SyncHistoryStore.record() call context
  found: Called from SyncEngine actor context which runs on background thread. entries array is @Observable and observed by UI.
  implication: Race between UI reads on main thread and background writes

- timestamp: 2026-01-28
  checked: ThemeManager thread safety
  found: No @MainActor isolation. currentTheme is @Observable and mutated in didSet callback. Used by SwiftUI views.
  implication: Minor risk - primarily main thread usage but not enforced

- timestamp: 2026-01-28
  checked: HealthKitSettings singleton thread safety
  found: No @MainActor isolation on singleton. enabledCategories computed property reads/writes UserDefaults. Accessed from HealthKitService (MainActor) and potentially other contexts.
  implication: Minor risk - UserDefaults is thread-safe but @Observable state tracking is not

- timestamp: 2026-01-28
  checked: Classes already properly isolated
  found: EventStore, AuthViewModel, AnalyticsViewModel, OnboardingViewModel, SyncStatusViewModel, InsightsViewModel, SupabaseService, OnboardingStatusService, FoundationModelService, HealthKitService, CalendarImportManager, AppRouter, GoogleSignInService, ProfileService - ALL have @MainActor
  implication: Majority of codebase is correct. Only 5 classes need fixing.

- timestamp: 2026-01-28
  checked: SyncEngine actor isolation
  found: SyncEngine is a proper actor. Its @MainActor state properties (state, pendingCount, lastSyncTime) use MainActor.run for updates. Single-flight sync pattern prevents concurrent syncs. DataStore is lazily created inside actor context.
  implication: Well-designed, no race conditions in SyncEngine itself

- timestamp: 2026-01-28
  checked: WidgetDataManager
  found: @MainActor final class - properly isolated. Creates its own ModelContext per operation.
  implication: No race conditions

## Resolution

root_cause: Five @Observable classes (NotificationManager, GeofenceManager, SyncHistoryStore, ThemeManager, HealthKitSettings) lack @MainActor isolation, allowing their @Observable-tracked state to be mutated from non-main threads while SwiftUI views observe them from the main thread
fix: Added @MainActor to all five classes. For GeofenceManager, also marked notification name constants as nonisolated (they're immutable), removed redundant @MainActor from methods/properties that inherit from the class, and added nonisolated static let for Notification.Name constants. Added MainActorIsolationTests to verify the isolation.
verification: BUILD SUCCEEDED. All 3 new MainActorIsolationTests passed. All existing MainActorDeinitTests passed (3/3). Pre-existing test failures in CircuitBreaker/ConflictHandling tests are unrelated.
files_changed:
  - apps/ios/trendy/Services/NotificationManager.swift
  - apps/ios/trendy/Services/Geofence/GeofenceManager.swift
  - apps/ios/trendy/Services/Geofence/GeofenceManager+Registration.swift
  - apps/ios/trendy/Services/Sync/SyncHistoryStore.swift
  - apps/ios/trendy/Services/ThemeManager.swift
  - apps/ios/trendy/Services/HealthKitSettings.swift
  - apps/ios/trendyTests/MainActorIsolationTests.swift (NEW)
