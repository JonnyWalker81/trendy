# External Integrations

**Analysis Date:** 2026-01-15

## APIs & External Services

**Supabase (Primary Backend-as-a-Service):**
- Purpose: Authentication, PostgreSQL database, Row Level Security
- SDK/Client (Web): `@supabase/supabase-js` ^2.48.1
  - File: `apps/web/src/lib/supabase.ts`
- SDK/Client (iOS): Supabase Swift SDK 2.0+
  - File: `apps/ios/trendy/Services/SupabaseService.swift`
- SDK/Client (Backend): Custom Go client
  - File: `apps/backend/pkg/supabase/client.go`
- Auth (Web/iOS): `SUPABASE_ANON_KEY` (public key)
- Auth (Backend): `SUPABASE_SERVICE_KEY` (service role key)
- URL var: `SUPABASE_URL`

**PostHog (Analytics):**
- Purpose: Product analytics and event tracking
- iOS integration (configured via xcconfig)
- Env vars: `POSTHOG_API_KEY`, `POSTHOG_HOST`

**Google Cloud Platform:**
- Cloud Run: Backend API hosting
- Artifact Registry: Docker image storage
- Secret Manager: Credential storage
- Cloud Build: Container builds
- Projects: `trendy-dev-477906`, `trendy-477704`

**Cloudflare:**
- Pages: Web app hosting
- Workers: Landing page (`apps/landing/`)
- CLI: Wrangler ^4.47.0

## Data Storage

**Primary Database:**
- PostgreSQL (via Supabase)
- Connection: Supabase REST API (`/rest/v1/`)
- Auth API: `/auth/v1/user` for token verification
- Tables:
  - `users` - User profiles (extends auth.users)
  - `event_types` - User-defined event categories
  - `events` - Event records with timestamps
- RLS: All tables have Row Level Security enabled

**iOS Local Storage:**
- SwiftData - Primary local persistence
- UserDefaults - App settings and flags
- App Group UserDefaults - HealthKit settings (`group.com.memento.trendy`)
- Keychain - Auth tokens (managed by Supabase SDK)

**Web Local Storage:**
- localStorage - Auth session (managed by Supabase SDK)

**File Storage:**
- None (no file uploads implemented)

**Caching:**
- Web: TanStack Query in-memory cache
- iOS: SwiftData local cache (hybrid mode)

## Authentication & Identity

**Supabase Auth:**
- Email/password authentication
- JWT token-based sessions
- Token refresh handled by SDKs

**OAuth Providers:**

Google Sign-In (iOS - prepared but not fully enabled):
- Files:
  - `apps/ios/trendy/Services/GoogleSignInService.swift`
  - `apps/ios/GOOGLE_SIGNIN_SETUP.md`
- Requires: GoogleSignIn-iOS package (not yet added)
- Requires: Google Cloud OAuth Client IDs (iOS + Web)
- Supabase config: Enable "Skip nonce check" for iOS

**Authentication Flow:**

Web App:
1. User authenticates via Supabase JS client
2. JWT stored in localStorage (managed by SDK)
3. Token sent as `Authorization: Bearer <token>` header
4. Backend verifies token via Supabase Auth API

iOS App:
1. User authenticates via SupabaseService
2. JWT stored in Keychain (managed by SDK)
3. APIClient injects token in requests
4. Supports offline queue for authenticated operations

Backend Token Verification:
- File: `apps/backend/internal/middleware/auth.go`
- Verifies via `GET /auth/v1/user` with user's token
- Extracts `user_id` and `user_email` into Gin context

## iOS System Integrations

**HealthKit:**
- Purpose: Import health data as events
- Service: `apps/ios/trendy/Services/HealthKitService.swift`
- Settings: `apps/ios/trendy/Services/HealthKitSettings.swift`
- Requires: HealthKit capability and entitlement
- Data persisted in App Group UserDefaults

**EventKit (Calendar):**
- Purpose: Import calendar events, sync events to calendar
- Manager: `apps/ios/trendy/Utilities/CalendarManager.swift`
- Import: `apps/ios/trendy/Utilities/CalendarImportManager.swift`
- Fields `externalId`, `originalTitle` synced to backend
- Field `calendarEventId` is iOS-only (not synced)

**CoreLocation (Geofencing):**
- Purpose: Location-based automatic event creation
- Manager: `apps/ios/trendy/Services/GeofenceManager.swift`
- Requires: "Always" location authorization for background monitoring
- Geofences stored in backend and monitored locally

## Monitoring & Observability

**Error Tracking:**
- None dedicated (logs only)

