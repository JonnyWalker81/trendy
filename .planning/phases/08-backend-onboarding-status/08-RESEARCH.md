# Phase 8: Backend Onboarding Status - Research

**Researched:** 2026-01-20
**Domain:** Go + Gin backend API, Supabase/PostgreSQL database, user state management
**Confidence:** HIGH

## Summary

Phase 8 requires adding backend support for storing and serving onboarding completion status per user. The research confirms that the existing codebase has well-established patterns for:
1. Clean architecture (Handler -> Service -> Repository)
2. Supabase integration with RLS support
3. RFC 9457 Problem Details error responses
4. Database migrations with cascade deletion

The CONTEXT.md decisions specify a separate `onboarding_status` table with explicit columns for each step and permission. This is the right approach for tracking granular onboarding state with timestamps.

**Primary recommendation:** Follow the existing geofence implementation pattern exactly - it's the closest analog (user-scoped resource with simple CRUD-like operations).

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Gin | v1.11.0 | HTTP framework | Already used, handles routing/middleware |
| Supabase Client | Custom pkg | Database operations | Project's established DB layer |
| Go standard library | 1.23+ | JSON, time, context | Native support, no dependencies |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Viper | v1.21.0 | Configuration | Already wired, not needed for this phase |
| google/uuid | v1.6.0 | UUID generation | Used for other tables, may use gen_random_uuid() instead |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate table | profiles table columns | CONTEXT.md decided against this - separate table is cleaner |
| JSONB for steps | Fixed columns | CONTEXT.md decided fixed columns - better validation, querying |

**Installation:**
```bash
# No new dependencies needed - uses existing stack
```

## Architecture Patterns

### Recommended Project Structure
```
apps/backend/internal/
├── models/
│   └── models.go              # Add OnboardingStatus, UpdateOnboardingStatusRequest
├── handlers/
│   └── onboarding.go          # NEW: GET/PATCH handlers
├── service/
│   ├── interfaces.go          # Add OnboardingService interface
│   └── onboarding.go          # NEW: Business logic
├── repository/
│   ├── interfaces.go          # Add OnboardingStatusRepository interface
│   └── onboarding_status.go   # NEW: Supabase queries

supabase/migrations/
└── 20260120000000_add_onboarding_status.sql  # NEW: Migration
```

### Pattern 1: Upsert for Initial GET
**What:** When user first calls GET, upsert a default record instead of returning 404
**When to use:** CONTEXT.md specifies GET returns 200 with defaults for new users
**Example:**
```go
// Repository method for GetOrCreate pattern
func (r *onboardingStatusRepository) GetOrCreate(ctx context.Context, userID string) (*models.OnboardingStatus, error) {
    // First try to get existing
    status, err := r.GetByUserID(ctx, userID)
    if err == nil {
        return status, nil
    }

    // Create default record on first access
    return r.Create(ctx, &models.OnboardingStatus{
        UserID:    userID,
        Completed: false,
        // All step timestamps and permission fields remain nil
    })
}
```

### Pattern 2: Full Object PATCH (Not Partial)
**What:** PATCH requires the full onboarding status object, not partial updates
**When to use:** CONTEXT.md specifies "PATCH requires full object (not partial updates)"
**Example:**
```go
// UpdateOnboardingStatusRequest - all fields required
type UpdateOnboardingStatusRequest struct {
    Completed                  bool    `json:"completed"`
    WelcomeCompletedAt         *string `json:"welcome_completed_at"`
    AuthCompletedAt            *string `json:"auth_completed_at"`
    PermissionsCompletedAt     *string `json:"permissions_completed_at"`
    NotificationsStatus        *string `json:"notifications_status"`
    NotificationsCompletedAt   *string `json:"notifications_completed_at"`
    HealthkitStatus            *string `json:"healthkit_status"`
    HealthkitCompletedAt       *string `json:"healthkit_completed_at"`
    LocationStatus             *string `json:"location_status"`
    LocationCompletedAt        *string `json:"location_completed_at"`
}
```

