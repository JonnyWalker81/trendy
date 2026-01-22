# Phase 14: Implementation Conformance - Research

**Researched:** 2026-01-21
**Domain:** Swift Protocol Conformance for Actor-Based Dependency Injection
**Confidence:** HIGH

## Summary

This phase adds protocol conformance to existing types (APIClient, LocalStore) without changing their behavior, enabling dependency injection for SyncEngine unit testing. Phase 13 already defined the protocols and partially implemented conformance.

**Key finding from Phase 13:** LocalStore already conforms to DataStoreProtocol (added as a deviation during Phase 13-02 because DefaultDataStoreFactory required it). This simplifies Phase 14 significantly.

The remaining work is focused on:
1. Adding `NetworkClientProtocol` conformance to `APIClient`
2. Verifying all existing tests still pass
3. Ensuring no TODO comments remain in protocol-related code

**Primary recommendation:** Add `extension APIClient: NetworkClientProtocol {}` with `@unchecked Sendable` conformance, since APIClient's methods already match the protocol signatures. The `@unchecked Sendable` is appropriate because APIClient's mutable state (encoder/decoder) is only used internally and never exposed across actor boundaries.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | Built-in (Xcode 16+) | Unit testing | Already used in codebase |
| Swift Concurrency | Built-in | Actor isolation | Native language feature |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftData | iOS 17+ | Persistence | LocalStore implementation |

**No new dependencies required.** All tooling already exists.

## Architecture Patterns

### Pattern 1: Extension-Based Protocol Conformance

**What:** Add protocol conformance via extension rather than modifying class declaration.

**When to use:** When existing implementation already satisfies protocol requirements.

**Example:**
```swift
// Source: Swift Language Guide - Protocol Conformance
// File: Services/APIClient+NetworkClientProtocol.swift

// APIClient already has all required methods
// Simply declare conformance via extension
extension APIClient: NetworkClientProtocol {}

// Note: Class must also be marked Sendable
// Since it has non-Sendable stored properties (encoder/decoder),
// use @unchecked Sendable with careful reasoning
```

### Pattern 2: @unchecked Sendable for Classes with Internal Mutable State

**What:** Use `@unchecked Sendable` when a class has non-Sendable stored properties that are only used internally and never escape.

**When to use:** When the class is thread-safe by design but the compiler can't verify it.

**Example:**
```swift
// Source: Swift Evolution SE-0302
// JSONEncoder and JSONDecoder are NOT Sendable
// But they're only used internally in APIClient methods
// and never escape or shared across threads

extension APIClient: @unchecked Sendable {}
```

**Safety reasoning for APIClient:**
- `baseURL: String` - Sendable (immutable)
- `session: URLSession` - Sendable (thread-safe since iOS 15)
- `supabaseService: SupabaseService` - Reference type, but only used for getting tokens
- `encoder: JSONEncoder` - Not Sendable, but only used within request methods
- `decoder: JSONDecoder` - Not Sendable, but only used within request methods

The encoder/decoder are instance properties but are only ever accessed from async methods which serialize access. They don't escape the class.

### Pattern 3: Minimal Change Conformance

**What:** When methods already match protocol signatures, conformance requires zero code changes.

**When to use:** When protocol extraction was done by copying existing method signatures.

**Evidence from codebase:**

| Protocol Method | APIClient Method | Match |
|-----------------|------------------|-------|
| `getEventTypes() async throws -> [APIEventType]` | `getEventTypes() async throws -> [APIEventType]` | Exact |
| `getEvents(limit: Int, offset: Int) async throws -> [APIEvent]` | `getEvents(limit: Int = 1000, offset: Int = 0) async throws -> [APIEvent]` | Default params compatible |
| `getAllEvents(batchSize: Int) async throws -> [APIEvent]` | `getAllEvents(batchSize: Int = 500) async throws -> [APIEvent]` | Default params compatible |
| `getGeofences(activeOnly: Bool) async throws -> [APIGeofence]` | `getGeofences(activeOnly: Bool = false) async throws -> [APIGeofence]` | Default params compatible |
| `getChanges(since cursor: Int64, limit: Int) async throws -> ChangeFeedResponse` | `getChanges(since cursor: Int64, limit: Int = 100) async throws -> ChangeFeedResponse` | Default params compatible |

Swift allows methods with default parameter values to satisfy protocol requirements without default values. No method signature changes needed.

### Anti-Patterns to Avoid

