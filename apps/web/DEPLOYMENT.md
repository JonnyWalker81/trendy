# Cloudflare Pages Deployment Guide

## Overview

The Trendy web app is configured to work with different backend URLs:
- **Local Development**: Uses Vite proxy to forward `/api` to `http://localhost:8888`
- **Production (Cloudflare Pages)**: Connects directly to Google Cloud Run backend

## Configuration Files

### 1. Environment Variables

**Local (.env)**
```env
VITE_SUPABASE_URL=https://cwxghazeohicindcznhx.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_SraJB44Ph6xwzsxvH-yXrA_BDK0oheV
VITE_API_BASE_URL=
```

**Production (Cloudflare Pages Dashboard)**
```env
VITE_SUPABASE_URL=https://cwxghazeohicindcznhx.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_SraJB44Ph6xwzsxvH-yXrA_BDK0oheV
VITE_API_BASE_URL=https://your-service-name.run.app/api/v1
NODE_VERSION=20
```

### 2. Cloudflare Pages Settings

**Build Configuration:**
- **Framework preset:** `Vite`
- **Build command:** `yarn build`
- **Build output directory:** `dist`
- **Root directory:** `apps/web`

**Environment Variables:**

Navigate to: `Settings → Environment Variables → Production`

Add the following variables:

| Variable Name | Value |
|--------------|-------|
| `NODE_VERSION` | `20` |
| `VITE_SUPABASE_URL` | `https://cwxghazeohicindcznhx.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | `sb_publishable_SraJB44Ph6xwzsxvH-yXrA_BDK0oheV` |
| `VITE_API_BASE_URL` | `https://your-service-name.run.app/api/v1` |

**Important Notes:**
- Replace `https://your-service-name.run.app/api/v1` with your actual Google Cloud Run service URL
- The `VITE_API_BASE_URL` must include the full path including `/api/v1`
- All environment variables starting with `VITE_` are embedded at build time

## How It Works

### Local Development

When `VITE_API_BASE_URL` is empty or unset:
1. API client uses `/api/v1` as the base URL
2. Vite dev server proxies `/api/*` requests to `http://localhost:8888`
3. Backend runs locally on port 8888

```
Browser → Vite Dev Server (port 3000) → Proxy → Local Backend (port 8888)
```

### Production (Cloudflare Pages)

When `VITE_API_BASE_URL` is set to your Cloud Run URL:
1. API client uses the full Cloud Run URL directly
2. No proxy needed - direct HTTPS connection
3. Backend runs on Google Cloud Run

```
Browser → Cloudflare Pages → Google Cloud Run
```

## Deployment Steps

### 1. Configure Backend URL

First, get your Google Cloud Run backend URL. It should look like:
```
https://trendy-api-xxxxx.run.app
```

### 2. Update Cloudflare Pages Environment Variables

1. Go to your Cloudflare Pages project
2. Navigate to **Settings → Environment Variables**
3. Click **Add variable** for Production environment
4. Add: `VITE_API_BASE_URL` = `https://trendy-api-xxxxx.run.app/api/v1`
5. Save changes

### 3. Deploy

Commit and push your changes:

```bash
git add apps/web/
git commit -m "feat: Configure dynamic backend URL for deployment"
git push
```

Cloudflare Pages will automatically build and deploy.

### 4. Verify Deployment

After deployment:

1. Visit your Cloudflare Pages URL
2. Open browser DevTools → Network tab
3. Log in to the app
4. Check that API requests go to your Google Cloud Run URL
5. Verify no CORS errors

## Backend CORS Configuration

Your Google Cloud Run backend must allow requests from your Cloudflare Pages domain.

**Update backend CORS middleware** to include:
```go
// In apps/backend/internal/middleware/cors.go
config := cors.DefaultConfig()
config.AllowOrigins = []string{
    "http://localhost:3000",           // Local dev
    "https://trendy-web.pages.dev",    // Cloudflare Pages
    "https://your-custom-domain.com",  // Custom domain if any
}
```

## Troubleshooting

### Issue: API requests failing with CORS errors

**Solution:** Update backend CORS configuration to allow your Cloudflare Pages domain

### Issue: API requests still going to localhost in production

**Solution:** Verify `VITE_API_BASE_URL` is set in Cloudflare Pages environment variables

### Issue: Build failing with "lockfile would have been modified"

**Solution:**
- Ensure `"packageManager": "yarn@1.22.22"` is in `package.json`
- Commit the `yarn.lock` file
- Push changes

### Issue: Environment variables not updating

**Solution:**
- Cloudflare caches environment variables
- After updating variables, trigger a new deployment
- Vite embeds env vars at build time, not runtime

## Testing Locally with Production URL

To test the production backend URL locally:

1. Temporarily set in `.env`:
   ```env
   VITE_API_BASE_URL=https://trendy-api-xxxxx.run.app/api/v1
   ```

2. Restart dev server:
   ```bash
   yarn dev
   ```

3. Requests will go directly to Cloud Run (bypassing local backend)

4. Remember to clear this variable when done testing

## Files Modified

- `apps/web/src/lib/api-client.ts` - Uses `VITE_API_BASE_URL` with fallback
- `apps/web/src/vite-env.d.ts` - TypeScript type definitions
- `apps/web/.env` - Local environment variables
- `apps/web/package.json` - Added `packageManager` field and `react-is`
- `apps/web/wrangler.toml` - Cloudflare Pages configuration
- `apps/web/.node-version` - Node version lock
