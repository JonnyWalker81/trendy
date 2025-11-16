/**
 * Unsubscribe Endpoint
 * Handles one-click unsubscribe from waitlist emails (CAN-SPAM & GDPR compliant)
 *
 * Route: GET /unsubscribe?token=<unsubscribe_token>
 */

export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { request, env } = context;
  const url = new URL(request.url);
  const token = url.searchParams.get('token');

  console.log('[UNSUBSCRIBE] Request received', { token: token?.substring(0, 10) + '...' });

  // Validate token presence
  if (!token) {
    return new Response(getErrorPage('Invalid unsubscribe link'), {
      status: 400,
      headers: { 'Content-Type': 'text/html' },
    });
  }

  try {
    // 1. Look up contact by unsubscribe token
    const contact = await env.WAITLIST_DB
      .prepare('SELECT * FROM waitlist WHERE unsubscribe_token = ?')
      .bind(token)
      .first<WaitlistSignup>();

    if (!contact) {
      console.log('[UNSUBSCRIBE] Token not found');
      return new Response(getErrorPage('This unsubscribe link is invalid.'), {
        status: 404,
        headers: { 'Content-Type': 'text/html' },
      });
    }

    // Check if already unsubscribed
    if (contact.email_status === 'unsubscribed') {
      console.log('[UNSUBSCRIBE] Already unsubscribed:', contact.email);
      return new Response(getAlreadyUnsubscribedPage(contact.email), {
        status: 200,
        headers: { 'Content-Type': 'text/html' },
      });
    }

    // 2. Update database - mark as unsubscribed
    const now = new Date().toISOString();
    await env.WAITLIST_DB
      .prepare(`
        UPDATE waitlist
        SET email_status = 'unsubscribed',
            unsubscribed_at = ?,
            marketing_consent = false
        WHERE id = ?
      `)
      .bind(now, contact.id)
      .run();

    console.log('[UNSUBSCRIBE] Unsubscribed successfully:', contact.email);

    // 3. Update Resend Audiences if synced
    if (contact.resend_contact_id && env.RESEND_API_KEY &&
        !env.RESEND_API_KEY.startsWith('re_test') &&
        env.RESEND_API_KEY !== 're_test_key_placeholder') {

      try {
        await updateResendContact(env, contact.resend_contact_id, true);
        console.log('[UNSUBSCRIBE] Updated Resend Audiences');
      } catch (error) {
        console.error('[UNSUBSCRIBE] Failed to update Resend:', error);
        // Don't fail unsubscribe if Resend update fails
      }
    }

    // 4. Return success page
    return new Response(getSuccessPage(contact.email, token), {
      status: 200,
      headers: { 'Content-Type': 'text/html' },
    });

  } catch (error) {
    console.error('[UNSUBSCRIBE] Error:', error);
    return new Response(getErrorPage('An error occurred. Please try again later.'), {
      status: 500,
      headers: { 'Content-Type': 'text/html' },
    });
  }
};

/**
 * Resubscribe endpoint (POST method)
 */
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    const formData = await request.formData();
    const token = formData.get('token') as string;

    if (!token) {
      return new Response(getErrorPage('Invalid request'), {
        status: 400,
        headers: { 'Content-Type': 'text/html' },
      });
    }

    // Look up contact
    const contact = await env.WAITLIST_DB
      .prepare('SELECT * FROM waitlist WHERE unsubscribe_token = ?')
      .bind(token)
      .first<WaitlistSignup>();

    if (!contact) {
      return new Response(getErrorPage('Invalid request'), {
        status: 404,
        headers: { 'Content-Type': 'text/html' },
      });
    }

    // Resubscribe
    await env.WAITLIST_DB
      .prepare(`
        UPDATE waitlist
        SET email_status = CASE
          WHEN verified_at IS NOT NULL THEN 'verified'
          ELSE 'pending'
        END,
        unsubscribed_at = NULL,
        marketing_consent = true
        WHERE id = ?
      `)
      .bind(contact.id)
      .run();

    console.log('[UNSUBSCRIBE] Resubscribed:', contact.email);

    // Update Resend if applicable
    if (contact.resend_contact_id && env.RESEND_API_KEY &&
        !env.RESEND_API_KEY.startsWith('re_test') &&
        env.RESEND_API_KEY !== 're_test_key_placeholder') {

      try {
        await updateResendContact(env, contact.resend_contact_id, false);
      } catch (error) {
        console.error('[UNSUBSCRIBE] Failed to update Resend:', error);
      }
    }

    return new Response(getResubscribedPage(contact.email), {
      status: 200,
      headers: { 'Content-Type': 'text/html' },
    });

  } catch (error) {
    console.error('[UNSUBSCRIBE] Resubscribe error:', error);
    return new Response(getErrorPage('An error occurred. Please try again later.'), {
      status: 500,
      headers: { 'Content-Type': 'text/html' },
    });
  }
};

/**
 * Update Resend Audiences contact unsubscribe status
 */
