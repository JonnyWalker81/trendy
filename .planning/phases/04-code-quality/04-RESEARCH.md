# Phase 4: Code Quality - Research

**Researched:** 2026-01-16
**Domain:** Swift service decomposition and protocol-oriented architecture
**Confidence:** HIGH

## Summary

Code quality improvement in this phase focuses on **splitting large monolithic services into focused, testable modules** without changing external behavior. HealthKitService.swift (2,313 lines) and GeofenceManager.swift (950 lines) both violate the single-responsibility principle by handling too many concerns in one file.

The established Swift pattern for decomposition is **extension-based file splitting** combined with **protocol-oriented design**. Rather than creating deep class hierarchies, Swift favors composing behavior through protocols and separating concerns via extensions in separate files. The key insight: Swift extensions can be placed in separate files while still being part of the same type, enabling logical grouping without architectural refactoring.

**Primary recommendation:** Split HealthKitService into focused extensions by responsibility (query management, per-data-type processors, event factory, persistence). Split GeofenceManager into auth, registration, and event handling concerns. Use `// MARK:` comments and separate files named `TypeName+Concern.swift` for organization.

## Standard Stack

The established patterns for Swift service decomposition:

### Core Patterns

| Pattern | Purpose | Why Standard |
|---------|---------|--------------|
| Extension-based file splitting | Organize large types across files | Native Swift feature, no runtime overhead, maintains type cohesion |
| Protocol-oriented composition | Define behavior contracts | Apple's recommended approach since Swift 2, enables testability |
| MARK comments | Segment code within files | Built-in Xcode support for navigation, industry standard |
| Dedicated error types | Centralize error definitions | Already exists in codebase (HealthKitError, GeofenceError) |
| Settings/Configuration extraction | Separate configuration from logic | Already exists (HealthKitSettings.swift) |

### Supporting Patterns

| Pattern | Purpose | When to Use |
|---------|---------|-------------|
| Internal protocols | Define contracts between components | When testing internal boundaries, dependency injection |
| Nested types | Group related types | Small helper types that don't warrant separate files |
| Factory methods | Centralize object creation | When creation logic is complex or varies by context |
| Coordinator pattern | Orchestrate multiple services | When a single entry point needs to coordinate decomposed parts |

### Naming Conventions

| File Name Pattern | Purpose | Example |
|-------------------|---------|---------|
| `TypeName+Concern.swift` | Extension file for a concern | `HealthKitService+WorkoutProcessing.swift` |
| `TypeName+Protocol.swift` | Protocol conformance extension | `GeofenceManager+CLLocationManagerDelegate.swift` |
| `ConcernProcessor.swift` | Dedicated processor type | `WorkoutProcessor.swift` |
| `ConcernError.swift` | Error types for concern | `HealthKitError.swift` (already exists) |

## Architecture Patterns

### Recommended Structure for HealthKitService Decomposition

Current: 1 file, 2,313 lines
Target: 8-10 files, <400 lines each

```
apps/ios/trendy/Services/HealthKit/
├── HealthKitService.swift           # Main coordinator (~200 lines)
│   - Public interface
│   - Dependency injection
│   - Lifecycle management
│
├── HealthKitService+Authorization.swift  # (~100 lines)
│   - Authorization request
│   - Status checking
│   - Permission handling
│
├── HealthKitService+QueryManagement.swift  # (~150 lines)
│   - Observer query setup/teardown
│   - Anchored query execution
│   - Background delivery registration
│
├── HealthKitService+Persistence.swift  # (~150 lines)
│   - UserDefaults persistence (anchors, processed IDs)
│   - Cache management
│   - Migration logic
│
├── Processors/
│   ├── WorkoutProcessor.swift      # (~200 lines)
│   │   - Workout sample processing
│   │   - Heart rate enrichment
│   │   - Workout-specific event creation
│   │
│   ├── SleepProcessor.swift        # (~200 lines)
│   │   - Sleep sample aggregation
│   │   - Daily sleep event creation
│   │   - Sleep stage breakdown
│   │
│   ├── DailyAggregateProcessor.swift  # (~200 lines)
│   │   - Steps aggregation
│   │   - Active energy aggregation
│   │   - Daily event updates
│   │
│   └── CategoryProcessor.swift     # (~150 lines)
│       - Mindfulness processing
│       - Water intake processing
│       - Generic category handling
│
├── HealthKitEventFactory.swift     # (~100 lines)
│   - Event creation for all categories
│   - Property building
│   - Deduplication checks
│
└── HealthKitDebugExtensions.swift  # (~300 lines)
    - Debug query methods
    - Simulation methods
    - Cache clearing utilities
```

### Recommended Structure for GeofenceManager Decomposition

Current: 1 file, 950 lines
Target: 4-5 files, <300 lines each

