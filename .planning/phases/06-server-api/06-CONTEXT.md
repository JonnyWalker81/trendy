# Phase 6: Server API - Context

**Gathered:** 2026-01-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Backend API changes to support idempotent creates, deduplication, and sync status. The iOS client already generates UUIDv7 IDs and queues mutations — this phase makes the server accept and handle them correctly.

Scope includes:
- UUIDv7 ID acceptance and validation
- Duplicate detection and upsert behavior
- Sync status endpoint for client health checks and debugging
- RFC 9457 error responses with actionable hints
- Migration of existing v4 UUIDs to v7

</domain>

<decisions>
## Implementation Decisions

### Duplicate Handling
- **Response:** 200 with existing record on duplicate (pure idempotency — client can't tell if new or existing)
- **Duplicate key:** `external_id` per user (same external_id from different users are separate)
- **Enforcement:** Database UNIQUE constraint on (user_id, external_id), catch conflict at DB level
- **On conflict with different data:** Upsert behavior — update existing record with new data
- **Modified timestamp:** Update `modified_at` when upserting duplicate
- **Batch handling:** Per-item handling — each item succeeds/dedupes independently, partial success OK
- **Batch response:** Include breakdown: `{ created: N, deduplicated: N, failed: N }`
- **Applies to:** All events (not just HealthKit) — use client-generated `event.id` as dedup key
- **Conflict resolution:** Last write wins (most recent request wins, regardless of payload timestamps)

### Sync Status Endpoint
- **Path:** `GET /api/v1/me/sync`
- **Use case:** Both client health check (production UI) and debug/diagnostics
- **Timestamps:** Full audit trail — last sync, last event, last type, with counts
- **Counts:** Include `{ events: N, event_types: N }` for client verification
- **HealthKit section:** Separate section with its own last_sync, count (no anchor — that's iOS-only)
- **Server operations:** Report any queued jobs, pending notifications if applicable
- **Integrity:** Timestamps sufficient, no checksums
- **Filtering:** Always full status, no date range params
- **Caching:** Short cache (30 seconds) to reduce load
- **Recommendations:** Include sync hints: `resync_recommended`, `all_synced`, etc.

### Error Response Format
- **Format:** RFC 9457 (Problem Details) — type, title, detail, instance
- **Retry hints:** Yes, `Retry-After` header AND `retry_after` field for 429, 503
- **Validation errors:** List all failures, not just first
- **Correlation ID:** `X-Request-ID` header + `request_id` field in error body
- **Message levels:** Both `user_message` (UI-safe) and `detail` (developer/debugging)
- **Client actions:** Include actionable hints: `{ action: 'refresh_event_types' }`
- **Error codes:** Global registry: `VALIDATION_ERROR`, `NOT_FOUND`, `CONFLICT`, etc.
- **Partial failures:** HTTP 207 Multi-Status with per-item status in body

### ID Acceptance Policy
- **Validation:** Require UUIDv7 format for new event IDs (reject non-v7)
- **Timestamp handling:** Store both client timestamp (from UUIDv7) and server timestamp
- **Future timestamp:** Reject if UUIDv7 timestamp is >1 minute in future
- **Existing data:** Migrate all existing v4 UUIDs to v7 (part of this phase)
- **Migration timestamp:** Use original `created_at` in the new v7 ID
- **Legacy support:** Clean break — no legacy_id field, clients must refresh
- **Scope:** Events only use UUIDv7; event_types keep existing v4 format

### Claude's Discretion
- Exact UUIDv7 parsing/generation library choice
- Database migration rollout strategy
- Cache implementation details for sync status endpoint
- Specific error code taxonomy beyond the examples given

</decisions>

<specifics>
## Specific Ideas

- RFC 9457 for errors — modern Problem Details standard
- 207 Multi-Status for batch partial failures follows WebDAV pattern
- UUIDv7 gives time-ordered IDs which helps with sync ordering
- 1 minute future tolerance balances clock skew against abuse

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-server-api*
*Context gathered: 2026-01-17*
