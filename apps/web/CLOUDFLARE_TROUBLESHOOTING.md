# Troubleshooting: VITE_API_BASE_URL Not Working in Cloudflare Pages

## The Problem

You've set `VITE_API_BASE_URL` in Cloudflare Pages, but the app is still using `/api/v1` instead of your Google Cloud Run URL.

## Root Cause

**Vite embeds environment variables at BUILD time, NOT runtime.**

This means:
- Environment variables are baked into the JavaScript bundle during `yarn build`
- If you added/changed the env var AFTER the last build, it won't be in the deployed code
- You must trigger a NEW build/deployment for the changes to take effect

## Solution: Step-by-Step Fix

### Step 1: Verify Environment Variable in Cloudflare

1. Go to your Cloudflare Pages project dashboard
2. Navigate to: **Settings → Environment Variables**
3. Click on **Production** tab (NOT Preview)
4. Verify you have:
   ```
   VITE_API_BASE_URL = https://your-service.run.app/api/v1
   ```

**Common Mistakes:**
- ❌ Set in "Preview" instead of "Production"
- ❌ Missing `/api/v1` at the end of the URL
- ❌ Extra spaces or quotes around the value
- ❌ Using `http://` instead of `https://`
- ❌ Typo in variable name (must be exactly `VITE_API_BASE_URL`)

**Correct Format:**
```
Variable name: VITE_API_BASE_URL
Value: https://trendy-api-xxxxx.run.app/api/v1
Environment: Production
```

### Step 2: Commit and Push Latest Code

Make sure the latest code with debugging is deployed:

```bash
cd /Users/phantom/Repositories/trendy
git add apps/web/
git commit -m "feat: Add API base URL debugging"
git push
```

### Step 3: Trigger a New Deployment

Cloudflare Pages needs to rebuild with the new environment variable.

**Option A: Push a new commit** (Recommended)
```bash
# Make a trivial change to force rebuild
echo "# Build $(date)" >> apps/web/README.md
git add apps/web/README.md
git commit -m "chore: Trigger rebuild for env vars"
git push
```

**Option B: Retry existing deployment**
1. Go to Cloudflare Pages → **Deployments** tab
2. Find the latest deployment
3. Click **...** (three dots) → **Retry deployment**

**Option C: Manual deployment**
1. Go to Cloudflare Pages → **Deployments** tab
2. Click **Create deployment** button
3. Select your main branch

### Step 4: Verify the Build

Watch the build logs in Cloudflare Pages:

1. Go to **Deployments** tab
2. Click on the in-progress deployment
3. Look for the build output
4. Environment variables should be listed (Cloudflare shows them during build)

### Step 5: Check Browser Console

After deployment completes:

1. Visit your Cloudflare Pages URL
2. Open browser DevTools (F12)
3. Go to **Console** tab
4. Look for the log message:
   ```
   🚀 Production API Base: https://your-service.run.app/api/v1
   ```

**If you see:**
- `🚀 Production API Base: /api/v1` → Environment variable NOT embedded (rebuild needed)
- `🚀 Production API Base: https://...` → Environment variable IS embedded ✅

### Step 6: Test API Request

1. Stay in DevTools, switch to **Network** tab
2. Log in to the app
3. Filter for "Fetch/XHR" requests
4. Click on any API request (e.g., `event-types`)
5. Check the **Request URL**:
   - ✅ Should be: `https://your-service.run.app/api/v1/event-types`
   - ❌ Should NOT be: `https://trendy-web.pages.dev/api/v1/event-types`

## Common Issues and Solutions

### Issue 1: Environment Variable Not Being Embedded

**Symptoms:**
- Console shows: `🚀 Production API Base: /api/v1`
- Environment variable is set in Cloudflare

**Solution:**
- Cloudflare build system might be caching
- Go to Settings → Build & deployments → Build cache → **Clear cache**
- Trigger a new deployment
- If still not working, check you're setting in "Production" not "Preview"

### Issue 2: Wrong Environment (Preview vs Production)

**Symptoms:**
- Works in one deployment but not another
- Env var shows in settings but not in app

**Solution:**
- Preview deployments and Production deployments have SEPARATE environment variables
- Make sure you set `VITE_API_BASE_URL` in BOTH if you want it in preview builds
- Or just set in Production for main branch deployments

### Issue 3: API Requests Return 404

