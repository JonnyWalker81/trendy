# Phase 6: Server API - Research

**Researched:** 2026-01-17
**Domain:** Go API server - UUIDv7, deduplication, sync status, RFC 9457 errors
**Confidence:** HIGH

## Summary

This research covers server-side support for idempotent creates, client-generated UUIDv7 IDs, deduplication via upsert, a sync status endpoint, and RFC 9457 Problem Details error responses. The codebase already has substantial infrastructure: UUIDv7 generation in PostgreSQL, the `change_log` table for sync, and existing upsert patterns for HealthKit events.

The `google/uuid` library (already at v1.6.0 in go.mod) fully supports UUIDv7 with `NewV7()` and time extraction via `UUID.Time()`. For RFC 9457, the `go-problem` library provides a mature implementation with Gin integration. The Supabase client already has `Upsert()` with `Prefer: resolution=merge-duplicates` header support.

**Primary recommendation:** Extend existing patterns rather than introducing new dependencies. Use `google/uuid` for UUIDv7 validation, implement RFC 9457 errors as a custom middleware/utility (no new library needed - it's just JSON), and leverage existing `Upsert()` client method for deduplication.

## Standard Stack

The established libraries/tools for this domain:

### Core (Already in go.mod)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `github.com/google/uuid` | v1.6.0 | UUID generation/validation | Already used, supports UUIDv7 via `NewV7()`, time extraction via `UUID.Time()` |
| `github.com/gin-gonic/gin` | v1.11.0 | HTTP framework | Already used throughout |
| `github.com/go-playground/validator/v10` | v10.27.0 | Request validation | Already indirect dependency via Gin |

### Supporting (No Additional Dependencies)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Standard library `time` | - | Timestamp handling | Parsing UUIDv7 embedded timestamps |
| Standard library `encoding/json` | - | RFC 9457 JSON responses | Problem Details serialization |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom RFC 9457 impl | `github.com/neocotic/go-problem` | go-problem is feature-rich but adds dependency; custom impl is ~100 lines and matches existing error patterns |
| `google/uuid` | `github.com/gofrs/uuid` | gofrs has equivalent UUIDv7; google/uuid already in project |

**No new dependencies required.** All functionality can be implemented with existing libraries.

## Architecture Patterns

### Recommended Project Structure
```
internal/
├── apierror/           # NEW: RFC 9457 Problem Details
│   ├── problem.go      # ProblemDetails struct, error codes
│   ├── codes.go        # Global error code registry
│   └── response.go     # Helper to write problem responses
├── handlers/
│   ├── event.go        # MODIFY: Use upsert, return problem details
│   └── sync.go         # NEW: GET /api/v1/me/sync endpoint
├── service/
│   ├── event.go        # MODIFY: UUIDv7 validation, dedup logic
│   └── sync.go         # NEW: Aggregate sync status
├── repository/
│   └── event.go        # MODIFY: Use Upsert for all events (not just HealthKit)
└── middleware/
    └── requestid.go    # EXISTING: Already has X-Request-ID
```

### Pattern 1: RFC 9457 Problem Details Response
**What:** Standardized error responses with `type`, `title`, `detail`, `status`, `instance`, and extensions
**When to use:** All error responses (400, 401, 403, 404, 409, 429, 500, etc.)

```go
// Source: RFC 9457 specification
// internal/apierror/problem.go

type ProblemDetails struct {
    Type       string         `json:"type"`                  // URI reference identifying problem type
    Title      string         `json:"title"`                 // Short human-readable summary
    Status     int            `json:"status"`                // HTTP status code
    Detail     string         `json:"detail,omitempty"`      // Human-readable explanation
    Instance   string         `json:"instance,omitempty"`    // URI for specific occurrence

    // RFC 9457 allows extensions
    RequestID   string         `json:"request_id,omitempty"`   // Correlation ID
    UserMessage string         `json:"user_message,omitempty"` // UI-safe message
    RetryAfter  *int           `json:"retry_after,omitempty"`  // Seconds until retry
    Action      string         `json:"action,omitempty"`       // Client hint: "refresh_token", etc.
    Errors      []FieldError   `json:"errors,omitempty"`       // Validation errors list
}

type FieldError struct {
    Field   string `json:"field"`
    Message string `json:"message"`
    Code    string `json:"code,omitempty"`
}

// Error codes registry
const (
    TypeValidation     = "urn:trendy:error:validation"
    TypeNotFound       = "urn:trendy:error:not_found"
    TypeConflict       = "urn:trendy:error:conflict"
    TypeRateLimit      = "urn:trendy:error:rate_limit"
    TypeUnauthorized   = "urn:trendy:error:unauthorized"
    TypeInternal       = "urn:trendy:error:internal"
    TypeInvalidUUID    = "urn:trendy:error:invalid_uuid"
    TypeFutureTimestamp = "urn:trendy:error:future_timestamp"
)
```

### Pattern 2: UUIDv7 Validation
**What:** Validate that client-provided IDs are valid UUIDv7 and not too far in the future
**When to use:** Event creation (events only, not event_types per CONTEXT.md)

```go
// Source: google/uuid v1.6.0 documentation (pkg.go.dev)

import (
    "time"
    "github.com/google/uuid"
)

// ValidateUUIDv7 checks if a string is a valid UUIDv7 and within time bounds
func ValidateUUIDv7(id string, maxFutureMinutes int) error {
    // Parse the UUID
    parsed, err := uuid.Parse(id)
    if err != nil {
        return fmt.Errorf("invalid UUID format: %w", err)
    }

    // Check version is 7
    if parsed.Version() != 7 {
        return fmt.Errorf("UUID must be version 7, got version %d", parsed.Version())
    }

    // Extract timestamp from UUIDv7
    // UUID.Time() returns 100-nanosecond intervals since Oct 15, 1582
    // For UUIDv7, this is derived from the embedded Unix milliseconds
    uuidTime := parsed.Time()
    sec, nsec := uuidTime.UnixTime()
    timestamp := time.Unix(sec, nsec)

    // Reject if more than maxFutureMinutes in the future
    maxAllowed := time.Now().Add(time.Duration(maxFutureMinutes) * time.Minute)
    if timestamp.After(maxAllowed) {
        return fmt.Errorf("UUID timestamp %v is more than %d minutes in the future",
            timestamp, maxFutureMinutes)
    }

    return nil
}
```

### Pattern 3: Idempotent Upsert with Deduplication
**What:** Insert-or-update on primary key (event.id), return existing on conflict
**When to use:** All event creates (not just HealthKit)

```go
// Source: Existing pkg/supabase/client.go Upsert method + PostgREST docs

// Repository: Use Upsert instead of Insert for CreateWithDedup
func (r *eventRepository) CreateOrUpdate(ctx context.Context, event *models.Event) (*models.Event, bool, error) {
    data := buildEventData(event)

    // id is primary key - PostgREST will detect conflict on id
    // Prefer: resolution=merge-duplicates causes UPDATE on conflict
    body, err := r.client.Upsert("events", data, "id")
    if err != nil {
        return nil, false, fmt.Errorf("failed to upsert event: %w", err)
    }

    var events []models.Event
    if err := json.Unmarshal(body, &events); err != nil {
        return nil, false, err
    }

    // Determine if this was a create or update by comparing timestamps
    wasCreated := events[0].CreatedAt.Equal(events[0].UpdatedAt) ||
                  time.Since(events[0].CreatedAt) < time.Second

    return &events[0], wasCreated, nil
}
```

### Pattern 4: Batch Response with Per-Item Status (HTTP 207)
**What:** Partial success reporting for batch operations
**When to use:** POST /api/v1/events/batch

```go
// Source: WebDAV HTTP 207 Multi-Status pattern

type BatchItemResult struct {
    Index    int              `json:"index"`              // Position in original request
    Status   int              `json:"status"`             // HTTP status for this item
    ID       string           `json:"id,omitempty"`       // Created/updated entity ID
    Error    *ProblemDetails  `json:"error,omitempty"`    // Problem if failed
    Action   string           `json:"action,omitempty"`   // "created" | "deduplicated" | "failed"
}

type BatchResponse struct {
    Results      []BatchItemResult `json:"results"`
    Summary      BatchSummary      `json:"summary"`
}

type BatchSummary struct {
    Total        int `json:"total"`
    Created      int `json:"created"`
    Deduplicated int `json:"deduplicated"`
    Failed       int `json:"failed"`
}

// Handler returns 207 when mixed results
func (h *EventHandler) CreateEventsBatch(c *gin.Context) {
    // ... process each item ...

    if response.Summary.Failed > 0 && response.Summary.Created > 0 {
        c.JSON(http.StatusMultiStatus, response) // 207
    } else if response.Summary.Failed == response.Summary.Total {
        c.JSON(http.StatusBadRequest, response)  // 400
    } else {
        c.JSON(http.StatusCreated, response)     // 201
    }
}
```

### Pattern 5: Sync Status Endpoint
**What:** Single endpoint returning comprehensive sync health information
**When to use:** GET /api/v1/me/sync

```go
// Source: CONTEXT.md decisions

type SyncStatus struct {
    // Audit trail
    LastSync      *time.Time `json:"last_sync,omitempty"`      // Last sync completion
    LastEvent     *time.Time `json:"last_event,omitempty"`     // Most recent event timestamp
    LastEventType *time.Time `json:"last_event_type,omitempty"`// Most recent event_type change

    // Counts for client verification
    Counts struct {
        Events     int64 `json:"events"`
        EventTypes int64 `json:"event_types"`
    } `json:"counts"`

    // HealthKit-specific section
    HealthKit struct {
        LastSync *time.Time `json:"last_sync,omitempty"`
        Count    int64      `json:"count"`
    } `json:"healthkit"`

    // Change log cursor (for sync resumption)
    LatestCursor int64 `json:"latest_cursor"`

    // Recommendations
    Status          string `json:"status"` // "all_synced" | "behind" | "resync_recommended"
    Recommendations []string `json:"recommendations,omitempty"`
}
```

### Anti-Patterns to Avoid
- **String-based UUID validation:** Don't use regex - use `uuid.Parse()` which handles all valid formats
- **Manual version checking:** Don't parse UUID bytes manually - use `UUID.Version()` method
- **Ignoring time extraction errors:** UUIDv7 time extraction can fail for malformed UUIDs
- **Blocking on idempotency check:** Don't add database round-trip to check for existing ID before upsert - let upsert handle it atomically
- **Returning 409 for duplicates:** Per CONTEXT.md, return 200 with existing record (pure idempotency)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UUID parsing/validation | Regex patterns | `uuid.Parse()` | Handles all UUID formats (with/without dashes, URN prefix, etc.) |
| UUIDv7 time extraction | Byte manipulation | `uuid.Time().UnixTime()` | RFC 9562 compliant, handles edge cases |
| Upsert with conflict detection | Check-then-insert | PostgREST `Prefer: resolution=merge-duplicates` | Atomic, race-condition free |
| Request ID generation | Custom timestamp+random | Existing `logger.RequestIDFromContext()` | Already in middleware, propagated correctly |
| JSON Problem Details | Full RFC 9457 library | Simple struct + `json.Marshal` | Minimal overhead, matches existing error patterns |

**Key insight:** The codebase already has most building blocks. Phase 6 is about composition, not new infrastructure.

## Common Pitfalls

### Pitfall 1: UUIDv7 Time Extraction Precision
**What goes wrong:** Assuming UUIDv7 timestamp has nanosecond precision
**Why it happens:** UUIDv7 only stores milliseconds; `UUID.Time()` returns a `Time` type that needs conversion
**How to avoid:** Always convert via `UnixTime()` which returns `(sec, nsec int64)`
**Warning signs:** Time comparisons failing at sub-millisecond precision

```go
// Correct approach
uuidTime := parsed.Time()
sec, nsec := uuidTime.UnixTime()
timestamp := time.Unix(sec, nsec) // nsec is derived, may not be precise
```

### Pitfall 2: PostgREST Upsert Requires Exact Constraint Match
**What goes wrong:** `Upsert("events", data, "id")` fails with "no unique constraint" error
**Why it happens:** PostgREST `on_conflict` must match a UNIQUE constraint or PRIMARY KEY exactly
**How to avoid:** Verify constraint exists; for partial indexes, may need direct SQL via RPC
**Warning signs:** Error code 42P10 from PostgreSQL

**Current state:** `events.id` is PRIMARY KEY - upsert on `id` will work. The existing partial index `idx_events_healthkit_dedupe` on `(user_id, healthkit_sample_id)` won't work with PostgREST upsert directly (it's a partial index with WHERE clause).

