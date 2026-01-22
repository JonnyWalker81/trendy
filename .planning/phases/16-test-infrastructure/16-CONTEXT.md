# Phase 16: Test Infrastructure - Context

**Gathered:** 2026-01-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Build reusable mock implementations for testing SyncEngine. Mocks must support the spy pattern (tracking calls), configurable responses (success/error), and work with the protocol-based DI from Phase 15. Test fixtures provide realistic test data. This phase delivers testing infrastructure — actual unit tests come in Phases 17-20.

</domain>

<decisions>
## Implementation Decisions

### Mock Behavior Configuration
- Property-based configuration: `mock.eventsToReturn = [...]`
- Sequenced responses via array: `responseQueue: [success, success, error]` — pops each call, enables retry testing
- Unconfigured methods return sensible defaults (empty arrays, nil optionals, success results)

### Spy Pattern Design
- Full call records: array of structs with method name, arguments, timestamp
- Rich assertions possible: verify call order, argument values, timing

### Claude's Discretion
- Whether call records are typed per method or generic with Any
- Convenience assertion helpers vs direct XCTAssert
- Reset method vs fresh mock instances
- Per-test configuration vs reusable defaults in setUp()

### Test Fixture Organization
- Dedicated TestFixtures.swift file with factory functions
- Shared across all test files

### Claude's Discretion (Fixtures)
- Default params with overrides vs builder pattern
- Whether to include scenario helpers for common setups
- Deterministic vs seeded random IDs

### Error Simulation
- Typed error enum: `MockNetworkError.rateLimited(retryAfter: 30)`
- Specific cases for each failure type tests need

### Claude's Discretion (Errors)
- Which error scenarios to include (based on what SyncEngine tests need)
- HTTP metadata inclusion (statusCode, headers like Retry-After)
- Deterministic-only vs seeded flaky mode

</decisions>

<specifics>
## Specific Ideas

- Response queuing is essential for circuit breaker tests (need to simulate 3 consecutive failures then success)
- Mocks should feel native to Swift — no heavy mocking frameworks
- Call records enable testing that methods were called in correct order with correct arguments

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 16-test-infrastructure*
*Context gathered: 2026-01-21*
