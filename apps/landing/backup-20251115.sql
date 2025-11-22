PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE waitlist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  referral_source TEXT,
  ip_address TEXT,
  user_agent TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
, email_status TEXT NOT NULL DEFAULT 'pending'
  CHECK(email_status IN ('pending', 'verified', 'bounced', 'invalid', 'unsubscribed')), verification_token TEXT, verification_sent_at DATETIME, verified_at DATETIME, verification_attempts INTEGER DEFAULT 0, consent_given_at DATETIME, consent_ip_address TEXT, consent_user_agent TEXT, privacy_policy_version TEXT DEFAULT 'v1.0', marketing_consent BOOLEAN DEFAULT true, unsubscribed_at DATETIME, unsubscribe_reason TEXT, unsubscribe_token TEXT, waitlist_position INTEGER, invite_code TEXT, referral_code TEXT, referrals_count INTEGER DEFAULT 0, tier TEXT DEFAULT 'standard'
  CHECK(tier IN ('standard', 'early_access', 'vip', 'beta_tester')), is_vip BOOLEAN DEFAULT false, tags TEXT, custom_metadata TEXT, resend_contact_id TEXT, resend_audience_id TEXT, last_synced_to_resend_at DATETIME, resend_sync_status TEXT DEFAULT 'pending'
  CHECK(resend_sync_status IN ('pending', 'synced', 'failed')), engagement_score INTEGER DEFAULT 0, last_email_opened_at DATETIME, last_email_clicked_at DATETIME, total_emails_sent INTEGER DEFAULT 0, total_emails_opened INTEGER DEFAULT 0, total_emails_clicked INTEGER DEFAULT 0);
CREATE TABLE rate_limits (
  ip_address TEXT PRIMARY KEY,
  attempt_count INTEGER DEFAULT 1,
  first_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "rate_limits" VALUES('2600:6c50:18f0:240:d5e8:3282:53bd:34b1',5,'2025-11-16 03:22:34','2025-11-16 04:33:27');
CREATE TABLE email_campaigns (
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
CREATE TABLE email_events (
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
CREATE TABLE data_requests (
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
DELETE FROM sqlite_sequence;
INSERT INTO "sqlite_sequence" VALUES('waitlist',11);
CREATE INDEX idx_waitlist_email ON waitlist(email);
CREATE INDEX idx_waitlist_created_at ON waitlist(created_at DESC);
CREATE INDEX idx_waitlist_referral_source ON waitlist(referral_source);
CREATE INDEX idx_rate_limits_last_attempt ON rate_limits(last_attempt_at);
CREATE INDEX idx_waitlist_email_status ON waitlist(email_status);
CREATE INDEX idx_waitlist_position ON waitlist(waitlist_position);
CREATE INDEX idx_waitlist_referral_code ON waitlist(referral_code);
CREATE INDEX idx_waitlist_tier ON waitlist(tier);
CREATE INDEX idx_waitlist_resend_sync_status ON waitlist(resend_sync_status);
CREATE INDEX idx_waitlist_engagement_score ON waitlist(engagement_score DESC);
CREATE INDEX idx_waitlist_marketing_consent ON waitlist(marketing_consent);
CREATE INDEX idx_waitlist_is_vip ON waitlist(is_vip);
CREATE UNIQUE INDEX idx_waitlist_verification_token ON waitlist(verification_token) WHERE verification_token IS NOT NULL;
CREATE UNIQUE INDEX idx_waitlist_unsubscribe_token ON waitlist(unsubscribe_token) WHERE unsubscribe_token IS NOT NULL;
CREATE UNIQUE INDEX idx_waitlist_invite_code ON waitlist(invite_code) WHERE invite_code IS NOT NULL;
CREATE UNIQUE INDEX idx_waitlist_resend_contact_id ON waitlist(resend_contact_id) WHERE resend_contact_id IS NOT NULL;
CREATE INDEX idx_campaigns_type ON email_campaigns(campaign_type);
CREATE INDEX idx_campaigns_sent_at ON email_campaigns(sent_at DESC);
CREATE INDEX idx_campaigns_broadcast_id ON email_campaigns(resend_broadcast_id);
CREATE INDEX idx_email_events_waitlist_id ON email_events(waitlist_id);
CREATE INDEX idx_email_events_campaign_id ON email_events(campaign_id);
CREATE INDEX idx_email_events_type ON email_events(event_type);
CREATE INDEX idx_email_events_timestamp ON email_events(event_timestamp DESC);
CREATE INDEX idx_email_events_resend_email_id ON email_events(resend_email_id);
CREATE INDEX idx_data_requests_email ON data_requests(email);
CREATE INDEX idx_data_requests_status ON data_requests(status);
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
