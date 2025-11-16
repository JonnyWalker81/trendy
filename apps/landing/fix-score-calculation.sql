-- Fix Score Calculation with Stable Formula
-- Uses a constant future timestamp to ensure scores don't change over time
--
-- Score Formula: (CONSTANT - signup_timestamp) + (referrals × 86400)
-- CONSTANT = 2524608000 (Unix timestamp for Jan 1, 2050, 00:00:00 UTC)
--
-- This ensures:
-- - Earlier signups have higher scores
-- - Scores are stable regardless of when they're recalculated
-- - Each referral adds 86400 (1 day) to the score

-- Drop and recreate all triggers with corrected formula
DROP TRIGGER IF EXISTS update_waitlist_timestamp;
DROP TRIGGER IF EXISTS assign_waitlist_position;
DROP TRIGGER IF EXISTS generate_invite_code;
DROP TRIGGER IF EXISTS increment_referral_count;
DROP TRIGGER IF EXISTS calculate_initial_score;
DROP TRIGGER IF EXISTS recalculate_score_on_verify;

-- Update timestamp trigger (unchanged)
CREATE TRIGGER update_waitlist_timestamp
AFTER UPDATE ON waitlist
BEGIN
  UPDATE waitlist SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Calculate initial score on insert
-- Score = (CONSTANT - signup_timestamp)
CREATE TRIGGER calculate_initial_score
AFTER INSERT ON waitlist
BEGIN
  UPDATE waitlist
  SET score = 2524608000 - CAST(strftime('%s', NEW.created_at) AS INTEGER)
  WHERE id = NEW.id;
END;

-- Recalculate score when email is verified (adds referral bonus)
-- Score = (CONSTANT - signup_timestamp) + (referrals × 86400)
CREATE TRIGGER recalculate_score_on_verify
AFTER UPDATE OF email_status ON waitlist
WHEN NEW.email_status = 'verified' AND OLD.email_status != 'verified'
BEGIN
  UPDATE waitlist
  SET score = (2524608000 - CAST(strftime('%s', NEW.created_at) AS INTEGER))
            + (NEW.referrals_count * 86400)
  WHERE id = NEW.id;
END;

-- Generate invite code (unchanged)
CREATE TRIGGER generate_invite_code
AFTER INSERT ON waitlist
BEGIN
  UPDATE waitlist
  SET invite_code = UPPER(SUBSTR(HEX(RANDOMBLOB(4)), 1, 8))
  WHERE id = NEW.id AND invite_code IS NULL;
END;

-- Increment referral count and recalculate REFERRER's score
-- CRITICAL: This updates the person who SENT the invite, not the new user
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

-- Backfill ALL scores with corrected formula
UPDATE waitlist
SET score = (2524608000 - CAST(strftime('%s', created_at) AS INTEGER))
          + (COALESCE(referrals_count, 0) * 86400);
