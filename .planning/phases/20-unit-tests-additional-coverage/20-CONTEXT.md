# Phase 20: Unit Tests - Additional Coverage - Context

**Gathered:** 2026-01-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Test single-flight pattern, pagination, bootstrap fetch, batch processing, and health checks for the SyncEngine. These tests verify sync patterns that weren't covered in the circuit breaker, resurrection prevention, or deduplication phases.

</domain>

<decisions>
## Implementation Decisions

### Test Isolation Strategy
- Fresh mock instances per test (no shared state between tests)
- Timing approach at Claude's discretion (no real delays vs short delays based on test needs)
- Concurrency simulation approach at Claude's discretion (TaskGroup vs manual continuations)
- State access approach at Claude's discretion (black-box vs white-box based on requirement)

### Failure Simulation Depth
- Batch processing: test BOTH per-item failures and whole-batch failures
- Pagination edge cases: test empty response, cursor overflow, malformed cursors (beyond basic first/middle/last)
- Bootstrap fetch: verify data presence AND relationship restoration (event→eventType links)
- Health check: Claude's discretion on captive portal simulation depth

### Verification Granularity
- Single-flight: full behavior verification (call count + data received + timing)
- Mock call count assertions: Claude's discretion (exact vs ranges based on what's being verified)
- Requirement documentation: BOTH structured test names AND comments (e.g., `testSYNC01_SingleFlightCoalesces` with `// Covers SYNC-01: ...` comment)
- Test organization: by behavior (SingleFlightTests, PaginationTests, BootstrapTests, BatchTests, HealthCheckTests)

### Claude's Discretion
- Timing approach for async operations (instant callbacks vs short delays)
- Concurrency simulation method (TaskGroup vs manual async/await)
- Internal state access vs observable outcomes (per test)
- Mock assertion style (exact counts vs ranges)
- Captive portal simulation depth

</decisions>

<specifics>
## Specific Ideas

- Follow same test patterns established in phases 17-19 (CircuitBreakerTests, ResurrectionPreventionTests, DeduplicationTests)
- Use existing test helpers: makeTestDependencies, configureForFlush, etc.
- Extend MockNetworkClient as needed (similar to phase 19's idempotency response queue)
- Tests will compile but can't run until FullDisclosureSDK blocker resolved (same as previous phases)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 20-unit-tests-additional-coverage*
*Context gathered: 2026-01-23*
