# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Trendy is a cross-platform event tracking application with three main components:
- **iOS App**: SwiftUI + SwiftData (local-first)
- **Web App**: React + TypeScript + Vite
- **Backend API**: Go + Gin + Supabase

The iOS app is currently standalone with local storage. The web app and backend are integrated and share authentication via Supabase.

## Essential Commands

### Development Workflow

```bash
# Start backend API (port 8080)
just dev-backend
# OR: cd apps/backend && go run ./cmd/trendy-api serve

# Start web app (port 3000)
just dev-web
# OR: cd apps/web && yarn dev

# Run both (instructions for separate terminals)
just dev
```

### Building

```bash
# Build everything
just build

# Build individual apps
just build-backend    # Creates apps/backend/trendy-api binary
just build-web        # Creates apps/web/dist/
just build-ios        # macOS only
```

### Testing

```bash
# Run all tests
just test

# Backend tests
just test-backend
# OR: cd apps/backend && go test ./...

# Test specific Go package
cd apps/backend && go test ./internal/service -v
```

### Code Quality

```bash
# Lint everything
just lint

# Format everything
just fmt

# Backend-specific
cd apps/backend && go fmt ./...
cd apps/backend && go vet ./...
```

### Database Operations

```bash
# Show setup instructions
just db-setup

# Show migration SQL (copy to Supabase SQL Editor)
just db-show-migration

# Link to remote Supabase project
just db-link <project-ref>
```

## Architecture Deep Dive

### Backend Clean Architecture

The Go backend follows strict layering: **Handler → Service → Repository**

```
Request Flow:
HTTP Request → Middleware (Auth/CORS/Logging) → Handler → Service → Repository → Supabase
```

**Key Principles:**
- Handlers only handle HTTP serialization/deserialization
- Services contain ALL business logic and validation
- Repositories handle database operations only
- Models are pure data structures with no behavior
- Middleware wraps routes for cross-cutting concerns

**Dependency Injection:**
All layers are wired together in `apps/backend/cmd/trendy-api/serve.go`:
1. Initialize Supabase client
2. Create repositories (inject Supabase client)
3. Create services (inject repositories)
4. Create handlers (inject services)
5. Register routes with middleware

**Adding New Endpoints:**
1. Add model to `internal/models/models.go`
2. Define repository interface in `internal/repository/interfaces.go`
3. Implement repository in `internal/repository/<feature>.go`
4. Define service interface in `internal/service/interfaces.go`
5. Implement service in `internal/service/<feature>.go`
6. Create handler in `internal/handlers/<feature>.go`
7. Wire up in `cmd/trendy-api/serve.go`

### Backend Configuration System

Uses Viper with multiple config sources (precedence order):
1. Command-line flags (`--port`)
2. Environment variables (`SUPABASE_URL`, `PORT`)
3. Config file (`apps/backend/config.yaml`)
4. Defaults

**CRITICAL:** Backend requires `service_role` key, NOT `anon` key. The service_role key:
- Verifies user JWT tokens
- Bypasses Row Level Security for backend operations
- Is used in `apps/backend/config.yaml` as `service_key`

### Authentication Flow

**Web App → Backend:**
1. User logs in via Supabase client in web app
2. Web app receives JWT access token
3. Web app sends token in `Authorization: Bearer <token>` header
4. Backend `Auth` middleware verifies token with Supabase
5. User ID extracted and stored in Gin context
6. Repositories use user token for RLS enforcement

**Token Storage:**
- Frontend: Managed by Supabase JS client (localStorage)
- Backend: Extracted from Authorization header per request
- User context: Stored in `c.Set("user_id")` and `c.Set("user_token")`

### Web App State Management

Uses TanStack Query (React Query) for server state:
- Query keys defined in hook files (`useEventTypes.ts`, `useEvents.ts`)
- Automatic caching, refetching, and invalidation
- Mutations trigger query invalidation for consistency

**Data Flow:**
```
Component → Custom Hook → API Client → Backend API → Supabase
```

**API Client Pattern:**
All API calls go through `apps/web/src/lib/api-client.ts`:
- Centralized auth header injection
- Consistent error handling
- Typed request/response via TypeScript

