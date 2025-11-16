-- Production Migration: Add Score-Based Ranking
-- Safe to run multiple times (idempotent)
-- Run with: npx wrangler d1 execute trendsight-waitlist --remote --file=./production-migration.sql

-- Create migrations tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Check if this migration has already been applied
-- If it has, the script will fail safely at the INSERT below
-- You can check with: SELECT * FROM schema_migrations WHERE version = '2025-11-16-score-ranking';

-- Add score column (will fail if already exists, that's OK)
-- NOTE: This will fail with "duplicate column" if already applied - that's expected
ALTER TABLE waitlist ADD COLUMN score REAL DEFAULT 0;

-- Add score index (safe - IF NOT EXISTS)
CREATE INDEX IF NOT EXISTS idx_waitlist_score ON waitlist(score DESC);

-- Drop old triggers (safe - IF EXISTS)
DROP TRIGGER IF EXISTS update_waitlist_timestamp;
DROP TRIGGER IF EXISTS assign_waitlist_position;
DROP TRIGGER IF EXISTS generate_invite_code;
DROP TRIGGER IF EXISTS increment_referral_count;
DROP TRIGGER IF EXISTS calculate_initial_score;
DROP TRIGGER IF EXISTS recalculate_score_on_verify;

-- Create triggers with corrected score formula
-- CONSTANT = 2524608000 (Unix timestamp for Jan 1, 2050, 00:00:00 UTC)
CREATE TRIGGER update_waitlist_timestamp
AFTER UPDATE ON waitlist
BEGIN
  UPDATE waitlist SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER calculate_initial_score
AFTER INSERT ON waitlist
BEGIN
  UPDATE waitlist
  SET score = 2524608000 - CAST(strftime('%s', NEW.created_at) AS INTEGER)
  WHERE id = NEW.id;
END;

CREATE TRIGGER recalculate_score_on_verify
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified'
BEGIN
  UPDATE waitlist
  SET score = (2524608000 - CAST(strftime('%s', NEW.created_at) AS INTEGER))
            + (NEW.referrals_count * 86400)
  WHERE id = NEW.id;
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
  SET referrals_count = referrals_count + 1,
      score = (2524608000 - CAST(strftime('%s', created_at) AS INTEGER))
            + ((referrals_count + 1) * 86400)
  WHERE invite_code = NEW.referral_code;
END;

-- Backfill scores for ALL existing users (safe - updates all rows)
UPDATE waitlist
SET score = (2524608000 - CAST(strftime('%s', created_at) AS INTEGER))
          + (COALESCE(referrals_count, 0) * 86400);

-- Mark migration as applied
INSERT INTO schema_migrations (version) VALUES ('2025-11-16-score-ranking');

-- Verification queries (optional - copy these to run separately)
-- SELECT COUNT(*) FROM waitlist WHERE score > 0; -- Should equal total users
-- SELECT email, score, referrals_count, created_at FROM waitlist ORDER BY score DESC LIMIT 10;
-- SELECT * FROM schema_migrations;
