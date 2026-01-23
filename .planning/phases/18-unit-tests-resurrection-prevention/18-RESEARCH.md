# Phase 18: Unit Tests - Resurrection Prevention - Research

**Researched:** 2026-01-22
**Domain:** iOS Swift Testing / SyncEngine Resurrection Prevention
**Confidence:** HIGH

## Summary

Research for testing the resurrection prevention mechanism in SyncEngine. The resurrection problem occurs when:
1. User deletes an item locally (creates pending DELETE mutation)
2. SyncEngine performs bootstrap fetch or pullChanges
3. Server's change_log contains CREATE/UPDATE entries for the deleted item (from before user deleted)
4. Without prevention, SyncEngine would recreate the deleted item

The current implementation uses two mechanisms:
- `pendingDeleteIds`: In-memory Set<String> tracking entity IDs with pending DELETE mutations
- `hasPendingDeleteInSwiftData()`: Fallback query checking PendingMutation table for deletes

Tests must verify all 5 RES requirements by manipulating mock responses to simulate resurrection scenarios.

**Primary recommendation:** Follow CircuitBreakerTests.swift patterns exactly - use response queues on MockNetworkClient to control change feed responses, verify both the in-memory set and SwiftData fallback paths.

## Standard Stack

The established test libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing | (built-in) | Test framework | Modern Swift-native, established in Phase 17 |
| MockNetworkClient | local | Network mock | Spy pattern with response queues |
| MockDataStore | local | Data mock | In-memory SwiftData with spy |
| APIModelFixture | local | Test data factory | Deterministic fixtures |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| MockDataStoreFactory | local | Factory injection | DI into SyncEngine |
| TestSupport.swift | local | Fixtures | All test data creation |

**Installation:** No additional packages needed - all infrastructure exists from Phase 16-17.

## Architecture Patterns

### Recommended Test Structure
```
apps/ios/trendyTests/SyncEngine/
  CircuitBreakerTests.swift     # Phase 17 (existing)
  ResurrectionPreventionTests.swift  # Phase 18 (new)
```

### Pattern 1: Test Dependencies Helper
**What:** Centralized factory for fresh test dependencies
**When to use:** Every test needs fresh SyncEngine instance
**Example:**
```swift
// Source: CircuitBreakerTests.swift
private func makeTestDependencies() -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}
```

### Pattern 2: Response Queue Configuration
**What:** Queue multiple responses for sequential network calls
**When to use:** Testing multi-step sync flows
**Example:**
```swift
// Source: MockNetworkClient.swift
// Configure change feed to return CREATE for deleted entity
mockNetwork.getChangesResponses = [
    .success(ChangeFeedResponse(
        changes: [makeResurrectingChangeEntry(entityId: "evt-deleted")],
        nextCursor: 1001,
        hasMore: false
    ))
]
```

### Pattern 3: Seeding Pending Mutations
**What:** Direct state injection for DELETE mutations
**When to use:** Setting up resurrection scenarios
**Example:**
```swift
// Source: MockDataStore.seedPendingMutation
let deletePayload = Data() // DELETE mutations don't need payload
_ = mockStore.seedPendingMutation(
    entityType: .event,
    entityId: "evt-to-delete",
    operation: .delete,
    payload: deletePayload
)
```

### Anti-Patterns to Avoid
- **Shared SyncEngine between tests:** Creates state bleed - always fresh instance
- **Real time waits:** No Task.sleep - use mock state manipulation
- **Testing private properties:** Only test via public API (isCircuitBreakerTripped, etc.)
- **Hardcoded UserDefaults keys:** Use AppEnvironment.current.rawValue for cursor key

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| API model creation | Manual dict/JSON | APIModelFixture | Type-safe, deterministic |
| Change entry creation | Manual struct | APIModelFixture.makeChangeEntry | Handles optional fields |
| Pending mutation state | Direct property access | seedPendingMutation | Proper ModelContext insertion |
| Date handling | Date() | DeterministicDate fixtures | Reproducible timestamps |

**Key insight:** All test data creation patterns exist in TestSupport.swift and should be extended rather than duplicated.