### Pattern 3: Enum Validation for Permission Status
**What:** Validate permission status values strictly at the service layer
**When to use:** Any PATCH request with permission status fields
**Example:**
```go
var validPermissionStatuses = map[string]bool{
    "granted":       true,
    "denied":        true,
    "skipped":       true,
    "not_requested": true,
}

func validatePermissionStatus(status *string, fieldName string) error {
    if status == nil {
        return nil // nil is allowed
    }
    if !validPermissionStatuses[*status] {
        return fmt.Errorf("invalid %s value: must be one of granted, denied, skipped, not_requested", fieldName)
    }
    return nil
}
```

### Anti-Patterns to Avoid
- **Using profiles table:** CONTEXT.md explicitly decided against this - use separate `onboarding_status` table
- **Returning 404 for new users:** GET should create default record and return 200
- **Partial PATCH updates:** Must send full object per CONTEXT.md decision
- **Storing computed `completed` flag only:** Store explicit flag AND step timestamps

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON timestamp parsing | Custom parser | `time.Parse(time.RFC3339, s)` | Standard format, handles timezones |
| Request validation | Manual if/else | Gin's `binding` tags + custom validators | Consistent with existing handlers |
| Error responses | Custom JSON | `apierror.WriteProblem()` | RFC 9457 compliant, established pattern |
| User ID extraction | Manual header parsing | `c.Get("user_id")` after Auth middleware | Middleware already handles this |
| Database upsert | INSERT + catch conflict | Supabase `Upsert()` with `on_conflict` | Built into client, atomic |

**Key insight:** The codebase already has robust patterns for auth, error handling, and database operations. Reuse them exactly.

## Common Pitfalls

### Pitfall 1: Forgetting ON DELETE CASCADE
**What goes wrong:** User deletion leaves orphaned onboarding_status records
**Why it happens:** Easy to forget FK constraints
**How to avoid:** Migration MUST include `REFERENCES auth.users(id) ON DELETE CASCADE` OR `REFERENCES public.users(id) ON DELETE CASCADE`
**Warning signs:** Records accumulating without corresponding users

### Pitfall 2: Not Handling Concurrent First Access
**What goes wrong:** Race condition if two requests try to create default record simultaneously
**Why it happens:** GET creates record if not exists - two parallel GETs could conflict
**How to avoid:** Use `INSERT ... ON CONFLICT DO NOTHING` or Supabase upsert pattern
**Warning signs:** 409 conflicts on first user access

### Pitfall 3: Incorrect Timestamp Timezone Handling
**What goes wrong:** Timestamps stored/returned in wrong timezone
**Why it happens:** Mixing local time and UTC
**How to avoid:** Always use `TIMESTAMP WITH TIME ZONE` in DB, `time.RFC3339` in Go, ISO8601 in JSON
**Warning signs:** Timestamps off by hours when viewed in different contexts

### Pitfall 4: Missing RLS Policies
**What goes wrong:** Users can read/modify other users' onboarding status
**Why it happens:** Forgetting to enable RLS or add policies
**How to avoid:** Migration MUST include `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` plus SELECT/UPDATE policies
**Warning signs:** Security audit findings, data leakage

### Pitfall 5: Forgetting Auth Middleware
**What goes wrong:** Endpoints accessible without authentication
**Why it happens:** Route registered in wrong group
**How to avoid:** Add endpoints under `protected` group in serve.go, which has `middleware.Auth()`
**Warning signs:** 200 responses without Authorization header

### Pitfall 6: Soft Reset Deleting Permission Data
**What goes wrong:** Reset clears permission status when it should only clear step completion
**Why it happens:** Misunderstanding CONTEXT.md requirement
**How to avoid:** Reset clears step timestamps BUT preserves permission status/timestamps
**Warning signs:** Permission data lost after reset, requiring re-prompting at OS level

## Code Examples

Verified patterns from the existing codebase:

