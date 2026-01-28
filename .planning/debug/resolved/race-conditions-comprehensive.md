---
status: resolved
trigger: "Comprehensively investigate all race conditions across the entire Trendy app codebase"
created: 2026-01-28T00:00:00Z
updated: 2026-01-28T02:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - Multiple iOS race conditions found and fixed
test: Code audit + Go race detector tests
expecting: All platforms race-condition free
next_action: Archive session

## Symptoms

expected: No race conditions - all concurrent operations properly synchronized
actual: 4 race conditions found in iOS platform, Go backend and Web app clean
errors: None specifically reported - proactive investigation
reproduction: Code analysis and testing
started: Proactive audit

## Eliminated

- hypothesis: Go backend has race conditions in handlers/services
  evidence: All handlers/services use immutable struct fields, no shared mutable state. Supabase client is stateless. RateLimiter properly uses sync.RWMutex. All tests pass with -race flag.
  timestamp: 2026-01-28T00:40:00Z

- hypothesis: Web app has race conditions in TanStack Query or API client
  evidence: TanStack Query handles mutations sequentially. API client creates fresh headers per request. Supabase JS SDK handles token refresh internally with mutex.
  timestamp: 2026-01-28T00:50:00Z

- hypothesis: APIClient JSONEncoder/JSONDecoder are not thread-safe
  evidence: JSONEncoder and JSONDecoder are thread-safe for encoding/decoding operations since iOS 12+. They create new internal state per call and don't share mutable state between invocations.
  timestamp: 2026-01-28T01:30:00Z

## Evidence

- timestamp: 2026-01-28T00:10:00Z
  checked: iOS AuthViewModel
  found: @Observable class without @MainActor. checkAuthState() sets isLoading directly without MainActor isolation, while signUp/signIn/signOut use MainActor.run wrappers inconsistently.
  implication: RACE CONDITION - UI state mutations from non-main thread

- timestamp: 2026-01-28T00:15:00Z
  checked: iOS SupabaseService
  found: @Observable class without @MainActor. currentSession and isAuthenticated written via MainActor.run but read from non-isolated getAccessToken/getUserId. authStateContinuation accessed from init (main) and authStateListener (background task).
  implication: RACE CONDITION - concurrent reads/writes on observable state

- timestamp: 2026-01-28T00:20:00Z
  checked: iOS GeofenceManager.processingGeofenceIds
  found: Static Set<String> with no synchronization. handleGeofenceEntry accesses it from CLLocationManager delegate callbacks (arbitrary queue) dispatched to @MainActor Tasks, but the method itself was not @MainActor.
  implication: RACE CONDITION - static mutable state accessed from multiple threads

- timestamp: 2026-01-28T00:25:00Z
  checked: iOS HealthKitService
  found: @Observable class (NOT @MainActor) with mutable state: processedSampleIds, processingWorkoutTimestamps, observerQueries, queryAnchors, etc. Individual methods annotated @MainActor but class-level isolation missing. HKObserverQuery callbacks fire on arbitrary HealthKit queue.
  implication: RACE CONDITION - class-level mutable state not uniformly isolated

- timestamp: 2026-01-28T00:35:00Z
  checked: Go backend rate limiter
  found: Properly uses sync.RWMutex. Concurrent tests pass with -race flag.
  implication: No race condition

- timestamp: 2026-01-28T00:40:00Z
  checked: Go backend architecture
  found: All handlers/services/repos are structs with immutable refs. Each request gets own context. No goroutine leaks.
  implication: No race conditions in Go backend

- timestamp: 2026-01-28T00:45:00Z
  checked: Web app React Query hooks and API client
  found: TanStack Query serializes mutations. Auth headers fetched per-request. Supabase SDK handles concurrency internally.
  implication: No race conditions in web app

## Resolution

root_cause: Four race conditions in iOS platform due to @Observable classes missing @MainActor isolation:
1. AuthViewModel - UI state mutated without consistent MainActor isolation
2. SupabaseService - Auth state read/written across isolation boundaries
3. GeofenceManager.processingGeofenceIds - static mutable state without isolation
4. HealthKitService - class-level mutable state with only per-method @MainActor

fix:
1. Added @MainActor to AuthViewModel, removed redundant MainActor.run wrappers
2. Added @MainActor to SupabaseService, marked getAccessToken/getUserId/getCurrentUser as nonisolated (they use Supabase SDK's thread-safe session API), removed redundant MainActor.run wrappers
3. Added @MainActor to GeofenceManager.processingGeofenceIds static property and handleGeofenceEntry/handleGeofenceExit methods
4. Added @MainActor to HealthKitService class (consolidates scattered per-method annotations)
5. Added Go rate limiter concurrent access test to verify no races

verification: Go tests pass with -race flag. Swift changes are compile-time enforced by Swift concurrency checker.
files_changed:
  - apps/ios/trendy/ViewModels/AuthViewModel.swift
  - apps/ios/trendy/Services/SupabaseService.swift
  - apps/ios/trendy/Services/Geofence/GeofenceManager.swift
  - apps/ios/trendy/Services/Geofence/GeofenceManager+EventHandling.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService.swift
  - apps/backend/internal/middleware/ratelimit_race_test.go