## Common Pitfalls

### Pitfall 1: Bootstrap vs PullChanges Confusion
**What goes wrong:** Testing wrong sync path - bootstrap wipes data, pullChanges preserves
**Why it happens:** Bootstrap (cursor=0) deletes all local data first; pullChanges (cursor>0) applies changes incrementally
**How to avoid:** Always set cursor to non-zero (1000) before testing pullChanges resurrection prevention
**Warning signs:** Test passes but didn't test resurrection (bootstrap wiped before changes applied)

### Pitfall 2: Health Check Consuming Responses
**What goes wrong:** Health check consumes getEventTypesResponses queue before actual test
**Why it happens:** SyncEngine calls getEventTypes() for health check before any sync operation
**How to avoid:** Always include health check success in response queue: `mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]`
**Warning signs:** Test fails with empty response or unexpected API call order

### Pitfall 3: Empty Change Feed Configuration
**What goes wrong:** pullChanges returns early with empty changes, resurrection not tested
**Why it happens:** Default MockNetworkClient returns empty ChangeFeedResponse
**How to avoid:** Explicitly configure `changeFeedResponseToReturn` or `getChangesResponses` with resurrection-triggering changes
**Warning signs:** upsertEventCalls.count == 0 after pullChanges

### Pitfall 4: Cursor Key Environment Specificity
**What goes wrong:** Tests interfere with each other or production state
**Why it happens:** Cursor key includes environment: `"sync_engine_cursor_\(AppEnvironment.current.rawValue)"`
**How to avoid:** Always use the same pattern in tests, clean up in test teardown
**Warning signs:** Tests pass individually but fail when run together

### Pitfall 5: pendingDeleteIds Not Persisted Before Assertion
**What goes wrong:** Tests verify in-memory set but not persistence
**Why it happens:** SyncEngine calls `savePendingDeleteIds()` which persists to UserDefaults
**How to avoid:** Verify both the in-memory behavior AND that entities aren't recreated
**Warning signs:** Test passes but resurrection still occurs after app restart

## Code Examples

Verified patterns from Phase 17 CircuitBreakerTests.swift:

### Creating Change Entry for Resurrection Test
```swift
// Source: Derived from APIModelFixture patterns
static func makeResurrectingChangeEntry(
    id: Int64 = 1,
    entityId: String,
    entityType: String = "event",
    timestamp: Date = DeterministicDate.jan1_2024
) -> ChangeEntry {
    // Create a change entry that would resurrect a deleted entity
    // This simulates a CREATE entry in change_log for an entity
    // that the user has locally deleted
    return ChangeEntry(
        id: id,
        entityType: entityType,
        operation: "create",
        entityId: entityId,
        data: makeChangeEntryData(timestamp: timestamp, eventTypeId: "type-1"),
        deletedAt: nil,
        createdAt: timestamp
    )
}
```

### Verifying Entity NOT Created (Resurrection Prevention)
```swift
// Source: CircuitBreakerTests verification pattern adapted
@Test("Deleted items not re-created during pullChanges (RES-01)")
func deletedItemsNotRecreated() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // Setup: Cursor non-zero to trigger pullChanges (not bootstrap)
    UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")

    // Setup: Health check passes
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Setup: Seed pending DELETE mutation for entity "evt-deleted"
    _ = mockStore.seedPendingMutation(
        entityType: .event,
        entityId: "evt-deleted",
        operation: .delete,
        payload: Data()
    )

    // Setup: Change feed returns CREATE for the deleted entity
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(
        changes: [APIModelFixture.makeChangeEntry(
            id: 1001,
            entityType: "event",
            operation: "create",
            entityId: "evt-deleted"
        )],
        nextCursor: 1002,
        hasMore: false
    )

    // Act
    await engine.performSync()

    // Assert: Entity was NOT upserted (resurrection prevented)
    #expect(mockStore.upsertEventCalls.isEmpty, "Deleted entity should not be resurrected")
}
```