### Handler Pattern (from geofence.go)
```go
// Source: apps/backend/internal/handlers/geofence.go
type OnboardingHandler struct {
    onboardingService service.OnboardingService
}

func NewOnboardingHandler(onboardingService service.OnboardingService) *OnboardingHandler {
    return &OnboardingHandler{
        onboardingService: onboardingService,
    }
}

// GetOnboardingStatus handles GET /api/v1/users/onboarding
func (h *OnboardingHandler) GetOnboardingStatus(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        requestID := apierror.GetRequestID(c)
        apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
        return
    }

    status, err := h.onboardingService.GetOnboardingStatus(c.Request.Context(), userID.(string))
    if err != nil {
        log := logger.Ctx(c.Request.Context())
        log.Error("failed to get onboarding status", logger.Err(err))
        requestID := apierror.GetRequestID(c)
        apierror.WriteProblem(c, apierror.NewInternalError(requestID))
        return
    }

    c.JSON(http.StatusOK, status)
}
```

### Repository Upsert Pattern (from supabase client)
```go
// Source: apps/backend/pkg/supabase/client.go (Upsert method exists)
func (r *onboardingStatusRepository) GetOrCreate(ctx context.Context, userID string) (*models.OnboardingStatus, error) {
    // Use upsert to atomically create or get
    data := map[string]interface{}{
        "user_id":   userID,
        "completed": false,
    }

    body, err := r.client.Upsert("onboarding_status", data, "user_id")
    if err != nil {
        return nil, fmt.Errorf("failed to get/create onboarding status: %w", err)
    }

    var statuses []models.OnboardingStatus
    if err := json.Unmarshal(body, &statuses); err != nil {
        return nil, fmt.Errorf("failed to unmarshal response: %w", err)
    }

    if len(statuses) == 0 {
        return nil, fmt.Errorf("no onboarding status returned")
    }

    return &statuses[0], nil
}
```

### Service Validation Pattern
```go
// Source: apps/backend/internal/service/geofence.go (validation style)
func (s *onboardingService) UpdateOnboardingStatus(ctx context.Context, userID string, req *models.UpdateOnboardingStatusRequest) (*models.OnboardingStatus, error) {
    // Validate permission status values
    if err := validatePermissionStatus(req.NotificationsStatus, "notifications_status"); err != nil {
        return nil, err
    }
    if err := validatePermissionStatus(req.HealthkitStatus, "healthkit_status"); err != nil {
        return nil, err
    }
    if err := validatePermissionStatus(req.LocationStatus, "location_status"); err != nil {
        return nil, err
    }

    // Build update object
    status := &models.OnboardingStatus{
        UserID:    userID,
        Completed: req.Completed,
        // ... map all fields
    }

    return s.onboardingRepo.Update(ctx, userID, status)
}
```

### Migration Pattern (from geofences migration)
```sql
-- Source: supabase/migrations/20251116000000_add_geofences.sql
CREATE TABLE IF NOT EXISTS public.onboarding_status (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    completed BOOLEAN NOT NULL DEFAULT FALSE,

    -- Step timestamps
    welcome_completed_at TIMESTAMP WITH TIME ZONE,
    auth_completed_at TIMESTAMP WITH TIME ZONE,
    permissions_completed_at TIMESTAMP WITH TIME ZONE,

    -- Permission statuses (granted/denied/skipped/not_requested)
    notifications_status TEXT,
    notifications_completed_at TIMESTAMP WITH TIME ZONE,
    healthkit_status TEXT,
    healthkit_completed_at TIMESTAMP WITH TIME ZONE,
    location_status TEXT,
    location_completed_at TIMESTAMP WITH TIME ZONE,

    -- Standard timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraint for valid permission status values
    CONSTRAINT check_notifications_status
        CHECK (notifications_status IS NULL OR notifications_status IN ('granted', 'denied', 'skipped', 'not_requested')),
    CONSTRAINT check_healthkit_status
        CHECK (healthkit_status IS NULL OR healthkit_status IN ('granted', 'denied', 'skipped', 'not_requested')),
    CONSTRAINT check_location_status
        CHECK (location_status IS NULL OR location_status IN ('granted', 'denied', 'skipped', 'not_requested'))
);

-- Enable RLS
ALTER TABLE public.onboarding_status ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own onboarding status"
    ON public.onboarding_status FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own onboarding status"
    ON public.onboarding_status FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own onboarding status"
    ON public.onboarding_status FOR UPDATE
    USING (auth.uid() = user_id);

-- Trigger for updated_at
CREATE TRIGGER update_onboarding_status_updated_at
    BEFORE UPDATE ON public.onboarding_status
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Grant permissions
GRANT ALL ON public.onboarding_status TO authenticated;
GRANT ALL ON public.onboarding_status TO service_role;
```

