#!/usr/bin/env bash
set -e

# Setup Google Secret Manager secrets for Trendy backend
# Usage: ./setup-secrets.sh <project-id> [env]

if [ -z "$1" ]; then
    echo "Error: Project ID required"
    echo "Usage: $0 <project-id> [env]"
    exit 1
fi

PROJECT_ID="$1"
ENV="${2:-dev}"

echo "🔐 Setting up Google Secret Manager secrets for ${ENV}..."
echo ""
echo "⚠️  You will need your Supabase credentials:"
echo "  - Supabase URL (https://your-project.supabase.co)"
echo "  - Supabase Service Role Key (from Project Settings → API)"
echo ""
echo "Press Ctrl+C to cancel at any time."
echo ""

# Create/update supabase-url secret
echo "→ Creating/updating supabase-url secret..."
read -p "Enter Supabase URL: " supabase_url

echo -n "$supabase_url" | gcloud secrets create supabase-url \
    --data-file=- \
    --replication-policy=automatic \
    --project="$PROJECT_ID" 2>/dev/null || \
echo -n "$supabase_url" | gcloud secrets versions add supabase-url \
    --data-file=- \
    --project="$PROJECT_ID"

# Create/update supabase-service-key secret
echo "→ Creating/updating supabase-service-key secret..."
read -p "Enter Supabase Service Role Key: " service_key

echo -n "$service_key" | gcloud secrets create supabase-service-key \
    --data-file=- \
    --replication-policy=automatic \
    --project="$PROJECT_ID" 2>/dev/null || \
echo -n "$service_key" | gcloud secrets versions add supabase-service-key \
    --data-file=- \
    --project="$PROJECT_ID"

echo ""
echo "→ Granting Cloud Run access to secrets..."

# Get project number
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format=json | jq -r .projectNumber)

if [ -z "$PROJECT_NUMBER" ]; then
    echo "⚠️  Could not get project number. Skipping IAM binding."
    echo "   You may need to grant permissions manually in the Cloud Console."
else
    # Grant access to supabase-url
    gcloud secrets add-iam-policy-binding supabase-url \
        --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
        --role="roles/secretmanager.secretAccessor" \
        --project="$PROJECT_ID" \
        --quiet 2>/dev/null || echo "   ✓ supabase-url binding already exists"

    # Grant access to supabase-service-key
    gcloud secrets add-iam-policy-binding supabase-service-key \
        --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
        --role="roles/secretmanager.secretAccessor" \
        --project="$PROJECT_ID" \
        --quiet 2>/dev/null || echo "   ✓ supabase-service-key binding already exists"
fi

echo ""
echo "✅ Secrets configured successfully!"
echo ""
echo "Next step:"
echo "  just gcp-deploy-backend ENV=${ENV}"
