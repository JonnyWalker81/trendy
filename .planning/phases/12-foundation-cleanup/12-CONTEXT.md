# Phase 12: Foundation & Cleanup - Context

**Gathered:** 2026-01-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Clean up technical debt in SyncEngine, APIClient, LocalStore, and HealthKit modules. This includes removing print() statements, fixing completion handler gaps, adding cursor state logging, replacing busy-wait polling, and surfacing silent errors. No new features — strictly cleanup work to enable reliable testing in subsequent phases.

</domain>

<decisions>
## Implementation Decisions

### Logging Replacement Strategy
- Use existing `Log` utility (Logger.swift) with structured categories
- Log levels determined per-statement based on content (debug for tracing, info for significant events, warn for recoverable issues)
- Category assignment at Claude's discretion based on operation context (Log.sync, Log.api, Log.data as appropriate)
- Add structured context fields to all converted logs (event_id, operation name, counts, etc.)

### Cursor State Debugging
- Log full context: cursor values, operation that triggered change, timestamps, and relevant metadata
- Log level at Claude's discretion based on cursor change importance
- Include actual cursor values (not redacted) for exact state tracking
- Nil/empty cursor representation at Claude's discretion

### Polling Replacement Approach
- Operation-specific timeout defaults (different timeouts for sync vs health queries)
- Timeout behavior: Research Swift Concurrency best practices and implement the most robust option
- Continuation type (throwing vs non-throwing) decided per-case based on operation needs
- Cancellation support at Claude's discretion based on typical wait durations
- Research codebase first to identify all busy-wait patterns before replacement
- Timing/duration logging at Claude's discretion where it aids debugging
- HealthKit async wrapper vs fix-in-place at Claude's discretion based on tradeoff evaluation
- Task.sleep vs DispatchQueue at Claude's discretion based on surrounding async context

### Error Visibility
- Property type fallback log level at Claude's discretion based on fallback severity
- Developer-only indicator for silent failures (visible only in debug builds)
- Full property context in error logs: expected type, actual type, property name, entity info, value preview
- Error counter preparation for metrics at Claude's discretion

### Claude's Discretion
- Log category assignment per operation
- Log level selection per print() statement
- Nil cursor representation format
- Continuation type selection per polling replacement
- Cancellation support based on wait duration analysis
- HealthKit wrapper approach (async wrapper vs fix callbacks)
- Task.sleep vs DispatchQueue selection
- Timing log inclusion where valuable
- Error counter preparation if beneficial

</decisions>

<specifics>
## Specific Ideas

- User wants a developer-only indicator for silent failures visible in debug builds
- Research existing busy-wait patterns in codebase before implementing replacements
- Follow Swift Concurrency best practices for timeout handling (robust option)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-foundation-cleanup*
*Context gathered: 2026-01-21*
