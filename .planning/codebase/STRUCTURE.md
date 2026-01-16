# Codebase Structure

**Analysis Date:** 2026-01-15

## Directory Layout

```
trendy/
├── apps/                       # All applications
│   ├── backend/                # Go API server
│   ├── ios/                    # SwiftUI iOS app
│   ├── web/                    # React web app
│   └── landing/                # Marketing landing page (Cloudflare Pages)
├── packages/                   # Shared code
│   └── shared-types/           # TypeScript type definitions
├── supabase/                   # Database migrations
├── docs/                       # Documentation
├── .planning/                  # GSD planning documents
│   └── codebase/               # Architecture analysis documents
├── .github/                    # GitHub Actions workflows
├── flake.nix                   # Nix development environment
├── justfile                    # Task runner commands
└── CLAUDE.md                   # AI assistant instructions
```

## Directory Purposes

### apps/backend/

- Purpose: Go API server with Clean Architecture
- Contains: HTTP handlers, business services, data repositories
- Key files:
  - `cmd/trendy-api/main.go` - Entry point
  - `cmd/trendy-api/serve.go` - Server bootstrap and DI wiring
  - `internal/handlers/` - HTTP request handlers
  - `internal/service/` - Business logic
  - `internal/repository/` - Data access
  - `internal/middleware/` - Auth, CORS, rate limiting, logging
  - `internal/models/models.go` - Domain types and request/response structs
  - `internal/logger/` - Structured logging
  - `internal/config/config.go` - Configuration loading
  - `pkg/supabase/` - Supabase client wrapper
  - `config.yaml` - Local configuration

### apps/ios/

- Purpose: SwiftUI iOS application with local-first architecture
- Contains: Views, ViewModels, Services, Models
- Key files:
  - `trendy/trendyApp.swift` - App entry point
  - `trendy/ContentView.swift` - Root view router
  - `trendy/ViewModels/EventStore.swift` - Main data store
  - `trendy/ViewModels/AuthViewModel.swift` - Authentication state
  - `trendy/Services/APIClient.swift` - Backend HTTP client
  - `trendy/Services/SupabaseService.swift` - Auth service
  - `trendy/Services/Sync/SyncEngine.swift` - Sync orchestrator
  - `trendy/Services/Sync/LocalStore.swift` - SwiftData helpers
  - `trendy/Services/HealthKitService.swift` - HealthKit integration
  - `trendy/Services/GeofenceManager.swift` - Location services
  - `trendy/Models/Event.swift` - Event SwiftData model
  - `trendy/Models/EventType.swift` - EventType SwiftData model
  - `trendy/Models/API/APIModels.swift` - Backend DTO structs
  - `trendy/Configuration/AppConfiguration.swift` - Environment config
  - `trendy/Utilities/Logger.swift` - Structured logging
  - `Config/*.xcconfig` - Build configurations per environment

### apps/web/

- Purpose: React web application
- Contains: Pages, components, hooks, utilities
- Key files:
  - `src/main.tsx` - Entry point
  - `src/App.tsx` - Router and providers
  - `src/pages/` - Route components (Dashboard, EventList, Analytics, Settings, Login, Signup)
  - `src/components/ui/` - Reusable UI components (card, input, dialog, select, etc.)
  - `src/components/events/` - Event-specific components
  - `src/components/event-types/` - EventType components
  - `src/components/analytics/` - Analytics charts and cards
  - `src/components/properties/` - Property definition components
  - `src/hooks/api/` - TanStack Query hooks
  - `src/lib/api-client.ts` - Backend API client
  - `src/lib/supabase.ts` - Supabase client initialization
  - `src/lib/useAuth.tsx` - Auth hook
  - `src/lib/logger.ts` - Structured logging
  - `src/lib/queryClient.ts` - TanStack Query configuration
  - `src/types/index.ts` - TypeScript type definitions
  - `vite.config.ts` - Vite configuration with API proxy

### apps/landing/

- Purpose: Marketing landing page with waitlist
- Contains: Cloudflare Pages functions, static assets
- Key files:
  - `functions/` - Cloudflare Workers edge functions
  - `migrations/` - D1 database migrations

### packages/shared-types/

- Purpose: Shared TypeScript type definitions
- Contains: Type definitions for cross-package use
- Key files:
  - `src/index.ts` - Type exports

### supabase/

- Purpose: Database schema and migrations
- Contains: SQL migration files
- Key files:
  - `migrations.sql` - Main migration file

## Key File Locations

**Entry Points:**
- `apps/backend/cmd/trendy-api/main.go` - Backend CLI entry
- `apps/web/src/main.tsx` - Web app entry
- `apps/ios/trendy/trendyApp.swift` - iOS app entry

**Configuration:**
- `apps/backend/config.yaml` - Backend local config
- `apps/backend/internal/config/config.go` - Config loading logic
- `apps/web/vite.config.ts` - Vite build config
- `apps/ios/Config/*.xcconfig` - iOS build configs per environment
- `apps/ios/trendy/Configuration/AppConfiguration.swift` - iOS runtime config

