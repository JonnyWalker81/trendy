-- Add Score-Based Ranking to Existing Database
-- This script is safe to run on databases that already have the new schema

-- Step 1: Add score column (if it doesn't exist)
-- Note: SQLite doesn't have "IF NOT EXISTS" for ALTER TABLE, so we'll check via a different approach
-- We'll just try to add it - if it fails, that's okay (column already exists)

-- Add the score column
ALTER TABLE waitlist ADD COLUMN score REAL DEFAULT 0;

-- Add index on score
CREATE INDEX IF NOT EXISTS idx_waitlist_score ON waitlist(score DESC);

-- Step 2: Drop and recreate triggers
DROP TRIGGER IF EXISTS update_waitlist_timestamp;
DROP TRIGGER IF EXISTS assign_waitlist_position;
DROP TRIGGER IF EXISTS generate_invite_code;
DROP TRIGGER IF EXISTS increment_referral_count;
DROP TRIGGER IF EXISTS calculate_initial_score;
DROP TRIGGER IF EXISTS recalculate_score_on_verify;

-- Step 3: Create new triggers
CREATE TRIGGER update_waitlist_timestamp
AFTER UPDATE ON waitlist
BEGIN
  UPDATE waitlist SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Calculate initial score on insert (based on signup time only)
CREATE TRIGGER calculate_initial_score
AFTER INSERT ON waitlist
BEGIN
  UPDATE waitlist
  SET score = CAST(strftime('%s', 'now') AS INTEGER) - CAST(strftime('%s', NEW.created_at) AS INTEGER)
  WHERE id = NEW.id;
END;

-- Recalculate score when email is verified
CREATE TRIGGER recalculate_score_on_verify
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified'
BEGIN
  UPDATE waitlist
  SET score = (CAST(strftime('%s', 'now') AS INTEGER) - CAST(strftime('%s', NEW.created_at) AS INTEGER))
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

-- Increment referral count and recalculate score when someone uses a referral code
CREATE TRIGGER increment_referral_count
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified' AND NEW.referral_code IS NOT NULL
BEGIN
  UPDATE waitlist
  SET referrals_count = referrals_count + 1,
      score = (CAST(strftime('%s', 'now') AS INTEGER) - CAST(strftime('%s', created_at) AS INTEGER))
            + ((referrals_count + 1) * 86400)
  WHERE invite_code = NEW.referral_code;
END;

-- Step 4: Backfill scores for existing users
UPDATE waitlist
SET score = (CAST(strftime('%s', 'now') AS INTEGER) - CAST(strftime('%s', created_at) AS INTEGER))
          + (COALESCE(referrals_count, 0) * 86400)
WHERE score = 0 OR score IS NULL;
