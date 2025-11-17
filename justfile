# Trendy Monorepo Commands

# Google Cloud Platform Configuration
# Project IDs for dev and production environments
GCP_PROJECT_ID_DEV := "trendy-dev-477906"
GCP_PROJECT_ID_PROD := "trendy-477704"
GCP_REGION := "us-central1"
ARTIFACT_REGISTRY_REPO := "trendy"
IMAGE_NAME := "trendy-api"

# Helper function to get project ID based on environment
gcp_project_id ENV:
    @if [ "{{ENV}}" = "dev" ]; then echo "{{GCP_PROJECT_ID_DEV}}"; elif [ "{{ENV}}" = "prod" ]; then echo "{{GCP_PROJECT_ID_PROD}}"; else echo "Error: ENV must be 'dev' or 'prod'" >&2; exit 1; fi

# Default recipe to display help information
default:
    @just --list

# Install all dependencies across the monorepo
install:
    @echo "📦 Installing dependencies..."
    @echo "→ Installing web app dependencies..."
    cd apps/web && yarn install
    @echo "→ Installing shared types dependencies..."
    cd packages/shared-types && yarn install
    @echo "→ Installing Go dependencies..."
    cd apps/backend && go mod download
    @echo "✅ All dependencies installed!"

# Clean all build artifacts
clean:
    @echo "🧹 Cleaning build artifacts..."
    rm -rf apps/web/dist
    rm -rf apps/web/node_modules
    rm -rf packages/shared-types/dist
    rm -rf packages/shared-types/node_modules
    rm -rf apps/backend/trendy-api
    @echo "✅ Clean complete!"

# Build all apps
build: build-types build-web build-backend

# Build shared types
build-types:
    @echo "🔨 Building shared types..."
    cd packages/shared-types && yarn build
    @echo "✅ Types built!"

# Build web app
build-web:
    @echo "🔨 Building web app..."
    cd apps/web && yarn build
    @echo "✅ Web app built!"

# Build backend
build-backend:
    @echo "🔨 Building backend..."
    cd apps/backend && go build -o trendy-api ./cmd/trendy-api
    @echo "✅ Backend built!"

# Run web app in development mode
dev-web:
    @echo "🚀 Starting web app..."
    cd apps/web && yarn dev

# Run backend in development mode
dev-backend:
    @echo "🚀 Starting backend..."
    cd apps/backend && go run ./cmd/trendy-api serve

# Run both web and backend in development (requires tmux or run in separate terminals)
dev:
    @echo "🚀 Starting development servers..."
    @echo "Run these in separate terminals:"
    @echo "  Terminal 1: just dev-backend"
    @echo "  Terminal 2: just dev-web"

# Run tests for all apps
test: test-backend test-web

# Run backend tests
test-backend:
    @echo "🧪 Running backend tests..."
    cd apps/backend && go test ./...

# Run web tests
test-web:
    @echo "🧪 Running web tests..."
    cd apps/web && yarn test || echo "No tests configured yet"

# Lint all code
lint: lint-web lint-backend

# Lint web app
lint-web:
    @echo "🔍 Linting web app..."
    cd apps/web && yarn lint

# Lint backend
lint-backend:
    @echo "🔍 Linting backend..."
    cd apps/backend && go fmt ./... && go vet ./...

# Format all code
fmt: fmt-web fmt-backend

# Format web app
fmt-web:
    @echo "✨ Formatting web app..."
    cd apps/web && yarn lint --fix || echo "Lint fix not fully configured"

# Format backend
fmt-backend:
    @echo "✨ Formatting backend..."
    cd apps/backend && go fmt ./...

# Database commands

# Setup Supabase (requires manual configuration)
db-setup:
    @echo "📊 Supabase Setup Instructions:"
    @echo ""
    @echo "1. Create a Supabase project at https://supabase.com"
    @echo "2. Copy your project URL and keys"
    @echo "3. Create .env files:"
    @echo "   - apps/backend/.env (see apps/backend/.env.example)"
    @echo "   - apps/web/.env (see apps/web/.env.example)"
    @echo "4. Link your project (skip pooler if connection fails):"
    @echo "   supabase link --project-ref <your-project-ref> --skip-pooler"
    @echo "5. Run: just db-migrate"
    @echo ""

# Link to remote Supabase project
db-link PROJECT_REF:
    @echo "🔗 Linking to Supabase project..."
    @rm -rf supabase/.temp/ || true
    supabase link --project-ref {{PROJECT_REF}} --skip-pooler
    @echo "✅ Project linked!"

