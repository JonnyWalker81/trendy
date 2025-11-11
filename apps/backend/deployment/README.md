# Backend Deployment Guide - Google Cloud Run

This guide walks you through deploying the Trendy backend API to Google Cloud Run.

## Prerequisites

### Required Tools

1. **Google Cloud SDK (gcloud CLI)**
   ```bash
   # Install gcloud CLI
   # macOS
   brew install google-cloud-sdk

   # Or download from: https://cloud.google.com/sdk/docs/install
   ```

2. **Docker**
   ```bash
   # macOS
   brew install docker

   # Or download Docker Desktop: https://www.docker.com/products/docker-desktop
   ```

3. **Just command runner** (already in Nix environment)
   ```bash
   # If not using Nix:
   brew install just
   ```

### Google Cloud Setup

1. **Authenticate with Google Cloud**
   ```bash
   gcloud auth login
   ```

2. **Set your default project**
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Enable required APIs**
   ```bash
   gcloud services enable run.googleapis.com
   gcloud services enable artifactregistry.googleapis.com
   gcloud services enable secretmanager.googleapis.com
   ```

### Supabase Configuration

You'll need your Supabase credentials:
- **Supabase URL**: Found in Project Settings → API → Project URL
- **Service Role Key**: Found in Project Settings → API → Service Role Key (secret)

⚠️ **IMPORTANT**: Use the **service_role** key, NOT the anon key!

## Configuration

### 1. Update Justfile Variables

Edit the justfile in the repository root and update these variables:

```just
GCP_PROJECT_ID := "your-actual-project-id"
GCP_REGION := "us-central1"  # Or your preferred region
ARTIFACT_REGISTRY_REPO := "trendy"
IMAGE_NAME := "trendy-api"
```

**Available GCP Regions:**
- `us-central1` (Iowa)
- `us-east1` (South Carolina)
- `us-west1` (Oregon)
- `europe-west1` (Belgium)
- `asia-northeast1` (Tokyo)
- See more: https://cloud.google.com/run/docs/locations

## First-Time Deployment

### Step 1: Create Artifact Registry Repository

This creates a Docker repository to store your container images.

```bash
just gcp-setup
```

This command will:
- Create an Artifact Registry repository in your specified region
- Configure Docker authentication for the registry

### Step 2: Configure Secrets

Store your Supabase credentials in Google Secret Manager.

```bash
just gcp-secrets-setup ENV=prod
```

You'll be prompted to enter:
1. Supabase URL
2. Supabase Service Role Key

This command will:
- Create secrets in Secret Manager
- Grant Cloud Run service account access to the secrets

### Step 3: Deploy to Cloud Run

Deploy your backend API to Cloud Run.

```bash
just gcp-deploy-backend ENV=prod
```

This command will:
1. Build the Docker image
2. Push to Artifact Registry
3. Deploy to Cloud Run with:
   - Service name: `trendy-api-prod`
   - Port: 8888
   - Memory: 256Mi
   - CPU: 1
   - Min instances: 0 (scales to zero for cost savings)
   - Max instances: 10
   - Secrets injected from Secret Manager

### Step 4: Get Your Service URL

After deployment completes, get your service URL:

```bash
gcloud run services describe trendy-api-prod \
  --region=us-central1 \
  --format='value(status.url)'
```

Your backend API is now live at: `https://trendy-api-prod-xxxxx-xx.a.run.app`

## Environment Management

The deployment supports multiple environments using the `ENV` parameter.

### Development Environment

```bash
# Deploy to dev
just gcp-deploy-backend ENV=dev

# Service name: trendy-api-dev
# Image tag: dev
```

### Staging Environment

```bash
# Deploy to staging
just gcp-deploy-backend ENV=staging

# Service name: trendy-api-staging
# Image tag: staging
```

### Production Environment

```bash
# Deploy to production
just gcp-deploy-backend ENV=prod

# Service name: trendy-api-prod
# Image tag: prod
```

## Individual Commands

### Build Docker Image Locally

Build without pushing to the registry:

```bash
just docker-build-backend ENV=prod
```

### Push to Artifact Registry

Build and push without deploying:

```bash
just gcp-push-backend ENV=prod
```

This is useful for:
- Pre-building images for faster deployment
- CI/CD pipelines
- Image testing before deployment

## Updating Secrets

To update secrets (e.g., if your Supabase key changes):

```bash
# Update secrets
just gcp-secrets-setup ENV=prod

# Redeploy to pick up new secrets
just gcp-deploy-backend ENV=prod
```

Or update manually:

```bash
# Update Supabase URL
echo -n "https://new-url.supabase.co" | \
  gcloud secrets versions add supabase-url --data-file=-

# Update Service Key
echo -n "new-service-key" | \
  gcloud secrets versions add supabase-service-key --data-file=-
```