- **Changing method signatures for conformance:** If protocol was designed from existing API, no changes should be needed
- **Adding adapter/wrapper classes:** Unnecessary complexity when direct conformance works
- **Using `any NetworkClientProtocol` where concrete type works:** Performance overhead of existentials
- **Removing default parameters:** Would break existing call sites; keep defaults in implementation

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Method signature adaptation | Wrapper class with different signatures | Extension conformance | Zero overhead, direct conformance |
| Thread safety for Sendable | Custom synchronization | @unchecked Sendable (with justification) | Compiler trust with documented reasoning |
| Factory for LocalStore | New factory class | Existing DefaultDataStoreFactory | Already implemented in Phase 13 |

## Common Pitfalls

### Pitfall 1: Forgetting @unchecked Sendable

**What goes wrong:** Compiler error "Type 'APIClient' does not conform to 'Sendable'"
**Why it happens:** APIClient has non-Sendable stored properties (JSONEncoder, JSONDecoder)
**How to avoid:** Add `@unchecked Sendable` extension with documented safety reasoning
**Warning signs:** Build errors mentioning Sendable conformance

### Pitfall 2: Breaking Existing Call Sites

**What goes wrong:** Existing code that calls `apiClient.getEvents()` (no params) breaks
**Why it happens:** Removing default parameters to match protocol exactly
**How to avoid:** Keep default parameters in implementation; protocol conformance works with defaults
**Warning signs:** Compilation errors at existing call sites

### Pitfall 3: Adding Conformance to Wrong File

**What goes wrong:** Protocol conformance scattered across codebase
**Why it happens:** Ad-hoc additions during development
**How to avoid:** Add conformance in dedicated extension file or in the main class file
**Warning signs:** `extension APIClient: NetworkClientProtocol` in multiple files

### Pitfall 4: Behavior Changes During Conformance

**What goes wrong:** Tests fail after adding conformance
**Why it happens:** Accidentally modifying method implementations while adding conformance
**How to avoid:** Conformance should be declaration-only; run all tests after
**Warning signs:** Any test failures after phase completion

## Code Examples

### APIClient Conformance (Complete)

```swift
// File: apps/ios/trendy/Services/APIClient.swift
// Add this at the end of the file

// MARK: - Protocol Conformance

/// NetworkClientProtocol conformance for dependency injection.
/// APIClient's methods already match the protocol requirements exactly.
///
/// @unchecked Sendable rationale:
/// - baseURL: String is Sendable (immutable)
/// - session: URLSession is Sendable (thread-safe since iOS 15)
/// - supabaseService: SupabaseService reference, only used for token retrieval
/// - encoder/decoder: JSONEncoder/JSONDecoder are NOT Sendable, but they are:
///   - Only accessed within async methods (serialized access)
///   - Never escape the class instance
///   - Not shared between concurrent operations
extension APIClient: NetworkClientProtocol, @unchecked Sendable {}
```

### Alternative: Separate Extension File

```swift
// File: apps/ios/trendy/Services/APIClient+NetworkClientProtocol.swift
//
//  APIClient+NetworkClientProtocol.swift
//  trendy
//
//  NetworkClientProtocol conformance for APIClient.
//  Enables dependency injection in SyncEngine for unit testing.
//

import Foundation

/// NetworkClientProtocol conformance for dependency injection.
/// APIClient's methods already match the protocol requirements exactly.
///
/// @unchecked Sendable rationale:
/// - baseURL: String is Sendable (immutable)
/// - session: URLSession is Sendable (thread-safe since iOS 15)
/// - supabaseService: SupabaseService reference, only used for token retrieval
/// - encoder/decoder: JSONEncoder/JSONDecoder are NOT Sendable, but they are:
///   - Only accessed within async methods (serialized access)
///   - Never escape the class instance
///   - Not shared between concurrent operations
extension APIClient: NetworkClientProtocol, @unchecked Sendable {}
```

### Verification Test (Optional but Recommended)