**Symptoms:**
- Console shows correct URL: `https://your-service.run.app/api/v1`
- But API requests fail with 404

**Solution:**
- Your Google Cloud Run service might not be running
- Verify backend URL is correct:
  ```bash
  curl https://your-service.run.app/api/v1/health
  # Should return: {"env":"production","status":"ok"}
  ```
- Check backend deployment logs in Google Cloud Console

### Issue 4: CORS Errors

**Symptoms:**
- Console shows correct URL
- Requests fail with "CORS policy" error

**Solution:**
- Backend CORS middleware needs to allow your Cloudflare domain
- Update `apps/backend/internal/middleware/cors.go`:
  ```go
  config.AllowOrigins = []string{
      "http://localhost:3000",
      "https://trendy-web.pages.dev",          // Add this
      "https://your-custom-domain.com",        // If you have one
  }
  ```
- Redeploy your backend to Google Cloud Run

### Issue 5: Empty String Value

**Symptoms:**
- Env var is set but appears empty
- Console logs show: `VITE_API_BASE_URL: ""`

**Solution:**
- In Cloudflare Pages, make sure there's no trailing/leading spaces
- Remove the variable completely and re-add it
- Value should NOT have quotes: `https://...` not `"https://..."`

## Debug Checklist

Use this checklist to systematically debug:

- [ ] Environment variable is set in **Production** (not Preview)
- [ ] Variable name is exactly: `VITE_API_BASE_URL` (no typos)
- [ ] Value includes full path: `https://your-service.run.app/api/v1`
- [ ] Latest code is pushed to GitHub
- [ ] New deployment was triggered AFTER setting env var
- [ ] Build completed successfully (no errors)
- [ ] Build cache was cleared if needed
- [ ] Browser console shows production API base URL
- [ ] Network tab shows requests going to correct URL
- [ ] Backend is accessible at the URL
- [ ] Backend CORS allows Cloudflare domain

## Testing Locally with Production URL

To test without deploying:

1. Edit `apps/web/.env`:
   ```env
   VITE_API_BASE_URL=https://your-service.run.app/api/v1
   ```

2. Restart dev server:
   ```bash
   yarn --cwd apps/web dev
   ```

3. Open http://localhost:3000
4. Console should show:
   ```
   🔧 API Configuration: {
     VITE_API_BASE_URL: 'https://your-service.run.app/api/v1',
     API_BASE: 'https://your-service.run.app/api/v1',
     isDev: true,
     mode: 'development'
   }
   ```

5. Test login and API calls
6. Remember to clear the `.env` variable when done

## Still Not Working?

### Inspect Built Bundle

Download the built JavaScript from Cloudflare and search for the API URL:

1. Visit your deployed site
2. View page source
3. Find the `<script>` tag loading the main JS bundle
4. Copy the URL (e.g., `/assets/index-XXXXX.js`)
5. Open that file directly: `https://trendy-web.pages.dev/assets/index-XXXXX.js`
6. Search (Cmd/Ctrl+F) for `/api/v1`
7. You should see your Google Cloud Run URL nearby

If you see `/api/v1` but NOT your Cloud Run URL, the env var wasn't embedded.

### Contact Support

If you've tried everything:

1. Provide the full Cloudflare build log
2. Show a screenshot of Environment Variables settings
3. Share the browser console output
4. Include the Network tab request URL

## Quick Reference

**Environment Variable:**
```
Name: VITE_API_BASE_URL
Value: https://your-service-name.run.app/api/v1
Where: Cloudflare Pages → Settings → Environment Variables → Production
```

**Force Rebuild Commands:**
```bash
git commit --allow-empty -m "chore: Trigger Cloudflare rebuild"
git push
```

**Test Backend:**
```bash
curl https://your-service.run.app/api/v1/health
# Expected: {"env":"production","status":"ok"}
```

**Check Console:**
- Look for: `🚀 Production API Base: https://...`
- Network tab should show requests to Cloud Run, not Cloudflare Pages

## Files Modified

- `apps/web/src/lib/api-client.ts` - Added debug logging
- `apps/web/.env` - Local env var configuration
- `apps/web/src/vite-env.d.ts` - TypeScript types

## Next Steps

Once working:
1. Remove debug console.log if desired (or keep for monitoring)
2. Set up error monitoring (Sentry, LogRocket, etc.)
3. Add health check endpoint to your frontend
4. Monitor API performance
