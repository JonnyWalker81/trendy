# Phase 21: Code Quality Refactoring - Context

**Gathered:** 2026-01-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Split two large SyncEngine methods (`flushPendingMutations` ~247 lines, `bootstrapFetch` ~200+ lines) into smaller, focused functions with each method under 50 lines. Existing unit tests from Phases 17-20 serve as the safety net. No behavior changes — pure refactoring.

</domain>

<decisions>
## Implementation Decisions

### Method extraction strategy
- Split by entity type (one method per entity)
- Separate batch method for event creates — continue existing `flushEventCreateBatch` pattern
- Extract circuit breaker helpers: `shouldTripCircuitBreaker()`, `handleCircuitBreakerTrip()` — reusable across mutation methods

### Naming conventions
- Bootstrap methods: `fetch{Entity}s()` — e.g., `fetchEventTypes()`, `fetchGeofences()`, `fetchEvents()`, `fetchPropertyDefinitions()`
- Flush methods: `sync{Entity}Changes()` — e.g., `syncEventChanges()`, `syncGeofenceChanges()`
- Helper methods: Claude's discretion based on Swift conventions (descriptive names preferred)

### Verification approach
- Run existing unit tests only (Phases 17-20 cover circuit breaker, resurrection, dedup, sync patterns)
- Incremental refactoring: one method per commit for easier bisect
  - First commit: refactor `flushPendingMutations`
  - Second commit: refactor `bootstrapFetch`
- Separate plan files for each method

### Claude's Discretion
- Whether to extract nuclear cleanup in `bootstrapFetch` into separate method (based on line count/clarity)
- Error handling consolidation — consolidate similar catch blocks if beneficial
- Rate limit counter centralization — extract if multiple call sites warrant it
- Retry-exceeded logic extraction — extract if 3+ duplications exist
- Complexity measurement approach (line count vs SwiftLint metrics)

</decisions>

<specifics>
## Specific Ideas

- Continue the existing pattern established by `flushEventCreateBatch` — that's the style to follow
- Methods should be under 50 lines each after extraction
- Circuit breaker checks appear in multiple places — good candidate for helper extraction

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 21-code-quality-refactoring*
*Context gathered: 2026-01-23*