### Vite Proxy Configuration

The web app proxies API requests to avoid CORS:
```
/api/* → http://localhost:8080/api/*
```

This is configured in `apps/web/vite.config.ts`. Frontend code calls `/api/v1/events`, Vite forwards to backend.

### Database & Supabase

**Row Level Security (RLS):**
All tables have RLS policies that filter by `user_id`. Backend uses service_role key to bypass RLS and manually filters by user ID from JWT.

**Key Tables:**
- `users` - Extended user profile (auto-created via trigger)
- `event_types` - User-defined categories (name, color, icon)
- `events` - Event records with timestamps, references event_types

**Migration Management:**
- Migrations in `supabase/migrations.sql`
- Applied manually via Supabase SQL Editor
- No automated migration runner (yet)

## Common Gotchas

### Backend Won't Start
- Check `apps/backend/config.yaml` has `service_key`, not `anon` key
- Verify Supabase URL and service key are correct
- Backend reads from `config.yaml` OR environment variables

### Event Types Not Loading
- Ensure backend is running on port 8080
- Check browser console for CORS or auth errors
- Verify user is logged in (check Network tab for 401s)
- Confirm backend has service_role key, not anon key

### CORS Errors
- Backend must be running for Vite proxy to work
- CORS middleware in `apps/backend/internal/middleware/cors.go` allows all origins in dev

### Authentication Issues
- Web app uses anon key (public), backend uses service_role key (secret)
- JWT tokens expire - check token in localStorage
- Backend verifies tokens via Supabase Auth API

## Development Environment

**Nix Flake:**
Provides reproducible environment with Node.js 20, Go 1.22, Yarn, Just, and Postgres tools.

```bash
# Enter dev shell
nix develop

# Or use direnv for auto-activation
direnv allow
```

**Without Nix:**
- Node.js 20+
- Go 1.21+
- Yarn package manager
- Just command runner

## Project Structure Notes

### Monorepo Layout
```
apps/          # All applications
  backend/     # Go API server
  web/         # React web app
  ios/         # SwiftUI iOS app
packages/      # Shared code (currently just TypeScript types)
supabase/      # Database migrations
```

### Backend Import Paths
All backend imports use module path: `github.com/JonnyWalker81/trendy/backend`

This is defined in `apps/backend/go.mod` and must be consistent across all Go files.

### Frontend Component Structure
- `pages/` - Route components (Dashboard, Login, EventList, etc.)
- `components/` - Shared UI components organized by feature
- `lib/` - Utilities, hooks, API clients
- `types/` - TypeScript type definitions

## iOS App Backend Integration

The iOS app now supports full backend integration with automatic data migration from local SwiftData to the backend API.

### Architecture Overview

**Hybrid Mode:**
- **Pre-Migration**: Local SwiftData only
- **Post-Migration**: Backend API with local caching for offline support
- **Offline Queue**: Changes made offline are queued and synced when connection returns

**Key Components:**
```
┌─────────────────┐
│  Authentication │  SupabaseService (Supabase Swift SDK)
└─────────────────┘
┌─────────────────┐
│  Data Migration │  MigrationManager (one-time sync on first login)
└─────────────────┘
┌─────────────────┐
│   API Client    │  APIClient (backend HTTP communication)
└─────────────────┘
┌─────────────────┐
│  Offline Queue  │  SyncQueue (queue offline changes)
└─────────────────┘
┌─────────────────┐
│   Event Store   │  EventStore (hybrid local/backend mode)
└─────────────────┘
```

### Setup Instructions

**1. Add Supabase Swift SDK**

See `apps/ios/SETUP_SUPABASE.md` for detailed instructions.

In Xcode:
- File → Add Packages
- URL: `https://github.com/supabase/supabase-swift`
- Version: 2.0.0+

**2. Environment Configuration**

The iOS app supports multiple environments (Local, Staging, Production, TestFlight) using xcconfig files. See `apps/ios/ENVIRONMENT_SETUP.md` for complete documentation.

**Quick Setup:**

1. Copy the secrets template:
   ```bash
   cd apps/ios/Config
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```

