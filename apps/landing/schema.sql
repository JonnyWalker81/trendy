-- TrendSight Waitlist Database Schema - Production Grade
-- D1 SQLite Database for storing waitlist signups with full email management

-- ============================================================================
-- MAIN WAITLIST TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS waitlist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Basic contact information
  email TEXT NOT NULL UNIQUE,
  name TEXT,

  -- Email verification & status
  email_status TEXT NOT NULL DEFAULT 'pending'
    CHECK(email_status IN ('pending', 'verified', 'bounced', 'invalid', 'unsubscribed')),
  verification_token TEXT UNIQUE,
  verification_sent_at DATETIME,
  verified_at DATETIME,
  verification_attempts INTEGER DEFAULT 0,

  -- Consent & compliance (GDPR)
  consent_given_at DATETIME,
  consent_ip_address TEXT,
  consent_user_agent TEXT,
  privacy_policy_version TEXT DEFAULT 'v1.0',
  marketing_consent BOOLEAN DEFAULT true,

  -- Unsubscribe handling
  unsubscribed_at DATETIME,
  unsubscribe_reason TEXT,
  unsubscribe_token TEXT UNIQUE,

  -- Waitlist position & personalization
  waitlist_position INTEGER,
  invite_code TEXT UNIQUE,
  referral_code TEXT, -- Code they used to sign up (who referred them)
  referrals_count INTEGER DEFAULT 0,
  tier TEXT DEFAULT 'standard'
    CHECK(tier IN ('standard', 'early_access', 'vip', 'beta_tester')),
  is_vip BOOLEAN DEFAULT false,
  tags TEXT, -- JSON array for flexible tagging
  custom_metadata TEXT, -- JSON object for additional data

  -- Attribution tracking
  referral_source TEXT,
  ip_address TEXT,
  user_agent TEXT,

  -- Resend integration
  resend_contact_id TEXT UNIQUE,
  resend_audience_id TEXT,
  last_synced_to_resend_at DATETIME,
  resend_sync_status TEXT DEFAULT 'pending'
    CHECK(resend_sync_status IN ('pending', 'synced', 'failed')),

  -- Engagement tracking
  engagement_score INTEGER DEFAULT 0,
  last_email_opened_at DATETIME,
  last_email_clicked_at DATETIME,
  total_emails_sent INTEGER DEFAULT 0,
  total_emails_opened INTEGER DEFAULT 0,
  total_emails_clicked INTEGER DEFAULT 0,

  -- Timestamps
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- WAITLIST TABLE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_waitlist_email ON waitlist(email);
CREATE INDEX IF NOT EXISTS idx_waitlist_email_status ON waitlist(email_status);
CREATE INDEX IF NOT EXISTS idx_waitlist_verification_token ON waitlist(verification_token);
CREATE INDEX IF NOT EXISTS idx_waitlist_unsubscribe_token ON waitlist(unsubscribe_token);
CREATE INDEX IF NOT EXISTS idx_waitlist_position ON waitlist(waitlist_position);
CREATE INDEX IF NOT EXISTS idx_waitlist_invite_code ON waitlist(invite_code);
CREATE INDEX IF NOT EXISTS idx_waitlist_referral_code ON waitlist(referral_code);
CREATE INDEX IF NOT EXISTS idx_waitlist_tier ON waitlist(tier);
CREATE INDEX IF NOT EXISTS idx_waitlist_resend_contact_id ON waitlist(resend_contact_id);
CREATE INDEX IF NOT EXISTS idx_waitlist_resend_sync_status ON waitlist(resend_sync_status);
CREATE INDEX IF NOT EXISTS idx_waitlist_engagement_score ON waitlist(engagement_score DESC);
CREATE INDEX IF NOT EXISTS idx_waitlist_created_at ON waitlist(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_waitlist_referral_source ON waitlist(referral_source);
CREATE INDEX IF NOT EXISTS idx_waitlist_marketing_consent ON waitlist(marketing_consent);
CREATE INDEX IF NOT EXISTS idx_waitlist_is_vip ON waitlist(is_vip);

-- ============================================================================
-- EMAIL CAMPAIGNS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS email_campaigns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_name TEXT NOT NULL,
  campaign_type TEXT NOT NULL
    CHECK(campaign_type IN ('verification', 'welcome', 'update', 'launch', 'reminder', 'early_access', 're_engagement')),
  resend_broadcast_id TEXT,
  subject_line TEXT,
  variant TEXT, -- For A/B testing
  sent_at DATETIME,
  recipient_count INTEGER DEFAULT 0,
  tier_filter TEXT, -- JSON array of tiers targeted
  segment_filter TEXT, -- JSON object with filter criteria
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_campaigns_type ON email_campaigns(campaign_type);
CREATE INDEX IF NOT EXISTS idx_campaigns_sent_at ON email_campaigns(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaigns_broadcast_id ON email_campaigns(resend_broadcast_id);

-- ============================================================================
-- EMAIL EVENTS TABLE (from Resend webhooks)
-- ============================================================================

CREATE TABLE IF NOT EXISTS email_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  waitlist_id INTEGER NOT NULL,
  campaign_id INTEGER,
  event_type TEXT NOT NULL
    CHECK(event_type IN ('sent', 'delivered', 'opened', 'clicked', 'bounced', 'complained', 'unsubscribed', 'delivery_delayed')),
  resend_email_id TEXT,
  link_url TEXT, -- For click events
  user_agent TEXT,
  ip_address TEXT,
  event_timestamp DATETIME NOT NULL,
  raw_webhook_data TEXT, -- Full JSON payload
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (waitlist_id) REFERENCES waitlist(id) ON DELETE CASCADE,
  FOREIGN KEY (campaign_id) REFERENCES email_campaigns(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_email_events_waitlist_id ON email_events(waitlist_id);
CREATE INDEX IF NOT EXISTS idx_email_events_campaign_id ON email_events(campaign_id);
CREATE INDEX IF NOT EXISTS idx_email_events_type ON email_events(event_type);
CREATE INDEX IF NOT EXISTS idx_email_events_timestamp ON email_events(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_email_events_resend_email_id ON email_events(resend_email_id);

-- ============================================================================
-- DATA REQUESTS TABLE (GDPR compliance)
-- ============================================================================

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
-- RATE LIMITING TABLE (unchanged)
-- ============================================================================

CREATE TABLE IF NOT EXISTS rate_limits (
  ip_address TEXT PRIMARY KEY,
  attempt_count INTEGER DEFAULT 1,
  first_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_last_attempt ON rate_limits(last_attempt_at);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp on any row update
CREATE TRIGGER IF NOT EXISTS update_waitlist_timestamp
AFTER UPDATE ON waitlist
BEGIN
  UPDATE waitlist SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Auto-assign waitlist position when email is verified
CREATE TRIGGER IF NOT EXISTS assign_waitlist_position
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified'
BEGIN
  UPDATE waitlist
  SET waitlist_position = (
    SELECT COUNT(*) + 1 FROM waitlist WHERE email_status = 'verified' AND id < NEW.id
  )
  WHERE id = NEW.id;

  -- Update positions of users who signed up after this one
  UPDATE waitlist
  SET waitlist_position = waitlist_position + 1
  WHERE email_status = 'verified' AND id > NEW.id AND waitlist_position IS NOT NULL;
END;

-- Auto-generate invite code on insert
CREATE TRIGGER IF NOT EXISTS generate_invite_code
AFTER INSERT ON waitlist
BEGIN
  UPDATE waitlist
  SET invite_code = UPPER(SUBSTR(HEX(RANDOMBLOB(4)), 1, 8))
  WHERE id = NEW.id AND invite_code IS NULL;
END;

-- Increment referral count when someone uses a referral code
CREATE TRIGGER IF NOT EXISTS increment_referral_count
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified' AND NEW.referral_code IS NOT NULL
BEGIN
  UPDATE waitlist
  SET referrals_count = referrals_count + 1
  WHERE invite_code = NEW.referral_code;
END;

-- ============================================================================
-- EXAMPLE QUERIES FOR REFERENCE
-- ============================================================================

-- Query: Get verified contacts ready for launch email
-- SELECT * FROM waitlist WHERE email_status = 'verified' AND marketing_consent = true ORDER BY waitlist_position;

-- Query: Get contacts by tier for segmented campaign
-- SELECT * FROM waitlist WHERE email_status = 'verified' AND tier = 'vip' ORDER BY waitlist_position;

-- Query: Calculate open rate for a campaign
-- SELECT
--   campaign_id,
--   COUNT(DISTINCT CASE WHEN event_type = 'opened' THEN waitlist_id END) * 100.0 /
--   COUNT(DISTINCT CASE WHEN event_type = 'sent' THEN waitlist_id END) as open_rate
-- FROM email_events
-- WHERE campaign_id = 1
-- GROUP BY campaign_id;

-- Query: Get highly engaged contacts (engagement score > 50)
-- SELECT * FROM waitlist WHERE engagement_score > 50 AND email_status = 'verified' ORDER BY engagement_score DESC;

-- Query: Find cold contacts who haven't opened recent emails
-- SELECT * FROM waitlist WHERE email_status = 'verified' AND total_emails_sent > 2 AND total_emails_opened = 0;

-- Query: Export all verified emails for Resend
-- SELECT email, name, waitlist_position, tier, invite_code FROM waitlist WHERE email_status = 'verified';

-- Query: Get top referrers
-- SELECT email, name, invite_code, referrals_count FROM waitlist WHERE referrals_count > 0 ORDER BY referrals_count DESC LIMIT 10;

-- Query: Cleanup old rate limits (run hourly)
-- DELETE FROM rate_limits WHERE last_attempt_at < datetime('now', '-1 hour');

-- Query: Cleanup old email events (run monthly, keep 2 years)
-- DELETE FROM email_events WHERE event_timestamp < datetime('now', '-2 years');
