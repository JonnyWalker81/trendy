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

## iOS App (Currently Standalone)

The iOS app uses SwiftData for local storage and is not yet connected to the backend. It has its own event tracking implementation.

**Key Differences from Web:**
- No backend sync
- Local-only data storage
- Calendar integration with iOS EventKit
- Different data models (SwiftData vs. Supabase schema)

Future work will sync iOS app with backend API.