```
apps/ios/trendy/Services/Geofence/
├── GeofenceManager.swift           # Main coordinator (~250 lines)
│   - Public interface
│   - Initialization
│   - Dependency injection
│   - Lifecycle (deinit, notification observers)
│
├── GeofenceManager+Authorization.swift  # (~100 lines)
│   - Authorization request flow
│   - Two-step authorization handling
│   - Status checking
│
├── GeofenceManager+Registration.swift  # (~200 lines)
│   - startMonitoring/stopMonitoring
│   - reconcileRegions
│   - ensureRegionsRegistered
│   - Region management
│
├── GeofenceManager+EventHandling.swift  # (~250 lines)
│   - handleGeofenceEntry
│   - handleGeofenceExit
│   - Active event tracking
│   - Event creation
│
└── GeofenceManager+CLLocationManagerDelegate.swift  # (~100 lines)
    - All CLLocationManagerDelegate methods
    - Delegate callback routing
```

### Pattern 1: Extension-Based File Splitting

**What:** Use Swift extensions to split a type across multiple files by concern.
**When to use:** Any type exceeding ~400 lines or handling multiple distinct responsibilities.
**Why:** Maintains type cohesion, no architecture changes, enables focused testing.

```swift
// Source: Swift by Sundell, Google Swift Style Guide

// HealthKitService.swift - Main file (~200 lines)
@Observable
class HealthKitService: NSObject {
    // MARK: - Properties
    private let healthStore: HKHealthStore
    private let modelContext: ModelContext
    private let eventStore: EventStore

    // MARK: - Initialization
    init(modelContext: ModelContext, eventStore: EventStore, ...) {
        // Initialization only
    }

    // MARK: - Public Interface
    func startMonitoringAllConfigurations() { ... }
    func stopMonitoringAll() { ... }
}

// HealthKitService+Authorization.swift (~100 lines)
extension HealthKitService {
    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async throws { ... }

    var hasHealthKitAuthorization: Bool { ... }

    private func shouldRequestAuthorization(for type: HKSampleType) async -> Bool { ... }
}

// HealthKitService+QueryManagement.swift (~150 lines)
extension HealthKitService {
    // MARK: - Query Management

    func startMonitoring(category: HealthDataCategory) { ... }
    func stopMonitoring(category: HealthDataCategory) { ... }

    @MainActor
    private func startObserverQuery(for category: HealthDataCategory, sampleType: HKSampleType) async { ... }
}
```

### Pattern 2: Processor Extraction

**What:** Extract data-type-specific processing into dedicated types.
**When to use:** When processing logic is self-contained and category-specific.
**Why:** Enables independent testing, clearer responsibility, easier maintenance.

```swift
// Source: Protocol-Oriented Programming best practices

// WorkoutProcessor.swift
struct WorkoutProcessor {
    private let healthStore: HKHealthStore
    private let eventFactory: HealthKitEventFactory

    func process(_ workout: HKWorkout, isBulkImport: Bool) async throws -> Event? {
        // Duplicate checks
        // Heart rate enrichment
        // Property building
        // Event creation via factory
    }

    private func fetchHeartRateStats(for workout: HKWorkout) async -> (avg: Double?, max: Double?) { ... }
}

// HealthKitService uses processor
extension HealthKitService {
    @MainActor
    private func processWorkoutSample(_ workout: HKWorkout, isBulkImport: Bool) async {
        guard let event = try? await workoutProcessor.process(workout, isBulkImport: isBulkImport) else {
            return
        }
        markSampleAsProcessed(workout.uuid.uuidString)
        await eventStore.syncEventToBackend(event)
    }
}
```

### Pattern 3: Delegate Conformance in Separate Extension

**What:** Put protocol conformance in a dedicated extension file.
**When to use:** When delegate methods are substantial or protocol is external.
**Why:** Keeps delegate implementation focused, easier to locate all protocol methods.

```swift
// Source: Apple Developer Documentation patterns

// GeofenceManager+CLLocationManagerDelegate.swift
extension GeofenceManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleRegionEntry(region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handleRegionExit(region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        handleStateChange(state, for: region)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        handleMonitoringFailure(region: region, error: error)
    }
}
```

### Anti-Patterns to Avoid

- **Deep inheritance hierarchies:** Don't create BaseProcessor -> HealthKitProcessor -> WorkoutProcessor chains. Use composition.
- **God coordinator:** Don't move all logic to a coordinator that just delegates everything. Keep meaningful logic in extensions.
- **Over-extraction:** Don't create 50 tiny files. Group related functionality. Target 200-400 lines per file.
- **Breaking the public API:** Decomposition should be internal. Public interface stays the same.
- **Circular dependencies between processors:** Each processor should be independent or have clear one-way dependencies.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Code organization | Custom module system | Swift extensions + file splitting | Native language feature, no overhead |
| Dependency injection | Custom DI framework | Constructor injection + protocols | Simple, testable, no external dependencies |
| Event creation | Duplicate code in each processor | Shared EventFactory | Centralize deduplication, property building |
| Settings management | Per-processor settings | HealthKitSettings singleton | Already exists, works well |
| Error handling | Per-processor error types | Shared HealthKitError enum | Already exists, comprehensive |

