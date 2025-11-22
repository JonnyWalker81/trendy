/**
 * API Endpoint: Link Invite Code to Supabase User
 * POST /api/waitlist/link
 *
 * Links a waitlist entry to a registered Supabase user
 * Called after successful signup
 */

interface Env {
  WAITLIST_DB: D1Database;
}

interface LinkRequest {
  invite_code: string;
  supabase_user_id: string;
}

interface WaitlistEntry {
  id: number;
  email: string;
  email_status: string;
  supabase_user_id: string | null;
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
  try {
    const { request, env } = context;

    // Parse request body
    let body: LinkRequest;
    try {
      body = await request.json();
    } catch (e) {
      return new Response(JSON.stringify({
        error: 'Invalid JSON body'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    const { invite_code, supabase_user_id } = body;

    // Validate input
    if (!invite_code || !supabase_user_id) {
      return new Response(JSON.stringify({
        error: 'Missing required fields: invite_code and supabase_user_id'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Validate UUID format (basic check)
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(supabase_user_id)) {
      return new Response(JSON.stringify({
        error: 'Invalid supabase_user_id format (must be UUID)'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Check if invite code exists and is valid
    const existingEntry = await env.WAITLIST_DB
      .prepare(`
        SELECT
          id,
          email,
          email_status,
          supabase_user_id
        FROM waitlist
        WHERE invite_code = ? COLLATE NOCASE
        LIMIT 1
      `)
      .bind(invite_code.toUpperCase())
      .first<WaitlistEntry>();

    if (!existingEntry) {
      return new Response(JSON.stringify({
        error: 'Invalid invite code'
      }), {
        status: 404,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Check if already linked
    if (existingEntry.supabase_user_id) {
      return new Response(JSON.stringify({
        error: 'This invite code has already been linked to a user'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Check if email is verified
    if (existingEntry.email_status !== 'verified') {
      return new Response(JSON.stringify({
        error: 'Email must be verified before linking'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Check if this Supabase user ID is already linked to another code
    const duplicateUser = await env.WAITLIST_DB
      .prepare(`
        SELECT id
        FROM waitlist
        WHERE supabase_user_id = ?
        LIMIT 1
      `)
      .bind(supabase_user_id)
      .first();

    if (duplicateUser) {
      return new Response(JSON.stringify({
        error: 'This user is already linked to another invite code'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Link the invite code to the Supabase user
    const result = await env.WAITLIST_DB
      .prepare(`
        UPDATE waitlist
        SET supabase_user_id = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE invite_code = ? COLLATE NOCASE
        AND supabase_user_id IS NULL
      `)
      .bind(supabase_user_id, invite_code.toUpperCase())
      .run();

    if (!result.success) {
      return new Response(JSON.stringify({
        error: 'Failed to link invite code'
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
        }
      });
    }

    // Success
    return new Response(JSON.stringify({
      success: true,
      message: 'Invite code successfully linked',
      email: existingEntry.email
    }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
      }
    });

  } catch (error) {
    console.error('Error linking invite code:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error'
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
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
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    }
  });
};
