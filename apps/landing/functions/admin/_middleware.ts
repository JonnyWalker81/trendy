/**
 * Admin Console Authentication Middleware
 * Protects all /admin/* routes with session-based authentication
 */

import { parseCookies } from '../shared/admin-layout';

interface AdminSession {
  id: number;
  token: string;
  admin_email: string;
  expires_at: string;
  created_at: string;
}

/**
 * Public routes that don't require authentication
 */
const PUBLIC_ROUTES = ['/admin/login'];

/**
 * Validate admin session token
 */
async function validateSession(token: string, env: Env): Promise<AdminSession | null> {
  try {
    const result = await env.WAITLIST_DB.prepare(
      `SELECT * FROM admin_sessions WHERE token = ? AND expires_at > datetime('now')`
    )
      .bind(token)
      .first<AdminSession>();

    return result;
  } catch (error) {
    console.error('Session validation error:', error);
    return null;
  }
}

/**
 * Clean up expired sessions (run periodically)
 */
async function cleanupExpiredSessions(env: Env): Promise<void> {
  try {
    await env.WAITLIST_DB.prepare(
      `DELETE FROM admin_sessions WHERE expires_at < datetime('now')`
    ).run();
  } catch (error) {
    console.error('Session cleanup error:', error);
  }
}

/**
 * Authentication middleware for admin routes
 */
export const onRequest: PagesFunction<Env> = async (context) => {
  const { request, env, next } = context;
  const url = new URL(request.url);
  const pathname = url.pathname;

  // Allow public routes (login page)
  if (PUBLIC_ROUTES.includes(pathname)) {
    return next();
  }

  // Extract session token from cookies
  const cookieHeader = request.headers.get('Cookie') || '';
  const cookies = parseCookies(cookieHeader);
  const sessionToken = cookies['admin_session'];

  // No session token - redirect to login
  if (!sessionToken) {
    return Response.redirect(new URL('/admin/login', request.url).toString(), 302);
  }

  // Validate session token
  const session = await validateSession(sessionToken, env);

  // Invalid or expired session - clear cookie and redirect to login
  if (!session) {
    return new Response(null, {
      status: 302,
      headers: {
        'Location': new URL('/admin/login', request.url).toString(),
        'Set-Cookie': 'admin_session=; Path=/admin; HttpOnly; Secure; SameSite=Lax; Max-Age=0',
      },
    });
  }

  // Valid session - attach admin context to request
  // Store in context.data for access in route handlers
  context.data.adminSession = session;

  // Periodically clean up expired sessions (1% chance on each request)
  if (Math.random() < 0.01) {
    cleanupExpiredSessions(env).catch(console.error);
  }

  // Continue to route handler
  return next();
};
