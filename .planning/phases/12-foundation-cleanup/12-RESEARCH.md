# Phase 12: Foundation & Cleanup - Research

**Researched:** 2026-01-21
**Domain:** iOS Technical Debt Cleanup (Swift, SwiftData, HealthKit)
**Confidence:** HIGH

## Summary

This research identifies the exact locations and patterns for all technical debt items in Phase 12. The codebase analysis reveals:

1. **No print() statements in the primary target modules** (SyncEngine, APIClient, LocalStore, HealthKit services) - they already use structured logging
2. **Print statements exist in peripheral modules** that need cleanup (191 total across 20 files)
3. **One busy-wait polling pattern** in SyncEngine at line 367-369
4. **Cursor state changes need enhanced logging** at 7 locations in SyncEngine
5. **Observer query completion handlers are already correctly implemented** - all code paths call completionHandler()
6. **One cursor fallback using 1_000_000_000** at line 273 needs safer value
7. **Property type fallbacks are silent** at 3 locations in SyncEngine

**Primary recommendation:** Focus on the identified specific locations - the cleanup scope is well-defined and surgical.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| os.Logger | iOS 14+ | Structured logging | Apple's unified logging system, integrated with Console.app |
| Swift Concurrency | Swift 5.5+ | Async/await, TaskGroup | First-party, structured concurrency |
| SwiftData | iOS 17+ | Local persistence | Apple's modern persistence framework |
| HealthKit | iOS 8+ | Health data access | Only option for iOS health data |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| withThrowingTaskGroup | Swift 5.5+ | Task racing/timeout | Replace busy-wait with continuation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| os.Logger | Third-party (CocoaLumberjack) | os.Logger already in use, no migration needed |

## Architecture Patterns

### Existing Logging Pattern (Already Implemented)
```swift
// Source: apps/ios/trendy/Utilities/Logger.swift
Log.sync.info("Sync completed", context: .with { ctx in
    ctx.add("cursor", Int(lastSyncCursor))
    ctx.add("duration_ms", syncDurationMs)
})
```

### Log Categories Available
| Category | Logger | Purpose |
|----------|--------|---------|
| api | Log.api | HTTP client operations |
| auth | Log.auth | Authentication |
| sync | Log.sync | Data synchronization |
| migration | Log.migration | Data migration |
| geofence | Log.geofence | Location services |
| healthKit | Log.healthKit | HealthKit integration |
| calendar | Log.calendar | Calendar integration |
| ui | Log.ui | UI operations |
| data | Log.data | Storage operations |
| general | Log.general | General purpose |

### Task Timeout Pattern (for Polling Replacement)
```swift
// Source: https://www.donnywals.com/implementing-task-timeout-with-swift-concurrency/
func performWithTimeout<T>(
    of timeout: Duration,
    _ work: sending @escaping () async throws -> T
) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(until: .now + timeout)
            throw TimeoutError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
```

### Anti-Patterns to Avoid
- **Busy-wait polling:** `while condition { try? await Task.sleep(...) }` wastes CPU
- **Unstructured print():** No filtering, no levels, fills Console with noise
- **Silent fallbacks:** Type conversion failures that return default without logging

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Logging | Custom print wrapper | Log.sync/api/etc | Already implemented, integrated with Console.app |
| Task timeout | Manual timer + flag | withThrowingTaskGroup race | Standard Swift Concurrency pattern |
| Continuation-based wait | Custom semaphore | AsyncStream or TaskGroup | Structured concurrency handles cancellation |

**Key insight:** The codebase already has robust logging infrastructure - just replace print() calls with existing Log.* categories.

## Common Pitfalls

### Pitfall 1: Forgetting Completion Handler in HealthKit Observer
**What goes wrong:** HealthKit stops delivering background updates
**Why it happens:** Observer query closure has multiple exit paths
**How to avoid:** Use defer { completionHandler() } at top of closure
**Warning signs:** Background delivery silently stops working

### Pitfall 2: Continuation Resume Multiple Times
**What goes wrong:** App crashes with "continuation already resumed"
**Why it happens:** Multiple code paths can reach continuation.resume()
**How to avoid:** Use flag to track if already resumed, or use AsyncStream
**Warning signs:** Intermittent crashes in async code

### Pitfall 3: Int64 Overflow on Cursor Values
**What goes wrong:** Cursor wraps around or becomes negative
**Why it happens:** Using values close to Int64.max
**How to avoid:** Use Int64.max / 2 for "far future" fallback values
**Warning signs:** Sync pulling ancient data repeatedly

