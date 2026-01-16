# Architecture Research: iOS Background Data Infrastructure

**Domain:** iOS background data systems (HealthKit, Geofence, Sync)
**Researched:** 2026-01-15
**Confidence:** MEDIUM-HIGH

## Executive Summary

The current iOS data infrastructure has grown organically into monolithic services:
- `HealthKitService.swift`: 1,972 lines handling authorization, observer setup, sample processing, event creation, persistence
- `GeofenceManager.swift`: 680 lines mixing CLLocationManager delegation, event handling, state tracking
- `SyncEngine.swift`: 1,117 lines combining mutation queue, pull sync, bootstrap fetch, conflict handling
- `EventStore.swift`: 1,355 lines serving as a god object for data access, sync coordination, network monitoring

**Primary Issue:** Single Responsibility Principle violations. Each file handles 4-6 distinct concerns that should be separate components.

**Recommendation:** Decompose into focused modules following Repository + Use Case patterns, with clear boundaries between:
1. Platform adapters (HealthKit queries, CLLocationManager delegation)
2. Processing logic (sample transformation, event creation)
3. Persistence coordination (SwiftData access)
4. Sync orchestration (mutation queue, pull sync)

---

## Standard Architecture

### System Overview

```
+-------------------------------------------------------------------------------------+
|                               APP LAYER                                             |
|  +-------------------+  +-------------------+  +-------------------+                |
|  |   ViewModels      |  |    Coordinators   |  |   App Delegate    |                |
|  +-------------------+  +-------------------+  +-------------------+                |
|           |                     |                       |                           |
|           v                     v                       v                           |
+-------------------------------------------------------------------------------------+
|                            USE CASE LAYER                                           |
|  +------------------+  +------------------+  +------------------+                   |
|  | RecordEventUC    |  | SyncDataUC       |  | ProcessHealthUC  |                   |
|  +------------------+  +------------------+  +------------------+                   |
|           |                     |                       |                           |
|           v                     v                       v                           |
+-------------------------------------------------------------------------------------+
|                           SERVICE LAYER                                             |
|  +------------------+  +------------------+  +------------------+                   |
|  | EventRepository  |  | SyncCoordinator  |  | HealthProcessor  |                   |
|  +------------------+  +------------------+  +------------------+                   |
|           |                     |                       |                           |
|           v                     v                       v                           |
+-------------------------------------------------------------------------------------+
|                          INFRASTRUCTURE LAYER                                       |
|  +------------------+  +------------------+  +------------------+                   |
|  | LocalStore       |  | APIClient        |  | HKQueryManager   |                   |
|  | (SwiftData)      |  | MutationQueue    |  | CLRegionMonitor  |                   |
|  +------------------+  +------------------+  +------------------+                   |
+-------------------------------------------------------------------------------------+
|                          PLATFORM ADAPTERS                                          |
|  +------------------+  +------------------+  +------------------+                   |
|  | HKHealthStore    |  | CLLocationMgr    |  | Network.framework|                   |
|  +------------------+  +------------------+  +------------------+                   |
+-------------------------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Current Location | Lines |
|-----------|---------------|------------------|-------|
| HKQueryManager | Observer query setup, background delivery registration | HealthKitService.swift (mixed) | ~300 |
| HealthProcessor | Sample processing, aggregation, deduplication | HealthKitService.swift (mixed) | ~800 |
| HealthEventFactory | Event creation from HealthKit samples | HealthKitService.swift (mixed) | ~400 |
| HealthKitAuthManager | Authorization state, permission flow | HealthKitService.swift (mixed) | ~150 |
| GeofenceMonitor | CLLocationManager delegation, region state | GeofenceManager.swift (mixed) | ~200 |
| GeofenceEventFactory | Event creation from entry/exit | GeofenceManager.swift (mixed) | ~200 |
| GeofenceReconciler | Region sync with backend definitions | GeofenceManager.swift (mixed) | ~100 |
| SyncCoordinator | Orchestrate push/pull, single-flight | SyncEngine.swift (mixed) | ~200 |
| MutationQueue | Queue/flush pending mutations | SyncEngine.swift (mixed) | ~300 |
| PullSyncEngine | Cursor-based incremental pull | SyncEngine.swift (mixed) | ~200 |
| BootstrapFetcher | Initial full fetch on first sync | SyncEngine.swift (mixed) | ~200 |
| LocalStore | SwiftData upsert/delete operations | LocalStore.swift | 323 (OK) |
| EventRepository | Unified data access layer | EventStore.swift (mixed) | ~600 |
| NetworkMonitor | Online/offline detection | EventStore.swift (mixed) | ~100 |

---

## Recommended Project Structure

```
apps/ios/trendy/
├── Services/
│   ├── HealthKit/
│   │   ├── HKQueryManager.swift           # Observer query setup, background delivery
│   │   ├── HKAuthorizationManager.swift   # Permission flow, authorization state
│   │   ├── Processors/
│   │   │   ├── WorkoutProcessor.swift     # Workout sample processing
│   │   │   ├── SleepProcessor.swift       # Sleep aggregation logic
│   │   │   ├── StepsProcessor.swift       # Daily step aggregation
│   │   │   ├── ActiveEnergyProcessor.swift
│   │   │   ├── MindfulnessProcessor.swift
│   │   │   └── WaterProcessor.swift
│   │   ├── HealthEventFactory.swift       # Create Event from processed samples
│   │   └── HealthKitSettings.swift        # Category configuration (existing)
│   │
│   ├── Location/
│   │   ├── GeofenceMonitor.swift          # CLLocationManager delegation
│   │   ├── GeofenceAuthManager.swift      # Location permission flow
│   │   ├── GeofenceReconciler.swift       # Sync regions with backend
│   │   └── GeofenceEventFactory.swift     # Create Event from entry/exit
│   │
│   ├── Sync/
│   │   ├── SyncCoordinator.swift          # Orchestrate sync operations
│   │   ├── MutationQueue.swift            # Queue/flush pending mutations
│   │   ├── PullSyncEngine.swift           # Cursor-based incremental pull
│   │   ├── BootstrapFetcher.swift         # Initial full fetch
│   │   ├── ConflictResolver.swift         # Handle sync conflicts
│   │   ├── LocalStore.swift               # SwiftData operations (existing)
│   │   └── SyncableEntity.swift           # Protocol (existing)
│   │
│   ├── Network/
│   │   ├── APIClient.swift                # HTTP client (existing)
│   │   ├── NetworkMonitor.swift           # Online/offline detection
│   │   └── RequestRetrier.swift           # Retry logic with backoff
│   │
│   └── Persistence/
│       ├── EventRepository.swift          # Event CRUD, queries
│       ├── EventTypeRepository.swift      # EventType CRUD
│       └── GeofenceRepository.swift       # Geofence CRUD
│
├── UseCases/
│   ├── RecordManualEventUC.swift          # Manual event recording
│   ├── RecordHealthEventUC.swift          # HealthKit event recording
│   ├── RecordGeofenceEventUC.swift        # Geofence event recording
│   ├── SyncDataUC.swift                   # Sync orchestration
│   └── FetchEventsUC.swift                # Load events with caching
│
└── ViewModels/
    ├── EventStore.swift                   # Simplified: delegates to repositories
    └── ...