2. In Xcode, configure build configurations and schemes (one-time setup):
   - Link xcconfig files to build configurations
   - Create shared schemes for each environment
   - See `apps/ios/ENVIRONMENT_SETUP.md` for detailed steps

3. Switch environments by selecting the appropriate scheme in Xcode:
   - **Trendy (Local)** - Local development (localhost backend + Supabase)
   - **Trendy (Staging)** - Remote staging environment
   - **Trendy (TestFlight)** - Beta builds for TestFlight
   - **Trendy (Production)** - Production/App Store builds

**Environment Variables:**

All environment-specific settings are defined in `apps/ios/Config/*.xcconfig` files:
- `SUPABASE_URL` - Supabase backend URL
- `SUPABASE_ANON_KEY` - Supabase anonymous key
- `API_BASE_URL` - Go backend API URL
- `PRODUCT_BUNDLE_IDENTIFIER` - Unique bundle ID per environment

**IMPORTANT:** Use the **anon key** (NOT service_role key) for iOS app.

**Configuration Files:**
- `apps/ios/Config/Debug.xcconfig` - Local development settings
- `apps/ios/Config/Staging.xcconfig` - Remote staging settings
- `apps/ios/Config/Release.xcconfig` - Production settings
- `apps/ios/Config/TestFlight.xcconfig` - TestFlight beta settings
- `apps/ios/Config/Secrets.xcconfig` - Developer-specific overrides (gitignored)

**3. Update SwiftData Schema**

The app now includes `QueuedOperation` model for offline sync queue. Schema is automatically managed by SwiftData.

### Authentication Flow

**iOS App → Supabase → Backend:**
1. User signs up/logs in via `SupabaseService`
2. Supabase returns JWT access token (stored in Keychain)
3. `APIClient` injects token in `Authorization: Bearer <token>` header
4. Backend verifies token and extracts user ID
5. All API requests are user-scoped

**Views:**
- `LoginView` - Email/password sign in
- `SignupView` - New user registration
- `AuthViewModel` - Manages auth state

### Data Migration

**Automatic Migration on First Login:**
1. User authenticates with backend
2. `MigrationView` appears if local data exists
3. `MigrationManager` syncs all data to backend:
   - Uploads EventTypes first (detects duplicates by name)
   - Maps iOS UUIDs → Backend UUIDs
   - Uploads Events using mapped EventType IDs
4. Local data kept indefinitely as backup
5. App switches to backend mode

**Zero Data Loss Guarantee:**
- All local EventTypes and Events are preserved
- Duplicate detection prevents data duplication
- Batch processing with progress tracking
- Retry logic for network failures
- Local data never deleted (kept as backup)

**Files:**
- `MigrationManager.swift` - Migration logic
- `MigrationView.swift` - Progress UI
- `QueuedOperation.swift` - Offline operation model

### Hybrid Data Layer

**EventStore Modes:**
- `useBackend = false` - Local-only mode (pre-migration)
- `useBackend = true` - Backend mode with local caching (post-migration)

**Online Behavior:**
- Fetch from backend API
- Cache results in SwiftData
- Create/Update/Delete on backend immediately
- Update local cache

**Offline Behavior:**
- Read from local cache
- Create/Update/Delete locally
- Queue operations in `QueuedOperation` table
- Auto-sync when connection restored

**CRUD Flow:**
```
recordEvent() →
  ├─ Online:  Backend API → Cache locally
  └─ Offline: Create locally → Queue for sync

fetchData() →
  ├─ Online:  Backend API → Refresh cache
  └─ Offline: Read from cache
```

### Offline Sync Queue

**SyncQueue** manages pending operations:
- Network monitoring (detects online/offline transitions)
- Automatic sync when connection restored
- Retry logic with exponential backoff
- Max 5 retry attempts per operation
- Batch processing to avoid timeouts

**Queue Processing:**
1. Operation created offline → Inserted into `QueuedOperation` table
2. Network restored → `SyncQueue` detects change
3. Operations processed in FIFO order
4. Success → Remove from queue
5. Failure → Increment attempt count, retry later

### API Client

