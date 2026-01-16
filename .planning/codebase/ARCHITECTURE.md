# Architecture

**Analysis Date:** 2026-01-15

## Pattern Overview

**Overall:** Monorepo with three platform-specific clients (iOS, Web, Backend API) sharing a common backend

**Key Characteristics:**
- Backend follows Clean Architecture (Handler → Service → Repository)
- iOS uses local-first hybrid architecture with sync engine
- Web uses React Query for server state management
- All platforms share Supabase for auth and data persistence
- UUIDv7 client-generated IDs enable offline-first operation

## Layers

### Backend (Go)

**Handler Layer:**
- Purpose: HTTP request/response serialization
- Location: `apps/backend/internal/handlers/`
- Contains: Request binding, response formatting, HTTP status codes
- Depends on: Service interfaces
- Used by: HTTP router (Gin)

**Service Layer:**
- Purpose: Business logic and validation
- Location: `apps/backend/internal/service/`
- Contains: Domain operations, authorization checks, data transformation
- Depends on: Repository interfaces
- Used by: Handlers

**Repository Layer:**
- Purpose: Data access abstraction
- Location: `apps/backend/internal/repository/`
- Contains: Supabase/PostgREST queries, data mapping
- Depends on: Supabase client
- Used by: Services

**Middleware:**
- Purpose: Cross-cutting concerns
- Location: `apps/backend/internal/middleware/`
- Contains: Auth (JWT verification), CORS, rate limiting, logging, security headers, idempotency

### iOS (Swift)

**ViewModels:**
- Purpose: UI state management and business logic
- Location: `apps/ios/trendy/ViewModels/`
- Contains: `EventStore`, `AuthViewModel`, `OnboardingViewModel`, `AnalyticsViewModel`, `InsightsViewModel`
- Uses: SwiftData ModelContext, Services

**Services:**
- Purpose: External system integration
- Location: `apps/ios/trendy/Services/`
- Contains: `APIClient`, `SupabaseService`, `SyncEngine`, `HealthKitService`, `GeofenceManager`, `NotificationManager`
- Key: SyncEngine handles bidirectional sync with cursor-based incremental pull

**Models:**
- Purpose: Data entities and persistence
- Location: `apps/ios/trendy/Models/`
- Contains: SwiftData models (`Event`, `EventType`, `Geofence`, `PropertyDefinition`), API models in `Models/API/`

**Views:**
- Purpose: SwiftUI view hierarchy
- Location: `apps/ios/trendy/Views/`
- Contains: Feature-organized views (Auth, Calendar, Dashboard, Geofence, HealthKit, Insights, Settings)

### Web (React)

**Pages:**
- Purpose: Route-level components
- Location: `apps/web/src/pages/`
- Contains: `Dashboard`, `Login`, `Signup`, `EventList`, `Analytics`, `Settings`

**Hooks (API):**
- Purpose: Server state management with TanStack Query
- Location: `apps/web/src/hooks/api/`
- Contains: `useEvents`, `useEventTypes`, `useAnalytics`, `usePropertyDefinitions`
- Pattern: Query keys, fetch functions, mutations with cache invalidation

**Components:**
- Purpose: Reusable UI elements
- Location: `apps/web/src/components/`
- Contains: Feature-organized components (ui, events, event-types, analytics, properties)

**Lib:**
- Purpose: Utilities and shared logic
- Location: `apps/web/src/lib/`
- Contains: `api-client.ts`, `supabase.ts`, `useAuth.tsx`, `logger.ts`, `queryClient.ts`

## Data Flow

### Web App Request Flow

```
Component
    ↓ uses hook
Custom Hook (useEvents, useEventTypes, etc.)
    ↓ calls query/mutation
TanStack Query
    ↓ fetches via
API Client (api-client.ts)
    ↓ sends HTTP request with Bearer token
Vite Proxy (/api/* → localhost:8080)
    ↓ forwards to
Backend API
    ↓ processes via
Middleware → Handler → Service → Repository → Supabase
```

### iOS App Sync Flow

```
User Action / HealthKit / Geofence Trigger
    ↓
EventStore (recordEvent, updateEvent, deleteEvent)
    ↓ saves to
SwiftData (local ModelContext)
    ↓ queues to
SyncEngine.queueMutation()
    ↓ when online
SyncEngine.performSync()
    ├─ flushPendingMutations() → APIClient → Backend
    └─ pullChanges() OR bootstrapFetch()
        ↓
LocalStore upsert/delete
    ↓
SwiftData persistence
```

### Backend Authentication Flow

