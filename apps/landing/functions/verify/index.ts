/**
 * Email Verification Endpoint
 * Handles double opt-in email verification for waitlist signups
 *
 * Route: GET /verify?token=<verification_token>
 */

export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { request, env } = context;
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  console.log('[VERIFY] Verification request received', { token: token?.substring(0, 10) + '...' });

  // Validate token presence
  if (!token) {
    return new Response(getErrorPage('Invalid verification link'), {
      status: 400,
      headers: { 'Content-Type': 'text/html' },
    });
  }

  try {
    // 1. Look up user by verification token
    const contact = await env.WAITLIST_DB
      .prepare('SELECT * FROM waitlist WHERE verification_token = ? AND email_status = ?')
      .bind(token, 'pending')
      .first<WaitlistSignup>();

    if (!contact) {
      console.log('[VERIFY] Token not found or already verified');
      return new Response(getErrorPage('This verification link is invalid or has already been used.'), {
        status: 404,
        headers: { 'Content-Type': 'text/html' },
      });
    }

    // 2. Check token expiration (24 hours)
    if (contact.verification_sent_at) {
      const sentAt = new Date(contact.verification_sent_at).getTime();
      const now = Date.now();
      const hoursSinceSent = (now - sentAt) / 1000 / 60 / 60;

      if (hoursSinceSent > 24) {
        console.log('[VERIFY] Token expired', { hoursSinceSent });
        return new Response(getExpiredPage(contact.email), {
          status: 410,
          headers: { 'Content-Type': 'text/html' },
        });
      }
    }

    // 3. Mark email as verified
    const now = new Date().toISOString();
    const ipAddress = request.headers.get('CF-Connecting-IP') || 'unknown';
    const userAgent = request.headers.get('User-Agent') || 'unknown';

    await env.WAITLIST_DB
      .prepare(`
        UPDATE waitlist
        SET email_status = 'verified',
            verified_at = ?,
            consent_given_at = ?,
            consent_ip_address = ?,
            consent_user_agent = ?
        WHERE id = ?
      `)
      .bind(now, now, ipAddress, userAgent, contact.id)
      .run();

    console.log('[VERIFY] Email verified successfully', { email: contact.email });

    // 4. Get updated contact with computed position (score-based ranking)
    const updatedContact = await env.WAITLIST_DB
      .prepare(`
        SELECT
          *,
          (
            SELECT COUNT(*) + 1
            FROM waitlist w2
            WHERE w2.email_status = 'verified'
            AND (
              w2.score > w1.score
              OR (w2.score = w1.score AND w2.created_at < w1.created_at)
            )
          ) as position
        FROM waitlist w1
        WHERE w1.id = ?
      `)
      .bind(contact.id)
      .first<WaitlistSignup & { position: number }>();

    // 5. Sync to Resend Audiences (if configured)
    if (env.RESEND_API_KEY && env.RESEND_AUDIENCE_ID &&
        !env.RESEND_API_KEY.startsWith('re_test') &&
        env.RESEND_API_KEY !== 're_test_key_placeholder') {

      try {
        await syncToResendAudience(env, updatedContact!);
        console.log('[VERIFY] Synced to Resend Audiences');
      } catch (error) {
        console.error('[VERIFY] Failed to sync to Resend:', error);
        // Don't fail verification if Resend sync fails
      }
    }

    // 6. Send welcome email with computed waitlist position
    try {
      await sendWelcomeEmail(env, updatedContact!);
    } catch (error) {
      console.error('[VERIFY] Failed to send welcome email:', error);
      // Don't fail verification if email sending fails
    }

    // 7. Return success page with computed position
    return new Response(getSuccessPage(updatedContact!), {
      status: 200,
      headers: { 'Content-Type': 'text/html' },
    });

  } catch (error) {
    console.error('[VERIFY] Verification error:', error);
    return new Response(getErrorPage('An error occurred during verification. Please try again later.'), {
      status: 500,
      headers: { 'Content-Type': 'text/html' },
    });
  }
};

/**
 * Sync verified contact to Resend Audience
 */
