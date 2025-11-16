/**
 * Admin Endpoint: Send Launch Emails by Score
 *
 * Usage:
 *   POST /admin/send-launch-emails
 *   Authorization: Bearer <ADMIN_SECRET>
 *   Body: { "batch": "vip" | "early_access" | "all" }
 *
 * Batches:
 *   - vip: Top 100 scorers
 *   - early_access: Position 101-500
 *   - all: Everyone
 */

interface LaunchEmailRequest {
  batch: 'vip' | 'early_access' | 'all';
  dry_run?: boolean; // If true, just return who would receive emails
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  // Admin authentication
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || authHeader !== `Bearer ${env.ADMIN_SECRET}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await request.json() as LaunchEmailRequest;
    const { batch, dry_run = false } = body;

    // Determine batch parameters
    let minPosition = 1;
    let maxPosition = 999999;
    let subject = '';
    let earlyAccessDays = 0;

    switch (batch) {
      case 'vip':
        maxPosition = 100;
        subject = "🌟 VIP Access: You're Top 100!";
        earlyAccessDays = 7;
        break;
      case 'early_access':
        minPosition = 101;
        maxPosition = 500;
        subject = "🚀 Early Access: You Made It!";
        earlyAccessDays = 3;
        break;
      case 'all':
        subject = "🎉 TrendSight is Live!";
        earlyAccessDays = 0;
        break;
    }

    // Get users from database with computed position
    const users = await env.WAITLIST_DB
      .prepare(`
        WITH ranked_users AS (
          SELECT
            id,
            email,
            name,
            score,
            referrals_count,
            invite_code,
            ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
          FROM waitlist
          WHERE email_status = 'verified'
            AND marketing_consent = true
        )
        SELECT * FROM ranked_users
        WHERE position >= ? AND position <= ?
        ORDER BY position ASC
      `)
      .bind(minPosition, maxPosition)
      .all();

    if (dry_run) {
      return new Response(JSON.stringify({
        dry_run: true,
        batch,
        total_recipients: users.results.length,
        recipients: users.results.map((u: any) => ({
          position: u.position,
          email: u.email,
          score: u.score,
          referrals: u.referrals_count,
        })),
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Send emails via Resend
    const results = [];
    for (const user of users.results as any[]) {
      try {
        const emailResponse = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${env.RESEND_API_KEY}`,
          },
          body: JSON.stringify({
            from: env.FROM_EMAIL,
            to: user.email,
            subject: subject,
            html: getLaunchEmailHTML(user, earlyAccessDays),
            tags: [
              { name: 'campaign', value: 'launch' },
              { name: 'batch', value: batch },
              { name: 'position', value: user.position.toString() },
            ],
          }),
        });

        if (!emailResponse.ok) {
          const error = await emailResponse.text();
          console.error(`[LAUNCH] Failed to send to ${user.email}:`, error);
          results.push({ email: user.email, status: 'failed', error });
        } else {
          const emailResult = await emailResponse.json();
          results.push({ email: user.email, status: 'sent', id: emailResult.id });

          // Record in database
          await env.WAITLIST_DB
            .prepare(`UPDATE waitlist SET total_emails_sent = total_emails_sent + 1 WHERE id = ?`)
            .bind(user.id)
            .run();
        }

        // Rate limiting: 10 emails per second max
        await new Promise(resolve => setTimeout(resolve, 100));

      } catch (error) {
        console.error(`[LAUNCH] Error sending to ${user.email}:`, error);
        results.push({ email: user.email, status: 'error', error: String(error) });
      }
    }

    return new Response(JSON.stringify({
      batch,
      total_sent: results.filter(r => r.status === 'sent').length,
      total_failed: results.filter(r => r.status === 'failed').length,
      results,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('[LAUNCH] Error:', error);
    return new Response(JSON.stringify({
      error: 'Failed to send launch emails',
      details: String(error),
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
};

function getLaunchEmailHTML(user: any, earlyAccessDays: number): string {
  const firstName = user.name?.split(' ')[0] || 'there';
  const position = user.position;
  const referrals = user.referrals_count || 0;

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
          <h1 style="margin: 0; font-size: 36px; color: #ffffff;">🚀 TrendSight is LIVE!</h1>
          <p style="margin: 10px 0 0 0; font-size: 18px; color: #e0e7ff;">Your patience paid off</p>
        </div>

        <div style="padding: 40px 30px;">
          <p style="margin: 0 0 20px 0; font-size: 18px; color: #333333;">Hi ${firstName},</p>

          <p style="margin: 0 0 20px 0; font-size: 16px; color: #333333;">The wait is over! TrendSight is officially live, and you're one of the first to get access.</p>

          <div style="background: linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%); padding: 30px; border-radius: 12px; margin: 30px 0; text-align: center; border-left: 4px solid #1e40af;">
            <div style="font-size: 56px; font-weight: bold; color: #1e40af; margin-bottom: 10px;">#${position}</div>
            <div style="font-size: 18px; color: #1e3a8a; font-weight: 500;">Your final position on the waitlist</div>
            ${referrals > 0 ? `<div style="margin-top: 15px; font-size: 14px; color: #1e40af;">🎉 You referred ${referrals} friend${referrals > 1 ? 's' : ''}!</div>` : ''}
          </div>

          ${earlyAccessDays > 0 ? `
          <div style="background: #fef3c7; border: 2px solid #f59e0b; border-radius: 8px; padding: 20px; margin: 20px 0;">
            <div style="font-size: 18px; font-weight: bold; color: #92400e; margin-bottom: 10px;">⚡ Early Access Bonus</div>
            <div style="font-size: 16px; color: #78350f;">You get ${earlyAccessDays} days of exclusive early access before the public launch!</div>
          </div>
          ` : ''}

          <div style="margin: 30px 0; text-align: center;">
            <a href="https://app.trendsight.app/signup?code=${user.invite_code}" style="display: inline-block; background: #1e40af; color: #ffffff !important; padding: 16px 40px; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 18px;">Get Started Now</a>
          </div>

          <h2 style="color: #1e40af; font-size: 20px; margin: 30px 0 15px 0;">🎯 What's Next?</h2>
          <ul style="margin: 0; padding-left: 20px; color: #333333; font-size: 16px;">
            <li style="margin-bottom: 10px;">Click the button above to create your account</li>
            <li style="margin-bottom: 10px;">Start tracking your first events</li>
            <li style="margin-bottom: 10px;">Discover patterns in your life</li>
            <li style="margin-bottom: 10px;">Share feedback - we're listening!</li>
          </ul>

          <p style="margin: 30px 0 0 0; font-size: 16px; color: #333333;">Thank you for being an early supporter. Your position (#${position}) reflects your commitment to discovering your life patterns.</p>

          <p style="margin: 20px 0 0 0; font-size: 16px; color: #333333;">Let's get tracking!<br><strong style="color: #1e40af;">The TrendSight Team</strong></p>
        </div>

        <div style="background: #f9fafb; padding: 30px; text-align: center; border-top: 1px solid #e5e7eb;">
          <p style="margin: 0 0 10px 0; color: #6b7280; font-size: 14px;">TrendSight - Track Anything, Discover Your Patterns</p>
          <p style="margin: 0; color: #9ca3af; font-size: 12px;">
            <a href="${env.VERIFICATION_BASE_URL || 'https://trendsight.app'}/unsubscribe?token=${user.unsubscribe_token}" style="color: #6b7280; text-decoration: underline;">Unsubscribe</a>
          </p>
        </div>
      </div>
    </body>
    </html>
  `;
}
