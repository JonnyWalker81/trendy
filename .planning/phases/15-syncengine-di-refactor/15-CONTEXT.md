# Phase 15: SyncEngine DI Refactor - Context

**Gathered:** 2026-01-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor SyncEngine to accept protocol-based dependencies via constructor injection. SyncEngine.init accepts NetworkClientProtocol and DataStoreFactory parameters. All internal references use protocol types. EventStore creates SyncEngine with protocol-based dependencies. Production app builds and runs with new DI architecture.

</domain>

<decisions>
## Implementation Decisions

### Migration strategy
- All-at-once replacement — no backward-compatible deprecated code
- Fix all hidden SyncEngine usages discovered during refactor (compiler errors guide discovery)
- Complete migration in single phase — clean break

### Claude's Discretion

**Init signature design:**
- Required vs optional parameters with defaults
- Convenience initializers (if any)
- Dependency validation approach
- Parameter naming conventions

**Property storage:**
- Stored properties vs closures/factories for dependencies
- Actor isolation strategy (nonisolated where safe vs actor-isolated always)
- Existentials vs generics for protocol types
- DataStoreFactory usage pattern (store factory vs create at init)

**Ownership model:**
- Whether EventStore is sole SyncEngine creator
- Handling of existing shared/global SyncEngine patterns

**Testing convenience:**
- Internal state exposure for tests
- Test-specific factories
- Mock locations (test target vs shared)
- Verification patterns (spy vs stub vs both)

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

User prioritized clean break (all-at-once migration) over gradual deprecation.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 15-syncengine-di-refactor*
*Context gathered: 2026-01-21*
