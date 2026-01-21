# Stack Research: SyncEngine Testing & Quality

**Project:** Trendy iOS SyncEngine
**Researched:** 2026-01-21
**Overall confidence:** HIGH

## Executive Summary

The Trendy iOS app already uses Swift Testing framework (introduced with Xcode 16) for unit tests, providing a modern foundation for testing the SyncEngine actor. This research identifies specific additions needed for comprehensive testing, dependency injection, and metrics collection without introducing heavyweight dependencies.

**Key Finding:** Use protocol-based dependency injection with actor-compatible initialization, Swift Testing's native async/await support, and Apple's native telemetry (os.signpost + MetricKit) rather than third-party frameworks.

## Recommended Stack Additions

### Testing Framework

| Component | Choice | Version | Why |
|-----------|--------|---------|-----|
| **Primary Framework** | Swift Testing | Built-in (Xcode 16+) | Already in use, native async/await support, parallel execution |
| **Fallback** | XCTest | Built-in | For UI tests and performance tests (Swift Testing doesn't support these yet) |
| **No Addition Needed** | - | - | Project already uses Swift Testing |

**Rationale:**
- Swift Testing ships with Xcode 16 and is **already used** in the project (see `trendyTests/trendyTests.swift`)
- Native support for async test methods: `@Test func syncOperation() async throws { }`
- `#expect` macro provides better failure messages than XCTest's 40+ assertion functions
- Parallel execution by default speeds up test runs
- Works seamlessly with actors and Swift concurrency

**iOS Version Support:**
- Swift Testing: Xcode 16+ (Swift 6 toolchain)
- Current project target: iOS 18.5 (deployment target per project.pbxproj)
- **No compatibility issues**

**Migration Status:**
- ✅ Framework already installed
- ✅ Test files already using `import Testing` and `@Test` macro
- ✅ Test fixtures already exist in `TestSupport.swift`

### Dependency Injection for Swift Actors

| Approach | Recommendation | Use Case |
|----------|----------------|----------|
| **Protocol + Init Injection** | ✅ PRIMARY | SyncEngine dependencies (APIClient, LocalStore) |
| **Property Injection** | ❌ AVOID | Breaks actor isolation, causes data races |
| **DI Frameworks** | ❌ AVOID | Overkill for actor-based code, complexity without benefit |

**Recommended Pattern:**

```swift
// 1. Define protocol for each dependency
protocol SyncAPIClient {
    func pushEvent(_ event: Event) async throws -> APIEvent
    func pullChanges(since cursor: Int64) async throws -> ChangeFeed
}

protocol LocalDataStore {
    func fetchPendingMutations() async throws -> [PendingMutation]
    func saveSyncCursor(_ cursor: Int64) async throws
}

// 2. Actor accepts protocols via initializer
actor SyncEngine {
    private let apiClient: SyncAPIClient
    private let dataStore: LocalDataStore

    init(apiClient: SyncAPIClient, dataStore: LocalDataStore) {
        self.apiClient = apiClient
        self.dataStore = dataStore
    }
}

// 3. Production uses concrete implementations
let syncEngine = SyncEngine(
    apiClient: APIClient(config: config),
    dataStore: SwiftDataStore(container: container)
)

// 4. Tests use mocks
let syncEngine = SyncEngine(
    apiClient: MockAPIClient(),
    dataStore: MockDataStore()
)
```

**Why This Pattern:**
- ✅ **Actor-safe:** All dependencies injected before actor starts, no isolation violations
- ✅ **Testable:** Easy to swap real dependencies for mocks
- ✅ **Type-safe:** Protocols enforce contracts at compile time
- ✅ **No magic:** No reflection, no runtime dependency resolution
- ✅ **Swift-native:** Uses language features, no third-party frameworks

**Critical Actor-Specific Consideration:**

From research: "When applied to Actors, any protocol/extension implementation will behave as if it was executed outside of the Actor's context." ([Source](https://lucasvandongen.dev/swift_actors_and_protocol_extensions.php))

**Solution:** Use protocols for dependency **types**, but ensure protocol methods are called **within** the actor's isolated context:

```swift
// ✅ CORRECT: Protocol method called from actor-isolated method
actor SyncEngine {
    private let apiClient: SyncAPIClient

    func sync() async throws {
        // This runs in actor's context, apiClient call is awaited properly
        let changes = try await apiClient.pullChanges(since: cursor)
    }
}

// ❌ WRONG: Protocol extension default implementation
protocol SyncAPIClient {
    func pullChanges(since: Int64) async throws -> ChangeFeed
}

extension SyncAPIClient {
    // This would run outside actor context!
    func pullChangesWithRetry(since: Int64) async throws -> ChangeFeed {
        // DON'T DO THIS
    }
}
```

### Mocking Strategy for Async Actors

**Pattern: Actor-Isolated Mock Implementations**

```swift
// Mock conforms to protocol, can be used in place of real implementation
actor MockAPIClient: SyncAPIClient {
    // Configurable responses for testing different scenarios
    var pushEventResponse: Result<APIEvent, Error> = .success(APIEvent(...))
    var pullChangesResponse: Result<ChangeFeed, Error> = .success(ChangeFeed(...))

    // Track calls for verification
    private(set) var pushEventCalls: [(Event)] = []
    private(set) var pullChangesCalls: [(Int64)] = []

    func pushEvent(_ event: Event) async throws -> APIEvent {
        pushEventCalls.append(event)
        return try pushEventResponse.get()
    }

    func pullChanges(since cursor: Int64) async throws -> ChangeFeed {
        pullChangesCalls.append(cursor)
        return try pullChangesResponse.get()
    }

    // Test helpers (actor-isolated)
    func assertPushEventCalled(times: Int) async -> Bool {
        pushEventCalls.count == times
    }

    func reset() async {
        pushEventCalls.removeAll()
        pullChangesCalls.removeAll()
    }
}
```

**Testing Pattern:**

```swift
@Test func circuitBreakerTripsAfterThreeRateLimits() async throws {
    // Arrange
    let mockAPI = MockAPIClient()
    await mockAPI.setResponse(.failure(APIError.rateLimited(retryAfter: 30)))

    let syncEngine = SyncEngine(apiClient: mockAPI, dataStore: MockDataStore())

    // Act - attempt sync 3 times
    for _ in 0..<3 {
        _ = try? await syncEngine.sync()
    }

    // Assert
    let state = await syncEngine.state
    #expect(state == .rateLimited(retryAfter: 30.0, pending: 0))

    let callCount = await mockAPI.pushEventCalls.count
    #expect(callCount == 3)
}
```

**Why Actor-Based Mocks:**
- ✅ **Thread-safe:** Actor isolation prevents data races in test mocks
- ✅ **Realistic:** Mirrors real async behavior of network calls
- ✅ **Verifiable:** Can track calls and state safely across async boundaries
- ✅ **Simple:** No mocking framework needed, just protocols + implementations

**Alternative (Simple Structs for Stateless Mocks):**

For stateless dependencies, non-actor structs work fine:

```swift
struct MockSyncHistoryStore: SyncHistoryStore {
    var eventsToReturn: [ChangeLogEntry] = []

    func getChangesSince(_ cursor: Int64) async throws -> [ChangeLogEntry] {
        return eventsToReturn
    }
}
```

### Metrics Collection

| Approach | Recommendation | Use Case | iOS Support |
|----------|----------------|----------|-------------|
| **os.signpost** | ✅ PRIMARY | Development profiling, duration tracking | iOS 12+ (OSSignposter: iOS 15+) |
| **MetricKit** | ✅ SECONDARY | Production metrics, aggregated telemetry | iOS 13+ |
| **Custom Counters** | ✅ SUPPLEMENT | Sync-specific metrics (success rate, retry count) | All versions |
| **swift-metrics** | ❌ AVOID | Server-side package, not designed for iOS | N/A |
| **Third-party APM** | ⚠️ DEFER | Already using PostHog, evaluate if sufficient | N/A |

#### os.signpost for Development

**Purpose:** Measure sync operation durations during development and profiling.

**Implementation:**

```swift
import os.signpost

actor SyncEngine {
    private let signposter = OSSignposter(subsystem: "com.trendy.sync", category: "SyncEngine")

    func sync() async throws {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("sync", id: signpostID)

        defer {
            signposter.endInterval("sync", state)
        }

        // Sync logic here
        let pushState = signposter.beginInterval("push", id: signpostID)
        try await pushLocalChanges()
        signposter.endInterval("push", pushState)

        let pullState = signposter.beginInterval("pull", id: signpostID)
        try await pullRemoteChanges()
        signposter.endInterval("pull", pullState)
    }
}
```

**Benefits:**
- ✅ **Low overhead:** Optimized for production use, negligible performance impact
- ✅ **Instruments integration:** View timing data in Xcode Instruments
- ✅ **Hierarchical:** Nest intervals to see push/pull breakdown
- ✅ **Native:** No dependencies, Apple-supported

**Viewing Metrics:**
1. Run app in Xcode
2. Open Instruments (Product → Profile)
3. Select "os_signpost" template
4. Filter by subsystem: `com.trendy.sync`

#### MetricKit for Production

**Purpose:** Aggregate real-world performance data from users' devices.

**Implementation:**

```swift
import MetricKit

class SyncMetricsManager: NSObject, MXMetricManagerSubscriber {
    override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // Extract app launch time, hang rate, etc.
            if let appTime = payload.applicationTimeMetrics {
                // Send to analytics backend
                Analytics.log("app_foreground_time", value: appTime.cumulativeForegroundTime)
            }

            // Custom signpost metrics (if using signposts)
            if let signpostMetrics = payload.signpostMetrics {
                // Process sync duration metrics
            }
        }
    }
}
```

**Benefits:**
- ✅ **Production data:** Real user performance, not synthetic tests
- ✅ **Aggregated:** Daily reports, not per-event overhead
- ✅ **Privacy-safe:** Apple aggregates data before delivery
- ✅ **Crash diagnostics:** Includes hang reports and crash logs

**Limitation:**
- ⚠️ Data delivered daily, not real-time
- ⚠️ Requires 1+ days of user activity to generate reports

#### Custom Metrics for Sync Operations

**Purpose:** Track sync-specific success/failure rates and operation counts.

**Implementation:**

```swift
actor SyncEngine {
    // Metrics counters
    private var syncAttempts = 0
    private var syncSuccesses = 0
    private var syncFailures = 0
    private var rateLimitHits = 0

    func sync() async throws {
        syncAttempts += 1

        do {
            try await performSync()
            syncSuccesses += 1
        } catch APIError.rateLimited {
            rateLimitHits += 1
            syncFailures += 1
            throw APIError.rateLimited(retryAfter: 30)
        } catch {
            syncFailures += 1
            throw error
        }
    }

    // Expose metrics for logging/telemetry
    func getMetrics() async -> SyncMetrics {
        SyncMetrics(
            attempts: syncAttempts,
            successes: syncSuccesses,
            failures: syncFailures,
            successRate: Double(syncSuccesses) / Double(max(syncAttempts, 1)),
            rateLimitHits: rateLimitHits
        )
    }
}

struct SyncMetrics: Codable {
    let attempts: Int
    let successes: Int
    let failures: Int
    let successRate: Double
    let rateLimitHits: Int
}
```

**Integration with PostHog:**

```swift
// Periodically (e.g., daily) send metrics to PostHog
let metrics = await syncEngine.getMetrics()
PostHogSDK.shared.capture("sync_metrics", properties: [
    "attempts": metrics.attempts,
    "success_rate": metrics.successRate,
    "rate_limit_hits": metrics.rateLimitHits
])
```

**Benefits:**
- ✅ **Custom:** Track exactly what matters for sync reliability
- ✅ **Lightweight:** Simple counters, no framework overhead
- ✅ **Actionable:** Surface issues like high failure rates or rate limiting

### Documentation Tooling

**Current Codebase:**
- ✅ Uses Swift documentation comments (`///`)
- ✅ Structured logging with custom `Log.sync` categories
- ✅ Planning docs in `.planning/` directory use Markdown

**Recommendation: NO NEW TOOLING**

| Tool | Status | Rationale |
|------|--------|-----------|
| **Org-mode** | ❌ NOT RECOMMENDED | Team uses Markdown, no Emacs requirement |
| **Mermaid** | ✅ ALREADY AVAILABLE | GitHub renders Mermaid in Markdown |
| **Swift DocC** | ⚠️ OPTIONAL | For API documentation export |

**Use Markdown + Mermaid:**

```markdown
## SyncEngine State Machine

\`\`\`mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Syncing: sync() called
    Syncing --> Pulling: Push complete
    Pulling --> Idle: Pull complete
    Syncing --> RateLimited: 429 error (3x)
    RateLimited --> Idle: Backoff expires
    Syncing --> Error: Other error
    Error --> Idle: User retries
\`\`\`
```

**Benefits:**
- ✅ **Zero setup:** GitHub/GitLab render Mermaid automatically
- ✅ **Team familiarity:** Everyone knows Markdown
- ✅ **Version control:** Diagrams stored as text, diffable
- ✅ **No tooling:** No Emacs, no external diagram tools

**For Technical Docs:**

Place in `.planning/phases/sync-engine/ARCHITECTURE.md`:
- Mermaid diagrams for state machines, sequence diagrams
- Code examples with syntax highlighting
- Decision records (why X over Y)

## Integration with Existing Stack

### Current Dependencies (No Changes Needed)

| Dependency | Purpose | Compatibility |
|------------|---------|---------------|
| SwiftData | Local persistence | ✅ Can be mocked via protocol |
| Supabase Swift SDK | Authentication | ✅ Can be mocked via protocol |
| os.Logger | Structured logging | ✅ Works in tests, actors |

### Test Target Setup

**Already Configured:**
- ✅ `trendyTests` target exists
- ✅ Uses Swift Testing framework
- ✅ Has `TestSupport.swift` with fixtures

**Addition Needed:**

Add mock protocols to `trendyTests/Mocks/`:

```
trendyTests/
├── Mocks/
│   ├── MockAPIClient.swift      # NEW
│   ├── MockLocalDataStore.swift # NEW
│   └── MockSyncHistory.swift    # NEW
├── SyncEngineTests.swift        # NEW
├── TestSupport.swift            # EXISTS
└── trendyTests.swift            # EXISTS
```

### Production Code Changes

**Minimal refactoring required:**

1. Extract protocols for dependencies:
   - `protocol SyncAPIClient` from `APIClient`
   - `protocol LocalDataStore` from SwiftData operations
   - `protocol SyncHistoryStore` from existing implementation

2. Change SyncEngine init:
   ```swift
   // Before
   init(apiClient: APIClient, modelContainer: ModelContainer)

   // After
   init(apiClient: SyncAPIClient, dataStore: LocalDataStore)
   ```

3. Update call sites (minimal):
   ```swift
   // Production code wraps concrete types
   let syncEngine = SyncEngine(
       apiClient: apiClient as SyncAPIClient,
       dataStore: SwiftDataStore(container: container)
   )
   ```

**Estimated effort:** 2-4 hours

## What NOT to Add

### ❌ Dependency Injection Frameworks

**Avoid:** Swinject, Needle, Factory, etc.

**Why:**
- Actor-based DI is simple with protocols + init injection
- Frameworks add complexity, learning curve, maintenance burden
- Protocol-oriented approach is more Swift-native
- Testing doesn't need runtime DI container

**Exception:** If project grows to 50+ injectable dependencies, revisit. Current scale (3-5 dependencies) doesn't justify framework.

### ❌ Mocking Frameworks

**Avoid:** Mockingbird, Mockolo, Cuckoo, etc.

**Why:**
- Swift protocols make manual mocks trivial
- Code generation adds build complexity
- Manual mocks are easier to debug and understand
- Actor-based mocks need manual implementation anyway (frameworks don't handle actors well)

**Exception:** If maintaining 20+ mock implementations becomes tedious, revisit. Current need (3-5 mocks) is manageable manually.

### ❌ swift-metrics Package

**Avoid:** Apple's swift-metrics from Server ecosystem

**Why:**
- Designed for server-side Swift (Linux, Vapor, etc.)
- iOS has native telemetry (os.signpost, MetricKit)
- Adding server package increases app size unnecessarily
- No iOS-specific integrations (Instruments, Xcode)

**Use instead:** os.signpost (dev) + MetricKit (prod) + custom counters

### ❌ Third-Party APM (New Additions)

**Avoid:** Adding Sentry, Datadog, New Relic for sync metrics

**Why:**
- PostHog already integrated (per project.pbxproj dependencies)
- Each APM adds SDK overhead (binary size, network usage)
- Custom metrics + PostHog sufficient for sync telemetry
- MetricKit provides Apple-native production data

**Use instead:** Extend PostHog usage with custom sync events

### ❌ XCTest for Unit Tests

**Avoid:** Writing new tests with XCTest

**Why:**
- Swift Testing already in use and superior for async code
- `#expect` has better failure messages than `XCTAssert*`
- Parallel execution by default (faster CI/CD)
- Incremental migration strategy allows coexistence

**Keep XCTest for:**
- ✅ UI tests (Swift Testing doesn't support UI testing yet)
- ✅ Performance tests (Swift Testing lacks performance APIs)
- ✅ Existing tests (migrate incrementally, don't rewrite working tests)

## Installation & Setup

### 1. Testing Framework

**Already installed.** Swift Testing ships with Xcode 16.

Verify:
```bash
# In Xcode
# File → New → Test → Choose "Swift Testing" template
```

### 2. Dependency Injection Protocols

**Create protocol definitions:**

```bash
# Add to project
touch apps/ios/trendy/Services/Protocols/SyncAPIClient.swift
touch apps/ios/trendy/Services/Protocols/LocalDataStore.swift
```

### 3. Test Mocks

**Create mock implementations:**

```bash
mkdir -p apps/ios/trendyTests/Mocks
touch apps/ios/trendyTests/Mocks/MockAPIClient.swift
touch apps/ios/trendyTests/Mocks/MockLocalDataStore.swift
```

### 4. Metrics (Signposts)

**Add to SyncEngine:**

```swift
import os.signpost

actor SyncEngine {
    private let signposter = OSSignposter(
        subsystem: "com.trendy.sync",
        category: "SyncEngine"
    )

    // ... existing code
}
```

**No package installation needed.** os.signpost is part of the OS framework.

### 5. MetricKit (Production Metrics)

**Create metrics subscriber:**

```bash
touch apps/ios/trendy/Services/SyncMetricsManager.swift
```

**Register in AppDelegate/App:**

```swift
import MetricKit

@main
struct TrendyApp: App {
    @State private var metricsManager = SyncMetricsManager()

    var body: some Scene {
        // ... existing code
    }
}
```

**No package installation needed.** MetricKit is part of iOS SDK.

## Validation Checklist

- [x] Testing framework supports async actors (Swift Testing ✅)
- [x] DI approach works with actor isolation (Protocol + init ✅)
- [x] Mocking strategy preserves thread safety (Actor-based mocks ✅)
- [x] Metrics have negligible performance impact (os.signpost ✅)
- [x] No heavyweight dependencies added (All native Apple frameworks ✅)
- [x] Compatible with iOS 18.5 deployment target (All APIs available ✅)
- [x] Works with existing Xcode 16 toolchain (No new Xcode version needed ✅)
- [x] Documentation tools already available (Markdown + Mermaid ✅)

## Sources

### Testing Framework
- [Swift Testing - Xcode - Apple Developer](https://developer.apple.com/xcode/swift-testing)
- [Hello Swift Testing, Goodbye XCTest | Medium](https://leocoout.medium.com/welcome-swift-testing-goodbye-xctest-7501b7a5b304)
- [Swift Testing vs. XCTest: A Comprehensive Comparison | Infosys](https://blogs.infosys.com/digital-experience/mobility/swift-testing-vs-xctest-a-comprehensive-comparison.html)
- [Unit Testing in Swift (XCTest VS. Swift Testing) | Medium](https://medium.com/@nourhenekrichene_66918/unit-testing-in-swift-xctest-vs-swift-testing-241fb92abe39)
- [Swift Testing basics explained – Donny Wals](https://www.donnywals.com/swift-testing-basics-explained/)
- [Getting started with Swift Testing](https://www.polpiella.dev/swift-testing)
- [swiftlang/swift-testing - GitHub](https://github.com/swiftlang/swift-testing)

### Dependency Injection
- [Dependency Injection in Swift (2025): Clean Architecture, Better Testing | Medium](https://medium.com/@varunbhola1991/dependency-injection-in-swift-2025-clean-architecture-better-testing-7228f971446c)
- [Advanced Dependency Injection on iOS with Swift 5](https://www.vadimbulavin.com/dependency-injection-in-swift/)
- [Dependency Injection in Swift using latest Swift features - SwiftLee](https://www.avanderlee.com/swift/dependency-injection/)
- [Lightweight dependency injection and unit testing using async functions | Swift by Sundell](https://www.swiftbysundell.com/articles/dependency-injection-and-unit-testing-using-async-await/)

### Actor Testing
- [Swift Actor in Unit Tests | Thumbtack Engineering | Medium](https://medium.com/thumbtack-engineering/swift-actor-in-unit-tests-9dc15498b631)
- [Testing Throwing Methods In Swift Actors – SerialCoder.dev](https://serialcoder.dev/text-tutorials/swift-tutorials/testing-throwing-methods-in-swift-actors/)
- [Unit testing async/await Swift code - SwiftLee](https://www.avanderlee.com/concurrency/unit-testing-async-await/)
- [Unit Testing Asynchronous Code in Swift](https://www.vadimbulavin.com/unit-testing-async-code-in-swift/)
- [Unit testing Swift code that uses async/await | Swift by Sundell](https://www.swiftbysundell.com/articles/unit-testing-code-that-uses-async-await/)
- [Unit Testing in Swift 6: Async/Await, Actors, and Modern Concurrency in Practice | Medium](https://medium.com/@mrhotfix/unit-testing-in-swift-6-async-await-actors-and-modern-concurrency-in-practice-5de4282d3fdd)
- [Exploring Actors and Protocol Extensions](https://lucasvandongen.dev/swift_actors_and_protocol_extensions.php)

### Metrics & Telemetry
- [Using Swift Signpost to Measure Performance | Medium](https://medium.com/@jpmtech/using-swift-signpost-to-measure-performance-of-a-specific-function-6779c920d0f4)
- [Measuring performance with os_signpost – Donny Wals](https://www.donnywals.com/measuring-performance-with-os_signpost/)
- [Getting started with signposts | Swift by Sundell](https://www.swiftbysundell.com/wwdc2018/getting-started-with-signposts/)
- [Measuring app performance in Swift | Swift with Majid](https://swiftwithmajid.com/2022/05/04/measuring-app-performance-in-swift/)
- [Monitoring app performance with MetricKit | Swift with Majid](https://swiftwithmajid.com/2025/12/09/monitoring-app-performance-with-metrickit/)
- [Using MetricKit to monitor user data like launch times - SwiftLee](https://www.avanderlee.com/swift/metrickit-launch-time/)
- [Unlocking MetricKit | Simform Engineering | Medium](https://medium.com/simform-engineering/unlocking-metrickit-see-what-your-app-is-really-doing-on-users-devices-1292026bdef0)
- [apple/swift-metrics - GitHub](https://github.com/apple/swift-metrics)

### Documentation
- [ob-mermaid: Generate mermaid diagrams within Emacs org-mode - GitHub](https://github.com/arnm/ob-mermaid)
- [Org Mode + Mermaid - Emacs TIL](https://emacstil.com/til/2021/09/19/org-mermaid/)

---

**Confidence Assessment:**
- Testing framework: HIGH (already in use, verified in codebase)
- DI patterns: HIGH (verified with recent Swift actor documentation)
- Mocking: HIGH (standard patterns, confirmed actor-safe)
- Metrics: HIGH (native Apple frameworks, verified availability)
- Documentation: HIGH (Markdown + Mermaid already supported)
