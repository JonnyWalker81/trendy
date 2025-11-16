export const onRequest: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  console.log('[MIDDLEWARE] Request received:', request.method, new URL(request.url).pathname);

  // Only handle POST requests to forms
  if (request.method !== "POST") {
    console.log('[MIDDLEWARE] Not a POST request, passing to next handler');
    return context.next();
  }

  console.log('[MIDDLEWARE] Processing POST request');

  try {
    // Initialize database tables if they don't exist (for local development)
    await initializeDatabase(env.WAITLIST_DB);

    // Parse form data
    const formData = await request.formData();

    // Check if this is a waitlist form submission
    const formName = formData.get("_static_form_name");
    if (formName !== "waitlist") {
      return env.ASSETS.fetch(request);
    }

    // Extract form data
    const email = formData.get("email") as string;
    const userName = formData.get("name") as string;
    const referralSource = formData.get("referral_source") as string;
    const referralCode = formData.get("referral_code") as string; // NEW: referral code from friend
    const turnstileToken = formData.get("cf-turnstile-response") as string;

    // Get request metadata
    const ipAddress = request.headers.get("CF-Connecting-IP") || "unknown";
    const userAgent = request.headers.get("User-Agent") || "unknown";

      // 1. VALIDATE TURNSTILE TOKEN
      const turnstileValid = await verifyTurnstile(turnstileToken, env.TURNSTILE_SECRET_KEY);
      if (!turnstileValid.valid) {
        return jsonResponse({ error: turnstileValid.error }, 400);
      }

      // 2. VALIDATE EMAIL
      const emailValid = validateEmail(email);
      if (!emailValid.valid) {
        return jsonResponse({ error: emailValid.error }, 400);
      }

      // 3. CHECK RATE LIMITING
      const rateLimitOk = await checkRateLimit(env.WAITLIST_DB, ipAddress);
      if (!rateLimitOk.valid) {
        return jsonResponse({ error: rateLimitOk.error }, 429);
      }

      // 4. CHECK FOR DUPLICATE EMAIL
      const duplicate = await checkDuplicate(env.WAITLIST_DB, email);
      if (duplicate) {
        return jsonResponse({ error: "This email is already on the waitlist." }, 409);
      }

      // 5. VALIDATE REFERRAL CODE (if provided)
      if (referralCode) {
        const validReferral = await validateReferralCode(env.WAITLIST_DB, referralCode);
        if (!validReferral) {
          // Don't fail signup, just log invalid referral code
          console.log('[SIGNUP] Invalid referral code provided:', referralCode);
        }
      }

      // 6. INSERT INTO DATABASE (with verification tokens)
      const newContact = await insertSignup(env.WAITLIST_DB, {
        email,
        name: userName || null,
        referral_source: referralSource || null,
        referral_code: referralCode || null,
        ip_address: ipAddress,
        user_agent: userAgent,
      });

      // 7. UPDATE RATE LIMIT TRACKING
      await updateRateLimit(env.WAITLIST_DB, ipAddress);

      // 8. SEND VERIFICATION EMAIL (double opt-in)
      await sendVerificationEmail(env, newContact);

      // 9. RETURN SUCCESS
      return jsonResponse({
        success: true,
        message: "Thanks for joining! Please check your email to verify your address."
      }, 200);

  } catch (error) {
    console.error("Waitlist signup error:", error);
    return jsonResponse({
      error: "An error occurred. Please try again later."
    }, 500);
  }
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Initialize database tables if they don't exist
 * This is especially important for local development with Miniflare
 */
async function initializeDatabase(db: D1Database): Promise<void> {
  try {
    // Check if tables exist by trying to query them
    const checkWaitlist = await db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='waitlist'")
      .first();

    if (!checkWaitlist) {
      console.log("Initializing database tables...");

      // Create waitlist table
      await db
        .prepare(
          `CREATE TABLE IF NOT EXISTS waitlist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            name TEXT,
            referral_source TEXT,
            ip_address TEXT,
            user_agent TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )`
        )
        .run();

      // Create rate_limits table
      await db
        .prepare(
          `CREATE TABLE IF NOT EXISTS rate_limits (
            ip_address TEXT PRIMARY KEY,
            attempt_count INTEGER DEFAULT 1,
            first_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_attempt_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )`
        )
        .run();

      // Create indexes
      await db
        .prepare("CREATE INDEX IF NOT EXISTS idx_waitlist_email ON waitlist(email)")
        .run();

      await db
        .prepare("CREATE INDEX IF NOT EXISTS idx_waitlist_created_at ON waitlist(created_at)")
        .run();

      await db
        .prepare("CREATE INDEX IF NOT EXISTS idx_rate_limits_ip ON rate_limits(ip_address)")
        .run();

      console.log("Database tables initialized successfully");
    }
  } catch (error) {
    console.error("Database initialization error:", error);
    // Don't throw - let the application continue and fail on actual operations if needed
  }
}

