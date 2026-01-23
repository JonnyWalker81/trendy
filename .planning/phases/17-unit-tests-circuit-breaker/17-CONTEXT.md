# Phase 17: Unit Tests - Circuit Breaker - Context

**Gathered:** 2026-01-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Write unit tests that verify SyncEngine's circuit breaker behavior: trips after consecutive rate limits, blocks sync while tripped, resets after backoff expires, uses exponential backoff timing. Tests validate existing implementation — no circuit breaker changes.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All test design decisions delegated to Claude. Make pragmatic choices based on:

**Test Isolation:**
- Time control approach (inject clock vs settable backoff values)
- SyncEngine lifecycle (fresh per test vs shared with reset)
- Async timing (synchronous mocks vs realistic delays)
- State access (expose internals vs behavior-based only)

**Error Simulation:**
- Rate limit simulation (use existing MockNetworkClient response queues)
- Error specificity (match how APIClient surfaces errors)
- Failure sequence approach (explicit calls vs helper methods)
- Edge case coverage (include counter reset on success if meaningful)

**Assertion Style:**
- Focus on behavior verification (sync blocked/allowed) over internal state
- Block verification approach (return values vs spy call counts)
- Timing tolerance (exact values vs ranges vs progression)
- Spy depth (call counts vs arguments — based on test value)

**Test Organization:**
- Framework choice (match existing test code style)
- File structure (based on test count and logical grouping)
- Naming convention (match existing patterns in project)
- Helper usage (balance DRY vs explicit setup)

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

User delegated all decisions with "You decide" — expects Claude to make pragmatic choices based on:
1. Existing codebase patterns
2. MockNetworkClient/MockDataStore capabilities from Phase 16
3. Testing best practices
4. Refactor-safe, readable tests

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 17-unit-tests-circuit-breaker*
*Context gathered: 2026-01-21*
