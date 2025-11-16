// Type definitions for TrendSight Landing Page Cloudflare Pages Functions

// Environment bindings
interface Env {
  // D1 Database binding
  WAITLIST_DB: D1Database;

  // Secrets (set in Cloudflare dashboard or .dev.vars)
  RESEND_API_KEY: string;
  TURNSTILE_SECRET_KEY: string;
  ADMIN_EMAIL: string;
  FROM_EMAIL: string;
}

// Waitlist signup data
interface WaitlistSignup {
  id?: number;
  email: string;
  name?: string;
  referral_source?: string;
  ip_address?: string;
  user_agent?: string;
  created_at?: string;
  updated_at?: string;
}

// Rate limit tracking
interface RateLimitEntry {
  ip_address: string;
  attempt_count: number;
  first_attempt_at: string;
  last_attempt_at: string;
}

// Cloudflare Turnstile verification response
interface TurnstileVerificationResponse {
  success: boolean;
  "error-codes"?: string[];
  challenge_ts?: string;
  hostname?: string;
  action?: string;
  cdata?: string;
}

// Form validation result
interface ValidationResult {
  valid: boolean;
  error?: string;
}
