# Technology Stack

**Analysis Date:** 2026-01-15

## Languages

**Primary:**
- Go 1.23 - Backend API (`apps/backend/`)
- Swift 5.0 - iOS app (`apps/ios/`)
- TypeScript 5.7+ - Web app (`apps/web/`)

**Secondary:**
- SQL (PostgreSQL) - Database migrations (`supabase/migrations.sql`)
- HTML/CSS - Landing page (`apps/landing/`)

## Runtime

**Backend:**
- Go 1.23.0
- Alpine Linux (production Docker container)

**Web:**
- Node.js 20.x
- Bun (available in dev shell)

**iOS:**
- iOS 17.0+ deployment target
- SwiftUI / SwiftData

**Package Managers:**
- Yarn 1.22.22 - Web app (`apps/web/package.json`)
- Go Modules - Backend (`apps/backend/go.mod`)
- Swift Package Manager - iOS (Xcode-managed)

**Lockfiles:**
- `apps/web/yarn.lock` - present
- `apps/backend/go.sum` - present

## Frameworks

**Backend (Go):**
- Gin v1.11.0 - HTTP router and middleware (`github.com/gin-gonic/gin`)
- Cobra v1.10.1 - CLI framework (`github.com/spf13/cobra`)
- Viper v1.21.0 - Configuration management (`github.com/spf13/viper`)

**Web (React):**
- React 18.3.1 - UI framework
- Vite 6.0.1 - Build tool and dev server
- TanStack Query 5.90.7 - Server state management
- React Router DOM 6.28.0 - Client-side routing
- Tailwind CSS 4.1.17 - Utility-first CSS

**iOS (Swift):**
- SwiftUI - UI framework
- SwiftData - Local persistence
- Supabase Swift SDK 2.0+ - Auth and API client
- HealthKit - Health data integration
- EventKit - Calendar integration
- CoreLocation - Geofencing

**Testing:**
- Go testing (built-in) - Backend
- ESLint 8.57.1 - Web linting

**Build/Dev:**
- Just - Task runner (see `justfile`)
- Docker - Containerization
- Nix Flake - Reproducible dev environment

## Key Dependencies

**Backend Critical:**
- `github.com/google/uuid` v1.6.0 - UUID generation
- `github.com/go-playground/validator/v10` v10.27.0 - Request validation
- `github.com/goccy/go-json` v0.10.2 - Fast JSON encoding

**Web Critical:**
- `@supabase/supabase-js` ^2.48.1 - Supabase client for auth/realtime
- `date-fns` ^4.1.0 - Date manipulation
- `recharts` ^3.3.0 - Charting library
- `lucide-react` ^0.553.0 - Icon library
- `tailwind-merge` ^3.3.1 - Tailwind class merging

**Infrastructure:**
- `wrangler` ^4.47.0 - Cloudflare Workers deployment (root `package.json`)

## Configuration

**Environment Variables:**

Backend (loaded via Viper):
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_SERVICE_KEY` - Service role key (NOT anon key)
- `PORT` - Server port (default 8888)
- `LOG_LEVEL` - Logging level (debug/info/warn/error)
- `LOG_FORMAT` - Log format (json/text)
- `CORS_ALLOWED_ORIGINS` - Allowed CORS origins
- `TRENDY_SERVER_ENV` - Environment (development/production)

Web (Vite environment):
- `VITE_SUPABASE_URL` - Supabase project URL
- `VITE_SUPABASE_ANON_KEY` - Supabase anon key (public)
- `VITE_API_BASE_URL` - Backend API URL (defaults to `/api/v1` for proxy)
- `VITE_LOG_LEVEL` - Client-side log level

iOS (xcconfig files in `apps/ios/Config/`):
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_ANON_KEY` - Supabase anon key
- `API_BASE_URL` - Backend API URL
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `POSTHOG_API_KEY` - Analytics API key
- `POSTHOG_HOST` - Analytics host URL

**Configuration Files:**

Backend:
- `apps/backend/config.yaml` - Optional local config (overridden by env vars)

Web:
- `apps/web/vite.config.ts` - Vite build/dev configuration
- `apps/web/tsconfig.json` - TypeScript configuration
- `apps/web/tailwind.config.js` - Tailwind CSS configuration
- `apps/web/postcss.config.js` - PostCSS configuration
- `apps/web/.eslintrc*` - ESLint configuration

iOS:
- `apps/ios/Config/Debug.xcconfig` - Local development
- `apps/ios/Config/Staging.xcconfig` - Staging environment
- `apps/ios/Config/Release.xcconfig` - Production
- `apps/ios/Config/TestFlight.xcconfig` - TestFlight builds
- `apps/ios/Config/Secrets-*.xcconfig` - Per-environment secrets (gitignored)

**Build Configuration:**
- `apps/backend/Dockerfile` - Multi-stage Alpine build
- `justfile` - Monorepo task runner with all common commands
- `flake.nix` - Nix development environment

## Platform Requirements

**Development:**
- Node.js 20+
- Go 1.23+
- Yarn package manager
- Just command runner
- Docker (for local Supabase or deployment)
- Xcode 15+ (macOS only, for iOS development)
- Nix (optional, provides reproducible environment via `nix develop`)

**Production:**

Backend:
- Google Cloud Run (primary deployment target)
- Artifact Registry for container images
- Secret Manager for credentials
- Project IDs: `trendy-dev-477906` (dev), `trendy-477704` (prod)

Web:
- Cloudflare Pages (primary deployment target)
- Vite static build output to `apps/web/dist/`

iOS:
- App Store / TestFlight distribution
- Bundle ID varies by environment (e.g., `com.shadowlabs.trendsight.dev`)

Landing Page:
- Cloudflare Workers/Pages (`apps/landing/`)

## Monorepo Structure

```
trendy/
├── apps/
│   ├── backend/     # Go API (Gin + Supabase)
│   ├── web/         # React SPA (Vite + Tailwind)
│   ├── ios/         # SwiftUI app (SwiftData + HealthKit)
│   └── landing/     # Landing page (Cloudflare Workers)
├── packages/
│   └── shared-types/  # Shared TypeScript types
├── supabase/        # Database migrations
├── .github/
│   └── workflows/
│       └── ci.yml   # GitHub Actions CI
├── justfile         # Task runner commands
├── flake.nix        # Nix dev environment
└── package.json     # Root (wrangler for landing)
```

---

*Stack analysis: 2026-01-15*