**APIClient.swift** handles all HTTP communication:
- Automatic JWT token injection
- ISO8601 date encoding/decoding
- Error handling with typed `APIError` enum
- Supports all backend endpoints:
  - Events: GET, POST, PUT, DELETE
  - Event Types: GET, POST, PUT, DELETE
  - Analytics: summary, trends, event-type-specific

**Request Flow:**
```swift
let events = try await apiClient.getEvents()
// Internally:
// 1. Get access token from SupabaseService
// 2. Build request with Authorization header
// 3. Perform URLSession request
// 4. Decode JSON response
```

### Calendar Integration

**Preserved iOS-Only Feature:**
- Calendar sync with iOS EventKit remains iOS-exclusive
- `calendarEventId` stored locally only (not synced to backend)
- `externalId` and `originalTitle` ARE synced (for calendar imports)
- Calendar sync works in both local and backend modes

### File Structure

```
apps/ios/trendy/
├── Models/
│   ├── Event.swift              # SwiftData model
│   ├── EventType.swift          # SwiftData model
│   ├── QueuedOperation.swift    # Offline queue model
│   └── API/
│       └── APIModels.swift      # Backend API models (Codable)
├── Services/
│   ├── SupabaseService.swift   # Auth service
│   ├── APIClient.swift          # HTTP client
│   ├── MigrationManager.swift  # Data migration
│   └── SyncQueue.swift          # Offline sync queue
├── ViewModels/
│   ├── EventStore.swift         # Hybrid data layer
│   └── AuthViewModel.swift      # Auth state
└── Views/
    ├── Auth/
    │   ├── LoginView.swift
    │   └── SignupView.swift
    └── Migration/
        └── MigrationView.swift
```

### Testing the Integration

**Prerequisites:**
- Backend running on `localhost:8080`
- Supabase credentials configured in Info.plist
- Supabase Swift SDK package added to Xcode project

**Test Flow:**
1. Build and run iOS app
2. Create local events/event types (pre-auth testing)
3. Sign up/login with email/password
4. Watch migration progress (should upload all local data)
5. Verify events appear in web app
6. Create new events in iOS app (should sync to backend)
7. Enable Airplane Mode → create events offline
8. Disable Airplane Mode → verify auto-sync

### Common Issues

**Migration Fails:**
- Check backend is running and accessible
- Verify Supabase credentials are correct
- Check Network tab in Xcode console for errors
- Migration can be retried from error screen

**Events Not Syncing:**
- Verify `migration_completed` flag is set (check @AppStorage)
- Check `use_backend` flag is true
- Ensure user is authenticated
- Check for queued operations in SwiftData

**Auth Token Expired:**
- Supabase SDK auto-refreshes tokens
- If refresh fails, user must re-authenticate
- Check Xcode console for token-related errors

**Offline Queue Not Processing:**
- Verify network monitor is detecting connection
- Check `SyncQueue.pendingCount` in debugger
- Manually trigger sync with `syncQueue.manualSync()`

### Backend API Compatibility

**iOS Models → Backend Schema Mapping:**

| iOS Model | Backend Schema | Notes |
|-----------|----------------|-------|
| `Event.id` | `events.id` | UUID → string |
| `Event.timestamp` | `events.timestamp` | Date → ISO8601 |
| `Event.notes` | `events.notes` | Optional string |
| `Event.eventType.id` | `events.event_type_id` | UUID → string |
| `Event.isAllDay` | `events.is_all_day` | Boolean |
| `Event.endDate` | `events.end_date` | Optional Date → ISO8601 |
| `Event.sourceType` | `events.source_type` | Enum → string ("manual"/"imported") |
| `Event.externalId` | `events.external_id` | Optional string |
| `Event.originalTitle` | `events.original_title` | Optional string |
| `Event.calendarEventId` | NOT SYNCED | iOS-only, local storage |
| `EventType.id` | `event_types.id` | UUID → string |
| `EventType.name` | `event_types.name` | String |
| `EventType.colorHex` | `event_types.color` | Hex color string |
| `EventType.iconName` | `event_types.icon` | SF Symbol or generic name |

### Future Enhancements

**Planned Improvements:**
- Bidirectional sync (backend changes reflected in iOS)
- Conflict resolution (last-write-wins currently)
- Background sync (iOS Background Tasks)
- Push notifications for server-side changes
- Optimistic UI updates
- Differential sync (only changed data)

