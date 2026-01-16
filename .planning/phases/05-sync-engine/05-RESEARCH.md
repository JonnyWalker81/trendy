# Phase 5: Sync Engine - Research

**Researched:** 2026-01-16
**Domain:** SwiftData offline-first sync with backend API
**Confidence:** HIGH

## Summary

The Trendy iOS app already has a solid sync foundation. The existing `SyncEngine.swift` (1,264 lines) implements a Swift actor pattern with cursor-based incremental pull, mutation queue (PendingMutation model), circuit breaker for rate limits, and idempotency via client-generated UUIDv7 IDs. The `EventStore` uses `NWPathMonitor` for network state and triggers sync on network restoration.

The research validates that the current architecture follows SwiftData best practices for 2025. The Swift actor pattern provides the serial execution guarantees that `@ModelActor` would provide, but the current implementation manually creates `ModelContext` instances from the shared `ModelContainer`. This is the correct pattern. The key gap is that **the current SyncEngine creates fresh ModelContext instances per-operation**, which is actually the recommended pattern for background sync actors.

**Primary recommendation:** The existing architecture is sound. Focus Phase 5 on reliability hardening, not architectural overhaul: improve error handling, add better state visibility, ensure mutations survive app crashes, and add integration tests.

## Standard Stack

The established libraries/tools for this domain:

### Core (Already in Use)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+ | Local persistence | Apple's modern persistence framework, replaces Core Data |
| Swift Actors | Swift 5.5+ | Concurrency safety | Serial execution for thread-safe data access |
| NWPathMonitor | iOS 12+ | Network monitoring | Apple's official Network framework, replaces Reachability |
| URLSession | iOS 7+ | HTTP networking | Standard, no third-party needed |

### Supporting (Already in Use)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UUIDv7 | Custom impl | Client-side ID generation | All entity creation - already implemented in Trendy |
| JSONEncoder/Decoder | Foundation | Payload serialization | Mutation payloads |

### Not Needed
| Library | Why Not |
|---------|---------|
| Alamofire | URLSession is sufficient, already working |
| Reachability | NWPathMonitor is Apple's modern replacement |
| Core Data | SwiftData is the modern replacement (already using) |
| Third-party sync libraries | Architecture principle: keep client thin, server does heavy lifting |

**Installation:** No new dependencies needed. The current stack is correct.

## Architecture Patterns

### Current Project Structure (Already Correct)
```
apps/ios/trendy/
├── Models/
│   ├── Event.swift              # @Model with UUIDv7 id, syncStatus
│   ├── EventType.swift          # @Model with UUIDv7 id, syncStatus
│   ├── Geofence.swift           # @Model with UUIDv7 id, syncStatus
│   ├── PendingMutation.swift    # @Model for mutation queue
│   └── SyncStatus.swift         # enum: pending/synced/failed
├── Services/
│   └── Sync/
│       ├── SyncEngine.swift     # Swift actor, cursor-based pull
│       ├── LocalStore.swift     # SwiftData utilities (upsert, delete)
│       └── SyncableEntity.swift # Protocol for syncable entities
└── ViewModels/
    └── EventStore.swift         # @MainActor, NWPathMonitor, UI state
```

### Pattern 1: Swift Actor for Sync Engine (Current - Correct)
**What:** Use a Swift `actor` to serialize all sync operations
**When to use:** Background sync operations that mutate SwiftData
**Why correct:** The existing `actor SyncEngine` provides serial execution equivalent to `@ModelActor` but with manual ModelContext creation per-operation. This is actually the recommended pattern.

```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift (current implementation)
actor SyncEngine {
    private let apiClient: APIClient
    private let modelContainer: ModelContainer

    // Creates fresh context per operation - CORRECT PATTERN
    private func flushPendingMutations() async throws {
        let context = ModelContext(modelContainer)
        let localStore = LocalStore(modelContext: context)
        // ... operations
        try context.save()
    }
}
```

### Pattern 2: PersistentIdentifier for Cross-Actor Communication
**What:** Pass `PersistentIdentifier` (not model objects) between actors
**When to use:** When SyncEngine needs to communicate entity IDs to MainActor UI
**Source:** [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency)

```swift
// CORRECT: Pass ID, load in receiving context
let entityId = event.id  // String (UUIDv7 in Trendy)
// In another context:
let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == entityId })
let event = try context.fetch(descriptor).first
```

**Note:** Trendy uses String UUIDv7 IDs, not `PersistentIdentifier`. This is fine because:
1. UUIDv7 is stable across contexts (unlike temporary PersistentIdentifier)
2. Same ID on client and server (no reconciliation needed)
3. String is Sendable, safe to pass between actors

### Pattern 3: Network-Triggered Sync (Current - Correct)
**What:** Use NWPathMonitor to detect network changes, auto-sync on restoration
**When to use:** Offline-first apps that need automatic sync
**Source:** [Hacking with Swift](https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor)

