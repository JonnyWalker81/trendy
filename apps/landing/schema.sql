-- TrendSight Waitlist Database Schema
-- D1 SQLite Database for storing waitlist signups

-- Main waitlist table
CREATE TABLE IF NOT EXISTS waitlist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  referral_source TEXT,
  ip_address TEXT,
  user_agent TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Index for faster email lookups (duplicate checking)
CREATE INDEX IF NOT EXISTS idx_waitlist_email ON waitlist(email);

-- Index for sorting by signup date
CREATE INDEX IF NOT EXISTS idx_waitlist_created_at ON waitlist(created_at DESC);

-- Index for analytics by referral source
CREATE INDEX IF NOT EXISTS idx_waitlist_referral_source ON waitlist(referral_source);

-- Rate limiting table (tracks submission attempts by IP)
CREATE TABLE IF NOT EXISTS rate_limits (
  ip_address TEXT PRIMARY KEY,
  attempt_count INTEGER DEFAULT 1,
  first_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Index for cleaning up old rate limit entries
CREATE INDEX IF NOT EXISTS idx_rate_limits_last_attempt ON rate_limits(last_attempt_at);

-- Trigger to update updated_at timestamp
CREATE TRIGGER IF NOT EXISTS update_waitlist_timestamp
AFTER UPDATE ON waitlist
BEGIN
  UPDATE waitlist SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Insert some example queries for reference (commented out)

-- Query: Get all signups from last 7 days
-- SELECT * FROM waitlist WHERE created_at >= datetime('now', '-7 days') ORDER BY created_at DESC;

-- Query: Count signups by referral source
-- SELECT referral_source, COUNT(*) as count FROM waitlist GROUP BY referral_source ORDER BY count DESC;

-- Query: Get total signup count
-- SELECT COUNT(*) as total_signups FROM waitlist;

-- Query: Export all emails
-- SELECT email FROM waitlist ORDER BY created_at;

-- Query: Get signups per day for last 30 days
-- SELECT DATE(created_at) as signup_date, COUNT(*) as signups
-- FROM waitlist
-- WHERE created_at >= datetime('now', '-30 days')
-- GROUP BY DATE(created_at)
-- ORDER BY signup_date DESC;

-- Query: Clean up old rate limit entries (older than 1 hour)
-- DELETE FROM rate_limits WHERE last_attempt_at < datetime('now', '-1 hour');