async function syncToResendAudience(env: Env, contact: WaitlistSignup): Promise<void> {
  const firstName = contact.name?.split(' ')[0] || '';
  const lastName = contact.name?.split(' ').slice(1).join(' ') || '';

  const response = await fetch(`https://api.resend.com/audiences/${env.RESEND_AUDIENCE_ID}/contacts`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      email: contact.email,
      first_name: firstName || undefined,
      last_name: lastName || undefined,
      unsubscribed: false,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Resend Audiences API error: ${error}`);
  }

  const result = await response.json() as ResendContact;

  // Update local database with Resend contact ID
  await env.WAITLIST_DB
    .prepare(`
      UPDATE waitlist
      SET resend_contact_id = ?,
          resend_audience_id = ?,
          resend_sync_status = 'synced',
          last_synced_to_resend_at = ?
      WHERE id = ?
    `)
    .bind(result.id, env.RESEND_AUDIENCE_ID, new Date().toISOString(), contact.id)
    .run();
}

/**
 * Send welcome email after verification
 */
async function sendWelcomeEmail(env: Env, contact: WaitlistSignup & { position: number }): Promise<void> {
  // Skip in dev mode
  if (!env.RESEND_API_KEY || env.RESEND_API_KEY.startsWith('re_test') || env.RESEND_API_KEY === 're_test_key_placeholder') {
    console.log('[VERIFY] Skipping welcome email (dev mode)');
    return;
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: env.FROM_EMAIL,
      to: contact.email,
      subject: `You're #${contact.position} on the TrendSight waitlist!`,
      html: getWelcomeEmailHTML(env, contact),
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    console.error('[VERIFY] Failed to send welcome email:', error);
    // Don't throw - verification still succeeded
  } else {
    console.log('[VERIFY] Welcome email sent to:', contact.email);
  }
}

/**
 * Generate welcome email HTML
 */
function getWelcomeEmailHTML(env: Env, contact: WaitlistSignup & { position: number }): string {
  const firstName = contact.name?.split(' ')[0] || 'there';
  const position = contact.position || 0;
  const inviteCode = contact.invite_code || '';

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
          <h1 style="margin: 0; font-size: 32px; color: #ffffff;">🎉 You're on the list!</h1>
          <p style="margin: 10px 0 0 0; font-size: 18px; color: #e0e7ff;">Welcome to TrendSight</p>
        </div>

        <div style="padding: 40px 30px;">
          <p style="margin: 0 0 20px 0; font-size: 16px; color: #333333;">Hi ${firstName},</p>

          <p style="margin: 0 0 20px 0; font-size: 16px; color: #333333;">Your email has been verified! You're officially on the TrendSight waitlist.</p>

          <div style="background: linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%); padding: 30px; border-radius: 12px; margin: 30px 0; text-align: center; border-left: 4px solid #1e40af;">
            <div style="font-size: 48px; font-weight: bold; color: #1e40af; margin-bottom: 10px;">#${position}</div>
            <div style="font-size: 18px; color: #1e3a8a; font-weight: 500;">Your position on the waitlist</div>
          </div>

          <h2 style="color: #1e40af; font-size: 20px; margin: 30px 0 15px 0;">📈 Move up in line!</h2>
          <p style="margin: 0 0 15px 0; font-size: 16px; color: #333333;">Share your unique invite code with friends. For each person who joins using your code, you'll move up in line!</p>

          <div style="background: #f9fafb; border: 2px dashed #d1d5db; border-radius: 8px; padding: 20px; text-align: center; margin: 20px 0;">
            <div style="font-size: 14px; color: #6b7280; margin-bottom: 8px;">Your invite code:</div>
            <div style="font-size: 28px; font-weight: bold; color: #1e40af; letter-spacing: 2px; font-family: 'Courier New', monospace;">${inviteCode}</div>
            <div style="margin-top: 15px;">
              <a href="https://trendsight.app?ref=${inviteCode}" style="display: inline-block; background: #1e40af; color: #ffffff !important; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 500; font-size: 14px;">Share Your Code</a>
            </div>
          </div>

          <h2 style="color: #1e40af; font-size: 20px; margin: 30px 0 15px 0;">🚀 What's next?</h2>
          <ul style="margin: 0; padding-left: 20px; color: #333333; font-size: 16px;">
            <li style="margin-bottom: 10px;">We'll keep you updated on our launch progress</li>
            <li style="margin-bottom: 10px;">You'll get early access when we're ready</li>
            <li style="margin-bottom: 10px;">We'll share exclusive insights about tracking your life patterns</li>
          </ul>

          <p style="margin: 30px 0 0 0; font-size: 16px; color: #333333;">Have questions? Just reply to this email—we'd love to hear from you!</p>

          <p style="margin: 20px 0 0 0; font-size: 16px; color: #333333;">Best regards,<br><strong style="color: #1e40af;">The TrendSight Team</strong></p>
        </div>

        <div style="background: #f9fafb; padding: 30px; text-align: center; border-top: 1px solid #e5e7eb;">
          <p style="margin: 0 0 10px 0; color: #6b7280; font-size: 14px;">TrendSight - Track Anything, Discover Your Patterns</p>
          <p style="margin: 0; color: #9ca3af; font-size: 12px;">
            You received this email because you verified your email for the TrendSight waitlist.<br>
            <a href="${env.VERIFICATION_BASE_URL || 'https://trendsight.app'}/unsubscribe?token=${contact.unsubscribe_token}" style="color: #6b7280; text-decoration: underline;">Unsubscribe</a>
          </p>
        </div>
      </div>
    </body>
    </html>
  `;
}

/**
 * Success page HTML
 */
function getSuccessPage(contact: WaitlistSignup & { position: number }): string {
  const firstName = contact.name?.split(' ')[0] || 'there';
  const position = contact.position || 0;
  const inviteCode = contact.invite_code || '';

  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Email Verified - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #1e40af 0%, #3730a3 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 600px; width: 100%; padding: 50px 40px; text-align: center; }
        .checkmark { width: 80px; height: 80px; border-radius: 50%; background: #10b981; display: flex; align-items: center; justify-content: center; margin: 0 auto 30px; }
        .checkmark svg { width: 50px; height: 50px; color: white; }
        h1 { font-size: 32px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 18px; color: #6b7280; margin-bottom: 30px; line-height: 1.6; }
        .position { background: linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%); padding: 30px; border-radius: 12px; margin: 30px 0; border-left: 4px solid #1e40af; }
        .position-number { font-size: 56px; font-weight: bold; color: #1e40af; margin-bottom: 10px; }
        .position-label { font-size: 16px; color: #1e3a8a; }
        .invite-code { background: #f9fafb; border: 2px dashed #d1d5db; border-radius: 8px; padding: 20px; margin: 30px 0; }
        .invite-code-label { font-size: 14px; color: #6b7280; margin-bottom: 10px; }
        .invite-code-value { font-size: 32px; font-weight: bold; color: #1e40af; letter-spacing: 3px; font-family: 'Courier New', monospace; margin-bottom: 15px; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 14px 32px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px; transition: background 0.3s; margin-top: 10px; }
        .btn:hover { background: #1e3a8a; }
        .info { background: #f0fdf4; border-left: 4px solid #10b981; padding: 20px; border-radius: 8px; margin-top: 30px; text-align: left; }
        .info h3 { color: #047857; font-size: 18px; margin-bottom: 10px; }
        .info ul { color: #374151; font-size: 15px; margin-left: 20px; }
        .info li { margin-bottom: 8px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="checkmark">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="width" stroke-width="3" d="M5 13l4 4L19 7"></path></svg>
        </div>

        <h1>Email Verified!</h1>
        <p>Hi ${firstName}, you're officially on the TrendSight waitlist.</p>

        <div class="position">
          <div class="position-number">#${position}</div>
          <div class="position-label">Your position on the waitlist</div>
        </div>

        <div class="invite-code">
          <div class="invite-code-label">Your unique invite code:</div>
          <div class="invite-code-value">${inviteCode}</div>
          <a href="https://trendsight.app?ref=${inviteCode}" class="btn">Share Your Code</a>
        </div>

        <div class="info">
          <h3>📧 Check your email</h3>
          <ul>
            <li>We've sent you a welcome email with more details</li>
            <li>Share your invite code to move up in line</li>
            <li>We'll notify you when we launch</li>
          </ul>
        </div>
      </div>
    </body>
    </html>
  `;
}