**Key insight:** The goal is organizational, not architectural. Use Swift's built-in features (extensions, protocols, file separation) rather than introducing new patterns.

## Common Pitfalls

### Pitfall 1: Breaking Access Control

**What goes wrong:** Private properties become inaccessible from extension files.
**Why it happens:** Swift extensions can't add stored properties or access private members from other files.
**How to avoid:** Use `internal` instead of `private` for properties that extensions need. Or use `fileprivate` if extension is in same file.
**Warning signs:** "Cannot find X in scope" errors when splitting into files.

```swift
// WRONG: private prevents access from extension files
class HealthKitService {
    private var observerQueries: [HealthDataCategory: HKObserverQuery] = [:]  // Can't access from other files
}

// RIGHT: internal allows access from extension files in same module
class HealthKitService {
    internal var observerQueries: [HealthDataCategory: HKObserverQuery] = [:]  // Accessible from extensions
}
```

### Pitfall 2: Extension File Import Issues

**What goes wrong:** Extension file can't find types it needs.
**Why it happens:** Missing imports in extension file.
**How to avoid:** Each extension file needs its own imports (Foundation, HealthKit, SwiftData, etc.).
**Warning signs:** "Cannot find type X in scope" in extension files.

### Pitfall 3: MARK Comment Pollution

**What goes wrong:** Too many MARK comments make navigation harder, not easier.
**Why it happens:** Over-segmenting code that's already in a focused file.
**How to avoid:** One MARK section per major responsibility in a file. Trust file names for top-level organization.
**Warning signs:** 10+ MARK sections in a 200-line file.

### Pitfall 4: Testing Regression

**What goes wrong:** Tests break after refactoring.
**Why it happens:** Changed internal method signatures, moved code without updating tests.
**How to avoid:** Refactor in small, testable increments. Keep public API stable. Run tests after each file split.
**Warning signs:** Test failures referencing moved methods.

### Pitfall 5: MainActor Isolation Confusion

**What goes wrong:** @MainActor methods in extensions behave unexpectedly.
**Why it happens:** @Observable class has implicit MainActor isolation; extensions must respect this.
**How to avoid:** Mark extension methods with @MainActor when they modify observable state.
**Warning signs:** "Call to main actor-isolated method in a synchronous non-isolated context" errors.

```swift
// The main type uses @Observable (implicitly MainActor)
@Observable
class HealthKitService: NSObject { ... }

// Extensions that modify state need @MainActor
extension HealthKitService {
    @MainActor
    func handleNewSamples(for category: HealthDataCategory) async {
        // Safe to modify observable properties
    }
}
```

## Code Examples

Verified patterns based on existing codebase and Swift best practices:

### Existing Good Pattern: Separate Settings Class

```swift
// Source: apps/ios/trendy/Services/HealthKitSettings.swift
// This pattern is already well-implemented in the codebase

@Observable
final class HealthKitSettings {
    static let shared = HealthKitSettings()

    // Clear responsibility: just settings management
    var enabledCategories: Set<HealthDataCategory> { ... }
    func isEnabled(_ category: HealthDataCategory) -> Bool { ... }
    func setEnabled(_ category: HealthDataCategory, enabled: Bool) { ... }
}
```

### Existing Good Pattern: Separate Error Types

```swift
// Source: apps/ios/trendy/Services/HealthKitError.swift
// This pattern is already well-implemented

enum HealthKitError: LocalizedError {
    case authorizationFailed(Error)
    case backgroundDeliveryFailed(String, Error)
    case eventSaveFailed(Error)
    case eventLookupFailed(Error)
    case eventUpdateFailed(Error)

    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}
```

### New Pattern: Event Factory

```swift
// HealthKitEventFactory.swift
struct HealthKitEventFactory {
    private let modelContext: ModelContext
    private let eventStore: EventStore

    /// Create an event, handling deduplication and sync
    @MainActor
    func createEvent(
        eventType: EventType,
        category: HealthDataCategory,
        timestamp: Date,
        endDate: Date?,
        notes: String,
        properties: [String: PropertyValue],
        healthKitSampleId: String,
        isAllDay: Bool = false,
        skipSync: Bool = false
    ) async throws -> Event {
        // Check database-level duplicate
        if try await eventExistsWithHealthKitSampleId(healthKitSampleId) {
            throw HealthKitError.duplicateEvent(healthKitSampleId)
        }

        let event = Event(
            timestamp: timestamp,
            eventType: eventType,
            notes: notes,
            sourceType: .healthKit,
            isAllDay: isAllDay,
            endDate: endDate,
            healthKitSampleId: healthKitSampleId,
            healthKitCategory: category.rawValue,
            properties: properties
        )

        modelContext.insert(event)
        try modelContext.save()

        if !skipSync {
            await eventStore.syncEventToBackend(event)
        }

        return event
    }
}
```

