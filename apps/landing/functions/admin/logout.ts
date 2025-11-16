/**
 * Admin Console Logout Handler
 * Destroys session and redirects to login
 */

import { parseCookies } from '../shared/admin-layout';

/**
 * POST /admin/logout - Handle logout
 */
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    // Extract session token from cookies
    const cookieHeader = request.headers.get('Cookie') || '';
    const cookies = parseCookies(cookieHeader);
    const sessionToken = cookies['admin_session'];

    // Delete session from database if token exists
    if (sessionToken) {
      await env.WAITLIST_DB.prepare(
        `DELETE FROM admin_sessions WHERE token = ?`
      )
        .bind(sessionToken)
        .run();
    }

    // Clear session cookie and redirect to login
    return new Response(null, {
      status: 302,
      headers: {
        'Location': new URL('/admin/login', request.url).toString(),
        'Set-Cookie': 'admin_session=; Path=/admin; HttpOnly; SameSite=Lax; Max-Age=0',
      },
    });
  } catch (error) {
    console.error('Logout error:', error);

    // Even on error, clear cookie and redirect
    return new Response(null, {
      status: 302,
      headers: {
        'Location': new URL('/admin/login', request.url).toString(),
        'Set-Cookie': 'admin_session=; Path=/admin; HttpOnly; SameSite=Lax; Max-Age=0',
      },
    });
  }
};