/**
 * Error page HTML
 */
function getErrorPage(message: string): string {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Verification Error - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 500px; width: 100%; padding: 50px 40px; text-align: center; }
        .icon { width: 80px; height: 80px; border-radius: 50%; background: #fee2e2; display: flex; align-items: center; justify-content: center; margin: 0 auto 30px; }
        .icon svg { width: 50px; height: 50px; color: #dc2626; }
        h1 { font-size: 28px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 16px; color: #6b7280; margin-bottom: 30px; line-height: 1.6; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
        </div>
        <h1>Verification Failed</h1>
        <p>${message}</p>
        <a href="/" class="btn">Back to Home</a>
      </div>
    </body>
    </html>
  `;
}

/**
 * Expired token page HTML
 */
function getExpiredPage(email: string): string {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Link Expired - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 500px; width: 100%; padding: 50px 40px; text-align: center; }
        .icon { width: 80px; height: 80px; border-radius: 50%; background: #fef3c7; display: flex; align-items: center; justify-content: center; margin: 0 auto 30px; }
        .icon svg { width: 50px; height: 50px; color: #f59e0b; }
        h1 { font-size: 28px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 16px; color: #6b7280; margin-bottom: 30px; line-height: 1.6; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; margin-top: 10px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
        </div>
        <h1>Link Expired</h1>
        <p>This verification link has expired (24 hours). Please sign up again to receive a new verification email.</p>
        <p style="font-size: 14px; color: #9ca3af;">Email: ${email}</p>
        <a href="/" class="btn">Sign Up Again</a>
      </div>
    </body>
    </html>
  `;
}