```

---

## Architectural Patterns

### Pattern 1: Observer-Processor-Factory Pipeline

**What:** Separate the three stages of background data handling

```
Observer (setup) → Processor (transform) → Factory (create)
```

**When to use:** Any background data source (HealthKit, Location, Push notifications)

**Example structure:**

```swift
// MARK: - Observer (Infrastructure Layer)
protocol HKQueryManaging {
    func startObserving(category: HealthDataCategory)
    func stopObserving(category: HealthDataCategory)
    var samplePublisher: AnyPublisher<HKSample, Never> { get }
}

actor HKQueryManager: HKQueryManaging {
    private let healthStore: HKHealthStore
    private var observerQueries: [HealthDataCategory: HKObserverQuery] = [:]
    private let sampleSubject = PassthroughSubject<HKSample, Never>()

    var samplePublisher: AnyPublisher<HKSample, Never> {
        sampleSubject.eraseToAnyPublisher()
    }

    func startObserving(category: HealthDataCategory) {
        // ONLY query setup logic here - no processing
        let query = HKObserverQuery(sampleType: category.hkSampleType, predicate: nil) { [weak self] _, _, _ in
            Task { await self?.fetchNewSamples(for: category) }
        }
        healthStore.execute(query)
        observerQueries[category] = query
        // Enable background delivery
        Task {
            try? await healthStore.enableBackgroundDelivery(for: category.hkSampleType, frequency: category.backgroundDeliveryFrequency)
        }
    }

    private func fetchNewSamples(for category: HealthDataCategory) async {
        // Fetch and emit samples - NO processing here
        let samples = await querySamples(for: category)
        for sample in samples {
            sampleSubject.send(sample)
        }
    }
}

