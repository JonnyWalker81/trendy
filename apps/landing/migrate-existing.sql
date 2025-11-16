-- Migration Script for Existing TrendSight Waitlist Databases
-- Safely adds new columns and tables to existing schema
-- Run this ONCE on existing production databases
--
-- Usage (LOCAL):
--   npx wrangler d1 execute trendsight-waitlist --local --file=./migrate-existing.sql
--
-- Usage (PRODUCTION):
--   npx wrangler d1 execute trendsight-waitlist --remote --file=./migrate-existing.sql
--
-- NOTE: D1 remote databases don't support explicit transaction statements
--       Each statement runs in its own implicit transaction
--

-- ============================================================================
-- STEP 1: Add new columns to waitlist table
-- ============================================================================

-- Email verification & status
ALTER TABLE waitlist ADD COLUMN email_status TEXT NOT NULL DEFAULT 'pending'
  CHECK(email_status IN ('pending', 'verified', 'bounced', 'invalid', 'unsubscribed'));
ALTER TABLE waitlist ADD COLUMN verification_token TEXT;
ALTER TABLE waitlist ADD COLUMN verification_sent_at DATETIME;
ALTER TABLE waitlist ADD COLUMN verified_at DATETIME;
ALTER TABLE waitlist ADD COLUMN verification_attempts INTEGER DEFAULT 0;

-- Consent & compliance
ALTER TABLE waitlist ADD COLUMN consent_given_at DATETIME;
ALTER TABLE waitlist ADD COLUMN consent_ip_address TEXT;
ALTER TABLE waitlist ADD COLUMN consent_user_agent TEXT;
ALTER TABLE waitlist ADD COLUMN privacy_policy_version TEXT DEFAULT 'v1.0';
ALTER TABLE waitlist ADD COLUMN marketing_consent BOOLEAN DEFAULT true;

-- Unsubscribe handling
ALTER TABLE waitlist ADD COLUMN unsubscribed_at DATETIME;
ALTER TABLE waitlist ADD COLUMN unsubscribe_reason TEXT;
ALTER TABLE waitlist ADD COLUMN unsubscribe_token TEXT;

-- Waitlist position & personalization
ALTER TABLE waitlist ADD COLUMN waitlist_position INTEGER;
ALTER TABLE waitlist ADD COLUMN invite_code TEXT;
ALTER TABLE waitlist ADD COLUMN referral_code TEXT;
ALTER TABLE waitlist ADD COLUMN referrals_count INTEGER DEFAULT 0;
ALTER TABLE waitlist ADD COLUMN tier TEXT DEFAULT 'standard'
  CHECK(tier IN ('standard', 'early_access', 'vip', 'beta_tester'));
ALTER TABLE waitlist ADD COLUMN is_vip BOOLEAN DEFAULT false;
ALTER TABLE waitlist ADD COLUMN tags TEXT;
ALTER TABLE waitlist ADD COLUMN custom_metadata TEXT;

-- Resend integration
ALTER TABLE waitlist ADD COLUMN resend_contact_id TEXT;
ALTER TABLE waitlist ADD COLUMN resend_audience_id TEXT;
ALTER TABLE waitlist ADD COLUMN last_synced_to_resend_at DATETIME;
ALTER TABLE waitlist ADD COLUMN resend_sync_status TEXT DEFAULT 'pending'
  CHECK(resend_sync_status IN ('pending', 'synced', 'failed'));

-- Engagement tracking
ALTER TABLE waitlist ADD COLUMN engagement_score INTEGER DEFAULT 0;
ALTER TABLE waitlist ADD COLUMN last_email_opened_at DATETIME;
ALTER TABLE waitlist ADD COLUMN last_email_clicked_at DATETIME;
ALTER TABLE waitlist ADD COLUMN total_emails_sent INTEGER DEFAULT 0;
ALTER TABLE waitlist ADD COLUMN total_emails_opened INTEGER DEFAULT 0;
ALTER TABLE waitlist ADD COLUMN total_emails_clicked INTEGER DEFAULT 0;

-- ============================================================================
-- STEP 2: Create new indexes
-- ============================================================================

-- Regular indexes
CREATE INDEX IF NOT EXISTS idx_waitlist_email_status ON waitlist(email_status);
CREATE INDEX IF NOT EXISTS idx_waitlist_position ON waitlist(waitlist_position);
CREATE INDEX IF NOT EXISTS idx_waitlist_referral_code ON waitlist(referral_code);
CREATE INDEX IF NOT EXISTS idx_waitlist_tier ON waitlist(tier);
CREATE INDEX IF NOT EXISTS idx_waitlist_resend_sync_status ON waitlist(resend_sync_status);
CREATE INDEX IF NOT EXISTS idx_waitlist_engagement_score ON waitlist(engagement_score DESC);
CREATE INDEX IF NOT EXISTS idx_waitlist_marketing_consent ON waitlist(marketing_consent);
CREATE INDEX IF NOT EXISTS idx_waitlist_is_vip ON waitlist(is_vip);

