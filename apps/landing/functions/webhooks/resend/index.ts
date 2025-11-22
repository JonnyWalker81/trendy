/**
 * Resend Webhook Handler
 * Tracks email events (sent, opened, clicked, bounced, etc.)
 * Complies with Resend's webhook signature verification
 *
 * Route: POST /webhooks/resend
 */

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  console.log('[WEBHOOK] Resend webhook received');

  try {
    // 1. Get webhook signature headers
    const svixId = request.headers.get('svix-id');
    const svixTimestamp = request.headers.get('svix-timestamp');
    const svixSignature = request.headers.get('svix-signature');

    if (!svixId || !svixTimestamp || !svixSignature) {
      console.error('[WEBHOOK] Missing signature headers');
      return new Response('Missing signature headers', { status: 401 });
    }

    // 2. Get raw body for signature verification
    const body = await request.text();

    // 3. Verify webhook signature
    const isValid = await verifyWebhookSignature(
      env.RESEND_WEBHOOK_SECRET,
      svixId,
      svixTimestamp,
      svixSignature,
      body
    );

    if (!isValid) {
      console.error('[WEBHOOK] Invalid signature');
      return new Response('Invalid signature', { status: 401 });
    }

    // 4. Parse webhook event
    const event: ResendWebhookEvent = JSON.parse(body);
    console.log('[WEBHOOK] Event type:', event.type);

    // 5. Process event based on type
    await processWebhookEvent(env, event);

    return new Response('Webhook processed', { status: 200 });

  } catch (error) {
    console.error('[WEBHOOK] Error processing webhook:', error);
    return new Response('Webhook processing failed', { status: 500 });
  }
};

/**
 * Verify webhook signature using Svix-compatible verification
 * Resend uses Svix for webhook signing
 */
async function verifyWebhookSignature(
  secret: string,
  svixId: string,
  svixTimestamp: string,
  svixSignature: string,
  body: string
): Promise<boolean> {
  // Skip verification in dev mode
  if (secret === 'whsec_test_secret' || secret.startsWith('whsec_test')) {
    console.log('[WEBHOOK] Dev mode: Skipping signature verification');
    return true;
  }

  try {
    // Construct the signed content (Svix format)
    const signedContent = `${svixId}.${svixTimestamp}.${body}`;

    // Extract the secret (remove "whsec_" prefix if present)
    const secretBytes = secret.startsWith('whsec_')
      ? base64ToBytes(secret.slice(6))
      : new TextEncoder().encode(secret);

    // Import key for HMAC
    const key = await crypto.subtle.importKey(
      'raw',
      secretBytes,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );

    // Generate signature
    const signature = await crypto.subtle.sign(
      'HMAC',
      key,
      new TextEncoder().encode(signedContent)
    );

    // Convert to base64
    const expectedSignature = bytesToBase64(new Uint8Array(signature));

    // Extract signatures from header (format: "v1,signature1 v1,signature2")
    const signatures = svixSignature.split(' ').map(sig => {
      const parts = sig.split(',');
      return parts.length === 2 ? parts[1] : null;
    }).filter(Boolean);

    // Check if any signature matches
    return signatures.some(sig => sig === expectedSignature);

  } catch (error) {
    console.error('[WEBHOOK] Signature verification error:', error);
    return false;
  }
}

/**
 * Process webhook event based on type
 */