// MARK: - Processor (Service Layer)
protocol HealthProcessing {
    func process(_ sample: HKSample) async -> ProcessedHealthData?
}

struct SleepProcessor: HealthProcessing {
    // ONLY transformation logic - no persistence, no event creation
    func process(_ sample: HKSample) async -> ProcessedHealthData? {
        guard let sleepSample = sample as? HKCategorySample else { return nil }
        // Aggregation, deduplication logic
        return ProcessedSleepData(...)
    }
}

// MARK: - Factory (Use Case Layer)
protocol HealthEventCreating {
    func createEvent(from data: ProcessedHealthData) async throws -> Event
}

struct HealthEventFactory: HealthEventCreating {
    private let eventRepository: EventRepository
    private let eventTypeRepository: EventTypeRepository

    func createEvent(from data: ProcessedHealthData) async throws -> Event {
        let eventType = try await eventTypeRepository.ensureExists(for: data.category)
        let event = Event(...)
        try await eventRepository.save(event)
        return event
    }
}
```

**Benefits:**
- Each component is testable in isolation
- Processors can be reused (e.g., same sleep processor for historical import)
- Observer changes (iOS updates) don't affect processing logic
- Factory can be called from multiple sources (background, manual refresh)

### Pattern 2: Repository with Sync Awareness

**What:** Repositories handle local persistence AND queue sync mutations

```swift
protocol EventRepositoryProtocol {
    func save(_ event: Event) async throws
    func delete(_ event: Event) async throws
    func fetch(matching predicate: Predicate<Event>) async throws -> [Event]
    func fetchAll() async throws -> [Event]
}

@MainActor
final class EventRepository: EventRepositoryProtocol {
    private let modelContext: ModelContext
    private let syncCoordinator: SyncCoordinator

    func save(_ event: Event) async throws {
        // 1. Save locally
        modelContext.insert(event)
        try modelContext.save()

        // 2. Queue for sync (fire-and-forget, SyncCoordinator handles offline)
        await syncCoordinator.queueCreate(entity: event)
    }

    func delete(_ event: Event) async throws {
        // 1. Queue delete BEFORE local delete (need the ID)
        await syncCoordinator.queueDelete(entityType: .event, id: event.id)

        // 2. Delete locally
        modelContext.delete(event)
        try modelContext.save()
    }
}
```

**When to use:** All entities that sync with backend (Event, EventType, Geofence)

### Pattern 3: Coordinator Pattern for Sync

**What:** Single coordinator orchestrates all sync operations with single-flight protection

```swift
actor SyncCoordinator {
    private var isSyncing = false
    private let mutationQueue: MutationQueue
    private let pullEngine: PullSyncEngine
    private let bootstrapFetcher: BootstrapFetcher

    func performSync() async {
        // Single-flight: prevent concurrent syncs
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // 1. Flush pending mutations (push)
        try await mutationQueue.flush()

        // 2. Pull changes (incremental or bootstrap)
        if needsBootstrap {
            try await bootstrapFetcher.fetch()
        } else {
            try await pullEngine.pull()
        }
    }

    func queueCreate(entity: any SyncableEntity) async {
        await mutationQueue.enqueue(.create(entity))
        // Trigger sync if online (fire-and-forget)
        Task { await performSync() }
    }
}
```

### Pattern 4: State Machine for Authorization

**What:** Explicit states for permission flows

```swift
enum LocationAuthState {
    case notDetermined
    case requestingWhenInUse
    case whenInUseGranted
    case requestingAlways
    case alwaysGranted
    case denied
    case restricted
}

