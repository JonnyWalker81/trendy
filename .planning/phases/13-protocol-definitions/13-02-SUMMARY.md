---
phase: 13-protocol-definitions
plan: 02
subsystem: ios-sync
tags: [protocol, dependency-injection, factory-pattern, swiftdata, actor]
depends:
  requires: []
  provides: [DataStoreProtocol, DataStoreFactory, DefaultDataStoreFactory]
  affects: [phase-14-conformance, phase-15-unit-tests]
tech-stack:
  added: []
  patterns: [factory-pattern, protocol-oriented-design, actor-safe-di]
key-files:
  created:
    - apps/ios/trendy/Protocols/DataStoreProtocol.swift
    - apps/ios/trendy/Protocols/DataStoreFactory.swift
  modified:
    - apps/ios/trendy/Services/Sync/LocalStore.swift
decisions:
  - id: DEC-13-02-01
    choice: "Factory pattern for ModelContext"
    rationale: "ModelContext is not Sendable, so factory creates DataStore inside actor isolation context"
  - id: DEC-13-02-02
    choice: "DataStoreProtocol NOT Sendable"
    rationale: "Instances created and used entirely within actor context, never cross boundaries"
  - id: DEC-13-02-03
    choice: "Added LocalStore conformance in this plan"
    rationale: "Required for DefaultDataStoreFactory to compile; deviation from plan 14 but necessary"
metrics:
  duration: "~5 minutes"
  completed: 2026-01-22
---

# Phase 13 Plan 02: DataStoreProtocol & Factory Summary

DataStoreProtocol (18 methods) and DataStoreFactory (Sendable) enable SyncEngine persistence DI with actor-safe factory pattern for ModelContext creation.

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | Create DataStoreProtocol | 9b3a930 | Protocols/DataStoreProtocol.swift |
| 2 | Create DataStoreFactory protocol | f4942e0 | Protocols/DataStoreFactory.swift, Services/Sync/LocalStore.swift |
| 3 | Verify all protocol files | - | (verification only) |

## What Was Built

### DataStoreProtocol (NOT Sendable)

Protocol abstracting all LocalStore methods SyncEngine uses:

- **Upsert Operations (4):** upsertEvent, upsertEventType, upsertGeofence, upsertPropertyDefinition
- **Delete Operations (4):** deleteEvent, deleteEventType, deleteGeofence, deletePropertyDefinition
- **Lookup Operations (4):** findEvent, findEventType, findGeofence, findPropertyDefinition
- **Pending Operations (1):** fetchPendingMutations
- **Sync Status (4):** markEventSynced, markEventTypeSynced, markGeofenceSynced, markPropertyDefinitionSynced
- **Persistence (1):** save

Total: 18 methods matching LocalStore interface exactly.

### DataStoreFactory (Sendable)

Factory protocol for creating DataStore instances within actor context:

```swift
protocol DataStoreFactory: Sendable {
    func makeDataStore() -> any DataStoreProtocol
}
```

### DefaultDataStoreFactory

Production implementation that holds ModelContainer (Sendable) and creates LocalStore with fresh ModelContext:

```swift
final class DefaultDataStoreFactory: DataStoreFactory, @unchecked Sendable {
    private let modelContainer: ModelContainer

    func makeDataStore() -> any DataStoreProtocol {
        let context = ModelContext(modelContainer)
        return LocalStore(modelContext: context)
    }
}
```

## Key Design Decisions

1. **DataStoreProtocol NOT Sendable:** DataStore instances are created inside the actor via factory, used only within actor's isolation context, never cross boundaries.

2. **DataStoreFactory IS Sendable:** Factory is passed INTO the actor from outside, so it must be Sendable.

3. **Factory Pattern for ModelContext:** Solves threading problem - ModelContainer (Sendable) is injected, ModelContext (non-Sendable) is created inside actor.

4. **@unchecked Sendable on DefaultDataStoreFactory:** Safe because ModelContainer is documented as thread-safe by Apple, class is final, no mutable state beyond Sendable container.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added LocalStore conformance to DataStoreProtocol**

- **Found during:** Task 2
- **Issue:** DefaultDataStoreFactory returns LocalStore but LocalStore didn't conform to DataStoreProtocol
- **Fix:** Added `: DataStoreProtocol` to LocalStore struct declaration
- **Files modified:** apps/ios/trendy/Services/Sync/LocalStore.swift
- **Commit:** f4942e0

Note: Plan 14 was supposed to add conformance, but factory compilation required it now.

## Verification Results

- DataStoreProtocol.swift exists with 18 methods
- DataStoreFactory.swift exists with Sendable conformance
- DefaultDataStoreFactory compiles and returns LocalStore
- LocalStore conforms to DataStoreProtocol
- iOS project builds successfully

## Next Phase Readiness

**Ready for Phase 14 (Conformance Wiring):**
- NetworkClientProtocol defined (plan 01)
- DataStoreProtocol defined (this plan)
- DataStoreFactory defined (this plan)
- LocalStore already conforms to DataStoreProtocol (deviation handled early)
- Next: APIClient conformance to NetworkClientProtocol