### New Pattern: Authorization Extension

```swift
// GeofenceManager+Authorization.swift
extension GeofenceManager {
    // MARK: - Authorization

    /// Request "When In Use" location permission
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request "Always" location permission (required for background geofence monitoring)
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Check if we have sufficient authorization for geofencing
    var hasGeofencingAuthorization: Bool {
        switch authorizationStatus {
        case .authorizedAlways:
            return true
        default:
            return false
        }
    }

    /// Request geofencing authorization using the proper two-step flow
    @discardableResult
    func requestGeofencingAuthorization() -> Bool {
        switch authorizationStatus {
        case .notDetermined:
            pendingAlwaysAuthorizationRequest = true
            locationManager.requestWhenInUseAuthorization()
            return false

        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
            return false

        case .denied, .restricted:
            return true  // Needs settings redirect

        case .authorizedAlways:
            return false

        @unknown default:
            return false
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Monolithic service classes | Extension-based file splitting | Swift 2+ (2015) | Industry standard, no recent changes |
| Deep class hierarchies | Protocol composition | Swift 2 "Protocol-Oriented Programming" | Fundamental Swift paradigm |
| #pragma mark | // MARK: | Swift 1 | Better Xcode integration |

**Key insight:** Swift's approach to code organization hasn't changed significantly. Extensions and protocols have been the recommended approach since Swift 2 (2015). This is a mature, stable pattern.

## Open Questions

1. **Processor vs Extension approach for HealthKit categories**
   - What we know: Both approaches work; processors are more testable, extensions are simpler.
   - What's unclear: Whether testability benefit justifies additional types.
   - Recommendation: Start with extensions, extract to processors only if testing requires it.

2. **Optimal file size**
   - What we know: Industry consensus is 200-500 lines per file.
   - What's unclear: Exact threshold for this codebase.
   - Recommendation: Target <400 lines per file, allow up to 500 for cohesive logic.

## Sources

### Primary (HIGH confidence)

- [Swift by Sundell: Structuring Swift code](https://www.swiftbysundell.com/articles/structuring-swift-code/) - Comprehensive organization guide
- [Google Swift Style Guide](https://google.github.io/swift/) - Industry-standard conventions
- [Apple Developer Documentation: Extensions](https://developer.apple.com/documentation/swift/extension) - Official reference

### Secondary (MEDIUM confidence)

- [Protocol-Oriented Programming in Swift](https://medium.com/@priyans05/protocol-oriented-programming-in-swift-design-patterns-and-best-practices-70b2ee030471) - POP best practices
- [Swift Forums: Organizing code by splitting files](https://forums.swift.org/t/what-is-the-official-ruling-on-organizing-code-by-splitting-large-files-into-extensions/12337) - Community discussion
- [Xcode Refactoring Options](https://www.avanderlee.com/swift/xcode-refactoring/) - Practical refactoring guide

### Tertiary (LOW confidence)

- Various Medium articles on Swift extensions - General patterns

## Metadata

**Confidence breakdown:**
- Extension-based splitting: HIGH - Native Swift feature, extensively used in codebase
- File naming conventions: HIGH - Industry standard `Type+Concern.swift`
- Processor extraction: MEDIUM - Depends on testing requirements
- Line count targets: MEDIUM - Based on industry consensus, not hard rules

**Research date:** 2026-01-16
**Valid until:** 2026-07-16 (stable domain, Swift organization patterns rarely change)

## Alignment with Existing Codebase

The codebase already demonstrates good decomposition patterns:

**Already Implemented Well:**
- `HealthKitSettings.swift` - Separate settings management
- `HealthKitError.swift` - Separate error types
- `GeofenceError.swift` - Separate error types
- `SyncEngine.swift` + `LocalStore.swift` - Sync concerns separated
- `HealthDataCategory` enum - Data type definitions

**Gaps to Address:**
1. HealthKitService.swift (2,313 lines) handles: authorization, query management, 6 data type processors, event creation, persistence, debug utilities
2. GeofenceManager.swift (950 lines) handles: authorization, registration, event handling, delegate callbacks, health status, debug utilities
3. Processing logic is duplicated across categories (workout, sleep, steps, etc.)
4. No clear separation between public API and internal implementation

**Constraints from Requirements:**
- "No single file handles more than 2 distinct responsibilities"
- "HealthKitService split into focused modules (<400 lines each)"
- "GeofenceManager has separate concerns (auth, registration, event handling)"
- Keep client thin - processing logic can be simplified
