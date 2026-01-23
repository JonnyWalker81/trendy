# Roadmap: Trendy v1.2 SyncEngine Quality

**Created:** 2026-01-21
**Phases:** 11 (Phase 12 through Phase 22)
**Requirements:** 44 total, 44 mapped
**Depth:** Comprehensive

## Milestones

- v1.0 iOS Data Infrastructure - Phases 1-7 (shipped 2026-01-18)
- v1.1 Onboarding Overhaul - Phases 8-11 (shipped 2026-01-21)
- v1.2 SyncEngine Quality - Phases 12-22 (in progress)

## Overview

v1.2 transforms the SyncEngine from working code to production-ready infrastructure. The journey follows a test-driven quality path: clean up technical debt, extract protocols for testability, build comprehensive test coverage for critical sync behaviors, refactor large methods with test safety nets, and add observability for production debugging. By the end, SyncEngine will have unit tests for circuit breaker, resurrection prevention, and deduplication — the three highest-risk sync bugs — plus metrics and documentation for ongoing maintenance.

## Phases

**Phase Numbering:**
- Integer phases (12-22): v1.2 milestone work
- Decimal phases (X.1, X.2): Urgent insertions if needed

---

<details>
<summary>v1.0 iOS Data Infrastructure (Phases 1-7) - SHIPPED 2026-01-18</summary>

See MILESTONES.md for v1.0 details (7 phases, 27 plans, 25 requirements).

</details>

<details>
<summary>v1.1 Onboarding Overhaul (Phases 8-11) - SHIPPED 2026-01-21</summary>

See MILESTONES.md for v1.1 details (4 phases, 12 plans, 21 requirements).

</details>

---

### v1.2 SyncEngine Quality (In Progress)

**Milestone Goal:** Production-ready sync infrastructure with comprehensive test coverage, code quality improvements, and observability

---

#### Phase 12: Foundation & Cleanup

**Goal:** Clean up technical debt before adding complexity

**Depends on:** Nothing (first phase of v1.2)

**Requirements:** QUAL-01, QUAL-02, QUAL-05, QUAL-06, QUAL-07

**Success Criteria** (what must be TRUE):
1. Zero print() statements in peripheral modules (191 statements across 20 files); core modules (SyncEngine, APIClient, LocalStore, HealthKit services) already use structured logging
2. All HealthKit observer query handlers call completion handler in every code path (success and error) - verified via audit
3. All cursor state changes logged with before/after values for debugging
4. Busy-wait polling replaced with continuation-based waiting in sync operations
5. Property type fallback errors logged (no silent failures)

**Plans:** 5 plans

Plans:
- [x] 12-01-PLAN.md — Replace print() in core app files (trendyApp, auth services)
- [x] 12-02-PLAN.md — Replace print() in service and utility modules
- [x] 12-03-PLAN.md — SyncEngine hardening (cursor, logging, async waiting)
- [x] 12-04-PLAN.md — Replace print() in UI views and debug utilities
- [x] 12-05-PLAN.md — Verify HealthKit completion handler correctness (QUAL-02 audit)

---

#### Phase 13: Protocol Definitions

**Goal:** Define abstraction contracts for dependency injection

**Depends on:** Phase 12

**Requirements:** TEST-01, TEST-02, TEST-03

**Success Criteria** (what must be TRUE):
1. NetworkClientProtocol exists with all methods SyncEngine requires for network operations
2. DataStoreProtocol exists with all persistence operations SyncEngine requires
3. DataStoreFactory protocol exists for creating ModelContext-based stores
4. All protocols marked Sendable for actor compatibility (except DataStoreProtocol which is used within actor)
5. Protocol files organized in Protocols/ directory

**Plans:** 2 plans

Plans:
- [x] 13-01-PLAN.md — Define NetworkClientProtocol with all SyncEngine network methods
- [x] 13-02-PLAN.md — Define DataStoreProtocol and DataStoreFactory for persistence

---

#### Phase 14: Implementation Conformance

**Goal:** Existing types conform to protocols without behavior changes

**Depends on:** Phase 13

**Requirements:** TEST-04, TEST-05

**Success Criteria** (what must be TRUE):
1. APIClient conforms to NetworkClientProtocol (compiler-verified)
2. LocalStore conforms to DataStoreProtocol (compiler-verified)
3. All existing unit tests pass (no behavior changes)
4. LocalStoreFactory implementation creates DataStore instances correctly
5. Protocol conformance complete with no TODO comments

**Plans:** 1 plan

Plans:
- [x] 14-01-PLAN.md — Add NetworkClientProtocol conformance to APIClient

---

#### Phase 15: SyncEngine DI Refactor

**Goal:** SyncEngine accepts protocol-based dependencies via constructor injection

**Depends on:** Phase 14

**Requirements:** TEST-06