@Observable
final class GeofenceAuthManager: NSObject {
    private(set) var state: LocationAuthState = .notDetermined
    private let locationManager: CLLocationManager

    func requestGeofenceAuthorization() {
        switch state {
        case .notDetermined:
            state = .requestingWhenInUse
            locationManager.requestWhenInUseAuthorization()
        case .whenInUseGranted:
            state = .requestingAlways
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
}
```

---

## Data Flow

### HealthKit Data Flow (Recommended)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Background Wake / App Launch                          │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │
                                  v
┌──────────────────────────────────────────────────────────────────────────────┐
│                    HKQueryManager.fetchNewSamples()                          │
│  - HKSampleQuery for recent data                                             │
│  - Emit samples via Combine publisher                                        │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │ [HKSample]
                                  v
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CategoryProcessor.process(sample)                         │
│  - Category-specific processing (sleep aggregation, step totals)             │
│  - Deduplication check (in-memory + database)                                │
│  - Return ProcessedHealthData or nil (skip)                                  │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │ ProcessedHealthData
                                  v
┌──────────────────────────────────────────────────────────────────────────────┐
│                    HealthEventFactory.createEvent()                          │
│  - Ensure EventType exists (auto-create if needed)                           │
│  - Create Event with properties                                              │
│  - Save via EventRepository (queues sync mutation)                           │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │ Event
                                  v
┌──────────────────────────────────────────────────────────────────────────────┐
│                    SyncCoordinator.performSync()                             │
│  - Flush pending mutations to backend                                        │
│  - Pull any server-side changes                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Sync Data Flow (Recommended)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PUSH FLOW (Local → Server)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  User Action / HealthKit / Geofence                                         │
│        │                                                                    │
│        v                                                                    │
│  Repository.save(entity)                                                    │
│        │                                                                    │
│        ├──> SwiftData.insert() + save()  [immediate local persistence]      │
│        │                                                                    │
│        └──> MutationQueue.enqueue(mutation)                                 │
│                  │                                                          │
│                  v                                                          │
│             PendingMutation (SwiftData model)                               │
│                  │                                                          │
│                  v                                                          │
│             SyncCoordinator.performSync() [when online]                     │
│                  │                                                          │
│                  v                                                          │
│             MutationQueue.flush()                                           │
│                  │                                                          │
│                  ├──> APIClient.createEntity()  [with idempotency key]      │
│                  │                                                          │
│                  └──> Delete PendingMutation on success                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                       PULL FLOW (Server → Local)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SyncCoordinator.performSync()                                              │
│        │                                                                    │
│        v                                                                    │
│  PullSyncEngine.pull(since: cursor)                                         │
│        │                                                                    │
│        v                                                                    │
│  APIClient.getChanges(since: cursor, limit: 100)                            │
│        │                                                                    │
│        v                                                                    │
│  [ChangeEntry] - create/update/delete operations                            │
│        │                                                                    │
│        v                                                                    │
│  LocalStore.upsert() or LocalStore.delete()                                 │
│        │                                                                    │
│        v                                                                    │
│  Update cursor, repeat if hasMore                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Module Decomposition Strategy

### Phase 1: Extract Infrastructure (Low Risk)

**Goal:** Create platform adapters without changing business logic

1. **Extract `HKQueryManager`** from HealthKitService
   - Move observer query setup (lines 330-460)
   - Move background delivery enablement
   - Keep all processing logic in HealthKitService temporarily

2. **Extract `NetworkMonitor`** from EventStore
   - Move `NWPathMonitor` setup (lines 76-94)
   - Create protocol for testability

3. **Extract `GeofenceAuthManager`** from GeofenceManager
   - Move authorization state machine (lines 71-139)
   - Move two-step permission flow

**Deliverable:** Three new focused infrastructure components

### Phase 2: Extract Processors (Medium Risk)

**Goal:** Isolate data transformation logic

1. **Create category-specific processors** from HealthKitService
   - `WorkoutProcessor` (lines 543-664)
   - `SleepProcessor` (lines 669-870)
   - `StepsProcessor` (lines 872-976)
   - `ActiveEnergyProcessor` (lines 978-1090)
   - Each processor: input HKSample, output ProcessedData

2. **Extract `GeofenceEventFactory`** from GeofenceManager
   - Move `handleGeofenceEntry` (lines 362-461)
   - Move `handleGeofenceExit` (lines 463-542)

**Deliverable:** Testable processing components with no dependencies on persistence

### Phase 3: Extract Sync Components (Higher Risk)

**Goal:** Decompose monolithic SyncEngine

1. **Extract `MutationQueue`** actor
   - Move `flushPendingMutations` (lines 320-411)
   - Move `flushCreate/Update/Delete` (lines 424-500)

2. **Extract `PullSyncEngine`**
   - Move `pullChanges` (lines 579-606)
   - Move `applyChanges` (lines 608-807)

3. **Extract `BootstrapFetcher`**
   - Move `bootstrapFetch` (lines 814-1027)

4. **Simplify `SyncCoordinator`** to orchestration only
   - Coordinate MutationQueue, PullSyncEngine, BootstrapFetcher
   - Single-flight protection
   - State management

**Deliverable:** Four focused sync components, easier to test and modify

### Phase 4: Create Repositories (Medium Risk)

**Goal:** Unified data access layer

1. **Create `EventRepository`** protocol and implementation
   - CRUD operations
   - Auto-queue sync mutations

2. **Create `EventTypeRepository`**
3. **Create `GeofenceRepository`**

4. **Simplify `EventStore`** to ViewModel role
   - Delegate persistence to repositories
   - Keep only UI state and coordination

**Deliverable:** Clean separation between ViewModels and persistence

### Build Order Summary

| Phase | Components | Risk | LOC Impact | Dependencies |
|-------|------------|------|------------|--------------|
| 1 | HKQueryManager, NetworkMonitor, GeofenceAuthManager | Low | Extract ~500 | None |
| 2 | Processors (5), GeofenceEventFactory | Medium | Extract ~1000 | Phase 1 |
| 3 | MutationQueue, PullSyncEngine, BootstrapFetcher, SyncCoordinator | Higher | Refactor ~800 | Phases 1-2 |
| 4 | Repositories (3), EventStore simplification | Medium | Refactor ~600 | Phases 1-3 |

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: God Object

**Current:** `EventStore` (1,355 lines) handles:
- Data access (CRUD)
- Network monitoring
- Sync coordination
- Widget integration
- Calendar integration
- Geofence reconciliation

**Problem:** Changes to any concern affect the entire class. Testing requires mocking everything.

**Solution:** Extract each concern into focused components, have EventStore delegate.

### Anti-Pattern 2: Mixed Abstraction Levels

**Current:** `HealthKitService.processWorkoutSample()` (lines 543-628):
```swift
// LOW-LEVEL: HKWorkout property access
let duration = workout.duration
let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

// MEDIUM-LEVEL: Property building
var properties: [String: PropertyValue] = [...]

// HIGH-LEVEL: Event creation and persistence
let event = Event(...)
modelContext.insert(event)
try modelContext.save()

// SYNC-LEVEL: Backend synchronization
await eventStore.syncEventToBackend(event)
```

**Problem:** Single method spans 4 abstraction levels, making it hard to modify or test any single level.

**Solution:** Each level in separate component:
- `WorkoutProcessor`: Extract data from HKWorkout
- `HealthEventFactory`: Build Event from processed data
- `EventRepository`: Persist and queue sync

### Anti-Pattern 3: Implicit State Machine

**Current:** GeofenceManager authorization flow uses `pendingAlwaysAuthorizationRequest` boolean flag

**Problem:** State transitions are implicit, easy to get into invalid states

**Solution:** Explicit enum-based state machine with defined transitions

### Anti-Pattern 4: Callback Soup

**Current:** HealthKitService observer queries use completion handlers that dispatch to async context:
```swift
let query = HKObserverQuery(...) { [weak self] _, completionHandler, error in
    Task {
        await self?.handleNewSamples(for: category)
    }
    completionHandler()
}
```

**Problem:** Mixed callback and async/await paradigms, completion handler timing issues

**Solution:** Use Combine or AsyncStream to bridge observer callbacks to async context:
```swift
// Better: Observable stream
func observeSamples(for category: HealthDataCategory) -> AsyncStream<HKSample> {
    AsyncStream { continuation in
        let query = HKObserverQuery(...) { ... in
            // yield samples to stream
        }
        ...
    }
}
```

### Anti-Pattern 5: Defensive Programming Overload

**Current:** HealthKitService has 45+ `print()` statements for debugging

**Problem:** Debug logging mixed with business logic, no structured logging, difficult to analyze

**Solution:** Use structured logging (`Log.healthkit.debug(...)`) with context, remove print statements

---

## HealthKit-Specific Patterns

### Observer Query Lifecycle

Based on [Apple's HKObserverQuery documentation](https://developer.apple.com/documentation/healthkit/hkobserverquery), observer queries should:

1. Be started once at app launch (not recreated)
2. Call completion handler promptly to avoid timeout
3. Use separate queries for each data type

**Recommended pattern:**
```swift
actor HKQueryManager {
    private var observerQueries: [HealthDataCategory: HKObserverQuery] = [:]

    // Start all at app launch, not on-demand
    func startAllObservers(for categories: Set<HealthDataCategory>) {
        for category in categories {
            guard observerQueries[category] == nil else { continue }
            let query = createObserverQuery(for: category)
            healthStore.execute(query)
            observerQueries[category] = query
        }
    }

    private func createObserverQuery(for category: HealthDataCategory) -> HKObserverQuery {
        HKObserverQuery(sampleType: category.hkSampleType, predicate: nil) { [weak self] _, completionHandler, _ in
            // Call completion handler IMMEDIATELY, before processing
            completionHandler()
            // Then process asynchronously
            Task { await self?.emitSamplesForProcessing(category: category) }
        }
    }
}
```

### Daily Aggregation Pattern

For steps, active energy, sleep - aggregate per day rather than per sample:

```swift
struct DailyAggregator {
    private let sampleIdPrefix: String // e.g., "steps-", "sleep-"

    func aggregationId(for date: Date) -> String {
        "\(sampleIdPrefix)\(dateFormatter.string(from: date))"
    }

    func shouldProcess(date: Date, lastProcessed: Date?, throttleSeconds: TimeInterval = 300) -> Bool {
        guard let last = lastProcessed else { return true }
        guard Calendar.current.isDate(last, inSameDayAs: date) else { return true }
        return Date().timeIntervalSince(last) >= throttleSeconds
    }
}
```

---

## Geofence-Specific Patterns

### Region Re-registration

Based on [Apple's region monitoring documentation](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions), geofences must be re-registered:
- After app reinstall
- After device reboot
- When authorization changes

**Recommended pattern:**
```swift
@Observable
final class GeofenceReconciler {
    func reconcile(desired: [GeofenceDefinition]) {
        let currentIds = Set(locationManager.monitoredRegions.map { $0.identifier })
        let desiredIds = Set(desired.map { $0.identifier })

        // Remove stale
        for id in currentIds.subtracting(desiredIds) {
            if let region = locationManager.monitoredRegions.first(where: { $0.identifier == id }) {
                locationManager.stopMonitoring(for: region)
            }
        }

        // Add missing
        for def in desired where !currentIds.contains(def.identifier) {
            let region = CLCircularRegion(...)
            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region) // Check if already inside
        }
    }
}
```

### Active Event Tracking

Track in-progress geofence visits persistently (survives app termination):

```swift
actor ActiveGeofenceTracker {
    private let userDefaults: UserDefaults
    private let key = "activeGeofenceEvents"

    func setActive(geofenceId: String, eventId: String) async {
        var active = loadActive()
        active[geofenceId] = eventId
        saveActive(active)
    }

    func clearActive(geofenceId: String) async {
        var active = loadActive()
        active.removeValue(forKey: geofenceId)
        saveActive(active)
    }

    func activeEventId(for geofenceId: String) async -> String? {
        loadActive()[geofenceId]
    }
}
```

---

## Sync-Specific Patterns

### Mutation Queue with Idempotency

```swift
actor MutationQueue {
    private let modelContainer: ModelContainer

    func enqueue(_ mutation: QueuedMutation) async throws {
        let context = ModelContext(modelContainer)
        let pending = PendingMutation(
            entityType: mutation.entityType,
            operation: mutation.operation,
            entityId: mutation.entityId,
            payload: mutation.payload,
            idempotencyKey: UUID().uuidString // Client-generated
        )
        context.insert(pending)
        try context.save()
    }

    func flush(using apiClient: APIClient) async throws {
        let context = ModelContext(modelContainer)
        let mutations = try fetchPending(context: context)

        for mutation in mutations {
            do {
                try await sendMutation(mutation, apiClient: apiClient)
                context.delete(mutation)
            } catch let error as APIError where error.isDuplicateError {
                // Idempotency: duplicate means it succeeded before
                context.delete(mutation)
            } catch {
                mutation.recordFailure()
                if mutation.hasExceededRetryLimit {
                    // Move to dead letter queue or mark entity failed
                }
            }
        }
        try context.save()
    }
}
```

### Cursor-Based Pull with Delete Protection

```swift
actor PullSyncEngine {
    private var cursor: Int64
    private var pendingDeleteIds: Set<String> = []

    func pull(capturingDeletesFrom mutationQueue: MutationQueue) async throws {
        // CRITICAL: Capture pending deletes BEFORE pulling
        pendingDeleteIds = await mutationQueue.pendingDeleteEntityIds()

        var hasMore = true
        while hasMore {
            let response = try await apiClient.getChanges(since: cursor, limit: 100)

            for change in response.changes {
                // Skip resurrection of entities we're about to delete
                guard !pendingDeleteIds.contains(change.entityId) else { continue }
                try apply(change)
            }

            cursor = response.nextCursor
            hasMore = response.hasMore
        }

        pendingDeleteIds.removeAll()
        persistCursor()
    }
}
```

---

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `/Users/cipher/Repositories/trendy/apps/ios/trendy/Services/` (direct review)
- [Apple HKObserverQuery Documentation](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- [Apple Region Monitoring Documentation](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)

### Secondary (MEDIUM confidence)
- [SwiftData Architecture Patterns and Practices](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html)
- [Designing Efficient Local-First Architectures with SwiftData](https://medium.com/@gauravharkhani01/designing-efficient-local-first-architectures-with-swiftdata-cc74048526f2)
- [Clean Architecture in iOS Development](https://medium.com/@dyaremyshyn/clean-architecture-in-ios-development-a-comprehensive-guide-7e3d5f851e79)
- [HealthKit Background Delivery Guide](https://medium.com/@ios_guru/working-with-healthkit-background-delivery-828d5144c5a8)
- [Geofencing iOS Limitations](https://radar.com/blog/limitations-of-ios-geofencing)
- [Offline-First SwiftUI with SwiftData](https://medium.com/@ashitranpura27/offline-first-swiftui-with-swiftdata-clean-fast-and-sync-ready-9a4faefdeedb)

### Tertiary (LOW confidence - patterns from web search, not verified)
- Repository pattern implementation specifics
- Exact Combine bridging patterns for HealthKit observers

---

## Metadata

**Confidence breakdown:**
- Component identification: HIGH - based on direct code analysis
- Architecture patterns: MEDIUM-HIGH - based on established iOS patterns
- Build order: MEDIUM - based on dependency analysis, may need adjustment
- Anti-patterns: HIGH - directly observed in codebase

**Research date:** 2026-01-15
**Valid until:** 2026-03-15 (patterns are stable, implementation details may change)

**Implications for roadmap:**
1. Phase 1 (Infrastructure extraction) can start immediately, low risk
2. Phase 2 (Processors) should follow Phase 1 to have clean boundaries
3. Phase 3 (Sync decomposition) is highest risk, should have comprehensive tests first
4. Phase 4 (Repositories) provides the clean API surface for future features
