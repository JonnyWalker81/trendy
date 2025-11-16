export const onRequest: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  // Only handle POST requests to forms
  if (request.method !== "POST") {
    return env.ASSETS.fetch(request);
  }

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

      // 5. INSERT INTO DATABASE
      await insertSignup(env.WAITLIST_DB, {
        email,
        name: userName || null,
        referral_source: referralSource || null,
        ip_address: ipAddress,
        user_agent: userAgent,
      });

      // 6. UPDATE RATE LIMIT TRACKING
      await updateRateLimit(env.WAITLIST_DB, ipAddress);

      // 7. SEND EMAILS
      await sendEmails(env, email, userName);

      // 8. RETURN SUCCESS
      return jsonResponse({
        success: true,
        message: "Thanks for joining the waitlist! Check your email for confirmation."
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
 * Insert new signup into database
 */
async function insertSignup(
  db: D1Database,
  data: Partial<WaitlistSignup>
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO waitlist (email, name, referral_source, ip_address, user_agent)
       VALUES (?, ?, ?, ?, ?)`
    )
    .bind(
      data.email,
      data.name || null,
      data.referral_source || null,
      data.ip_address || null,
      data.user_agent || null
    )
    .run();
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
 * Send confirmation email to user and notification to admin
 */
async function sendEmails(
  env: Env,
  email: string,
  name: string
): Promise<void> {
  // Log environment variables for debugging (first 10 chars of API key)
  console.log("[EMAIL] Environment check:", {
    hasResendKey: !!env.RESEND_API_KEY,
    resendKeyPrefix: env.RESEND_API_KEY?.substring(0, 10) || "undefined",
    fromEmail: env.FROM_EMAIL || "undefined",
    adminEmail: env.ADMIN_EMAIL || "undefined",
  });

  // Skip email sending in development mode
  if (!env.RESEND_API_KEY || env.RESEND_API_KEY.startsWith("re_test") || env.RESEND_API_KEY === "re_test_key_placeholder") {
    console.log("[EMAIL] Development mode: Skipping email sending (no valid Resend API key)");
    return;
  }

  // Validate required environment variables
  if (!env.FROM_EMAIL) {
    console.error("[EMAIL] FROM_EMAIL environment variable is not set");
    return;
  }

  if (!env.ADMIN_EMAIL) {
    console.error("[EMAIL] ADMIN_EMAIL environment variable is not set");
    return;
  }

  // Send confirmation email to user
  try {
    console.log(`[EMAIL] Attempting to send confirmation email to: ${email}`);
    await sendResendEmail(env, {
      from: env.FROM_EMAIL,
      to: email,
      subject: "Welcome to the TrendSight Waitlist!",
      html: getUserConfirmationEmail(name),
    });
    console.log(`[EMAIL] ✓ Confirmation email sent successfully to: ${email}`);
  } catch (error) {
    console.error("[EMAIL] ✗ Failed to send user confirmation email:", error);
    console.error("[EMAIL] Error details:", error instanceof Error ? error.message : String(error));
    // Don't throw - signup is still successful even if email fails
  }

  // Send notification to admin
  try {
    console.log(`[EMAIL] Attempting to send admin notification to: ${env.ADMIN_EMAIL}`);
    await sendResendEmail(env, {
      from: env.FROM_EMAIL,
      to: env.ADMIN_EMAIL,
      subject: "New TrendSight Waitlist Signup",
      html: getAdminNotificationEmail(email, name),
    });
    console.log(`[EMAIL] ✓ Admin notification sent successfully to: ${env.ADMIN_EMAIL}`);
  } catch (error) {
    console.error("[EMAIL] ✗ Failed to send admin notification email:", error);
    console.error("[EMAIL] Error details:", error instanceof Error ? error.message : String(error));
    // Don't throw - signup is still successful
  }
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