**Core Logic:**
- `apps/backend/internal/service/*.go` - Business logic
- `apps/ios/trendy/ViewModels/EventStore.swift` - iOS data layer
- `apps/ios/trendy/Services/Sync/SyncEngine.swift` - iOS sync logic
- `apps/web/src/hooks/api/*.ts` - Web data fetching

**Testing:**
- `apps/backend/*_test.go` - Go tests (co-located)
- `apps/ios/trendyTests/*.swift` - Swift unit tests
- `apps/ios/trendyUITests/*.swift` - Swift UI tests

**Models:**
- `apps/backend/internal/models/models.go` - Backend domain models
- `apps/ios/trendy/Models/*.swift` - iOS SwiftData models
- `apps/ios/trendy/Models/API/APIModels.swift` - iOS API DTOs
- `apps/web/src/types/index.ts` - Web TypeScript types

## Naming Conventions

**Files:**
- Go: `snake_case.go` (e.g., `event_type.go`, `property_definition.go`)
- Swift: `PascalCase.swift` (e.g., `EventStore.swift`, `APIClient.swift`)
- TypeScript: `camelCase.ts` or `PascalCase.tsx` for components (e.g., `api-client.ts`, `Dashboard.tsx`)
- Config: `lowercase.yaml`, `PascalCase.xcconfig`

**Directories:**
- Go: `lowercase` (e.g., `handlers`, `service`, `repository`)
- Swift: `PascalCase` (e.g., `ViewModels`, `Services`, `Models`)
- TypeScript: `lowercase` (e.g., `components`, `hooks`, `pages`)

**Code:**
- Go functions: `PascalCase` for exported, `camelCase` for internal
- Go types: `PascalCase` (e.g., `EventService`, `CreateEventRequest`)
- Swift types: `PascalCase` (e.g., `EventStore`, `SyncEngine`)
- Swift functions: `camelCase` (e.g., `performSync`, `recordEvent`)
- TypeScript functions: `camelCase` (e.g., `useEvents`, `handleSubmit`)
- TypeScript types: `PascalCase` (e.g., `Event`, `CreateEventRequest`)

## Where to Add New Code

**New Backend Endpoint:**
1. Add/modify models in `apps/backend/internal/models/models.go`
2. Define repository interface in `apps/backend/internal/repository/interfaces.go`
3. Implement repository in `apps/backend/internal/repository/<feature>.go`
4. Define service interface in `apps/backend/internal/service/interfaces.go`
5. Implement service in `apps/backend/internal/service/<feature>.go`
6. Create handler in `apps/backend/internal/handlers/<feature>.go`
7. Wire up in `apps/backend/cmd/trendy-api/serve.go`
8. Add route registration in `serve.go` under appropriate route group

**New iOS Feature:**
1. Add SwiftData model (if new entity) in `apps/ios/trendy/Models/`
2. Add API models in `apps/ios/trendy/Models/API/APIModels.swift`
3. Add API methods to `apps/ios/trendy/Services/APIClient.swift`
4. Add sync handling to `apps/ios/trendy/Services/Sync/SyncEngine.swift`
5. Create ViewModel in `apps/ios/trendy/ViewModels/` or extend `EventStore`
6. Create Views in `apps/ios/trendy/Views/<Feature>/`
7. Add to navigation in `ContentView.swift` or `MainTabView.swift`

**New Web Feature:**
1. Add types in `apps/web/src/types/index.ts`
2. Add API methods to `apps/web/src/lib/api-client.ts`
3. Create TanStack Query hooks in `apps/web/src/hooks/api/`
4. Create components in `apps/web/src/components/<feature>/`
5. Create page in `apps/web/src/pages/`
6. Add route in `apps/web/src/App.tsx`

**New UI Component (Web):**
- Shared UI: `apps/web/src/components/ui/`
- Feature-specific: `apps/web/src/components/<feature>/`

**New Utility:**
- Backend: `apps/backend/internal/<category>/` or `apps/backend/pkg/` if reusable
- iOS: `apps/ios/trendy/Utilities/`
- Web: `apps/web/src/lib/`

**New Tests:**
- Backend: Co-located with source (`*_test.go` files)
- iOS Unit: `apps/ios/trendyTests/`
- iOS UI: `apps/ios/trendyUITests/`
- Web: Co-located with source (`*.test.ts` or `*.test.tsx`)

## Special Directories

**node_modules/**
- Purpose: NPM dependencies
- Generated: Yes
- Committed: No (gitignored)

**dist/**
- Purpose: Web app build output
- Generated: Yes
- Committed: No (gitignored)

**.wrangler/**
- Purpose: Cloudflare Workers local state
- Generated: Yes
- Committed: No (gitignored)

**DerivedData/**
- Purpose: Xcode build artifacts
- Generated: Yes
- Committed: No (gitignored)

**.planning/**
- Purpose: GSD planning and codebase analysis documents
- Generated: By GSD commands
- Committed: Yes

**Config/Secrets.xcconfig**
- Purpose: iOS developer-specific secrets
- Generated: Copied from template
- Committed: No (gitignored)

---

*Structure analysis: 2026-01-15*