## Monitoring and Logs

### View Live Logs

```bash
# Production logs
gcloud run services logs tail trendy-api-prod --region=us-central1

# Development logs
gcloud run services logs tail trendy-api-dev --region=us-central1
```

### View Service Details

```bash
gcloud run services describe trendy-api-prod --region=us-central1
```

### View Recent Logs in Console

Visit: https://console.cloud.google.com/run

Select your service → Logs tab

## Scaling Configuration

To adjust resource limits, edit the `gcp-deploy-backend` command in the justfile:

```bash
gcloud run deploy trendy-api-{{ENV}} \
    --memory=512Mi \      # Increase memory
    --cpu=2 \             # Increase CPU
    --min-instances=1 \   # Always-on instance
    --max-instances=100 \ # Higher max instances
    ...
```

Then redeploy:

```bash
just gcp-deploy-backend ENV=prod
```

## Cost Optimization

Cloud Run pricing is based on:
- Request count
- CPU/Memory usage
- Egress bandwidth

**Cost-saving tips:**
1. Keep `min-instances=0` to scale to zero when idle
2. Start with minimal resources (256Mi/1 CPU)
3. Monitor usage and scale up only if needed
4. Use regional deployments (cheaper than multi-region)

**Free tier (as of 2025):**
- 2 million requests per month
- 360,000 GB-seconds of memory
- 180,000 vCPU-seconds

See: https://cloud.google.com/run/pricing

## Troubleshooting

### Deployment Fails

**Check Docker is running:**
```bash
docker ps
```

**Check gcloud authentication:**
```bash
gcloud auth list
```

**Check enabled APIs:**
```bash
gcloud services list --enabled
```

### Service Returns 500 Errors

**Check logs:**
```bash
gcloud run services logs tail trendy-api-prod --region=us-central1
```

**Common issues:**
- Incorrect Supabase credentials
- Service key vs anon key confusion
- Port mismatch (must be 8888)
- Missing environment variables

### Health Check Fails

The Dockerfile includes a health check on `/health` endpoint.

**Test locally:**
```bash
docker run -p 8888:8888 trendy-api:prod

# In another terminal
curl http://localhost:8888/health
```

### Permission Denied Errors

Ensure Cloud Run service account has access to secrets:

```bash
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID \
  --format='value(projectNumber)')

gcloud secrets add-iam-policy-binding supabase-url \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding supabase-service-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

## Rollback

To rollback to a previous revision:

```bash
# List revisions
gcloud run revisions list --service=trendy-api-prod --region=us-central1

# Rollback to specific revision
gcloud run services update-traffic trendy-api-prod \
  --to-revisions=trendy-api-prod-00001-abc=100 \
  --region=us-central1
```

## CI/CD Integration

For automated deployments, use the individual commands:

```yaml
# Example GitHub Actions workflow
steps:
  - name: Authenticate to Google Cloud
    uses: google-github-actions/auth@v1
    with:
      credentials_json: ${{ secrets.GCP_SA_KEY }}

  - name: Build and Push
    run: just gcp-push-backend ENV=prod

  - name: Deploy
    run: just gcp-deploy-backend ENV=prod
```

## Security Best Practices

1. ✅ **Never commit secrets to git**
   - Use Secret Manager for all sensitive data
   - Keep `.env` files local only

2. ✅ **Use service_role key for backend**
   - Anon key is for frontend/client apps
   - Service role key verifies JWT tokens

3. ✅ **Review IAM permissions**
   - Grant minimum required permissions
   - Use separate service accounts for different environments

4. ✅ **Enable Cloud Armor** (optional, for DDoS protection)
   ```bash
   gcloud compute security-policies create trendy-policy
   ```

5. ✅ **Monitor logs regularly**
   - Set up log-based alerts
   - Watch for unusual traffic patterns

## Additional Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Artifact Registry Guide](https://cloud.google.com/artifact-registry/docs)
- [Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Supabase API Documentation](https://supabase.com/docs/guides/api)

## Support

For issues specific to:
- **Cloud Run**: Check logs and Cloud Run troubleshooting guide
- **Supabase**: Verify credentials and check Supabase status
- **Backend API**: Review backend logs and application code

## Quick Reference

```bash
# Full deployment workflow
just gcp-setup                      # One-time setup
just gcp-secrets-setup ENV=prod     # One-time secret configuration
just gcp-deploy-backend ENV=prod    # Deploy

# Common operations
just docker-build-backend ENV=prod           # Build only
just gcp-push-backend ENV=prod               # Build and push
gcloud run services logs tail trendy-api-prod --region=us-central1  # View logs

# Get service URL
gcloud run services describe trendy-api-prod \
  --region=us-central1 \
  --format='value(status.url)'
```