**Logging:**

Backend:
- Custom structured logger: `apps/backend/internal/logger/`
- Implementation: Go slog
- Request ID and user ID propagation via context
- Env vars: `LOG_LEVEL`, `LOG_FORMAT`, `LOG_BODIES`

Web:
- Custom logger: `apps/web/src/lib/logger.ts`
- Categories: apiLogger, authLogger, uiLogger
- Env var: `VITE_LOG_LEVEL`

iOS:
- Apple unified logging (os.Logger): `apps/ios/trendy/Utilities/Logger.swift`
- Categories: Log.api, Log.auth, Log.sync, Log.migration, Log.geofence, Log.calendar, Log.ui, Log.data

**Analytics:**
- PostHog (iOS) - configured via xcconfig

## CI/CD & Deployment

**CI Pipeline:**
- GitHub Actions: `.github/workflows/ci.yml`
- Triggered: Manual (`workflow_dispatch`)
- Jobs:
  1. Backend (Go): vet, fmt, test, build
  2. Frontend (React): install, lint, typecheck, build
  3. Security: Trivy vulnerability scan, TruffleHog secrets scan

**Backend Deployment:**
- Target: Google Cloud Run
- Build: Cloud Build (native AMD64)
- Image: `us-central1-docker.pkg.dev/{project}/trendy/trendy-api:{env}`
- Commands: `just gcp-deploy-backend ENV=dev|prod`
- Secrets: Cloud Secret Manager (`supabase-url`, `supabase-service-key`)

**Web Deployment:**
- Target: Cloudflare Pages
- Build: `yarn build` produces `apps/web/dist/`
- Config: Environment variables set in Cloudflare dashboard

**iOS Deployment:**
- Target: TestFlight / App Store
- Tool: Fastlane (setup instructions in `flake.nix` shellHook)
- Command: `bundle exec fastlane beta`

## Environment Configuration

**Required Environment Variables (Production):**

Backend:
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_SERVICE_KEY` - Service role key (secret)
- `CORS_ALLOWED_ORIGINS` - Allowed frontend origins

Web:
- `VITE_SUPABASE_URL` - Supabase project URL
- `VITE_SUPABASE_ANON_KEY` - Supabase anon key (public)
- `VITE_API_BASE_URL` - Backend API URL

iOS (via xcconfig):
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `API_BASE_URL`

**Secrets Location:**
- GCP: Secret Manager (accessed at runtime)
- Cloudflare: Environment variables in dashboard
- iOS: `apps/ios/Config/Secrets-*.xcconfig` (gitignored)
- Local dev: `.env` files or `config.yaml`

## Webhooks & Callbacks

**Incoming:**
- None implemented

**Outgoing:**
- None implemented

## API Endpoints (Backend)

Base URL: `/api/v1`

**Events:**
- `GET /events` - List events (with pagination)
- `GET /events/:id` - Get single event
- `POST /events` - Create event
- `PUT /events/:id` - Update event
- `DELETE /events/:id` - Delete event
- `POST /events/batch` - Batch create events
- `GET /events/export` - Export events with filters

**Event Types:**
- `GET /event-types` - List event types
- `GET /event-types/:id` - Get single event type
- `POST /event-types` - Create event type
- `PUT /event-types/:id` - Update event type
- `DELETE /event-types/:id` - Delete event type
- `GET /event-types/:id/properties` - Get property definitions
- `POST /event-types/:id/properties` - Create property definition

**Property Definitions:**
- `GET /property-definitions/:id` - Get property definition
- `PUT /property-definitions/:id` - Update property definition
- `DELETE /property-definitions/:id` - Delete property definition

**Analytics:**
- `GET /analytics/summary` - Get analytics summary
- `GET /analytics/trends` - Get trend data
- `GET /analytics/event-type/:id` - Get event type analytics

**Geofences:**
- `GET /geofences` - List geofences
- `GET /geofences/:id` - Get single geofence
- `POST /geofences` - Create geofence
- `PUT /geofences/:id` - Update geofence
- `DELETE /geofences/:id` - Delete geofence

**Insights:**
- `GET /insights` - Get all insights
- `GET /insights/correlations` - Get correlations
- `GET /insights/streaks` - Get streaks
- `GET /insights/weekly-summary` - Get weekly summary
- `POST /insights/refresh` - Force refresh insights

**Change Feed (Sync):**
- `GET /changes` - Get changes since cursor
- `GET /changes/latest-cursor` - Get latest cursor

**Health:**
- `GET /health` - Health check endpoint

---

*Integration audit: 2026-01-15*