### Verifying pendingDeleteIds Population (RES-02)
```swift
// The pendingDeleteIds set is private, but we can verify its effect
// by checking that entities with pending deletes aren't upserted
@Test("pendingDeleteIds populated before pullChanges (RES-02)")
func pendingDeleteIdsPopulatedBeforePull() async throws {
    let (mockNetwork, mockStore, _, engine) = makeTestDependencies()

    // Setup with non-zero cursor
    UserDefaults.standard.set(1000, forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Seed multiple DELETE mutations
    for i in 1...3 {
        _ = mockStore.seedPendingMutation(
            entityType: .event,
            entityId: "evt-\(i)",
            operation: .delete,
            payload: Data()
        )
    }

    // Configure change feed with CREATE entries for all deleted entities
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(
        changes: [
            APIModelFixture.makeChangeEntry(id: 1, entityType: "event", operation: "create", entityId: "evt-1"),
            APIModelFixture.makeChangeEntry(id: 2, entityType: "event", operation: "create", entityId: "evt-2"),
            APIModelFixture.makeChangeEntry(id: 3, entityType: "event", operation: "create", entityId: "evt-3"),
        ],
        nextCursor: 1003,
        hasMore: false
    )

    await engine.performSync()

    // None of the deleted entities should have been upserted
    #expect(mockStore.upsertEventCalls.isEmpty, "All entities with pending DELETE should be skipped")
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No resurrection prevention | pendingDeleteIds + SwiftData fallback | Phase 05 | Deleted items stay deleted |
| Bootstrap always wipes | Bootstrap wipes + resurrection check | Phase 05 | Belt-and-suspenders protection |

**Deprecated/outdated:**
- Testing with `@MainActor` on entire test class - use `async` tests with explicit `await`

## Open Questions

Things that couldn't be fully resolved:

1. **ChangeEntryData construction for tests**
   - What we know: ChangeEntryData uses custom Codable with rawData dictionary
   - What's unclear: Best way to construct test instances (JSON roundtrip vs direct)
   - Recommendation: Add `makeChangeEntryData()` helper to APIModelFixture if needed, or use nil for DELETE operations

2. **Bootstrap resurrection path**
   - What we know: Bootstrap skips pendingDeleteIds via same mechanism
   - What's unclear: Whether bootstrap resurrection test adds value (bootstrap wipes first anyway)
   - Recommendation: Focus on pullChanges path for RES-01 through RES-03; bootstrap implicitly tested

## Test Scenario Matrix

| Requirement | Scenario | Setup | Verification |
|-------------|----------|-------|--------------|
| RES-01 | Deleted item CREATE in change feed | Seed DELETE mutation, configure CREATE change | upsertEventCalls empty |
| RES-02 | pendingDeleteIds populated | Seed multiple DELETE mutations | None of them resurrected |
| RES-03 | Bootstrap skips pendingDeleteIds | Same as RES-01/02 | Entities not created |
| RES-04 | Cursor advances after delete sync | Configure successful DELETE flush | Check cursor via UserDefaults |
| RES-05 | pendingDeleteIds cleared after confirm | Successful DELETE sync | Subsequent CREATE allowed |

## Sources

### Primary (HIGH confidence)
- CircuitBreakerTests.swift - Established test patterns
- SyncEngine.swift lines 88-161, 1331-1351, 1510-1521 - Resurrection prevention implementation
- MockDataStore.swift lines 570-575 - seedPendingMutation method
- MockNetworkClient.swift lines 848-872 - getChanges response configuration

### Secondary (MEDIUM confidence)
- APIModels.swift lines 889-1180 - ChangeEntry, ChangeEntryData, ChangeFeedResponse definitions
- TestSupport.swift - APIModelFixture patterns

### Tertiary (LOW confidence)
- None - all patterns derived from existing codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Direct verification from existing Phase 17 tests
- Architecture: HIGH - Established patterns from CircuitBreakerTests
- Pitfalls: HIGH - Derived from SyncEngine implementation and Phase 17 learnings
- Test scenarios: MEDIUM - Mapping to requirements straightforward but may need refinement

**Research date:** 2026-01-22
**Valid until:** Indefinite (patterns are codebase-specific, not library-dependent)
