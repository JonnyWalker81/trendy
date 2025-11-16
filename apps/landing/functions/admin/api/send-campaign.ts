/**
 * Admin Send Campaign API
 * Send batch emails to waitlist segments
 */

interface SendCampaignRequest {
  campaign_type: 'launch' | 'update' | 'early_access' | 'reminder';
  segment: 'vip' | 'early_access' | 'all' | 'verified' | 'custom';
  subject: string;
  html_content: string;
  dry_run?: boolean;
  custom_filter?: {
    min_score?: number;
    max_score?: number;
    tier?: string;
    min_referrals?: number;
  };
}

interface Recipient {
  email: string;
  name: string | null;
  position: number;
  score: number;
  invite_code: string;
}

/**
 * POST /admin/api/send-campaign - Send email campaign
 */
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    // Parse request body
    const body = await request.json<SendCampaignRequest>();
    const { campaign_type, segment, subject, html_content, dry_run = false, custom_filter } = body;

    // Validate required fields
    if (!campaign_type || !segment || !subject || !html_content) {
      return Response.json(
        { error: 'Missing required fields: campaign_type, segment, subject, html_content' },
        { status: 400 }
      );
    }

    // Build query based on segment
    let query = '';
    let bindings: any[] = [];

    switch (segment) {
      case 'vip':
        // Top 100 by score
        query = `
          SELECT email, name, score, invite_code,
                 ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
          FROM waitlist
          WHERE email_status = 'verified' AND marketing_consent = true
          ORDER BY score DESC, created_at ASC
          LIMIT 100
        `;
        break;

      case 'early_access':
        // Position 101-500
        query = `
          WITH ranked AS (
            SELECT email, name, score, invite_code,
                   ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
            FROM waitlist
            WHERE email_status = 'verified' AND marketing_consent = true
          )
          SELECT * FROM ranked
          WHERE position > 100 AND position <= 500
        `;
        break;

      case 'all':
        // All verified with marketing consent
        query = `
          SELECT email, name, score, invite_code,
                 ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
          FROM waitlist
          WHERE email_status = 'verified' AND marketing_consent = true
          ORDER BY score DESC, created_at ASC
        `;
        break;

      case 'verified':
        // All verified (no marketing consent filter)
        query = `
          SELECT email, name, score, invite_code,
                 ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
          FROM waitlist
          WHERE email_status = 'verified'
          ORDER BY score DESC, created_at ASC
        `;
        break;

      case 'custom':
        // Custom filter
        const conditions: string[] = ['email_status = ?'];
        bindings.push('verified');

        if (custom_filter?.min_score) {
          conditions.push('score >= ?');
          bindings.push(custom_filter.min_score);
        }
        if (custom_filter?.max_score) {
          conditions.push('score <= ?');
          bindings.push(custom_filter.max_score);
        }
        if (custom_filter?.tier) {
          conditions.push('tier = ?');
          bindings.push(custom_filter.tier);
        }
        if (custom_filter?.min_referrals) {
          conditions.push('referrals_count >= ?');
          bindings.push(custom_filter.min_referrals);
        }

        query = `
          SELECT email, name, score, invite_code,
                 ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
          FROM waitlist
          WHERE ${conditions.join(' AND ')}
          ORDER BY score DESC, created_at ASC
        `;
        break;

      default:
        return Response.json({ error: 'Invalid segment' }, { status: 400 });
    }

    // Fetch recipients
    const result = await env.WAITLIST_DB.prepare(query)
      .bind(...bindings)
      .all<Recipient>();

    const recipients = result.results || [];

    // Dry run - return preview
    if (dry_run) {
      return Response.json({
        dry_run: true,
        recipient_count: recipients.length,
        preview: recipients.slice(0, 10),
        segment,
        campaign_type,
        subject,
      });
    }

    // Send emails via Resend
    const sentEmails: string[] = [];
    const failedEmails: string[] = [];

    for (const recipient of recipients) {
      try {
        // Personalize content
        const personalizedContent = html_content
          .replace(/{{email}}/g, recipient.email)
          .replace(/{{name}}/g, recipient.name || recipient.email.split('@')[0])
          .replace(/{{position}}/g, recipient.position.toString())
          .replace(/{{score}}/g, recipient.score.toLocaleString())
          .replace(/{{invite_code}}/g, recipient.invite_code);

        // Send email via Resend with retry logic for rate limits
        let emailResponse = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${env.RESEND_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: env.FROM_EMAIL,
            to: recipient.email,
            subject,
            html: personalizedContent,
            tags: [
              { name: 'campaign_type', value: campaign_type },
              { name: 'segment', value: segment },
            ],
            headers: {
              'X-Entity-Ref-ID': recipient.email, // Enable per-recipient tracking
            },
          }),
        });

        // Retry once if rate limited (429)
        if (emailResponse.status === 429) {
          console.log('Rate limited, waiting 1 second before retry for:', recipient.email);
          await new Promise((resolve) => setTimeout(resolve, 1000));

          emailResponse = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${env.RESEND_API_KEY}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              from: env.FROM_EMAIL,
              to: recipient.email,
              subject,
              html: personalizedContent,
              tags: [
                { name: 'campaign_type', value: campaign_type },
                { name: 'segment', value: segment },
              ],
              headers: {
                'X-Entity-Ref-ID': recipient.email, // Enable per-recipient tracking
              },
            }),
          });
        }

        if (emailResponse.ok) {
          sentEmails.push(recipient.email);
        } else {
          const errorData = await emailResponse.text();
          console.error('Failed to send to', recipient.email, errorData);
          failedEmails.push(recipient.email);
        }

        // Rate limit: 2 emails per second for Resend (500ms delay)
        await new Promise((resolve) => setTimeout(resolve, 500));
      } catch (error) {
        console.error('Error sending to', recipient.email, error);
        failedEmails.push(recipient.email);
      }
    }

    // Log campaign to database
    await env.WAITLIST_DB.prepare(
      `INSERT INTO email_campaigns (campaign_name, campaign_type, subject_line, sent_at, recipient_count, segment_filter)
       VALUES (?, ?, ?, datetime('now'), ?, ?)`
    )
      .bind(
        `${campaign_type} - ${segment}`,
        campaign_type,
        subject,
        sentEmails.length,
        JSON.stringify({ segment, custom_filter })
      )
      .run();

    return Response.json({
      success: true,
      sent_count: sentEmails.length,
      failed_count: failedEmails.length,
      total_recipients: recipients.length,
      failed_emails: failedEmails.slice(0, 10), // Return first 10 failures
    });
  } catch (error) {
    console.error('Send campaign error:', error);
    return Response.json(
      { error: 'Failed to send campaign', details: error instanceof Error ? error.message : 'Unknown error' },
      { status: 500 }
    );
  }
};