## API Design Recommendations

Based on CONTEXT.md discretion areas:

### API Path
**Recommendation:** `/api/v1/users/onboarding`
**Reasoning:** Follows REST convention (resource under user), consistent with `/me` pattern

### Response Structure (Flat vs Nested)
**Recommendation:** Flat structure
**Reasoning:** Simpler parsing on iOS, matches existing model patterns

```json
{
  "user_id": "uuid",
  "completed": false,
  "welcome_completed_at": "2026-01-20T10:00:00Z",
  "auth_completed_at": "2026-01-20T10:01:00Z",
  "permissions_completed_at": null,
  "notifications_status": "granted",
  "notifications_completed_at": "2026-01-20T10:02:00Z",
  "healthkit_status": "not_requested",
  "healthkit_completed_at": null,
  "location_status": "skipped",
  "location_completed_at": "2026-01-20T10:02:30Z",
  "created_at": "2026-01-20T10:00:00Z",
  "updated_at": "2026-01-20T10:02:30Z"
}
```

### Reset Endpoint
**Recommendation:** `DELETE /api/v1/users/onboarding` for soft reset
**Reasoning:**
- DELETE semantically means "remove/clear" which matches soft reset
- Returns 200 with reset state (not 204) so iOS can see new state
- Soft reset: clears `completed` and step timestamps, preserves permission data

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Existing profiles table | Separate onboarding_status table | CONTEXT.md decision | Better separation of concerns |
| JSONB for flexible fields | Fixed columns | CONTEXT.md decision | DB-level validation, better queries |

**Deprecated/outdated:**
- profiles table migration (20260109000000) exists but won't be used for this phase per CONTEXT.md

## Open Questions

Things that couldn't be fully resolved:

1. **Auto-creation trigger vs service-level creation**
   - What we know: Can use DB trigger (like profiles table) or service-level GetOrCreate
   - What's unclear: Performance implications of trigger vs explicit creation
   - Recommendation: Use service-level GetOrCreate for consistency with existing patterns; avoid trigger complexity

2. **Relationship to existing profiles table**
   - What we know: profiles table already exists with some onboarding fields
   - What's unclear: Whether to migrate data or start fresh
   - Recommendation: Ignore profiles table for this phase - CONTEXT.md decided on separate table

## Sources

### Primary (HIGH confidence)
- `apps/backend/internal/handlers/geofence.go` - Handler pattern reference
- `apps/backend/internal/service/geofence.go` - Service pattern reference
- `apps/backend/internal/repository/geofence.go` - Repository pattern reference
- `supabase/migrations/20251116000000_add_geofences.sql` - Migration pattern reference
- `apps/backend/cmd/trendy-api/serve.go` - Route wiring pattern
- `apps/backend/pkg/supabase/client.go` - Upsert capability confirmed
- `apps/backend/internal/apierror/` - Error handling patterns

### Secondary (MEDIUM confidence)
- CONTEXT.md phase decisions - User requirements

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - using existing codebase patterns
- Architecture: HIGH - directly follows geofence pattern
- Pitfalls: HIGH - based on existing migration and handler patterns
- API Design: MEDIUM - some discretionary choices made

**Research date:** 2026-01-20
**Valid until:** 2026-02-20 (stable patterns, no external dependencies)