**Success Criteria** (what must be TRUE):
1. SyncEngine.init accepts NetworkClientProtocol and DataStoreFactory parameters
2. All internal references use protocol types (not concrete APIClient/LocalStore)
3. EventStore creates SyncEngine with protocol-based dependencies
4. Compiler enforces protocol boundaries (no direct concrete usage)
5. Production app builds and runs with new DI architecture

**Plans:** 1 plan

Plans:
- [x] 15-01-PLAN.md — Refactor SyncEngine to accept protocol-based dependencies

---

#### Phase 16: Test Infrastructure

**Goal:** Build reusable mock implementations for testing

**Depends on:** Phase 15

**Requirements:** TEST-07, TEST-08, TEST-09

**Success Criteria** (what must be TRUE):
1. MockNetworkClient tracks all method calls with spy pattern (callCount, arguments)
2. MockNetworkClient supports configurable responses (success, error, rate limit)
3. MockDataStore provides in-memory state management for tests
4. MockDataStoreFactory creates test-compatible stores
5. Test fixtures exist for APIEvent, ChangeFeedResponse, and other API models

**Plans:** 2 plans

Plans:
- [x] 16-01-PLAN.md — Create MockNetworkClient with spy pattern and response configuration
- [x] 16-02-PLAN.md — Create MockDataStore, MockDataStoreFactory, and extend test fixtures

---

#### Phase 17: Unit Tests - Circuit Breaker

**Goal:** Verify rate limit handling trips and resets correctly

**Depends on:** Phase 16

**Requirements:** CB-01, CB-02, CB-03, CB-04, CB-05

**Success Criteria** (what must be TRUE):
1. Test verifies circuit breaker trips after 3 consecutive rate limit errors
2. Test verifies circuit breaker resets after backoff period expires
3. Test verifies sync blocked while circuit breaker tripped
4. Test verifies exponential backoff timing (30s -> 60s -> 120s -> max 300s)
5. Test verifies rate limit counter resets on successful sync

**Plans:** 1 plan

Plans:
- [ ] 17-01-PLAN.md — Create circuit breaker unit tests covering trip, reset, blocking, backoff timing

---

#### Phase 18: Unit Tests - Resurrection Prevention

**Goal:** Verify deleted items don't reappear during bootstrap fetch

**Depends on:** Phase 17

**Requirements:** RES-01, RES-02, RES-03, RES-04, RES-05

**Success Criteria** (what must be TRUE):
1. Test verifies deleted items not re-created during bootstrap fetch
2. Test verifies pendingDeleteIds populated before pullChanges
3. Test verifies bootstrap skips items in pendingDeleteIds set
4. Test verifies cursor advances only after successful delete sync
5. Test verifies pendingDeleteIds cleared after delete confirmed server-side

**Plans:** TBD

Plans:
- [ ] 18-01: TBD

---

#### Phase 19: Unit Tests - Deduplication

**Goal:** Verify idempotency keys prevent duplicate creation

**Depends on:** Phase 18

**Requirements:** DUP-01, DUP-02, DUP-03, DUP-04, DUP-05

**Success Criteria** (what must be TRUE):
1. Test verifies same event not created twice with same idempotency key
2. Test verifies retry after network error reuses same idempotency key
3. Test verifies different mutations use different idempotency keys
4. Test verifies server 409 Conflict response handled correctly
5. Test verifies mutation queue prevents duplicate pending entries

**Plans:** TBD

Plans:
- [ ] 19-01: TBD

---

#### Phase 20: Unit Tests - Additional Coverage

**Goal:** Test single-flight, pagination, bootstrap, and health checks

**Depends on:** Phase 19

**Requirements:** SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05

**Success Criteria** (what must be TRUE):
1. Test verifies single-flight pattern coalesces concurrent sync calls
2. Test verifies cursor pagination with hasMore flag and cursor advancement
3. Test verifies bootstrap fetch downloads full data and restores relationships
4. Test verifies batch processing with 50-event batches and partial failure handling
5. Test verifies health check detects captive portal (prevents false syncs)

**Plans:** TBD

Plans:
- [ ] 20-01: TBD

---

#### Phase 21: Code Quality Refactoring

**Goal:** Split large methods with test safety nets

**Depends on:** Phase 20 (tests provide regression protection)

**Requirements:** QUAL-03, QUAL-04

**Success Criteria** (what must be TRUE):
1. flushPendingMutations split into smaller focused methods (each <50 lines)
2. bootstrapFetch split into entity-specific methods
3. All existing unit tests still pass (no behavior changes)
4. Cyclomatic complexity reduced (measurable improvement)
5. No new TODO or FIXME comments introduced

**Plans:** TBD

Plans:
- [ ] 21-01: TBD

---

#### Phase 22: Metrics & Documentation

**Goal:** Add production observability and architecture documentation

**Depends on:** Phase 21

**Requirements:** METR-01, METR-02, METR-03, METR-04, METR-05, METR-06, DOC-01, DOC-02, DOC-03, DOC-04