## Structured Logging

The project uses structured logging across all platforms with consistent patterns and environment-based verbosity.

### Log Levels

| Level | When to Use |
|-------|-------------|
| **debug** | Development debugging, request/response details, verbose tracing |
| **info** | Significant events: startup, auth success, sync completion |
| **warn** | Recoverable issues: rate limits, auth failures, validation errors |
| **error** | Unrecoverable errors: crashes, connection failures, data corruption |

### Environment-Based Defaults

| Environment | Default Level |
|-------------|---------------|
| Development | debug |
| Staging | info |
| Production | warn |

### Backend (Go) - `internal/logger/`

**Abstraction Pattern:** Interface-based logger that can swap implementations.

```go
// Using the logger in handlers/services
log := logger.Ctx(ctx)  // Gets logger with request_id and user_id
log.Info("operation completed",
    logger.String("event_id", id),
    logger.Duration("duration", elapsed),
)

// Available field helpers
logger.String(key, value)
logger.Int(key, value)
logger.Duration(key, value)
logger.Err(err)
```

**Configuration (environment variables):**
- `LOG_LEVEL` or `TRENDY_LOGGING_LEVEL`: debug, info, warn, error
- `LOG_FORMAT` or `TRENDY_LOGGING_FORMAT`: json, text
- `LOG_BODIES` or `TRENDY_LOGGING_LOG_BODIES`: true/false (request/response bodies)

**Key Files:**
- `internal/logger/logger.go` - Interface and field helpers
- `internal/logger/slog.go` - slog implementation
- `internal/logger/context.go` - Request ID and user ID propagation

### Web App (TypeScript) - `src/lib/logger.ts`

**Pattern:** Lightweight structured logger with environment-aware output.

```typescript
import { apiLogger, errorContext } from './logger'

// Using named loggers
apiLogger.info('Request completed', { operation: 'getEvents', status: 200 })
apiLogger.error('Request failed', { ...errorContext(error), endpoint: '/events' })

// Available loggers
logger      // General purpose
apiLogger   // API/network operations
authLogger  // Authentication
uiLogger    // UI operations
```

**Configuration:**
- `VITE_LOG_LEVEL`: debug, info, warn, error
- Development: Pretty console output with colors
- Production: JSON output for aggregation

### iOS (Swift) - `Utilities/Logger.swift`

**Pattern:** Apple's unified logging (os.Logger) with categories.

```swift
// Using category-specific loggers
Log.api.info("Request completed", context: .with { ctx in
    ctx.add("endpoint", "/events")
    ctx.add("status", 200)
    ctx.add(duration: elapsed)
})

Log.auth.error("Login failed", error: error)

// Available categories
Log.api        // API/network
Log.auth       // Authentication
Log.sync       // Data synchronization
Log.migration  // Data migration
Log.geofence   // Location
Log.calendar   // Calendar integration
Log.ui         // UI operations
Log.data       // Storage operations
```

**Context Builder:**
```swift
Log.api.debug("API call", context: .with { ctx in
    ctx.add("method", "GET")
    ctx.add("path", endpoint)
    ctx.add("user_id", userId)
    ctx.add(error: error)       // Automatically extracts message
    ctx.add(duration: elapsed)  // Converts to milliseconds
})
```

### Common Field Names

Use consistent field names across platforms:

| Field | Description |
|-------|-------------|
| `request_id` | Unique ID for request tracing |
| `user_id` | Authenticated user ID |
| `operation` | Name of the operation being performed |
| `duration` / `duration_ms` | Time elapsed |
| `status` / `status_code` | HTTP status code |
| `error` / `error_message` | Error description |
| `endpoint` / `path` | API endpoint |
| `method` | HTTP method |

### Security Guidelines

1. **Never log sensitive data:**
   - Passwords, tokens, API keys
   - Personal information (full names, addresses)
   - Request/response bodies in production

2. **Sanitize user input:**
   - Truncate long values
   - Redact authorization headers

3. **Environment awareness:**
   - Debug output only in development
   - JSON format in production for aggregation
