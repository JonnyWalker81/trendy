# Phase 18: Unit Tests - Resurrection Prevention - Context

**Gathered:** 2026-01-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Test coverage verifying deleted items don't reappear during bootstrap fetch. Tests must cover the `pendingDeleteIds` mechanism that prevents resurrection of items the user has deleted locally but that still exist on the server during a full bootstrap sync.

Requirements: RES-01 through RES-05 (5 requirements)

</domain>

<decisions>
## Implementation Decisions

### Test Scenarios
- Claude determines race condition coverage based on code complexity
- Claude determines partial failure scenarios based on which failure modes matter most
- Claude determines if explicit empty `pendingDeleteIds` test adds value
- Claude determines entity type coverage based on actual sync code

### Fixture Strategy
- Claude determines state injection vs operation-based setup based on isolation vs realism tradeoffs
- Claude determines mock bootstrap response design for conflict scenarios
- Claude determines cursor state setup based on requirements
- Claude determines whether to extend Phase 17 helpers based on code reuse potential

### Assertion Approach
- Claude determines verification method (state query vs call tracking vs both)
- Claude determines `pendingDeleteIds` assertion granularity based on requirement coverage
- Claude determines cursor assertion strictness based on cursor semantics
- Claude determines if timing tolerances are needed for resurrection logic

### Test Organization
- Claude determines file structure based on test file conventions
- Claude determines naming convention based on existing test patterns
- Claude determines grouping approach based on Phase 17 patterns
- Claude determines helper location based on reuse potential

### Claude's Discretion
All test design decisions delegated to Claude:
- Race condition test depth
- Failure scenario coverage
- Fixture setup patterns
- Assertion strategy
- File organization
- Naming conventions
- Helper reuse patterns

</decisions>

<specifics>
## Specific Ideas

- Follow patterns established in Phase 17 (CircuitBreakerTests.swift)
- Reuse existing test infrastructure: makeTestDependencies, MockNetworkClient, MockDataStore
- Tests should compile even if they can't run due to FullDisclosureSDK blocker
- Wide timing tolerances if any time-dependent assertions needed

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-unit-tests-resurrection-prevention*
*Context gathered: 2026-01-22*