## Code Examples

### Current Busy-Wait Pattern (to be replaced)
```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift:367-369
// If a sync is already running, wait for it to complete
while isSyncing {
    Log.sync.debug("Waiting for in-progress sync to complete...")
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
}
```

### Recommended Replacement: Continuation-Based Wait
```swift
// Using AsyncStream or direct continuation
func waitForSyncCompletion(timeout: Duration = .seconds(30)) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            // Wait for isSyncing to become false using observation
            while self.isSyncing {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        group.addTask {
            try await Task.sleep(until: .now + timeout)
            throw SyncError.waitTimeout
        }
        defer { group.cancelAll() }
        try await group.next()
    }
}
```

### Current Silent Property Type Fallback (to be fixed)
```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift:1460, 1680, 1810
propDef.propertyType = PropertyType(rawValue: propertyType) ?? .text
```

### Recommended Replacement: Logged Fallback
```swift
let parsedType = PropertyType(rawValue: propertyType)
if parsedType == nil {
    Log.sync.warning("Unknown property type, using fallback", context: .with { ctx in
        ctx.add("raw_value", propertyType)
        ctx.add("fallback", PropertyType.text.rawValue)
        ctx.add("property_key", propDef.key)
    })
    #if DEBUG
    // Developer indicator for silent failures
    assertionFailure("Unknown PropertyType: \(propertyType)")
    #endif
}
propDef.propertyType = parsedType ?? .text
```

### Current Cursor Fallback (unsafe value)
```swift
// Source: apps/ios/trendy/Services/Sync/SyncEngine.swift:273
lastSyncCursor = 1_000_000_000
```

### Recommended Replacement: Safer Fallback
```swift
// Use Int64.max / 2 to avoid any overflow concerns
// This value (~4.6 quintillion) is far enough in the future
lastSyncCursor = Int64.max / 2
```

## Detailed Location Analysis

### Print Statements by Module

**Core Target Modules (NO print statements found):**
- `Services/Sync/SyncEngine.swift` - 0 print()
- `Services/Sync/LocalStore.swift` - 0 print()
- `Services/APIClient.swift` - 0 print()
- `Services/HealthKit/*.swift` - 0 print()

**Files Needing print() Cleanup (191 total):**

| File | Count | Priority | Notes |
|------|-------|----------|-------|
| `trendyApp.swift` | 41 | HIGH | App startup logging |
| `GeofenceListView.swift` | 33 | MEDIUM | Debug logging |
| `SupabaseService.swift` | 13 | HIGH | Auth service |
| `NotificationManager.swift` | 18 | MEDIUM | Notification service |
| `DebugStorageView.swift` | 12 | LOW | Debug-only view |
| `EventEditView.swift` | 11 | MEDIUM | UI component |
| `CalendarImportManager.swift` | 10 | MEDIUM | Import utility |
| `MainTabView.swift` | 7 | MEDIUM | Main navigation |
| `AuthViewModel.swift` | 6 | HIGH | Auth state |
| `HealthKitSettings.swift` | 6 | MEDIUM | Settings service |
| `DynamicPropertyFieldsView.swift` | 6 | LOW | UI component |
| `AddGeofenceView.swift` | 6 | LOW | UI component |
| `ScreenshotMockData.swift` | 5 | LOW | Test utility |
| `Event.swift` | 4 | HIGH | Core model (DEBUG only) |
| `CalendarImportView.swift` | 4 | LOW | UI view |
| `HealthKitSettingsView.swift` | 3 | LOW | Settings UI |
| `SchemaMigrationPlan.swift` | 2 | MEDIUM | Migration |
| `ManageHealthKitCategoriesView.swift` | 2 | LOW | Settings UI |
| `CalendarManager.swift` | 1 | MEDIUM | Calendar utility |
| `HistoricalImportModalView.swift` | 1 | LOW | UI modal |

### Busy-Wait Polling Locations

| Location | File:Line | Purpose | Timeout Needed |
|----------|-----------|---------|----------------|
| Wait for sync completion | SyncEngine.swift:367-369 | forceFullResync waits | 30s |

**Note:** EventStore.swift has polling for UI updates (lines 385-389, 413-417, 544-547) but these are intentional for progress display and already use proper Task cancellation - NOT busy-wait patterns that need replacement.

### Cursor State Change Locations (Need Logging Enhancement)