### Pitfall 3: RFC 9457 Content-Type
**What goes wrong:** Returning error JSON with `application/json` instead of `application/problem+json`
**Why it happens:** Gin defaults to `application/json`
**How to avoid:** Explicitly set content type in error response helper

```go
func WriteProblem(c *gin.Context, problem *ProblemDetails) {
    c.Header("Content-Type", "application/problem+json")
    c.JSON(problem.Status, problem)
}
```

### Pitfall 4: Batch Deduplication Performance
**What goes wrong:** N+1 queries checking each event ID before insert
**Why it happens:** Naive implementation of "check if exists, then insert"
**How to avoid:** Use batch upsert; PostgREST handles conflict resolution at DB level
**Warning signs:** Batch of 500 events taking >10 seconds

### Pitfall 5: Missing Retry-After Header
**What goes wrong:** 429 responses without `Retry-After` header
**Why it happens:** RFC 9457 `retry_after` field exists but header forgotten
**How to avoid:** Set both header AND field for 429 and 503 responses

```go
if status == http.StatusTooManyRequests {
    c.Header("Retry-After", strconv.Itoa(retryAfter))
    problem.RetryAfter = &retryAfter
}
```

## Code Examples

Verified patterns from official sources:

### UUIDv7 Generation and Validation
```go
// Source: pkg.go.dev/github.com/google/uuid

import "github.com/google/uuid"

// Generate new UUIDv7
id, err := uuid.NewV7()
if err != nil {
    return err
}

// Parse and validate existing
parsed, err := uuid.Parse(clientProvidedID)
if err != nil {
    return apierror.InvalidUUID(clientProvidedID, err)
}

if parsed.Version() != 7 {
    return apierror.WrongUUIDVersion(parsed.Version())
}

// Extract timestamp
sec, nsec := parsed.Time().UnixTime()
ts := time.Unix(sec, nsec)
```

