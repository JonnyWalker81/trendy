/**
 * Admin Console Login Page
 * Handles login form display and authentication
 */

import { getAlert } from '../shared/admin-layout';

/**
 * Generate random session token
 */
function generateSessionToken(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * GET /admin/login - Display login form
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { request } = context;
  const url = new URL(request.url);
  const error = url.searchParams.get('error');

  const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Login - TrendSight</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    .gradient-bg {
      background: linear-gradient(135deg, #1e40af 0%, #3730a3 100%);
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .fade-in {
      animation: fadeIn 0.5s ease-out;
    }
  </style>
</head>
<body class="gradient-bg min-h-screen flex items-center justify-center p-4">
  <div class="w-full max-w-md fade-in">
    <!-- Logo Card -->
    <div class="bg-white/10 backdrop-blur-sm rounded-2xl p-8 mb-6 text-center text-white">
      <h1 class="text-4xl font-bold mb-2">TrendSight</h1>
      <p class="text-blue-200">Admin Console</p>
    </div>

    <!-- Login Card -->
    <div class="bg-white rounded-2xl shadow-2xl p-8">
      <h2 class="text-2xl font-bold text-gray-900 mb-6">Sign In</h2>

      ${error ? getAlert({ type: 'error', message: error }) : ''}

      <form method="POST" action="/admin/login" class="space-y-6">
        <!-- Email Field -->
        <div>
          <label for="email" class="block text-sm font-medium text-gray-700 mb-2">
            Email Address
          </label>
          <input
            type="email"
            id="email"
            name="email"
            required
            autocomplete="email"
            class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
            placeholder="admin@trendsight.app"
          />
        </div>

        <!-- Password Field -->
        <div>
          <label for="password" class="block text-sm font-medium text-gray-700 mb-2">
            Password
          </label>
          <input
            type="password"
            id="password"
            name="password"
            required
            autocomplete="current-password"
            class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
            placeholder="••••••••"
          />
        </div>

        <!-- Submit Button -->
        <button
          type="submit"
          class="w-full gradient-bg text-white font-semibold py-3 rounded-lg hover:opacity-90 transition-opacity focus:ring-4 focus:ring-blue-300"
        >
          Sign In
        </button>
      </form>

      <!-- Footer -->
      <div class="mt-6 text-center text-sm text-gray-500">
        <p>Authorized access only</p>
      </div>
    </div>

    <!-- Back to Site -->
    <div class="mt-6 text-center">
      <a href="/" class="text-white hover:text-blue-200 transition-colors text-sm">
        ← Back to TrendSight
      </a>
    </div>
  </div>
</body>
</html>
  `;

  return new Response(html, {
    headers: { 'Content-Type': 'text/html' },
  });
};

/**
 * POST /admin/login - Handle login submission
 */
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    // Parse form data
    const formData = await request.formData();
    const email = formData.get('email')?.toString().trim();
    const password = formData.get('password')?.toString();

    // Validate input
    if (!email || !password) {
      return Response.redirect(
        new URL('/admin/login?error=' + encodeURIComponent('Email and password are required'), request.url).toString(),
        302
      );
    }

    // Verify credentials against environment variables
    const validEmail = env.ADMIN_EMAIL;
    const validPassword = env.ADMIN_PASSWORD;

    if (email !== validEmail || password !== validPassword) {
      // Log failed attempt (optional - for security monitoring)
      console.warn('Failed login attempt:', { email, timestamp: new Date().toISOString() });

      return Response.redirect(
        new URL('/admin/login?error=' + encodeURIComponent('Invalid email or password'), request.url).toString(),
        302
      );
    }

    // Generate session token
    const sessionToken = generateSessionToken();
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 24); // 24-hour session

    // Store session in database
    await env.WAITLIST_DB.prepare(
      `INSERT INTO admin_sessions (token, admin_email, expires_at)
       VALUES (?, ?, ?)`
    )
      .bind(sessionToken, email, expiresAt.toISOString())
      .run();

    // Set session cookie (HTTP-only, Secure in production)
    const isProduction = new URL(request.url).hostname !== 'localhost';
    const cookieOptions = [
      `admin_session=${sessionToken}`,
      'Path=/admin',
      'HttpOnly',
      'SameSite=Lax',
      `Max-Age=${24 * 60 * 60}`, // 24 hours in seconds
      isProduction ? 'Secure' : '', // HTTPS only in production
    ]
      .filter(Boolean)
      .join('; ');

    // Redirect to dashboard with cookie
    return new Response(null, {
      status: 302,
      headers: {
        'Location': new URL('/admin', request.url).toString(),
        'Set-Cookie': cookieOptions,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    return Response.redirect(
      new URL('/admin/login?error=' + encodeURIComponent('Login failed. Please try again.'), request.url).toString(),
      302
    );
  }
};