```swift
// Source: apps/ios/trendy/ViewModels/EventStore.swift (current implementation)
private func setupNetworkMonitor() {
    monitor.pathUpdateHandler = { [weak self] path in
        Task { @MainActor in
            let wasOffline = !(self?.isOnline ?? false)
            self?.isOnline = (path.status == .satisfied)
            if wasOffline && (self?.isOnline ?? false) {
                await self?.handleNetworkRestored()
            }
        }
    }
    let queue = DispatchQueue(label: "com.trendy.eventstore-network-monitor")
    monitor.start(queue: queue)
}
```

### Pattern 4: Mutation Queue with SwiftData (Current - Correct)
**What:** Persist mutations as SwiftData models, process FIFO
**When to use:** Offline mutations that must survive app restart

```swift
// Source: apps/ios/trendy/Models/PendingMutation.swift (current implementation)
@Model
final class PendingMutation {
    var clientRequestId: String  // Idempotency key
    var entityTypeRaw: String    // event, event_type, geofence
    var operationRaw: String     // create, update, delete
    var entityId: String         // UUIDv7 of entity
    var payload: Data            // JSON-encoded request
    var attempts: Int            // Retry count
}
```

### Anti-Patterns to Avoid
- **Passing @Model objects across actors:** Use ID strings instead, fetch in receiving context
- **Creating ModelContext on MainActor for sync:** Creates UI blocking; use actor with private context
- **Assuming NWPathMonitor is 100% reliable:** Captive portals can fool it; have manual sync fallback
- **Retrying rate-limited requests immediately:** Already handled via circuit breaker in SyncEngine

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Client-side IDs | Timestamp-based custom IDs | UUIDv7 (already implemented) | RFC 9562 compliant, time-ordered, no collision risk |
| Network monitoring | Custom reachability | NWPathMonitor (already using) | Apple's official, handles all edge cases |
| Serial background execution | Manual locks/queues | Swift actor (already using) | Language-level concurrency safety |
| Mutation idempotency | Custom dedup logic | Idempotency-Key header + UUIDv7 | Already implemented correctly |

**Key insight:** The existing Trendy implementation already uses the correct patterns. The risk is over-engineering or replacing working code with "better" alternatives that introduce new bugs.

## Common Pitfalls

### Pitfall 1: SwiftData Relationship Detachment
**What goes wrong:** After sync, `event.eventType` is nil even though the relationship exists
**Why it happens:** SwiftData relationships can become detached when accessed from a different ModelContext
**How to avoid:** Store backup `eventTypeId` field (already done), call `restoreEventTypeRelationships()` after fetch
**Warning signs:** "Unknown" showing instead of event type name in UI

```swift
// Source: apps/ios/trendy/ViewModels/EventStore.swift - current mitigation
private func restoreBrokenRelationshipsInPlace(events: [Event], eventTypes: [EventType]) {
    let eventTypeById = Dictionary(uniqueKeysWithValues: eventTypes.map { ($0.id, $0) })
    for event in events where event.eventType == nil {
        if let eventTypeId = event.eventTypeId,
           let eventType = eventTypeById[eventTypeId] {
            event.eventType = eventType
        }
    }
}
```

### Pitfall 2: Race Condition on Pending Delete
**What goes wrong:** pullChanges resurrects an entity that was locally deleted but not yet synced
**Why it happens:** Change feed has CREATE entry from before user deleted locally
**How to avoid:** Track `pendingDeleteIds` set before flush, skip in applyUpsert (already implemented)
**Warning signs:** Deleted items reappear after sync

### Pitfall 3: Circuit Breaker Not Resetting
**What goes wrong:** After rate limit storm, sync never resumes
**Why it happens:** Backoff multiplier accumulates, user must wait too long
**How to avoid:** Reset circuit breaker state when user clears pending mutations (already implemented)
**Warning signs:** Sync banner shows "Circuit breaker tripped" for extended period

### Pitfall 4: ModelContext Not Saved Before Task Ends
**What goes wrong:** Entities created in background task disappear
**Why it happens:** autosave doesn't fire before task discards context
**How to avoid:** Always call `try context.save()` explicitly after mutations
**Warning signs:** Events created but gone after app restart
**Source:** [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency)

### Pitfall 5: NWPathMonitor Captive Portal False Positive
**What goes wrong:** App thinks it's online but HTTP requests fail
**Why it happens:** Connected to WiFi with captive portal (hotel, airport)
**How to avoid:** Implement health check before sync, handle HTTP errors gracefully
**Warning signs:** Sync starts but all mutations fail with network errors

## Code Examples

Verified patterns from official sources and existing implementation:

### Network Restoration Trigger
```swift
// Source: apps/ios/trendy/ViewModels/EventStore.swift
monitor.pathUpdateHandler = { [weak self] path in
    Task { @MainActor in
        let wasOffline = !(self?.isOnline ?? false)
        self?.isOnline = (path.status == .satisfied)
        if wasOffline && (self?.isOnline ?? false) {
            await self?.handleNetworkRestored()
        }
    }
}
```

### Mutation Queue with Idempotency
```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift
func queueMutation(entityType: MutationEntityType, operation: MutationOperation,
                   entityId: String, payload: Data) async throws {
    let context = ModelContext(modelContainer)
    let mutation = PendingMutation(
        entityType: entityType,
        operation: operation,
        entityId: entityId,
        payload: payload
    )
    context.insert(mutation)
    try context.save()
    await updatePendingCount()
}
```