/**
 * Verify Cloudflare Turnstile token
 */
async function verifyTurnstile(
  token: string,
  secretKey: string
): Promise<ValidationResult> {
  if (!token) {
    return { valid: false, error: "Security verification failed. Please refresh and try again." };
  }

  // In development with test key, skip verification
  // Test keys start with "1x" and development mode uses placeholder keys
  if (secretKey.startsWith("1x") || secretKey.includes("placeholder") || secretKey.length < 20) {
    console.log("Development mode: Skipping Turnstile verification (test key detected)");
    return { valid: true };
  }

  try {
    const response = await fetch(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secret: secretKey,
          response: token,
        }),
      }
    );

    const result = (await response.json()) as TurnstileVerificationResponse;

    if (!result.success) {
      console.error("Turnstile verification failed:", result["error-codes"]);
      return { valid: false, error: "Security verification failed. Please try again." };
    }

    return { valid: true };
  } catch (error) {
    console.error("Turnstile verification error:", error);
    return { valid: false, error: "Security verification error. Please try again." };
  }
}

/**
 * Validate email format and check against disposable domains
 */
function validateEmail(email: string): ValidationResult {
  if (!email) {
    return { valid: false, error: "Email address is required." };
  }

  // Email format validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    return { valid: false, error: "Please enter a valid email address." };
  }

  // Check for disposable email domains
  const disposableDomains = [
    "tempmail.com",
    "throwaway.email",
    "guerrillamail.com",
    "10minutemail.com",
    "mailinator.com",
    "trashmail.com",
    "yopmail.com",
  ];

  const domain = email.split("@")[1]?.toLowerCase();
  if (disposableDomains.includes(domain)) {
    return { valid: false, error: "Disposable email addresses are not allowed." };
  }

  return { valid: true };
}

/**
 * Check rate limiting - max 5 submissions per IP per hour
 */
async function checkRateLimit(
  db: D1Database,
  ipAddress: string
): Promise<ValidationResult> {
  try {
    // Clean up old entries first (older than 1 hour)
    await db
      .prepare("DELETE FROM rate_limits WHERE last_attempt_at < datetime('now', '-1 hour')")
      .run();

    // Get current rate limit entry
    const entry = await db
      .prepare("SELECT * FROM rate_limits WHERE ip_address = ?")
      .bind(ipAddress)
      .first<RateLimitEntry>();

    if (!entry) {
      return { valid: true };
    }

    // Check if within the last hour and over limit
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    if (entry.first_attempt_at > oneHourAgo && entry.attempt_count >= 5) {
      return {
        valid: false,
        error: "Too many submission attempts. Please try again later."
      };
    }

    return { valid: true };
  } catch (error) {
    console.error("Rate limit check error:", error);
    // Allow on error to not block legitimate users
    return { valid: true };
  }
}

/**
 * Check if email already exists in waitlist
 */
async function checkDuplicate(
  db: D1Database,
  email: string
): Promise<boolean> {
  try {
    const existing = await db
      .prepare("SELECT id FROM waitlist WHERE email = ?")
      .bind(email)
      .first();

    return existing !== null;
  } catch (error) {
    console.error("Duplicate check error:", error);
    return false;
  }
}

/**
 * Validate referral code exists
 */
async function validateReferralCode(
  db: D1Database,
  referralCode: string
): Promise<boolean> {
  try {
    const referrer = await db
      .prepare("SELECT id FROM waitlist WHERE invite_code = ?")
      .bind(referralCode)
      .first();
    return referrer !== null;
  } catch (error) {
    console.error("Referral code validation error:", error);
    return false;
  }
}

/**
 * Insert new signup into database with verification tokens
 */
async function insertSignup(
  db: D1Database,
  data: Partial<WaitlistSignup>
): Promise<WaitlistSignup> {
  // Generate verification and unsubscribe tokens
  const verificationToken = generateToken();
  const unsubscribeToken = generateToken();
  const now = new Date().toISOString();

  // Insert the record
  const result = await db
    .prepare(
      `INSERT INTO waitlist (
        email, name, referral_source, referral_code, ip_address, user_agent,
        email_status, verification_token, verification_sent_at, unsubscribe_token
      )
      VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)`
    )
    .bind(
      data.email,
      data.name || null,
      data.referral_source || null,
      data.referral_code || null,
      data.ip_address || null,
      data.user_agent || null,
      verificationToken,
      now,
      unsubscribeToken
    )
    .run();

  // Fetch and return the newly created contact (with auto-generated invite_code from trigger)
  const contact = await db
    .prepare("SELECT * FROM waitlist WHERE id = ?")
    .bind(result.meta.last_row_id)
    .first<WaitlistSignup>();

  return contact!;
}