### RFC 9457 Problem Details Response
```go
// Source: RFC 9457 specification, adapted for Gin

func NewValidationError(requestID string, errors []FieldError) *ProblemDetails {
    return &ProblemDetails{
        Type:        TypeValidation,
        Title:       "Validation Error",
        Status:      http.StatusBadRequest,
        Detail:      fmt.Sprintf("%d validation errors", len(errors)),
        RequestID:   requestID,
        UserMessage: "Please check your input and try again",
        Errors:      errors,
    }
}

func NewDuplicateResponse(requestID string, existing *models.Event) *ProblemDetails {
    // Per CONTEXT.md: 200 with existing record, not 409
    return &ProblemDetails{
        Type:        "about:blank", // Not an error per se
        Title:       "Resource Already Exists",
        Status:      http.StatusOK,
        Detail:      "Duplicate detected; returning existing record",
        RequestID:   requestID,
        Instance:    fmt.Sprintf("/api/v1/events/%s", existing.ID),
    }
}
```

### Sync Status Aggregation
```go
// Source: Existing repository patterns + CONTEXT.md

func (s *syncService) GetSyncStatus(ctx context.Context, userID string) (*SyncStatus, error) {
    // Parallel queries for efficiency
    var wg sync.WaitGroup
    var eventCount, eventTypeCount, healthKitCount int64
    var latestCursor int64
    var lastEvent, lastEventType *time.Time

    wg.Add(4)
    go func() { defer wg.Done(); eventCount, _ = s.eventRepo.CountByUser(ctx, userID) }()
    go func() { defer wg.Done(); eventTypeCount, _ = s.eventTypeRepo.CountByUser(ctx, userID) }()
    go func() { defer wg.Done(); healthKitCount, _ = s.eventRepo.CountHealthKit(ctx, userID) }()
    go func() { defer wg.Done(); latestCursor, _ = s.changeLogRepo.GetLatestCursor(ctx, userID) }()
    wg.Wait()

    // Compute recommendations
    status := "all_synced"
    var recommendations []string

    // Cache for 30 seconds per CONTEXT.md
    return &SyncStatus{
        Counts:       SyncCounts{Events: eventCount, EventTypes: eventTypeCount},
        HealthKit:    HealthKitStatus{Count: healthKitCount},
        LatestCursor: latestCursor,
        Status:       status,
        Recommendations: recommendations,
    }, nil
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| RFC 7807 Problem Details | RFC 9457 Problem Details | July 2023 | Minor clarifications; `type` field guidance improved |
| UUIDv4 random IDs | UUIDv7 time-ordered IDs | 2024-2025 | Better index performance, embedded timestamps |
| Check-then-insert | Upsert with `ON CONFLICT` | PostgreSQL 9.5+ (2016) | Atomic, no race conditions |
| Custom error structs | RFC 9457 standard format | Industry trend 2023-2025 | Interoperability with client libraries |

**Current/recommended:**
- UUIDv7 for new event IDs (already default in database per migration `20251222000000`)
- RFC 9457 for all error responses
- PostgREST upsert for idempotent creates
- `google/uuid` v1.6.0 for UUIDv7 support (already in go.mod)

## Open Questions

Things that couldn't be fully resolved:

1. **V4 to V7 Migration Strategy**
   - What we know: Database already generates UUIDv7 for new records; existing v4 IDs are valid UUIDs
   - What's unclear: CONTEXT.md says "migrate all existing v4 UUIDs to v7" - this requires generating new v7 IDs from `created_at` timestamps for existing rows
   - Recommendation: Add migration script that generates v7 IDs preserving creation order; run as background job, not blocking API

2. **Cache Implementation for Sync Status**
   - What we know: CONTEXT.md specifies 30-second cache
   - What's unclear: In-memory cache vs Redis vs HTTP cache headers
   - Recommendation: Start with in-memory (per-instance) using `sync.Map` with TTL; simple, no new dependencies

3. **Batch Size Limits**
   - What we know: Current limit is 500 events per batch (in model validation)
   - What's unclear: Whether this limit is appropriate with deduplication overhead
   - Recommendation: Keep 500, monitor performance; PostgREST can handle large batches efficiently

## Sources

### Primary (HIGH confidence)
- `github.com/google/uuid` v1.6.0 - [pkg.go.dev documentation](https://pkg.go.dev/github.com/google/uuid) - UUIDv7 functions, time extraction
- RFC 9457 - [IETF specification](https://www.rfc-editor.org/rfc/rfc9457.html) - Problem Details standard
- PostgREST v12.2 - [Official documentation](https://docs.postgrest.org/en/v12/references/api/tables_views.html) - Upsert with `Prefer: resolution=merge-duplicates`
- Existing codebase - `pkg/supabase/client.go`, `internal/repository/event.go` - Current patterns

### Secondary (MEDIUM confidence)
- [go-problem library](https://github.com/neocotic/go-problem) - Reference implementation for RFC 9457 in Go
- [Swagger RFC 9457 guide](https://swagger.io/blog/problem-details-rfc9457-doing-api-errors-well/) - Best practices

### Tertiary (LOW confidence)
- None - all findings verified with official sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Already in go.mod, verified with pkg.go.dev
- Architecture: HIGH - Extends existing patterns, verified with codebase
- Pitfalls: HIGH - Based on PostgreSQL docs and existing code issues

**Research date:** 2026-01-17
**Valid until:** 2026-02-17 (30 days - stable domain, well-established standards)
