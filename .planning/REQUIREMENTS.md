# Requirements: Trendy v1.2 SyncEngine Quality

**Defined:** 2026-01-21
**Core Value:** Effortless tracking — reliable sync that stays out of the way

## v1.2 Requirements

Requirements for SyncEngine quality milestone. Each maps to roadmap phases.

### Testability

- [x] **TEST-01**: Define NetworkClientProtocol with all SyncEngine-required methods
- [x] **TEST-02**: Define DataStoreProtocol with all persistence operations
- [x] **TEST-03**: Define DataStoreFactory protocol for ModelContext creation
- [x] **TEST-04**: APIClient conforms to NetworkClientProtocol
- [x] **TEST-05**: LocalStore conforms to DataStoreProtocol
- [ ] **TEST-06**: SyncEngine accepts protocol-based dependencies via init
- [ ] **TEST-07**: MockNetworkClient with spy pattern (tracks calls, configurable responses)
- [ ] **TEST-08**: MockDataStore with spy pattern (in-memory state)
- [ ] **TEST-09**: MockDataStoreFactory for test injection

### Unit Tests - Circuit Breaker

- [ ] **CB-01**: Test circuit breaker trips after 3 consecutive rate limit errors
- [ ] **CB-02**: Test circuit breaker resets after backoff period expires
- [ ] **CB-03**: Test sync blocked while circuit breaker tripped
- [ ] **CB-04**: Test exponential backoff timing (30s → 60s → 120s → max 300s)
- [ ] **CB-05**: Test rate limit counter resets on successful sync

### Unit Tests - Resurrection Prevention

- [ ] **RES-01**: Test deleted items not re-created during bootstrap fetch
- [ ] **RES-02**: Test pendingDeleteIds populated before pullChanges
- [ ] **RES-03**: Test bootstrap skips items in pendingDeleteIds set
- [ ] **RES-04**: Test cursor advances only after successful delete sync
- [ ] **RES-05**: Test pendingDeleteIds cleared after delete confirmed server-side

### Unit Tests - Deduplication

- [ ] **DUP-01**: Test same event not created twice with same idempotency key
- [ ] **DUP-02**: Test retry after network error reuses same idempotency key
- [ ] **DUP-03**: Test different mutations use different idempotency keys
- [ ] **DUP-04**: Test server 409 Conflict response handled (duplicate detected)
- [ ] **DUP-05**: Test mutation queue prevents duplicate pending entries

### Unit Tests - Additional Coverage

- [ ] **SYNC-01**: Test single-flight pattern (concurrent sync calls coalesced)
- [ ] **SYNC-02**: Test cursor pagination (hasMore flag, cursor advancement)
- [ ] **SYNC-03**: Test bootstrap fetch (full data download, relationship restoration)
- [ ] **SYNC-04**: Test batch processing (50-event batches, partial failure handling)
- [ ] **SYNC-05**: Test health check detects captive portal (prevents false syncs)

### Code Quality

- [x] **QUAL-01**: Replace all print() statements with structured Log.sync logging
- [x] **QUAL-02**: Audit HealthKit completion handlers called in all code paths
- [ ] **QUAL-03**: Split flushPendingMutations into smaller focused methods
- [ ] **QUAL-04**: Split bootstrapFetch into entity-specific methods
- [x] **QUAL-05**: Replace busy-wait polling with continuation-based waiting
- [x] **QUAL-06**: Use safer cursor fallback (Int64.max/2 instead of 1B)
- [x] **QUAL-07**: Add logging for property type fallback (silent error fix)

### Metrics

- [ ] **METR-01**: Track sync operation duration (start to completion)
- [ ] **METR-02**: Track sync success/failure rates
- [ ] **METR-03**: Track rate limit hit counts
- [ ] **METR-04**: Track retry patterns (count per operation, total per sync)
- [ ] **METR-05**: Implement os.signpost instrumentation for development profiling
- [ ] **METR-06**: Implement MetricKit subscriber for production telemetry

