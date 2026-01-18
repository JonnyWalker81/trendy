-- Migration: Add Email Events Table and Engagement Tracking
-- Safe to run multiple times (uses IF NOT EXISTS and tries each ALTER separately)
--
-- Run with:
--   npx wrangler d1 execute trendsight-waitlist --remote --file=./add-email-events.sql
--
-- This fixes the Resend webhook 500 error by adding the missing email_events table
-- and engagement tracking columns that the webhook handler expects.

-- ============================================================================
-- STEP 1: Create email_events table (required for webhook handler)
-- ============================================================================

CREATE TABLE IF NOT EXISTS email_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  waitlist_id INTEGER NOT NULL,
  campaign_id INTEGER,
  event_type TEXT NOT NULL
    CHECK(event_type IN ('sent', 'delivered', 'opened', 'clicked', 'bounced', 'complained', 'unsubscribed', 'delivery_delayed')),
  resend_email_id TEXT,
  link_url TEXT,
  user_agent TEXT,
  ip_address TEXT,
  event_timestamp DATETIME NOT NULL,
  raw_webhook_data TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (waitlist_id) REFERENCES waitlist(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_email_events_waitlist_id ON email_events(waitlist_id);
CREATE INDEX IF NOT EXISTS idx_email_events_type ON email_events(event_type);
CREATE INDEX IF NOT EXISTS idx_email_events_timestamp ON email_events(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_email_events_resend_email_id ON email_events(resend_email_id);

-- ============================================================================
-- STEP 2: Create email_campaigns table (optional but referenced by email_events)
-- ============================================================================

CREATE TABLE IF NOT EXISTS email_campaigns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_name TEXT NOT NULL,
  campaign_type TEXT NOT NULL
    CHECK(campaign_type IN ('verification', 'welcome', 'update', 'launch', 'reminder', 'early_access', 're_engagement')),
  resend_broadcast_id TEXT,
  subject_line TEXT,
  variant TEXT,
  sent_at DATETIME,
  recipient_count INTEGER DEFAULT 0,
  tier_filter TEXT,
  segment_filter TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_campaigns_type ON email_campaigns(campaign_type);
CREATE INDEX IF NOT EXISTS idx_campaigns_sent_at ON email_campaigns(sent_at DESC);

-- ============================================================================
-- STEP 3: Add engagement tracking columns to waitlist table
-- Note: Each ALTER TABLE is run separately. If a column already exists,
-- that statement will fail but the rest will continue.
-- ============================================================================

-- Run these one at a time in Cloudflare D1 console if the batch fails:
-- ALTER TABLE waitlist ADD COLUMN engagement_score INTEGER DEFAULT 0;
-- ALTER TABLE waitlist ADD COLUMN last_email_opened_at DATETIME;
-- ALTER TABLE waitlist ADD COLUMN last_email_clicked_at DATETIME;
-- ALTER TABLE waitlist ADD COLUMN total_emails_sent INTEGER DEFAULT 0;
-- ALTER TABLE waitlist ADD COLUMN total_emails_opened INTEGER DEFAULT 0;
-- ALTER TABLE waitlist ADD COLUMN total_emails_clicked INTEGER DEFAULT 0;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- After running, verify with:
-- SELECT name FROM sqlite_master WHERE type='table' AND name='email_events';
-- SELECT name FROM sqlite_master WHERE type='table' AND name='email_campaigns';
-- PRAGMA table_info(waitlist); -- Check for engagement columns