### Exponential Backoff with Circuit Breaker
```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift
private func tripCircuitBreaker() {
    let backoffDuration = min(rateLimitBaseBackoff * rateLimitBackoffMultiplier, rateLimitMaxBackoff)
    rateLimitBackoffUntil = Date().addingTimeInterval(backoffDuration)
    rateLimitBackoffMultiplier = min(rateLimitBackoffMultiplier * 2.0, 10.0)
}
```

### Observable State from Actor to MainActor
```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift
actor SyncEngine {
    @MainActor public private(set) var state: SyncState = .idle
    @MainActor public private(set) var pendingCount: Int = 0

    @MainActor
    private func updateState(_ newState: SyncState) {
        state = newState
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Core Data + NSManagedObjectContext | SwiftData + @Model | WWDC 2023 | Simpler API, better Swift integration |
| Reachability libraries | NWPathMonitor | iOS 12 (2018) | Official Apple API, no dependency |
| DispatchQueue for serial work | Swift actors | Swift 5.5 (2021) | Language-level safety |
| Server-generated IDs | Client-generated UUIDv7 | RFC 9562 (2024) | Offline-first, no reconciliation |

**Current in 2025:**
- `@ModelActor` macro (WWDC 2023) - Trendy uses equivalent manual actor pattern
- SwiftData automatic merging across contexts - Trendy relies on explicit save/fetch
- iOS 17+ required for SwiftData - Trendy already targets iOS 17+

**Deprecated/outdated:**
- `NSPersistentContainer.performBackgroundTask` - replaced by ModelActor/actors
- Reachability third-party libraries - NWPathMonitor is the standard
- `ObservableObject` for view models - `@Observable` macro is current (Trendy uses `@Observable`)

## Open Questions

Things that couldn't be fully resolved:

1. **BGTaskScheduler for Offline Sync**
   - What we know: BGAppRefreshTask provides ~30 seconds, BGProcessingTask longer but requires charging
   - What's unclear: Whether iOS reliably schedules background sync tasks when offline changes exist
   - Recommendation: Implement as enhancement (v2), primary trigger should remain network restoration
   - Source: [BGTaskScheduler docs note limited execution time](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)

2. **Conflict Resolution UX**
   - What we know: Current implementation is LWW (last-write-wins) on server
   - What's unclear: How to surface conflicts to user per REQUIREMENTS.md ("no silent resolution")
   - Recommendation: Defer to Phase 7 (UX) - SYNC-03 says server handles this

3. **Widget Extension Sync**
   - What we know: Widget creates events with `syncStatus = .pending`, main app queues mutations
   - What's unclear: Whether current Darwin notification + mutation queue is reliable
   - Recommendation: Add integration test in Phase 5 to verify widget-created events sync

## Sources

### Primary (HIGH confidence)
- [Hacking with Swift - SwiftData Concurrency](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency) - ModelContainer sendability, PersistentIdentifier patterns
- [FatBobMan - Concurrent Programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/) - @ModelActor deep dive, Task.detached patterns
- [UseYourLoaf - SwiftData Background Tasks](https://useyourloaf.com/blog/swiftdata-background-tasks/) - ModelActor macro expansion, background patterns
- [Hacking with Swift - NWPathMonitor](https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor) - Network monitoring setup

### Secondary (MEDIUM confidence)
- [BrightDigit - ModelActor Tutorial](https://brightdigit.com/tutorials/swiftdata-modelactor/) - DefaultSerialModelExecutor details
- [Medium - Offline First SwiftData](https://medium.com/@ashitranpura27/offline-first-swiftui-with-swiftdata-clean-fast-and-sync-ready-9a4faefdeedb) - 2025 architecture patterns

### Tertiary (LOW confidence - needs validation)
- Various Medium articles on LWW conflict resolution - theory sound but implementation varies
- BGTaskScheduler reliability claims - needs real device testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Current implementation matches 2025 best practices
- Architecture: HIGH - Actor pattern, NWPathMonitor, mutation queue all verified
- Pitfalls: HIGH - Documented from actual bugs fixed in codebase (relationship detachment, pending deletes)
- Background sync (BGTask): MEDIUM - Apple docs confirm limitations, but real-world reliability unclear

**Research date:** 2026-01-16
**Valid until:** 2026-04-16 (SwiftData is stable, unlikely to change significantly)

---

## Key Recommendation for Planning

The existing SyncEngine implementation is architecturally sound. Phase 5 should focus on:

1. **Reliability Testing** - Integration tests for mutation queue, network restoration, widget sync
2. **State Visibility** - Better UI for pending count, last sync time (SYNC-04)
3. **Error Handling** - Ensure all sync errors are surfaced, not swallowed
4. **Edge Cases** - Captive portal detection, mutation survival across crashes
5. **Code Cleanup** - Remove deprecated QueuedOperation model, consolidate on PendingMutation

Do NOT:
- Replace actor with @ModelActor (equivalent, adds complexity)
- Add third-party sync libraries (keeps client thin)
- Implement complex conflict resolution on client (server handles this)