-- Unique indexes (for uniqueness constraints)
CREATE UNIQUE INDEX IF NOT EXISTS idx_waitlist_verification_token ON waitlist(verification_token) WHERE verification_token IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_waitlist_unsubscribe_token ON waitlist(unsubscribe_token) WHERE unsubscribe_token IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_waitlist_invite_code ON waitlist(invite_code) WHERE invite_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_waitlist_resend_contact_id ON waitlist(resend_contact_id) WHERE resend_contact_id IS NOT NULL;

-- ============================================================================
-- STEP 3: Create new tables
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
CREATE INDEX IF NOT EXISTS idx_campaigns_broadcast_id ON email_campaigns(resend_broadcast_id);

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
  FOREIGN KEY (waitlist_id) REFERENCES waitlist(id) ON DELETE CASCADE,
  FOREIGN KEY (campaign_id) REFERENCES email_campaigns(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_email_events_waitlist_id ON email_events(waitlist_id);
CREATE INDEX IF NOT EXISTS idx_email_events_campaign_id ON email_events(campaign_id);
CREATE INDEX IF NOT EXISTS idx_email_events_type ON email_events(event_type);
CREATE INDEX IF NOT EXISTS idx_email_events_timestamp ON email_events(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_email_events_resend_email_id ON email_events(resend_email_id);

CREATE TABLE IF NOT EXISTS data_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  request_type TEXT NOT NULL
    CHECK(request_type IN ('export', 'delete', 'update')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending', 'completed', 'rejected')),
  requested_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  completed_at DATETIME,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_data_requests_email ON data_requests(email);
CREATE INDEX IF NOT EXISTS idx_data_requests_status ON data_requests(status);

-- ============================================================================
-- STEP 4: Backfill data for existing users
-- ============================================================================

-- Generate unique invite codes for existing users
UPDATE waitlist
SET invite_code = UPPER(SUBSTR(HEX(RANDOMBLOB(4)), 1, 8))
WHERE invite_code IS NULL;

-- Generate unsubscribe tokens for existing users
UPDATE waitlist
SET unsubscribe_token = HEX(RANDOMBLOB(32))
WHERE unsubscribe_token IS NULL;

-- Mark existing users as pending (they'll need to verify)
-- OR mark as verified if you want to grandfather them in
-- OPTION 1: Require verification (recommended for compliance)
UPDATE waitlist SET email_status = 'pending' WHERE email_status IS NULL;

-- OPTION 2: Grandfather existing users as verified (comment out OPTION 1, uncomment this)
-- UPDATE waitlist SET email_status = 'verified', verified_at = created_at WHERE email_status IS NULL;

-- ============================================================================
-- STEP 5: Update triggers
-- ============================================================================

-- Drop old triggers if they exist
DROP TRIGGER IF EXISTS update_waitlist_timestamp;
DROP TRIGGER IF EXISTS assign_waitlist_position;
DROP TRIGGER IF EXISTS generate_invite_code;
DROP TRIGGER IF EXISTS increment_referral_count;

-- Recreate with new logic
CREATE TRIGGER update_waitlist_timestamp
AFTER UPDATE ON waitlist
BEGIN
  UPDATE waitlist SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER assign_waitlist_position
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified'
BEGIN
  UPDATE waitlist
  SET waitlist_position = (
    SELECT COUNT(*) + 1 FROM waitlist WHERE email_status = 'verified' AND id < NEW.id
  )
  WHERE id = NEW.id;

  UPDATE waitlist
  SET waitlist_position = waitlist_position + 1
  WHERE email_status = 'verified' AND id > NEW.id AND waitlist_position IS NOT NULL;
END;

CREATE TRIGGER generate_invite_code
AFTER INSERT ON waitlist
BEGIN
  UPDATE waitlist
  SET invite_code = UPPER(SUBSTR(HEX(RANDOMBLOB(4)), 1, 8))
  WHERE id = NEW.id AND invite_code IS NULL;
END;

CREATE TRIGGER increment_referral_count
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified' AND NEW.referral_code IS NOT NULL
BEGIN
  UPDATE waitlist
  SET referrals_count = referrals_count + 1
  WHERE invite_code = NEW.referral_code;
END;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- After running, verify the migration was successful:
-- SELECT COUNT(*) FROM waitlist;
-- SELECT COUNT(*) FROM email_campaigns;
-- SELECT COUNT(*) FROM email_events;
-- SELECT COUNT(*) FROM data_requests;
--
-- Check that all existing users have invite codes:
-- SELECT COUNT(*) FROM waitlist WHERE invite_code IS NULL; -- Should be 0
--
-- Check that all existing users have unsubscribe tokens:
-- SELECT COUNT(*) FROM waitlist WHERE unsubscribe_token IS NULL; -- Should be 0
