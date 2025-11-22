-- Add Admin Sessions Table
-- For managing admin console authentication sessions
-- Run with: npx wrangler d1 execute trendsight-waitlist --local --file=./add-admin-sessions.sql

CREATE TABLE IF NOT EXISTS admin_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT UNIQUE NOT NULL,
  admin_email TEXT NOT NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_token ON admin_sessions(token);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires ON admin_sessions(expires_at);

-- Cleanup old sessions (run periodically)
-- DELETE FROM admin_sessions WHERE expires_at < datetime('now');
