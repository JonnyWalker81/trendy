# Codebase Concerns

**Analysis Date:** 2025-01-15

## Tech Debt

**Deprecated Models Still in Codebase:**
- Issue: Two deprecated SwiftData models exist alongside their replacements
- Files: `apps/ios/trendy/Models/QueuedOperation.swift`, `apps/ios/trendy/Models/HealthKitConfiguration.swift`
- Impact: Schema confusion, potential SwiftData migration issues, code maintenance burden
- Fix approach: Remove deprecated models after confirming no references remain, update SwiftData schema migration plan

**Extensive Debug Print Statements:**
- Issue: 320+ `print()` statements scattered across iOS codebase alongside proper structured logging
- Files: `apps/ios/trendy/Services/HealthKitService.swift` (78 occurrences), `apps/ios/trendy/Services/GeofenceManager.swift` (45), `apps/ios/trendy/Utilities/CalendarImportManager.swift` (10+)
- Impact: Console noise in production, inconsistent logging, potential PII exposure
- Fix approach: Replace all `print()` calls with `Log.{category}.{level}()` calls, ensure debug output is #if DEBUG guarded

**Debug Storage View Exposed in Release:**
- Issue: TODO comment indicates debug UI should be wrapped in #if DEBUG
- Files: `apps/ios/trendy/Views/Settings/EventTypeSettingsView.swift:106`
- Impact: Developer tools accessible to end users
- Fix approach: Add `#if DEBUG` guard around developer section in settings

**Google Sign-In Not Implemented:**
- Issue: GoogleSignInService has all implementation commented out with TODO markers
- Files: `apps/ios/trendy/Services/GoogleSignInService.swift:64, :113, :125`
- Impact: Feature incomplete, code is placeholder-only, throws `notConfigured` error always
- Fix approach: Either complete GoogleSignIn-iOS integration or remove the placeholder service

**Web App Has Zero Tests:**
- Issue: No test files found in `apps/web/src/`
- Files: `apps/web/src/**/*.test.{ts,tsx}` - 0 files found
- Impact: No regression protection for web frontend, high risk during refactors
- Fix approach: Add Vitest tests for critical flows (auth, event CRUD, API client)

**Backend Test Coverage Minimal:**
- Issue: Only 2 test files for 46 Go source files (~4% file coverage)
- Files: `apps/backend/internal/service/event_test.go`, `apps/backend/internal/middleware/cors_test.go`
- Impact: Core business logic untested (handlers, repositories, most services)
- Fix approach: Prioritize tests for `event.go`, `event_type.go`, `analytics.go`, and auth middleware

## Known Bugs

**Backend Go Tests Cannot Run:**
- Symptoms: `go test ./...` fails with "directory prefix . does not contain main module"
- Files: `apps/backend/`
- Trigger: Running tests from wrong directory or module configuration issue
- Workaround: Must run from `apps/backend` directory with proper GOPATH setup

## Security Considerations

**Hardcoded Localhost URLs in iOS Code:**
- Risk: Development URLs could leak to production if DEBUG flags fail
- Files: `apps/ios/trendy/ContentView.swift:133`, `apps/ios/trendy/Views/Onboarding/*.swift`
- Current mitigation: Should be guarded by environment configuration
- Recommendations: Ensure all localhost URLs are strictly in DEBUG builds only, audit all occurrences

**CORS Allows HTTP in Production (with warning):**
- Risk: Man-in-the-middle attacks possible with HTTP origins
- Files: `apps/backend/internal/middleware/cors.go:160`
- Current mitigation: Warning logged but request allowed
- Recommendations: Consider rejecting HTTP origins in production rather than just warning

**Service Key vs Anon Key Confusion Potential:**
- Risk: Using wrong key type can bypass RLS or expose service-level access
- Files: `apps/backend/pkg/supabase/client.go`
- Current mitigation: Backend uses service_key, iOS uses anon key as documented
- Recommendations: Add validation on startup to detect key type mismatches

