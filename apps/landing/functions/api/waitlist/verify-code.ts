/**
 * API Endpoint: Verify Invite Code
 * GET /api/waitlist/verify-code?code=XXX
 *
 * Returns invite code details if valid, used by signup flow
 */

interface Env {
  WAITLIST_DB: D1Database;
}

interface WaitlistEntry {
  id: number;
  email: string;
  name: string | null;
  email_status: string;
  tier: string;
  invite_code: string;
  supabase_user_id: string | null;
}

export const onRequestGet: PagesFunction<Env> = async (context) => {
  try {
    const { request, env } = context;
    const url = new URL(request.url);
    const code = url.searchParams.get('code');

    // Validate code parameter
    if (!code || code.trim() === '') {
      return new Response(JSON.stringify({
        error: 'Missing or invalid invite code'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*', // Allow web app to call this
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
        }
      });
    }

    // Query waitlist database
    const result = await env.WAITLIST_DB
      .prepare(`
        SELECT
          id,
          email,
          name,
          email_status,
          tier,
          invite_code,
          supabase_user_id
        FROM waitlist
        WHERE invite_code = ? COLLATE NOCASE
        LIMIT 1
      `)
      .bind(code.toUpperCase())
      .first<WaitlistEntry>();

    // Code not found
    if (!result) {
      return new Response(JSON.stringify({
        valid: false,
        error: 'Invalid invite code'
      }), {
        status: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
        }
      });
    }

    // Check if email is verified
    if (result.email_status !== 'verified') {
      return new Response(JSON.stringify({
        valid: false,
        error: 'Email not verified. Please verify your email first.'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
        }
      });
    }

    // Check if already used
    if (result.supabase_user_id) {
      return new Response(JSON.stringify({
        valid: false,
        already_used: true,
        error: 'This invite code has already been used'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
        }
      });
    }

    // Valid code - return details
    return new Response(JSON.stringify({
      valid: true,
      email: result.email,
      name: result.name,
      tier: result.tier,
      already_used: false
    }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
      }
    });

  } catch (error) {
    console.error('Error verifying invite code:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error'
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
      }
    });
  }
};

// Handle CORS preflight
export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    }
  });
};