async function updateResendContact(env: Env, contactId: string, unsubscribed: boolean): Promise<void> {
  const response = await fetch(`https://api.resend.com/audiences/${env.RESEND_AUDIENCE_ID}/contacts/${contactId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      unsubscribed,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Resend API error: ${error}`);
  }
}

/**
 * Success page HTML
 */
function getSuccessPage(email: string, token: string): string {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Unsubscribed - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #6b7280 0%, #4b5563 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 600px; width: 100%; padding: 50px 40px; text-align: center; }
        .icon { width: 80px; height: 80px; border-radius: 50%; background: #e5e7eb; display: flex; align-items: center; justify-content: center; margin: 0 auto 30px; }
        .icon svg { width: 50px; height: 50px; color: #6b7280; }
        h1 { font-size: 28px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 16px; color: #6b7280; margin-bottom: 20px; line-height: 1.6; }
        .email { font-size: 14px; color: #9ca3af; font-family: 'Courier New', monospace; margin-bottom: 30px; }
        .info { background: #f9fafb; border-left: 4px solid #6b7280; padding: 20px; border-radius: 8px; margin: 30px 0; text-align: left; }
        .info h3 { color: #374151; font-size: 16px; margin-bottom: 10px; }
        .info ul { color: #6b7280; font-size: 14px; margin-left: 20px; }
        .info li { margin-bottom: 6px; }
        form { margin-top: 20px; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; border: none; cursor: pointer; font-size: 14px; }
        .btn:hover { background: #1e3a8a; }
        .btn-secondary { background: #e5e7eb; color: #374151 !important; margin-left: 10px; }
        .btn-secondary:hover { background: #d1d5db; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path></svg>
        </div>

        <h1>You've been unsubscribed</h1>
        <p>You won't receive any more marketing emails from TrendSight.</p>
        <p class="email">${email}</p>

        <div class="info">
          <h3>📧 What this means:</h3>
          <ul>
            <li>You'll no longer receive waitlist updates or launch notifications</li>
            <li>Your spot on the waitlist has been removed</li>
            <li>We've kept your email to honor this unsubscribe request</li>
          </ul>
        </div>

        <p style="font-size: 14px; color: #374151; margin-top: 30px;">Changed your mind?</p>
        <form method="POST" action="/unsubscribe">
          <input type="hidden" name="token" value="${token}" />
          <button type="submit" class="btn">Resubscribe</button>
          <a href="/" class="btn btn-secondary">Go to Homepage</a>
        </form>
      </div>
    </body>
    </html>
  `;
}

/**
 * Already unsubscribed page
 */
function getAlreadyUnsubscribedPage(email: string): string {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Already Unsubscribed - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #6b7280 0%, #4b5563 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 500px; width: 100%; padding: 50px 40px; text-align: center; }
        h1 { font-size: 24px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 16px; color: #6b7280; margin-bottom: 20px; }
        .email { font-size: 14px; color: #9ca3af; font-family: 'Courier New', monospace; margin-bottom: 30px; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Already Unsubscribed</h1>
        <p>This email address has already been unsubscribed from TrendSight emails.</p>
        <p class="email">${email}</p>
        <a href="/" class="btn">Back to Home</a>
      </div>
    </body>
    </html>
  `;
}

/**
 * Resubscribed success page
 */
function getResubscribedPage(email: string): string {
  return `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Resubscribed - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #10b981 0%, #059669 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 500px; width: 100%; padding: 50px 40px; text-align: center; }
        .icon { width: 80px; height: 80px; border-radius: 50%; background: #d1fae5; display: flex; align-items: center; justify-content: center; margin: 0 auto 30px; }
        .icon svg { width: 50px; height: 50px; color: #10b981; }
        h1 { font-size: 28px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 16px; color: #6b7280; margin-bottom: 20px; }
        .email { font-size: 14px; color: #9ca3af; font-family: 'Courier New', monospace; margin-bottom: 30px; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"></path></svg>
        </div>
        <h1>Welcome Back!</h1>
        <p>You've been successfully resubscribed to TrendSight emails.</p>
        <p class="email">${email}</p>
        <p style="font-size: 14px; color: #6b7280;">You'll now receive updates about our launch and early access opportunities.</p>
        <a href="/" class="btn" style="margin-top: 20px;">Back to Home</a>
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
      <title>Error - TrendSight</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .container { background: white; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 500px; width: 100%; padding: 50px 40px; text-align: center; }
        .icon { width: 80px; height: 80px; border-radius: 50%; background: #fee2e2; display: flex; align-items: center; justify-content: center; margin: 0 auto 30px; }
        .icon svg { width: 50px; height: 50px; color: #dc2626; }
        h1 { font-size: 24px; color: #1f2937; margin-bottom: 15px; }
        p { font-size: 16px; color: #6b7280; margin-bottom: 30px; }
        .btn { display: inline-block; background: #1e40af; color: white !important; padding: 12px 28px; text-decoration: none; border-radius: 8px; font-weight: 600; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="icon">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
        </div>
        <h1>Oops!</h1>
        <p>${message}</p>
        <a href="/" class="btn">Back to Home</a>
      </div>
    </body>
    </html>
  `;
}