/**
 * Generate secure random token
 */
function generateToken(): string {
  // Generate 32 random bytes as hex string
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * Update rate limit tracking for IP address
 */
async function updateRateLimit(
  db: D1Database,
  ipAddress: string
): Promise<void> {
  try {
    // Try to update existing entry
    const result = await db
      .prepare(
        `UPDATE rate_limits
         SET attempt_count = attempt_count + 1,
             last_attempt_at = CURRENT_TIMESTAMP
         WHERE ip_address = ?`
      )
      .bind(ipAddress)
      .run();

    // If no rows updated, insert new entry
    if (result.meta.changes === 0) {
      await db
        .prepare(
          `INSERT INTO rate_limits (ip_address, attempt_count)
           VALUES (?, 1)`
        )
        .bind(ipAddress)
        .run();
    }
  } catch (error) {
    console.error("Rate limit update error:", error);
    // Don't throw - this is not critical
  }
}

/**
 * Send verification email (double opt-in)
 */
async function sendVerificationEmail(
  env: Env,
  contact: WaitlistSignup
): Promise<void> {
  console.log("[VERIFY_EMAIL] Sending verification email to:", contact.email);

  // Skip email sending in development mode
  if (!env.RESEND_API_KEY || env.RESEND_API_KEY.startsWith("re_test") || env.RESEND_API_KEY === "re_test_key_placeholder") {
    console.log("[VERIFY_EMAIL] Development mode: Skipping email (no valid Resend API key)");
    return;
  }

  // Validate required environment variables
  if (!env.FROM_EMAIL) {
    console.error("[VERIFY_EMAIL] FROM_EMAIL environment variable is not set");
    return;
  }

  if (!env.VERIFICATION_BASE_URL) {
    console.error("[VERIFY_EMAIL] VERIFICATION_BASE_URL environment variable is not set");
    return;
  }

  const verificationUrl = `${env.VERIFICATION_BASE_URL}/verify?token=${contact.verification_token}`;

  try {
    await sendResendEmail(env, {
      from: env.FROM_EMAIL,
      to: contact.email,
      subject: "Verify your email for TrendSight waitlist",
      html: getVerificationEmailHTML(contact, verificationUrl),
    });
    console.log(`[VERIFY_EMAIL] ✓ Verification email sent to: ${contact.email}`);
  } catch (error) {
    console.error("[VERIFY_EMAIL] ✗ Failed to send verification email:", error);
    console.error("[VERIFY_EMAIL] Error details:", error instanceof Error ? error.message : String(error));
    // Don't throw - signup is still recorded, user can request new verification
  }
}

/**
 * Generate verification email HTML
 */
function getVerificationEmailHTML(contact: WaitlistSignup, verificationUrl: string): string {
  const firstName = contact.name?.split(' ')[0] || 'there';

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; line-height: 1.6; color: #333333; margin: 0; padding: 0; background-color: #f5f5f5;">
      <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff;">
        <div style="background: linear-gradient(135deg, #1e40af 0%, #3730a3 100%); color: #ffffff; padding: 40px 20px; text-align: center;">
          <h1 style="margin: 0; font-size: 28px; color: #ffffff;">✉️ Verify Your Email</h1>
        </div>

        <div style="padding: 40px 30px;">
          <p style="margin: 0 0 20px 0; font-size: 16px; color: #333333;">Hi ${firstName},</p>

          <p style="margin: 0 0 20px 0; font-size: 16px; color: #333333;">Thanks for joining the TrendSight waitlist! Please verify your email address to confirm your spot.</p>

          <div style="text-align: center; margin: 35px 0;">
            <a href="${verificationUrl}" style="display: inline-block; background: #1e40af; color: #ffffff !important; padding: 16px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;">Verify Email Address</a>
          </div>

          <p style="margin: 20px 0; font-size: 14px; color: #6b7280; text-align: center;">Or copy and paste this link into your browser:</p>
          <p style="margin: 0 0 30px 0; font-size: 13px; color: #1e40af; word-break: break-all; text-align: center; font-family: 'Courier New', monospace;">${verificationUrl}</p>

          <div style="background: #fffbeb; border-left: 4px solid #f59e0b; padding: 15px 20px; border-radius: 6px; margin: 30px 0;">
            <p style="margin: 0; font-size: 14px; color: #92400e;"><strong>⏰ This link expires in 24 hours</strong></p>
          </div>

          <p style="margin: 30px 0 0 0; font-size: 16px; color: #333333;">Once verified, you'll get your waitlist position and unique invite code to share with friends!</p>

          <p style="margin: 20px 0 0 0; font-size: 14px; color: #6b7280;">If you didn't sign up for TrendSight, you can safely ignore this email.</p>
        </div>

        <div style="background: #f9fafb; padding: 30px; text-align: center; border-top: 1px solid #e5e7eb;">
          <p style="margin: 0; color: #6b7280; font-size: 14px;">TrendSight - Track Anything, Discover Your Patterns</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

/**
 * Send email via Resend REST API (avoiding SDK to prevent React dependencies)
 */
async function sendResendEmail(
  env: Env,
  emailData: { from: string; to: string; subject: string; html: string }
): Promise<void> {
  console.log("[RESEND] Sending email request:", {
    from: emailData.from,
    to: emailData.to,
    subject: emailData.subject,
  });

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${env.RESEND_API_KEY}`,
    },
    body: JSON.stringify(emailData),
  });

  console.log("[RESEND] Response status:", response.status, response.statusText);

  if (!response.ok) {
    const errorText = await response.text();
    console.error("[RESEND] API error response:", errorText);

    let errorDetails;
    try {
      errorDetails = JSON.parse(errorText);
    } catch {
      errorDetails = errorText;
    }

    throw new Error(`Resend API error (${response.status}): ${JSON.stringify(errorDetails)}`);
  }

  const result = await response.json();
  console.log("[RESEND] Success response:", result);
}

/**
 * Generate user confirmation email HTML
 */
function getUserConfirmationEmail(name: string): string {
  const greeting = name ? `Hi ${name}` : "Hi there";

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; line-height: 1.6; color: #333333; margin: 0; padding: 0;">
      <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #1e40af 0%, #3730a3 100%); color: #ffffff; padding: 30px 20px; text-align: center; border-radius: 8px 8px 0 0;">
          <h1 style="margin: 0; font-size: 28px; color: #ffffff;">🎉 You're on the list!</h1>
        </div>
        <div style="background: #ffffff; padding: 30px 20px; border: 1px solid #e5e7eb; border-top: none; border-radius: 0 0 8px 8px;">
          <p style="margin: 16px 0; color: #333333;">${greeting},</p>
          <p style="margin: 16px 0; color: #333333;">Thanks for joining the TrendSight waitlist! We're excited to have you as part of our early community.</p>
          <p style="margin: 16px 0; color: #333333;"><strong>What's next?</strong></p>
          <ul style="margin: 16px 0; color: #333333;">
            <li style="margin: 8px 0;">We'll keep you updated on our launch progress</li>
            <li style="margin: 8px 0;">You'll get early access when we're ready</li>
            <li style="margin: 8px 0;">We'll share exclusive insights and tips about tracking your life patterns</li>
          </ul>
          <p style="margin: 16px 0; color: #333333;">In the meantime, follow our journey and get a sneak peek at what we're building:</p>
          <p style="text-align: center; margin: 20px 0;">
            <a href="https://trendsight.com" style="display: inline-block; background: #1e40af; color: #ffffff !important; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 500;">Visit TrendSight</a>
          </p>
          <p style="margin: 16px 0; color: #333333;">Have questions? Just reply to this email—we'd love to hear from you!</p>
          <p style="margin: 16px 0; color: #333333;">Best regards,<br><strong>The TrendSight Team</strong></p>
        </div>
        <div style="text-align: center; margin-top: 20px; padding: 20px; color: #6b7280; font-size: 14px;">
          <p style="margin: 8px 0; color: #6b7280;">TrendSight - Track Anything, Discover Your Patterns</p>
          <p style="font-size: 12px; color: #9ca3af; margin: 8px 0;">You received this email because you signed up for the TrendSight waitlist.</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

/**
 * Generate admin notification email HTML
 */
function getAdminNotificationEmail(email: string, name: string): string {
  const timestamp = new Date().toISOString();

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; line-height: 1.6; color: #333333; margin: 0; padding: 0;">
      <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #333333; margin-bottom: 20px;">🎉 New Waitlist Signup</h2>
        <div style="background: #eff6ff; padding: 20px; border-radius: 8px; border-left: 4px solid #1e40af; margin: 20px 0;">
          <p style="margin: 8px 0; color: #333333;"><strong>Email:</strong> ${email}</p>
          <p style="margin: 8px 0; color: #333333;"><strong>Name:</strong> ${name || "(not provided)"}</p>
          <p style="margin: 8px 0; color: #333333;"><strong>Timestamp:</strong> ${timestamp}</p>
        </div>
        <p style="margin: 16px 0; color: #333333;">Check your Cloudflare D1 database for full details.</p>
      </div>
    </body>
    </html>
  `;
}

/**
 * Create JSON response helper
 */
function jsonResponse(data: object, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