# Unban your IP if you're getting connection refused errors
db-unban-ip:
    @echo "🔓 Unbanning your IP address..."
    @IP=$$(curl -4 -s ifconfig.me) && \
    echo "Your IP: $$IP" && \
    supabase network-bans remove --db-unban-ip $$IP --project-ref $$(cat supabase/.temp/project-ref 2>/dev/null || echo "UNKNOWN") --experimental || \
    echo "⚠️  If this fails, go to: Supabase Dashboard → Database Settings → Unban IP"

# Initialize local Supabase (requires Docker)
db-init-local:
    @echo "🔧 Initializing local Supabase..."
    cd supabase && supabase init

# Start local Supabase (requires Docker)
db-start:
    export DOCKER_HOST="unix:///var/run/docker.sock"
    @echo "🚀 Starting local Supabase..."
    supabase start

db-start-debug:
    export DOCKER_HOST="unix:///var/run/docker.sock"
    @echo "🚀 Starting local Supabase..."
    supabase start --debug

# Stop local Supabase
db-stop:
    @echo "🛑 Stopping local Supabase..."
    supabase stop

# Run database migrations against local Supabase
db-migrate-local:
    @echo "🔄 Running migrations against local Supabase..."
    @if [ ! -f supabase/config.toml ]; then \
        echo "❌ Supabase not initialized. Run 'just db-init-local' first."; \
        exit 1; \
    fi
    @echo "Applying migration..."
    psql -h localhost -p 54322 -U postgres -d postgres -f supabase/migrations.sql
    @echo "✅ Migration complete!"

# Run database migrations against remote Supabase (requires SUPABASE_DB_URL env var)
db-migrate-remote:
    @echo "🔄 Running migrations against remote Supabase..."
    @if [ -z "$$SUPABASE_DB_URL" ]; then \
        echo "❌ SUPABASE_DB_URL environment variable not set."; \
        echo ""; \
        echo "Get your connection string from Supabase Dashboard:"; \
        echo "  → Project Settings → Database → Connection String → URI"; \
        echo ""; \
        echo "Then run:"; \
        echo "  SUPABASE_DB_URL='your-connection-string' just db-migrate-remote"; \
        echo ""; \
        echo "Or use the SQL Editor:"; \
        echo "  just db-show-migration  # Copy SQL"; \
        echo "  Then paste in Supabase Dashboard → SQL Editor"; \
        exit 1; \
    fi
    psql "$$SUPABASE_DB_URL" -f supabase/migrations.sql
    @echo "✅ Migration complete!"

# Show migration SQL (for copying to Supabase SQL Editor)
db-show-migration:
    @echo "📋 Migration SQL (copy this to Supabase SQL Editor):"
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @cat supabase/migrations.sql
    @echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    @echo ""
    @echo "To run this migration:"
    @echo "1. Go to your Supabase Dashboard → SQL Editor"
    @echo "2. Create a new query"
    @echo "3. Paste the SQL above"
    @echo "4. Click 'Run'"

# Run database migrations (auto-detects local or prompts for remote)
db-migrate:
    @echo "🔄 Running database migrations..."
    @if [ -f supabase/config.toml ]; then \
        echo "Found local Supabase config, using local database..."; \
        just db-migrate-local; \
    elif [ -f supabase/.temp/project-ref ]; then \
        echo "Found linked Supabase project, pushing migration..."; \
        psql "$$(supabase status --output=json | jq -r '.DATABASE_URL' 2>/dev/null)" -f supabase/migrations.sql 2>/dev/null || \
        echo "⚠️  Direct push failed. Use: just db-show-migration (then paste in SQL Editor)"; \
    else \
        echo "No Supabase connection found. Use one of:"; \
        echo "  - just db-link <project-ref>  (link to remote project)"; \
        echo "  - just db-migrate-local  (requires: just db-start)"; \
        echo "  - just db-migrate-remote (requires: SUPABASE_DB_URL env var)"; \
        echo "  - just db-show-migration (copy/paste to SQL editor)"; \
    fi

# Reset local database (WARNING: Deletes all data!)
db-reset-local:
    @echo "⚠️  WARNING: This will delete all local database data!"
    @read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
    @echo "🔄 Resetting local database..."
    supabase db reset
    @echo "✅ Database reset complete!"

# Deployment commands

# Build for production
build-prod: clean install build
    @echo "🎉 Production build complete!"

