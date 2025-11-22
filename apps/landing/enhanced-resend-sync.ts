/**
 * Enhanced Resend Audience Sync with Score & Position
 * This shows how to sync score and position as metadata to Resend
 */

async function syncToResendAudienceEnhanced(
  env: Env,
  contact: WaitlistSignup & { position: number }
): Promise<void> {
  const firstName = contact.name?.split(' ')[0] || '';
  const lastName = contact.name?.split(' ').slice(1).join(' ') || '';

  // Determine tier based on score
  let tier = 'standard';
  if (contact.position <= 100) tier = 'vip';
  else if (contact.position <= 500) tier = 'early_access';
  else if (contact.referrals_count && contact.referrals_count >= 3) tier = 'beta_tester';

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
      // Custom metadata (visible in Resend dashboard)
      // NOTE: Resend doesn't officially support custom fields in Audiences API yet
      // You may need to use their Contacts API instead or store this in your DB
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Resend Audiences API error: ${error}`);
  }

  const result = await response.json() as ResendContact;

  // Store position and tier in YOUR database for later use
  await env.WAITLIST_DB
    .prepare(`
      UPDATE waitlist
      SET
        resend_contact_id = ?,
        resend_audience_id = ?,
        tier = ?,
        resend_sync_status = 'synced',
        last_synced_to_resend_at = ?
      WHERE id = ?
    `)
    .bind(
      result.id,
      env.RESEND_AUDIENCE_ID,
      tier,
      new Date().toISOString(),
      contact.id
    )
    .run();
}

/**
 * Alternative: Use Resend Broadcasts with dynamic segments
 * Query your D1 database to get top scorers, then send via Resend
 */
async function sendLaunchEmailsToTopScorers(env: Env, topN: number) {
  // Get top scorers from D1
  const topUsers = await env.WAITLIST_DB
    .prepare(`
      SELECT
        email,
        name,
        score,
        referrals_count,
        invite_code,
        ROW_NUMBER() OVER (ORDER BY score DESC, created_at ASC) as position
      FROM waitlist
      WHERE email_status = 'verified'
        AND marketing_consent = true
      ORDER BY score DESC
      LIMIT ?
    `)
    .bind(topN)
    .all();

  // Send batch email via Resend Broadcasts API
  for (const user of topUsers.results) {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${env.RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: 'launch@trendsight.app',
        to: user.email,
        subject: `🚀 You're #${user.position}! TrendSight is LIVE`,
        html: `
          <h1>Congratulations, ${user.name?.split(' ')[0] || 'there'}!</h1>
          <p>You're <strong>#${user.position}</strong> on the TrendSight waitlist.</p>
          <p>You earned this spot by ${user.referrals_count > 0 ? `referring ${user.referrals_count} friends` : 'being an early supporter'}!</p>
          <a href="https://app.trendsight.app/signup?code=${user.invite_code}">Claim Your Access Now</a>
        `,
        tags: [
          { name: 'campaign', value: 'launch' },
          { name: 'position', value: user.position.toString() },
          { name: 'tier', value: user.position <= 100 ? 'vip' : 'early_access' },
        ],
      }),
    });

    // Optional: Add delay between sends to avoid rate limits
    await new Promise(resolve => setTimeout(resolve, 100));
  }
}