async function processWebhookEvent(env: Env, event: ResendWebhookEvent): Promise<void> {
  const { type, created_at, data } = event;

  // Extract email address from event data
  const email = Array.isArray(data.to) ? data.to[0] : data.to;
  if (!email) {
    console.log('[WEBHOOK] No email address in event data');
    return;
  }

  // Look up waitlist contact by email
  const contact = await env.WAITLIST_DB
    .prepare('SELECT * FROM waitlist WHERE email = ?')
    .bind(email)
    .first<WaitlistSignup>();

  if (!contact) {
    console.log('[WEBHOOK] Email not found in waitlist:', email);
    return;
  }

  console.log('[WEBHOOK] Processing event for contact ID:', contact.id);

  // Map Resend event types to our event types
  const eventTypeMap: Record<string, EmailEventType> = {
    'email.sent': 'sent',
    'email.delivered': 'delivered',
    'email.delivery_delayed': 'delivery_delayed',
    'email.bounced': 'bounced',
    'email.complained': 'complained',
    'email.opened': 'opened',
    'email.clicked': 'clicked',
  };

  const eventType = eventTypeMap[type];
  if (!eventType) {
    console.log('[WEBHOOK] Unknown event type:', type);
    return;
  }

  // Insert event into email_events table
  await env.WAITLIST_DB
    .prepare(`
      INSERT INTO email_events (
        waitlist_id,
        event_type,
        resend_email_id,
        link_url,
        user_agent,
        ip_address,
        event_timestamp,
        raw_webhook_data
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .bind(
      contact.id,
      eventType,
      data.email_id || null,
      data.link || null,
      data.user_agent || null,
      data.ip || null,
      created_at,
      JSON.stringify(event)
    )
    .run();

  console.log('[WEBHOOK] Event inserted:', eventType);

  // Update aggregate metrics based on event type
  await updateContactMetrics(env, contact.id!, eventType);

  // Handle special cases
  if (eventType === 'bounced') {
    await handleBounce(env, contact.id!);
  } else if (eventType === 'complained') {
    await handleComplaint(env, contact.id!);
  }
}

/**
 * Update contact aggregate metrics
 */
async function updateContactMetrics(
  env: Env,
  contactId: number,
  eventType: EmailEventType
): Promise<void> {
  const now = new Date().toISOString();

  switch (eventType) {
    case 'sent':
      await env.WAITLIST_DB
        .prepare('UPDATE waitlist SET total_emails_sent = total_emails_sent + 1 WHERE id = ?')
        .bind(contactId)
        .run();
      break;

    case 'opened':
      await env.WAITLIST_DB
        .prepare(`
          UPDATE waitlist
          SET total_emails_opened = total_emails_opened + 1,
              last_email_opened_at = ?,
              engagement_score = engagement_score + 5
          WHERE id = ?
        `)
        .bind(now, contactId)
        .run();
      break;

    case 'clicked':
      await env.WAITLIST_DB
        .prepare(`
          UPDATE waitlist
          SET total_emails_clicked = total_emails_clicked + 1,
              last_email_clicked_at = ?,
              engagement_score = engagement_score + 10
          WHERE id = ?
        `)
        .bind(now, contactId)
        .run();
      break;

    case 'complained':
      // Negative engagement score for spam complaints
      await env.WAITLIST_DB
        .prepare('UPDATE waitlist SET engagement_score = engagement_score - 50 WHERE id = ?')
        .bind(contactId)
        .run();
      break;
  }

  console.log('[WEBHOOK] Metrics updated for contact:', contactId);
}

/**
 * Handle bounced email
 */
async function handleBounce(env: Env, contactId: number): Promise<void> {
  // Mark email as bounced (permanent bounce)
  await env.WAITLIST_DB
    .prepare('UPDATE waitlist SET email_status = ? WHERE id = ?')
    .bind('bounced', contactId)
    .run();

  console.log('[WEBHOOK] Contact marked as bounced:', contactId);
}

/**
 * Handle spam complaint
 */
async function handleComplaint(env: Env, contactId: number): Promise<void> {
  // Automatically unsubscribe users who mark as spam
  const now = new Date().toISOString();

  await env.WAITLIST_DB
    .prepare(`
      UPDATE waitlist
      SET email_status = ?,
          unsubscribed_at = ?,
          unsubscribe_reason = ?,
          marketing_consent = false
      WHERE id = ?
    `)
    .bind('unsubscribed', now, 'spam_complaint', contactId)
    .run();

  console.log('[WEBHOOK] Contact unsubscribed due to complaint:', contactId);
}

/**
 * Base64 utilities for signature verification
 */
function base64ToBytes(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