```
Client (Web/iOS)
    ↓ includes Authorization: Bearer <token>
Auth Middleware
    ↓ extracts token
Supabase.VerifyToken()
    ↓ validates JWT
c.Set("user_id", user.ID)
    ↓ proceeds to
Handler
    ↓ retrieves user_id from context
Service
    ↓ filters by user_id
Repository
    ↓ executes query
Supabase (uses service_role key, bypasses RLS)
```

**State Management:**
- **Backend**: Stateless - all state in Supabase
- **Web**: TanStack Query cache with automatic invalidation
- **iOS**: SwiftData local storage + SyncEngine cursor for incremental sync

## Key Abstractions

### EventRepository Interface (Go)
- Purpose: Data access contract for events
- Location: `apps/backend/internal/repository/interfaces.go`
- Pattern: Repository pattern with CRUD + specialized queries
- Key methods: `Create`, `GetByID`, `GetByUserID`, `Update`, `Delete`, `UpsertHealthKitEvent`, `UpsertHealthKitEventsBatch`

### EventService Interface (Go)
- Purpose: Business logic contract for events
- Location: `apps/backend/internal/service/interfaces.go`
- Pattern: Service layer abstraction
- Key methods: `CreateEvent`, `GetEvent`, `GetUserEvents`, `UpdateEvent`, `DeleteEvent`, `ExportEvents`

### SyncEngine (Swift)
- Purpose: Bidirectional sync orchestrator
- Location: `apps/ios/trendy/Services/Sync/SyncEngine.swift`
- Pattern: Actor-based single-flight sync with cursor-based incremental pull
- Key methods: `performSync`, `queueMutation`, `forceFullResync`, `syncGeofences`

### APIClient (Swift)
- Purpose: HTTP client for backend communication
- Location: `apps/ios/trendy/Services/APIClient.swift`
- Pattern: Generic request method with auth injection, retry logic, idempotency support
- Features: Rate limit handling, exponential backoff, idempotency keys

### TanStack Query Hooks (TypeScript)
- Purpose: Server state management
- Location: `apps/web/src/hooks/api/`
- Pattern: Query keys + fetch functions + mutations with invalidation
- Example: `eventKeys.all`, `useEvents()`, `useCreateEvent()`

## Entry Points

### Backend API
- Location: `apps/backend/cmd/trendy-api/main.go` → `serve.go`
- Triggers: HTTP requests to port 8080
- Responsibilities: Initialize config, logger, Supabase client, repositories, services, handlers, router, middleware

### Web App
- Location: `apps/web/src/main.tsx` → `App.tsx`
- Triggers: Browser navigation
- Responsibilities: Render React app, provide QueryClient and Router, handle auth state

### iOS App
- Location: `apps/ios/trendy/trendyApp.swift`
- Triggers: App launch
- Responsibilities: Initialize services (Supabase, API, Foundation Models, PostHog), configure SwiftData container, set up view hierarchy with environment objects

## Error Handling

**Strategy:** Layer-appropriate error handling with propagation

**Backend Patterns:**
- Handlers: Return appropriate HTTP status codes (400, 401, 404, 409, 500)
- Services: Return wrapped errors with context
- Repositories: Return database errors with `fmt.Errorf` wrapping
- Change log failures: Log but don't fail operation

**iOS Patterns:**
- APIError enum with typed cases (invalidResponse, httpError, serverError, decodingError, networkError, duplicateEvent)
- SyncEngine: Retry with exponential backoff, mark entities as failed after max retries
- EventStore: Set errorMessage property for UI display

**Web Patterns:**
- API client throws typed errors
- TanStack Query handles loading/error states
- Components display error messages from mutation errors

## Cross-Cutting Concerns

**Logging:**
- Backend: Structured logging via `internal/logger/` with slog, context propagation (request_id, user_id)
- iOS: Apple's os.Logger via `Utilities/Logger.swift` with categories (api, auth, sync, geofence, etc.)
- Web: Custom logger in `lib/logger.ts` with named loggers (apiLogger, authLogger, etc.)

**Validation:**
- Backend: Gin binding tags (`binding:"required"`) on request structs
- iOS: Swift type system, optional chaining
- Web: TypeScript types, runtime checks in API responses

**Authentication:**
- Backend: JWT verification via Supabase, user_id stored in Gin context
- iOS: SupabaseService manages session, APIClient injects Bearer token
- Web: useAuth hook manages session, api-client injects token from Supabase client

**Rate Limiting:**
- Backend: `middleware.RateLimit()` (100 req/min general), `middleware.RateLimitAuth()` (10 req/min for auth)
- iOS: APIClient has retry with exponential backoff for 429 responses

**Idempotency:**
- Backend: `middleware.Idempotency()` stores response by Idempotency-Key header
- iOS: SyncEngine generates `clientRequestId` for mutation deduplication

---

*Architecture analysis: 2026-01-15*