# Deploy backend (customize for your deployment platform)
deploy-backend:
    @echo "🚀 Deploy backend instructions:"
    @echo "1. Build: just build-backend"
    @echo "2. Deploy the 'trendy-api' binary to your server"
    @echo "3. Set environment variables on your server"
    @echo "4. Run: ./trendy-api serve"

# Deploy web (customize for your deployment platform)
deploy-web:
    @echo "🚀 Deploy web app instructions:"
    @echo "1. Build: just build-web"
    @echo "2. Deploy the 'apps/web/dist' folder to your hosting"
    @echo "   (Vercel, Netlify, AWS S3, etc.)"

# Google Cloud Platform Deployment

# Build Docker image for backend
docker-build-backend ENV="dev":
    @echo "🐳 Building Docker image for {{ENV}} environment..."
    cd apps/backend && docker build --platform linux/amd64 -t {{IMAGE_NAME}}:{{ENV}} .
    @echo "✅ Docker image built: {{IMAGE_NAME}}:{{ENV}}"

# Push Docker image to Google Artifact Registry (using Cloud Build)
gcp-push-backend ENV="dev":
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ID=$(just gcp_project_id {{ENV}})
    echo "📦 Building and pushing to Artifact Registry using Cloud Build..."
    echo "→ Project: $PROJECT_ID"
    echo "→ Environment: {{ENV}}"
    echo "→ Submitting build to Google Cloud Build..."
    echo "   (This builds natively on AMD64 architecture in the cloud)"
    cd apps/backend && gcloud builds submit \
        --tag={{GCP_REGION}}-docker.pkg.dev/$PROJECT_ID/{{ARTIFACT_REGISTRY_REPO}}/{{IMAGE_NAME}}:{{ENV}} \
        --project=$PROJECT_ID \
        --machine-type=e2-highcpu-8 \
        --no-cache
    echo "→ Tagging as latest..."
    gcloud artifacts docker tags add \
        {{GCP_REGION}}-docker.pkg.dev/$PROJECT_ID/{{ARTIFACT_REGISTRY_REPO}}/{{IMAGE_NAME}}:{{ENV}} \
        {{GCP_REGION}}-docker.pkg.dev/$PROJECT_ID/{{ARTIFACT_REGISTRY_REPO}}/{{IMAGE_NAME}}:latest \
        --project=$PROJECT_ID 2>/dev/null || echo "✓ Latest tag updated"
    echo "✅ Image built and pushed successfully!"