**No Request Timeout Configuration:**
- Risk: Slow requests could exhaust server resources
- Files: `apps/backend/pkg/supabase/client.go` - uses `http.DefaultClient`
- Current mitigation: None found
- Recommendations: Configure explicit timeouts for HTTP client (connection, read, write)

## Performance Bottlenecks

**HealthKitService is Massive Single File:**
- Problem: 1,972 lines in one file - largest in codebase
- Files: `apps/ios/trendy/Services/HealthKitService.swift`
- Cause: Accumulation of workout types, sleep tracking, steps, and configuration
- Improvement path: Split into HealthKitWorkoutService, HealthKitSleepService, etc.

**EventStore.swift Complexity:**
- Problem: 1,354 lines handling both local and backend modes
- Files: `apps/ios/trendy/ViewModels/EventStore.swift`
- Cause: Hybrid local/backend architecture with sync logic
- Improvement path: Extract SyncCoordinator, separate local-only and backend-aware code paths

**Intelligence Service (956 lines):**
- Problem: Large service computing insights with no caching in DB queries
- Files: `apps/backend/internal/service/intelligence.go`
- Cause: Complex correlation and pattern analysis
- Improvement path: Consider background job processing for insight computation

## Fragile Areas

**iOS Sync Engine:**
- Files: `apps/ios/trendy/Services/Sync/SyncEngine.swift` (1,116 lines)
- Why fragile: Complex cursor-based sync with bootstrap logic, pending delete tracking
- Safe modification: Test thoroughly with offline/online transitions, multiple devices
- Test coverage: No unit tests found for SyncEngine

**HealthKit Authorization State:**
- Files: `apps/ios/trendy/Services/HealthKitService.swift:55-86`
- Why fragile: Relies on UserDefaults + App Group + HealthKitSettings fallback chain
- Safe modification: Must verify on fresh install, reinstall after deletion, and upgrade scenarios
- Test coverage: Manual testing only

**Schema Migration:**
- Files: `apps/ios/trendy/Models/Migration/SchemaMigrationPlan.swift`
- Why fragile: SwiftData schema migrations can fail silently
- Safe modification: Test with actual data from previous versions
- Test coverage: Limited

## Scaling Limits

**In-Memory Rate Limiter:**
- Current capacity: Per-server instance only
- Limit: Won't work correctly with multiple backend instances
- Scaling path: Move to Redis-based rate limiting for distributed deployment

**InsightCache Duration:**
- Current: 6 hours cache validity
- Limit: Heavy users may trigger frequent recomputation
- Scaling path: Consider event-driven invalidation rather than time-based

## Dependencies at Risk

**None Critical Identified**

The project uses stable, well-maintained dependencies (Supabase, HealthKit, SwiftData, Gin). No immediate dependency risks detected.

## Missing Critical Features

**No Bidirectional Sync:**
- Problem: Backend changes not pushed to iOS clients
- Blocks: Multi-device usage where web changes should appear on iOS
- Current state: iOS must manually refresh to see backend changes

**No Conflict Resolution Strategy:**
- Problem: Last-write-wins implicit behavior
- Blocks: Reliable multi-device editing
- Current state: Documented in CLAUDE.md as "future enhancement"

## Test Coverage Gaps

**iOS Services Layer:**
- What's not tested: APIClient, SyncEngine, HealthKitService, GeofenceManager
- Files: `apps/ios/trendy/Services/*.swift`
- Risk: Core data flow and sync logic could break silently
- Priority: High

**Backend Handlers:**
- What's not tested: All handler files (`internal/handlers/*.go`)
- Files: `apps/backend/internal/handlers/`
- Risk: HTTP request/response handling, error codes, validation
- Priority: High

**Backend Repositories:**
- What's not tested: All repository implementations
- Files: `apps/backend/internal/repository/*.go`
- Risk: Database queries, RLS enforcement, data integrity
- Priority: Medium

**Web App Everything:**
- What's not tested: Entire frontend codebase
- Files: `apps/web/src/**/*`
- Risk: UI regressions, API integration, auth flows
- Priority: High

---

*Concerns audit: 2025-01-15*
