// Type definitions for TrendSight Landing Page Cloudflare Pages Functions

// Environment bindings
interface Env {
  // D1 Database binding
  WAITLIST_DB: D1Database;

  // Secrets (set in Cloudflare dashboard or .dev.vars)
  RESEND_API_KEY: string;
  TURNSTILE_SECRET_KEY: string;
  TURNSTILE_SITE_KEY: string;
  RESEND_WEBHOOK_SECRET: string;
  RESEND_AUDIENCE_ID: string;
  ADMIN_EMAIL: string;
  ADMIN_PASSWORD: string; // For admin console login
  FROM_EMAIL: string;
  VERIFICATION_BASE_URL: string;
  ADMIN_SECRET: string; // For admin API endpoints like /admin/send-launch-emails

  // Assets binding (for fetching static files)
  ASSETS: Fetcher;
}

// Email status enum
type EmailStatus = 'pending' | 'verified' | 'bounced' | 'invalid' | 'unsubscribed';

// Waitlist tier enum
type WaitlistTier = 'standard' | 'early_access' | 'vip' | 'beta_tester';

// Resend sync status enum
type ResendSyncStatus = 'pending' | 'synced' | 'failed';

// Waitlist signup data (complete schema)
interface WaitlistSignup {
  id?: number;

  // Basic contact info
  email: string;
  name?: string;

  // Email verification & status
  email_status: EmailStatus;
  verification_token?: string;
  verification_sent_at?: string;
  verified_at?: string;
  verification_attempts?: number;

  // Consent & compliance
  consent_given_at?: string;
  consent_ip_address?: string;
  consent_user_agent?: string;
  privacy_policy_version?: string;
  marketing_consent?: boolean;

  // Unsubscribe handling
  unsubscribed_at?: string;
  unsubscribe_reason?: string;
  unsubscribe_token?: string;

  // Waitlist position & personalization
  waitlist_position?: number; // DEPRECATED: Use score-based ranking
  score?: number; // Score-based ranking (higher = better position)
  invite_code?: string;
  referral_code?: string;
  referrals_count?: number;
  tier?: WaitlistTier;
  is_vip?: boolean;
  tags?: string; // JSON array
  custom_metadata?: string; // JSON object

  // Attribution tracking
  referral_source?: string;
  ip_address?: string;
  user_agent?: string;

  // Resend integration
  resend_contact_id?: string;
  resend_audience_id?: string;
  last_synced_to_resend_at?: string;
  resend_sync_status?: ResendSyncStatus;

  // Engagement tracking
  engagement_score?: number;
  last_email_opened_at?: string;
  last_email_clicked_at?: string;
  total_emails_sent?: number;
  total_emails_opened?: number;
  total_emails_clicked?: number;

  // Timestamps
  created_at?: string;
  updated_at?: string;
}

// Email campaign tracking
type CampaignType = 'verification' | 'welcome' | 'update' | 'launch' | 'reminder' | 'early_access' | 're_engagement';

interface EmailCampaign {
  id?: number;
  campaign_name: string;
  campaign_type: CampaignType;
  resend_broadcast_id?: string;
  subject_line?: string;
  variant?: string;
  sent_at?: string;
  recipient_count?: number;
  tier_filter?: string; // JSON array
  segment_filter?: string; // JSON object
  created_at?: string;
}

// Email event tracking (from webhooks)
type EmailEventType = 'sent' | 'delivered' | 'opened' | 'clicked' | 'bounced' | 'complained' | 'unsubscribed' | 'delivery_delayed';

interface EmailEvent {
  id?: number;
  waitlist_id: number;
  campaign_id?: number;
  event_type: EmailEventType;
  resend_email_id?: string;
  link_url?: string;
  user_agent?: string;
  ip_address?: string;
  event_timestamp: string;
  raw_webhook_data?: string; // JSON
  created_at?: string;
}

// GDPR data requests
type DataRequestType = 'export' | 'delete' | 'update';
type DataRequestStatus = 'pending' | 'completed' | 'rejected';

interface DataRequest {
  id?: number;
  email: string;
  request_type: DataRequestType;
  status: DataRequestStatus;
  requested_at?: string;
  completed_at?: string;
  notes?: string;
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

// Resend API types
interface ResendContact {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  created_at: string;
  unsubscribed: boolean;
}

interface ResendEmailRequest {
  from: string;
  to: string | string[];
  subject: string;
  html?: string;
  text?: string;
  reply_to?: string;
  tags?: Array<{ name: string; value: string }>;
}

interface ResendEmailResponse {
  id: string;
}

interface ResendWebhookEvent {
  type: string;
  created_at: string;
  data: {
    email_id?: string;
    from?: string;
    to?: string | string[];
    subject?: string;
    created_at?: string;
    html?: string;
    text?: string;
    link?: string;
    ip?: string;
    user_agent?: string;
  };
}

// Campaign segment filter
interface CampaignSegment {
  tiers?: WaitlistTier[];
  min_engagement_score?: number;
  verified_only?: boolean;
  marketing_consent_only?: boolean;
  exclude_unsubscribed?: boolean;
}