### Documentation

- [ ] **DOC-01**: Document sync state machine with Mermaid diagram (org-mode)
- [ ] **DOC-02**: Document error recovery flows with sequence diagram
- [ ] **DOC-03**: Document data flow (create event, sync cycle, bootstrap)
- [ ] **DOC-04**: Document DI architecture and protocol relationships

## Future Requirements

Deferred to later milestone. Not in v1.2 roadmap.

### Advanced Testing

- **ADVT-01**: Integration tests against real backend (staging)
- **ADVT-02**: Performance tests for sync with 1000+ pending mutations
- **ADVT-03**: Stress tests for concurrent ModelContext access

### Observability

- **OBS-01**: Real-time sync status dashboard (web)
- **OBS-02**: Automated alerting on sync failure patterns
- **OBS-03**: User-facing sync health indicator

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Bidirectional sync (server → client push) | WebSocket/SSE adds complexity; pull-based sufficient for v1.2 |
| Conflict resolution UI | Last-write-wins sufficient; user-facing conflicts deferred |
| Background sync optimization | Focus on correctness before performance |
| HealthKit real-time updates | iOS controls timing; best-effort acceptable |
| >20 geofence smart rotation | Complexity not justified by current usage |
| Mock library (Quick/Nimble) | Swift Testing + manual mocks sufficient |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TEST-01 | Phase 13 | Complete |
| TEST-02 | Phase 13 | Complete |
| TEST-03 | Phase 13 | Complete |
| TEST-04 | Phase 14 | Complete |
| TEST-05 | Phase 14 | Complete |
| TEST-06 | Phase 15 | Pending |
| TEST-07 | Phase 16 | Pending |
| TEST-08 | Phase 16 | Pending |
| TEST-09 | Phase 16 | Pending |
| CB-01 | Phase 17 | Pending |
| CB-02 | Phase 17 | Pending |
| CB-03 | Phase 17 | Pending |
| CB-04 | Phase 17 | Pending |
| CB-05 | Phase 17 | Pending |
| RES-01 | Phase 18 | Pending |
| RES-02 | Phase 18 | Pending |
| RES-03 | Phase 18 | Pending |
| RES-04 | Phase 18 | Pending |
| RES-05 | Phase 18 | Pending |
| DUP-01 | Phase 19 | Pending |
| DUP-02 | Phase 19 | Pending |
| DUP-03 | Phase 19 | Pending |
| DUP-04 | Phase 19 | Pending |
| DUP-05 | Phase 19 | Pending |
| SYNC-01 | Phase 20 | Pending |
| SYNC-02 | Phase 20 | Pending |
| SYNC-03 | Phase 20 | Pending |
| SYNC-04 | Phase 20 | Pending |
| SYNC-05 | Phase 20 | Pending |
| QUAL-01 | Phase 12 | Complete |
| QUAL-02 | Phase 12 | Complete |
| QUAL-03 | Phase 21 | Pending |
| QUAL-04 | Phase 21 | Pending |
| QUAL-05 | Phase 12 | Complete |
| QUAL-06 | Phase 12 | Complete |
| QUAL-07 | Phase 12 | Complete |
| METR-01 | Phase 22 | Pending |
| METR-02 | Phase 22 | Pending |
| METR-03 | Phase 22 | Pending |
| METR-04 | Phase 22 | Pending |
| METR-05 | Phase 22 | Pending |
| METR-06 | Phase 22 | Pending |
| DOC-01 | Phase 22 | Pending |
| DOC-02 | Phase 22 | Pending |
| DOC-03 | Phase 22 | Pending |
| DOC-04 | Phase 22 | Pending |

**Coverage:**
- v1.2 requirements: 44 total
- Mapped to phases: 44 (100% coverage)
- Unmapped: 0

---
*Requirements defined: 2026-01-21*
*Last updated: 2026-01-21 (Phase 14 complete)*