**Success Criteria** (what must be TRUE):
1. os.signpost instrumentation added for all sync operations (viewable in Instruments)
2. Custom metrics track sync duration, success/failure rates, rate limit hits, retry counts
3. MetricKit subscriber collects production telemetry (daily aggregation)
4. Sync state machine documented with Mermaid diagram
5. Error recovery flows documented with sequence diagrams
6. Data flow diagrams exist for create event, sync cycle, and bootstrap
7. DI architecture and protocol relationships documented
8. Documentation includes runnable code examples

**Plans:** TBD

Plans:
- [ ] 22-01: TBD

---

## Phase Overview

| # | Phase | Goal | Requirements | Criteria |
|---|-------|------|--------------|----------|
| 12 | Foundation & Cleanup | Clean up technical debt | QUAL-01, QUAL-02, QUAL-05, QUAL-06, QUAL-07 | 5 |
| 13 | Protocol Definitions | Define abstraction contracts | TEST-01, TEST-02, TEST-03 | 5 |
| 14 | Implementation Conformance | Types conform to protocols | TEST-04, TEST-05 | 5 |
| 15 | SyncEngine DI Refactor | Protocol-based dependencies | TEST-06 | 5 |
| 16 | Test Infrastructure | Build mock implementations | TEST-07, TEST-08, TEST-09 | 5 |
| 17 | Unit Tests - Circuit Breaker | Verify rate limit handling | CB-01 to CB-05 | 5 |
| 18 | Unit Tests - Resurrection Prevention | Prevent deleted item reappearance | RES-01 to RES-05 | 5 |
| 19 | Unit Tests - Deduplication | Prevent duplicate creation | DUP-01 to DUP-05 | 5 |
| 20 | Unit Tests - Additional Coverage | Test sync patterns | SYNC-01 to SYNC-05 | 5 |
| 21 | Code Quality Refactoring | Split large methods | QUAL-03, QUAL-04 | 5 |
| 22 | Metrics & Documentation | Add observability | METR-01 to METR-06, DOC-01 to DOC-04 | 8 |

## Requirement Coverage

All 44 v1.2 requirements mapped:

- **Testability (9):**
  - Phase 13: TEST-01, TEST-02, TEST-03
  - Phase 14: TEST-04, TEST-05
  - Phase 15: TEST-06
  - Phase 16: TEST-07, TEST-08, TEST-09

- **Circuit Breaker Tests (5):** Phase 17 (CB-01 to CB-05)

- **Resurrection Prevention Tests (5):** Phase 18 (RES-01 to RES-05)

- **Deduplication Tests (5):** Phase 19 (DUP-01 to DUP-05)

- **Additional Sync Tests (5):** Phase 20 (SYNC-01 to SYNC-05)

- **Code Quality (7):**
  - Phase 12: QUAL-01, QUAL-02, QUAL-05, QUAL-06, QUAL-07
  - Phase 21: QUAL-03, QUAL-04

- **Metrics (6):** Phase 22 (METR-01 to METR-06)

- **Documentation (4):** Phase 22 (DOC-01 to DOC-04)

**Coverage:** 44/44 requirements mapped (100%)

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Foundation cleanup first | Technical debt (print statements, missing completion handlers) blocks reliable testing |
| Protocol extraction over frameworks | Actor-safe DI without heavyweight dependencies |
| Factory pattern for ModelContext | Handles non-Sendable limitation, prevents SwiftData file locking |
| Tests before refactoring | Large method splits risky without test coverage as safety net |
| Circuit breaker tests first | Simpler than full sync, validates mock infrastructure early |
| Resurrection tests separate phase | Most complex sync bug, needs dedicated focus |
| Metrics last | Observability important but not blocking for correctness |
| Comprehensive depth (11 phases) | Complex codebase with actor isolation requires careful incremental migration |

## Progress

**Execution Order:** Phases execute in numeric order: 12 -> 13 -> 14 -> 15 -> 16 -> 17 -> 18 -> 19 -> 20 -> 21 -> 22

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Foundation & Cleanup | v1.2 | 5/5 | Complete | 2026-01-21 |
| 13. Protocol Definitions | v1.2 | 2/2 | Complete | 2026-01-21 |
| 14. Implementation Conformance | v1.2 | 1/1 | Complete | 2026-01-21 |
| 15. SyncEngine DI Refactor | v1.2 | 1/1 | Complete | 2026-01-21 |
| 16. Test Infrastructure | v1.2 | 2/2 | Complete | 2026-01-21 |
| 17. Unit Tests - Circuit Breaker | v1.2 | 0/1 | Planned | - |
| 18. Unit Tests - Resurrection Prevention | v1.2 | 0/? | Not started | - |
| 19. Unit Tests - Deduplication | v1.2 | 0/? | Not started | - |
| 20. Unit Tests - Additional Coverage | v1.2 | 0/? | Not started | - |
| 21. Code Quality Refactoring | v1.2 | 0/? | Not started | - |
| 22. Metrics & Documentation | v1.2 | 0/? | Not started | - |

---
*Roadmap created: 2026-01-21*
*Last updated: 2026-01-22 (Phase 17 planned)*
