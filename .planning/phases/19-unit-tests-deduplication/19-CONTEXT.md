# Phase 19: Unit Tests - Deduplication - Context

**Gathered:** 2026-01-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Unit tests verifying that idempotency mechanisms prevent duplicate event creation during sync operations. The deduplication logic already exists in SyncEngine; this phase tests it works correctly across normal flows, retries, and edge cases.

</domain>

<decisions>
## Implementation Decisions

### Test Data Setup
- Claude's discretion on explicit vs generated idempotency keys (based on testability)
- Claude's discretion on network failure simulation approach (consistent with existing patterns)
- Claude's discretion on mutation type combinations for uniqueness tests
- Claude's discretion on key format verification vs uniqueness-only

### Assertion Patterns
- Verify BOTH: single API call AND single database record for duplicate prevention
- Full idempotency key lifecycle verification (generation → use → cleanup)
- Claude's discretion on queue state assertions during process
- Claude's discretion on 409 Conflict handling assertions

### Edge Case Coverage
- **Race condition test required:** Rapid duplicate submissions (same event twice before first completes)
- **Error variety testing required:** Verify non-409 codes (400, 500) don't falsely deduplicate
- **Key collision test required:** Force collision scenario, verify system handles it
- Claude's discretion on partial batch failure testing

### Mock Behavior
- Claude's discretion on 409 Conflict simulation approach
- Claude's discretion on smart mock (key tracking) vs explicit config
- Claude's discretion on extending MockNetworkClient vs using existing
- Claude's discretion on idempotency key capture for spy assertions

### Claude's Discretion
- Test data setup details (key generation, failure simulation, mutation combinations)
- Queue state assertion depth
- 409 handling assertion comprehensiveness
- Partial batch failure coverage
- Mock implementation approach (response queues vs conditional logic)

</decisions>

<specifics>
## Specific Ideas

- Follow established patterns from Phase 17 (circuit breaker) and Phase 18 (resurrection) tests
- Use existing MockNetworkClient response queue pattern where applicable
- Tests should compile (FullDisclosureSDK blocker noted — same as Phase 17/18)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 19-unit-tests-deduplication*
*Context gathered: 2026-01-22*