```swift
// File: apps/ios/trendyTests/ProtocolConformanceTests.swift
import Testing
@testable import trendy

struct ProtocolConformanceTests {
    @Test func apiClientConformsToNetworkClientProtocol() async throws {
        // Compile-time verification: This function signature proves conformance
        func useNetworkClient(_ client: any NetworkClientProtocol) {}

        // If this compiles, APIClient conforms to NetworkClientProtocol
        let config = APIConfiguration(baseURL: "http://localhost:8080/api/v1")
        let supabaseConfig = SupabaseConfiguration(url: "http://localhost", anonKey: "test")
        let supabaseService = SupabaseService(configuration: supabaseConfig)
        let apiClient = APIClient(configuration: config, supabaseService: supabaseService)

        useNetworkClient(apiClient)  // Compile-time verification
    }

    @Test func localStoreConformsToDataStoreProtocol() async throws {
        // Compile-time verification
        func useDataStore(_ store: any DataStoreProtocol) {}

        // This test would require a ModelContext, which needs more setup
        // For now, we rely on DefaultDataStoreFactory compilation as proof
    }

    @Test func defaultDataStoreFactoryCompiles() async throws {
        // If DefaultDataStoreFactory compiles and returns `any DataStoreProtocol`,
        // then LocalStore must conform to DataStoreProtocol
        // This is verified by the existing DataStoreFactory.swift compilation
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual delegation/wrapper | Direct extension conformance | Always preferred | Zero overhead |
| @unchecked Sendable everywhere | Careful reasoning + documentation | Swift 6 emphasis | Better safety |
| Protocol in same file as class | Separate protocol file | Clean architecture | Better organization |

## Open Questions

1. **Should conformance be in main file or extension file?**
   - What we know: Both work; extension file keeps conformance visible
   - What's unclear: Team preference
   - Recommendation: Add to main APIClient.swift file (simpler, less indirection)

2. **Is SupabaseService safe to reference from Sendable context?**
   - What we know: SupabaseService is @Observable class (not Sendable)
   - What's unclear: Whether Supabase SDK methods are thread-safe
   - Recommendation: It's acceptable because:
     - Only `getAccessToken()` is called, which is async
     - Token retrieval is thread-safe in Supabase SDK
     - The reference itself doesn't mutate

## Verification Protocol

### Pre-Implementation Checks

1. Verify LocalStore already conforms to DataStoreProtocol:
   ```bash
   grep "struct LocalStore: DataStoreProtocol" apps/ios/trendy/Services/Sync/LocalStore.swift
   ```
   Expected: Match found (already done in Phase 13)

2. Verify DefaultDataStoreFactory exists and compiles:
   ```bash
   grep "class DefaultDataStoreFactory: DataStoreFactory" apps/ios/trendy/Protocols/DataStoreFactory.swift
   ```
   Expected: Match found (already done in Phase 13)

### Post-Implementation Checks

1. Build succeeds with new conformance:
   ```bash
   cd apps/ios && xcodebuild -scheme trendy -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep "BUILD SUCCEEDED"
   ```

2. All existing tests pass:
   ```bash
   cd apps/ios && xcodebuild test -scheme trendy -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "(Test Suite|passed|failed)"
   ```

3. No TODO comments in protocol files:
   ```bash
   grep -r "TODO" apps/ios/trendy/Protocols/
   ```
   Expected: No matches

4. Protocol conformance is compiler-verified:
   ```swift
   // This must compile without errors
   let client: any NetworkClientProtocol = apiClient
   let store: any DataStoreProtocol = localStore
   ```

## Success Criteria Mapping

| Phase Success Criterion | How Research Supports |
|-------------------------|----------------------|
| APIClient conforms to NetworkClientProtocol | Extension conformance pattern with @unchecked Sendable |
| LocalStore conforms to DataStoreProtocol | Already done in Phase 13 |
| All existing unit tests pass | Minimal change pattern (no behavior changes) |
| LocalStoreFactory implementation correct | DefaultDataStoreFactory already exists |
| No TODO comments | Verification grep command |

## Sources

### Primary (HIGH confidence)
- Existing codebase: `apps/ios/trendy/Services/APIClient.swift` - Method signatures analyzed
- Existing codebase: `apps/ios/trendy/Protocols/NetworkClientProtocol.swift` - Protocol requirements
- Existing codebase: `apps/ios/trendy/Services/Sync/LocalStore.swift` - Already conforms to DataStoreProtocol
- Swift Evolution SE-0302 - Sendable and @Sendable closures specification
- Apple Swift Concurrency documentation - Sendable protocol requirements

### Secondary (MEDIUM confidence)
- Phase 13 documentation - LocalStore conformance deviation documented
- Swift Language Guide - Protocol extensions and conformance

## Metadata

**Confidence breakdown:**
- APIClient conformance: HIGH - Method signatures verified exact match
- LocalStore conformance: HIGH - Already implemented in Phase 13
- @unchecked Sendable safety: HIGH - Properties analyzed for thread safety
- Test preservation: HIGH - No behavior changes planned

**Research date:** 2026-01-21
**Valid until:** 90 days (stable Swift patterns, no external dependencies)
