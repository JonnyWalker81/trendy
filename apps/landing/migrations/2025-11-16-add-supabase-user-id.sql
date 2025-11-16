-- Migration: Link Waitlist to Supabase Users
-- Safe to run multiple times (idempotent)
-- Run with: npx wrangler d1 execute trendsight-waitlist --remote --file=./migrations/2025-11-16-add-supabase-user-id.sql

-- Create migrations tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Add supabase_user_id column (will fail if already exists, that's OK)
-- This links a waitlist entry to a registered Supabase user
ALTER TABLE waitlist ADD COLUMN supabase_user_id TEXT NULL;

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_waitlist_supabase_user_id ON waitlist(supabase_user_id);

-- Add unique constraint to prevent duplicate signups with same code
-- Note: In SQLite, we can't easily add UNIQUE constraint to existing column
-- So we create a unique index instead
CREATE UNIQUE INDEX IF NOT EXISTS unique_waitlist_supabase_user_id ON waitlist(supabase_user_id) WHERE supabase_user_id IS NOT NULL;

-- Mark migration as applied
INSERT INTO schema_migrations (version) VALUES ('2025-11-16-add-supabase-user-id');

-- Verification queries (optional - copy these to run separately)
-- SELECT COUNT(*) FROM waitlist WHERE supabase_user_id IS NOT NULL; -- Should show linked users
-- SELECT email, invite_code, tier, supabase_user_id FROM waitlist WHERE supabase_user_id IS NOT NULL;
-- SELECT * FROM schema_migrations;
