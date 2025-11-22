# TrendSight Landing Page

Production-ready landing page with waitlist signup form powered by Cloudflare Pages, D1 SQLite database, Resend email service, and Turnstile spam protection.

## Features

- 📝 **Waitlist signup form** with email, name, and referral source fields
- 🗄️ **D1 SQLite database** for persistent storage
- 📧 **Resend email integration** via REST API for confirmation emails
- 🛡️ **Cloudflare Turnstile** spam protection
- 🚀 **Cloudflare Pages** deployment
- ⚡ **Serverless** - no backend server needed
- 🔒 **Rate limiting** - 5 submissions per IP per hour
- ✅ **Validation** - email format, disposable domains, duplicates

## Prerequisites

Before deploying, you'll need:

1. **Cloudflare account** ([sign up free](https://dash.cloudflare.com/sign-up))
2. **Resend account** ([sign up free](https://resend.com/signup))
3. **Node.js 18+** installed locally
4. **npm/yarn** package manager

## Local Development Setup

### 1. Install Dependencies

```bash
cd apps/landing
npm install
# or
yarn install
```

### 2. Create D1 Database

```bash
# Create the database
npx wrangler d1 create trendsight-waitlist

# Copy the database_id from the output and update wrangler.toml
# Look for: database_id = "YOUR_DATABASE_ID_HERE"
```

### 3. Initialize Database Schema

```bash
# Apply the schema to your D1 database
npx wrangler d1 execute trendsight-waitlist --file=./schema.sql
```

### 4. Set Up Cloudflare Turnstile

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → Turnstile
2. Click "Add Site"
3. Configure:
   - **Site name**: TrendSight Waitlist
   - **Domain**: Your domain (or `localhost` for testing)
   - **Widget mode**: Managed (recommended)
4. Copy the **Site Key** and **Secret Key**
5. Update `index.html` line 699 with your Site Key:
   ```html
   <div class="cf-turnstile" data-sitekey="YOUR_SITE_KEY_HERE" data-theme="dark"></div>
   ```

### 5. Set Up Resend

1. Go to [Resend Dashboard](https://resend.com/domains)
2. Click "Add Domain"
3. Add your domain (e.g., `trendsight.com`)
4. Add the DNS records to your Cloudflare DNS:
   - **DKIM** record (TXT)
   - **SPF** record (TXT)
   - **DMARC** record (TXT)
5. Wait for verification (usually a few minutes)
6. Go to [API Keys](https://resend.com/api-keys)
7. Create a new API key
8. Copy the API key

### 6. Configure Environment Variables

Create a `.dev.vars` file in the `apps/landing/` directory:

```bash
cp .dev.vars.example .dev.vars
```

Edit `.dev.vars` and add your actual values:

```env
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TURNSTILE_SECRET_KEY=0x4AAAAAAAxxxxxxxxxxxxxxxxxxxxxxxxx
ADMIN_EMAIL=your-email@yourdomain.com
FROM_EMAIL=noreply@yourdomain.com
```

**Important**: Make sure `FROM_EMAIL` uses the domain you verified in Resend!

### 7. Run Local Development Server

```bash
npm run dev
# or
yarn dev
```

Visit http://localhost:8788 to see your landing page.

**Note**: The Turnstile test/dummy site key `1x00000000000000000000AA` always passes. Replace it with your real site key for production.

## Production Deployment

### Option 1: Deploy via Wrangler CLI

```bash
# Build and deploy
npm run deploy
# or
yarn deploy
```

After deployment, you'll need to:

1. Set production environment variables in Cloudflare dashboard
2. Link your D1 database to the Pages project

### Option 2: Deploy via Cloudflare Dashboard

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → Pages
2. Click "Create a project"
3. Connect your Git repository
4. Configure build settings:
   - **Build command**: (leave empty)
   - **Build output directory**: `.`
   - **Root directory**: `apps/landing`
5. Click "Save and Deploy"

### Configure Production Environment Variables

After deployment, add environment variables:

1. Go to your Pages project → Settings → Environment variables
2. Add the following **production** variables:
   - `RESEND_API_KEY` (mark as secret)
   - `TURNSTILE_SECRET_KEY` (mark as secret)
   - `ADMIN_EMAIL`
   - `FROM_EMAIL`

### Link D1 Database to Pages

1. Go to your Pages project → Settings → Functions
2. Scroll to "D1 database bindings"
3. Click "Add binding"
4. **Variable name**: `WAITLIST_DB`
5. **D1 database**: Select `trendsight-waitlist`
6. Click "Save"

### Update Turnstile Site Key

Don't forget to update the Turnstile site key in `index.html` (line 699) with your production site key before deploying!

## Database Operations

### View Waitlist Signups

```bash
# Get all signups
npx wrangler d1 execute trendsight-waitlist --command "SELECT * FROM waitlist ORDER BY created_at DESC"

# Get count
npx wrangler d1 execute trendsight-waitlist --command "SELECT COUNT(*) as total FROM waitlist"

# Get signups from last 7 days
npx wrangler d1 execute trendsight-waitlist --command "SELECT * FROM waitlist WHERE created_at >= datetime('now', '-7 days') ORDER BY created_at DESC"
```

### Analytics Queries

```bash
# Count by referral source
npx wrangler d1 execute trendsight-waitlist --command "SELECT referral_source, COUNT(*) as count FROM waitlist GROUP BY referral_source ORDER BY count DESC"

# Signups per day for last 30 days
npx wrangler d1 execute trendsight-waitlist --command "SELECT DATE(created_at) as date, COUNT(*) as signups FROM waitlist WHERE created_at >= datetime('now', '-30 days') GROUP BY DATE(created_at) ORDER BY date DESC"
```

### Export Waitlist Data

```bash
# Export entire database
npm run db:export
# or
npx wrangler d1 export trendsight-waitlist --output=waitlist-export.sql

# Export just emails (for email marketing)
npx wrangler d1 execute trendsight-waitlist --command "SELECT email FROM waitlist ORDER BY created_at" --json > emails.json
```

### Backup and Restore

```bash
# Backup (export)
npx wrangler d1 export trendsight-waitlist --output=backup-$(date +%Y%m%d).sql

# Restore (import)
npx wrangler d1 execute trendsight-waitlist --file=backup-20250114.sql
```

## Testing the Form

### Testing Turnstile

Cloudflare provides test site keys that always pass or fail:

- **Always passes**: `1x00000000000000000000AA`
- **Always blocks**: `2x00000000000000000000AB`
- **Force challenge**: `3x00000000000000000000FF`

Use these for local testing, then replace with your real site key for production.

### Testing Email Delivery

1. Use your real email address in the form
2. Check spam folder if you don't see the confirmation email
3. Verify DNS records are correct in Resend dashboard
4. Check Resend logs for delivery status

### Testing Rate Limiting

The rate limiter allows 5 submissions per IP per hour. To test:

1. Submit the form 5 times quickly
2. The 6th submission should fail with "Too many attempts"
3. Wait 1 hour or clear the `rate_limits` table to reset

## Troubleshooting

### Form Submission Fails

1. **Check browser console** for JavaScript errors
2. **Verify Turnstile** is loaded (check Network tab)
3. **Check environment variables** are set correctly
4. **View function logs** in Cloudflare dashboard → Pages → project → Functions

### Email Not Sending

1. **Verify Resend domain** is verified (green checkmark in dashboard)
2. **Check DNS records** are correct (DKIM, SPF, DMARC)
3. **Verify FROM_EMAIL** matches verified domain
4. **Check Resend logs** for error messages
5. **Try sending test email** via Resend dashboard

### Turnstile Not Working

1. **Verify site key** in HTML matches Turnstile dashboard
2. **Check domain** in Turnstile settings matches your domain
3. **Look for errors** in browser console
4. **Test with dummy key** `1x00000000000000000000AA` to isolate issue

### D1 Database Issues

1. **Verify database binding** in Pages settings (variable name: `WAITLIST_DB`)
2. **Check schema** was applied: `npx wrangler d1 execute trendsight-waitlist --command "SELECT name FROM sqlite_master WHERE type='table'"`
3. **Test connection** locally with `npm run dev`

### Rate Limit False Positives

If legitimate users are being blocked:

1. Increase limit in `functions/_middleware.ts` (line 142)
2. Adjust time window (currently 1 hour)
3. Or clear old entries more frequently

## Architecture

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ 1. Form Submit
       ▼
┌─────────────────────────┐
│  Cloudflare Pages       │
│  Static Form Plugin     │
└──────┬──────────────────┘
       │
       ├─ 2. Verify Turnstile
       │  (Cloudflare API)
       │
       ├─ 3. Validate Email
       │  (Format + Disposable Check)
       │
       ├─ 4. Check Rate Limit
       │  (D1 Query)
       │
       ├─ 5. Check Duplicate
       │  (D1 Query)
       │
       ├─ 6. Insert Signup
       │  (D1 Insert)
       │
       ├─ 7. Send Emails
       │  (Resend API)
       │
       └─ 8. Return Response
          (JSON)
```

## Tech Stack

- **Frontend**: HTML, Tailwind CSS, Vanilla JavaScript
- **Backend**: Cloudflare Pages Functions (TypeScript)
- **Database**: Cloudflare D1 (SQLite)
- **Email**: Resend REST API (no SDK dependencies)
- **Spam Protection**: Cloudflare Turnstile
- **Deployment**: Cloudflare Pages

## Cost Breakdown (Free Tiers)

| Service | Free Tier | Enough For |
|---------|-----------|------------|
| Cloudflare Pages | 500 builds/month, Unlimited requests | ✅ Yes |
| Cloudflare D1 | 5M reads/day, 100K writes/day | ✅ ~3,000 signups/day |
| Cloudflare Functions | 100K requests/day | ✅ Yes |
| Resend | 3,000 emails/month, 100/day | ✅ ~1,500 signups/month |
| Turnstile | Unlimited | ✅ Yes |

**Total monthly cost**: $0 for most waitlists 🎉

## Security Features

✅ **Turnstile spam protection** - Prevents bots
✅ **Rate limiting** - Prevents abuse (5 req/hour per IP)
✅ **Email validation** - Format + disposable domain check
✅ **Duplicate prevention** - Unique email constraint
✅ **Server-side validation** - Never trust client input
✅ **Environment secrets** - API keys stored securely
✅ **HTTPS only** - Enforced by Cloudflare

## Privacy & GDPR

The form collects:
- Email address (required)
- Name (optional)
- Referral source (optional)
- IP address (for rate limiting)
- User agent (for analytics)

Make sure to:
1. Add privacy policy link in the form
2. Explain data usage clearly
3. Provide option to delete data (GDPR right to be forgotten)
4. Don't use data for anything other than stated purpose

## Customization

### Change Form Fields

Edit `index.html` and `functions/_middleware.ts` to add/remove fields.

### Change Email Templates

Edit `getUserConfirmationEmail()` and `getAdminNotificationEmail()` functions in `functions/_middleware.ts`.

### Change Rate Limit

Edit `checkRateLimit()` function in `functions/_middleware.ts` (line 142).

### Add More Validation

Add custom validation functions in `functions/_middleware.ts`.

## Support

For issues or questions:
- **Cloudflare**: https://community.cloudflare.com/
- **Resend**: https://resend.com/support
- **TrendSight**: hello@trendsight.com

## License

Part of the TrendSight project.