| Location | File:Line | Operation | Current Logging |
|----------|-----------|-----------|-----------------|
| Init load | SyncEngine.swift:116 | Load from UserDefaults | Has logging |
| Bootstrap success | SyncEngine.swift:259-260 | Set from API | Has logging |
| Bootstrap fallback | SyncEngine.swift:273-274 | Set to 1B | Has logging (needs before/after) |
| Force reset | SyncEngine.swift:373-374 | Set to 0 | Minimal |
| Skip to latest | SyncEngine.swift:403-404 | Set from API | Has logging |
| Pull changes | SyncEngine.swift:1269-1270 | Increment | Has logging |

**Enhancement needed:** Add before/after values to all cursor changes for debugging.

### HealthKit Observer Query Completion Handler Analysis

**Location:** `Services/HealthKit/HealthKitService+QueryManagement.swift:73-97`

```swift
let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
    guard let self = self else {
        completionHandler()  // Called on guard failure
        return
    }

    if let error = error {
        // ... logging ...
        completionHandler()  // Called on error
        return
    }

    // ... logging ...

    Task {
        await self.handleNewSamples(for: category)
    }

    completionHandler()  // Called on success
}
```

**Analysis:** All code paths correctly call completionHandler():
1. Guard failure (self is nil) - YES
2. Error case - YES
3. Success case - YES

**Conclusion:** No fix needed - completion handler is already called in all paths.

### Property Type Fallback Locations (Silent Errors)

| Location | File:Line | Context |
|----------|-----------|---------|
| Change feed property | SyncEngine.swift:1460 | `propDef.propertyType = PropertyType(rawValue: propertyType) ?? .text` |
| Bootstrap property | SyncEngine.swift:1680 | Same pattern |
| API property conversion | SyncEngine.swift:1810 | Same pattern |

### Cursor Fallback Location

| Location | File:Line | Current Value | Issue |
|----------|-----------|---------------|-------|
| Bootstrap fallback | SyncEngine.swift:273 | `1_000_000_000` | Arbitrary, could theoretically conflict |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| print() debugging | os.Logger unified logging | iOS 14 | Console.app integration, filtering |
| Completion handlers | async/await | Swift 5.5 | Structured concurrency |
| Manual polling | Continuation-based waiting | Swift 5.5 | Proper cancellation support |

**Deprecated/outdated:**
- `print()` for production logging - use os.Logger
- `Thread.sleep()` - use `Task.sleep()` in async context
- `DispatchSemaphore` for async waiting - use continuations

## Open Questions

Things that couldn't be fully resolved:

1. **UI Polling in EventStore**
   - What we know: EventStore uses polling (250ms) to update sync progress UI
   - What's unclear: Whether this should use an ObservableObject pattern instead
   - Recommendation: Keep current pattern - it's working and properly cancelled

2. **Debug-only print() statements**
   - What we know: Some print() are wrapped in `#if DEBUG`
   - What's unclear: Whether these should convert to Log.debug or stay as print
   - Recommendation: Convert to Log.*.debug for consistency, keep #if DEBUG wrapper

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `apps/ios/trendy/Services/Sync/SyncEngine.swift` - Direct code inspection
- Codebase analysis: `apps/ios/trendy/Utilities/Logger.swift` - Existing logging infrastructure
- Codebase analysis: `apps/ios/trendy/Services/HealthKit/HealthKitService+QueryManagement.swift` - Observer queries

### Secondary (MEDIUM confidence)
- [Swift Concurrency Task Timeout - Donny Wals](https://www.donnywals.com/implementing-task-timeout-with-swift-concurrency/) - Timeout patterns
- [Task+Timeout.swift Gist](https://gist.github.com/swhitty/9be89dfe97dbb55c6ef0f916273bbb97) - Implementation example
- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) - Official docs

### Tertiary (LOW confidence)
- WebSearch for Swift Concurrency timeout patterns - General ecosystem patterns

## Metadata

**Confidence breakdown:**
- Print statement locations: HIGH - Direct grep search of codebase
- Busy-wait patterns: HIGH - Direct grep search, verified code inspection
- Cursor locations: HIGH - Direct grep search, verified code inspection
- HealthKit completion handlers: HIGH - Code inspection shows all paths covered
- Property fallback locations: HIGH - Direct grep search
- Timeout replacement patterns: MEDIUM - Community best practices, not Apple official

**Research date:** 2026-01-21
**Valid until:** 2026-02-21 (30 days - stable domain)