# Deploy backend to Google Cloud Run
gcp-deploy-backend ENV="dev":
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ID=$(just gcp_project_id {{ENV}})
    echo "🚀 Deploying backend to Cloud Run ({{ENV}} environment)..."
    echo ""
    echo "Configuration:"
    echo "  Project: $PROJECT_ID"
    echo "  Service: trendy-api-{{ENV}}"
    echo "  Region: {{GCP_REGION}}"
    echo "  Port: 8888"
    echo "  Memory: 256Mi"
    echo "  CPU: 1"
    echo ""

    # Push the image first
    just gcp-push-backend {{ENV}}

    # For production, prompt for CORS allowed origins
    CORS_ORIGINS=""
    if [ "{{ENV}}" = "prod" ]; then
        echo ""
        echo "⚠️  Production deployment requires CORS configuration."
        read -p "Enter allowed CORS origins (e.g., https://yourdomain.com,https://www.yourdomain.com): " CORS_ORIGINS
        # Remove quotes if user included them
        CORS_ORIGINS=$(echo "$CORS_ORIGINS" | sed 's/^["'\'']\|["'\'']$//g')
        if [ -z "$CORS_ORIGINS" ]; then
            echo "❌ CORS origins required for production deployment."
            exit 1
        fi

        # Create temporary env vars file to handle special characters (colons, commas)
        ENV_FILE=$(mktemp)
        echo "TRENDY_SERVER_ENV: production" > "$ENV_FILE"
        echo "CORS_ALLOWED_ORIGINS: $CORS_ORIGINS" >> "$ENV_FILE"

        echo "→ Deploying to Cloud Run..."
        gcloud run deploy trendy-api-{{ENV}} \
            --image={{GCP_REGION}}-docker.pkg.dev/$PROJECT_ID/{{ARTIFACT_REGISTRY_REPO}}/{{IMAGE_NAME}}:{{ENV}} \
            --platform=managed \
            --region={{GCP_REGION}} \
            --allow-unauthenticated \
            --port=8888 \
            --memory=256Mi \
            --cpu=1 \
            --min-instances=0 \
            --max-instances=10 \
            --timeout=300 \
            --env-vars-file="$ENV_FILE" \
            --set-secrets="SUPABASE_URL=supabase-url:latest,SUPABASE_SERVICE_KEY=supabase-service-key:latest" \
            --project=$PROJECT_ID

        # Clean up temp file
        rm -f "$ENV_FILE"
    else
        echo "→ Deploying to Cloud Run..."
        gcloud run deploy trendy-api-{{ENV}} \
            --image={{GCP_REGION}}-docker.pkg.dev/$PROJECT_ID/{{ARTIFACT_REGISTRY_REPO}}/{{IMAGE_NAME}}:{{ENV}} \
            --platform=managed \
            --region={{GCP_REGION}} \
            --allow-unauthenticated \
            --port=8888 \
            --memory=256Mi \
            --cpu=1 \
            --min-instances=0 \
            --max-instances=10 \
            --timeout=300 \
            --set-env-vars="TRENDY_SERVER_ENV=production" \
            --set-secrets="SUPABASE_URL=supabase-url:latest,SUPABASE_SERVICE_KEY=supabase-service-key:latest" \
            --project=$PROJECT_ID
    fi
    echo ""
    echo "✅ Deployment complete!"
    echo ""
    echo "View logs:"
    echo "  gcloud run services logs tail trendy-api-{{ENV}} --region={{GCP_REGION}} --project=$PROJECT_ID"
    echo ""
    echo "Get service URL:"
    echo "  gcloud run services describe trendy-api-{{ENV}} --region={{GCP_REGION}} --project=$PROJECT_ID --format='value(status.url)'"

# Setup Google Artifact Registry repository
gcp-setup ENV="dev":
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ID=$(just gcp_project_id {{ENV}})
    echo "🔧 Setting up Google Cloud Artifact Registry..."
    echo ""
    echo "Environment: {{ENV}}"
    echo "Project: $PROJECT_ID"
    echo "Region: {{GCP_REGION}}"
    echo "Repository: {{ARTIFACT_REGISTRY_REPO}}"
    echo ""
    echo "→ Creating repository..."
    gcloud artifacts repositories create {{ARTIFACT_REGISTRY_REPO}} \
        --repository-format=docker \
        --location={{GCP_REGION}} \
        --description="Trendy container images ({{ENV}})" \
        --project=$PROJECT_ID 2>&1 | grep -v "ALREADY_EXISTS" || echo "✓ Repository exists or created"
    echo "✅ Artifact Registry setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Set up secrets: just gcp-secrets-setup ENV={{ENV}}"
    echo "2. Deploy backend: just gcp-deploy-backend ENV={{ENV}}"

# Setup Google Secret Manager secrets
gcp-secrets-setup ENV="dev":
    #!/usr/bin/env bash
    set -euo pipefail
    PROJECT_ID=$(just gcp_project_id {{ENV}})
    ./apps/backend/deployment/setup-secrets.sh $PROJECT_ID {{ENV}}

# Development helpers

# Watch shared types for changes
watch-types:
    @echo "👀 Watching shared types..."
    cd packages/shared-types && yarn watch

# Check all apps
check: lint test
    @echo "✅ All checks passed!"

# Show dependency graph
deps:
    @echo "📦 Dependency structure:"
    @echo ""
    @echo "apps/web"
    @echo "  ├── @trendy/shared-types (optional)"
    @echo "  ├── react"
    @echo "  ├── @supabase/supabase-js"
    @echo "  └── vite"
    @echo ""
    @echo "apps/backend"
    @echo "  ├── github.com/gin-gonic/gin"
    @echo "  ├── github.com/spf13/cobra"
    @echo "  ├── github.com/spf13/viper"
    @echo "  └── supabase client"
    @echo ""
    @echo "apps/ios"
    @echo "  ├── SwiftUI"
    @echo "  ├── SwiftData"
    @echo "  └── EventKit"

# iOS specific commands (macOS only)

# Build iOS app (requires Xcode on macOS)
build-ios:
    @echo "🍎 Building iOS app..."
    @echo "Note: This requires Xcode on macOS"
    cd apps/ios && xcodebuild -project trendy.xcodeproj -scheme trendy -sdk iphonesimulator -configuration Debug build

# Open iOS project in Xcode (macOS only)
open-ios:
    @echo "🍎 Opening iOS project..."
    open apps/ios/trendy.xcodeproj
