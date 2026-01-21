# Requirements: Trendy v1.2 SyncEngine Quality

**Defined:** 2026-01-21
**Core Value:** Effortless tracking — reliable sync that stays out of the way

## v1.2 Requirements

Requirements for SyncEngine quality milestone. Each maps to roadmap phases.

### Testability

- [ ] **TEST-01**: Define NetworkClientProtocol with all SyncEngine-required methods
- [ ] **TEST-02**: Define DataStoreProtocol with all persistence operations
- [ ] **TEST-03**: Define DataStoreFactory protocol for ModelContext creation
- [ ] **TEST-04**: APIClient conforms to NetworkClientProtocol
- [ ] **TEST-05**: LocalStore conforms to DataStoreProtocol
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

- [ ] **QUAL-01**: Replace all print() statements with structured Log.sync logging
- [ ] **QUAL-02**: Audit HealthKit completion handlers called in all code paths
- [ ] **QUAL-03**: Split flushPendingMutations into smaller focused methods
- [ ] **QUAL-04**: Split bootstrapFetch into entity-specific methods
- [ ] **QUAL-05**: Replace busy-wait polling with continuation-based waiting
- [ ] **QUAL-06**: Use safer cursor fallback (Int64.max/2 instead of 1B)
- [ ] **QUAL-07**: Add logging for property type fallback (silent error fix)

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
| TEST-01 | TBD | Pending |
| TEST-02 | TBD | Pending |
| TEST-03 | TBD | Pending |
| TEST-04 | TBD | Pending |
| TEST-05 | TBD | Pending |
| TEST-06 | TBD | Pending |
| TEST-07 | TBD | Pending |
| TEST-08 | TBD | Pending |
| TEST-09 | TBD | Pending |
| CB-01 | TBD | Pending |
| CB-02 | TBD | Pending |
| CB-03 | TBD | Pending |
| CB-04 | TBD | Pending |
| CB-05 | TBD | Pending |
| RES-01 | TBD | Pending |
| RES-02 | TBD | Pending |
| RES-03 | TBD | Pending |
| RES-04 | TBD | Pending |
| RES-05 | TBD | Pending |
| DUP-01 | TBD | Pending |
| DUP-02 | TBD | Pending |
| DUP-03 | TBD | Pending |
| DUP-04 | TBD | Pending |
| DUP-05 | TBD | Pending |
| SYNC-01 | TBD | Pending |
| SYNC-02 | TBD | Pending |
| SYNC-03 | TBD | Pending |
| SYNC-04 | TBD | Pending |
| SYNC-05 | TBD | Pending |
| QUAL-01 | TBD | Pending |
| QUAL-02 | TBD | Pending |
| QUAL-03 | TBD | Pending |
| QUAL-04 | TBD | Pending |
| QUAL-05 | TBD | Pending |
| QUAL-06 | TBD | Pending |
| QUAL-07 | TBD | Pending |
| METR-01 | TBD | Pending |
| METR-02 | TBD | Pending |
| METR-03 | TBD | Pending |
| METR-04 | TBD | Pending |
| METR-05 | TBD | Pending |
| METR-06 | TBD | Pending |
| DOC-01 | TBD | Pending |
| DOC-02 | TBD | Pending |
| DOC-03 | TBD | Pending |
| DOC-04 | TBD | Pending |

**Coverage:**
- v1.2 requirements: 44 total
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 44

---
*Requirements defined: 2026-01-21*
*Last updated: 2026-01-21 after initial definition*
