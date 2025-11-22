/**
 * Dynamic Landing Page Handler
 * Serves the landing page with environment-specific Turnstile site key
 * Catch-all handler for GET requests that don't match other routes
 */

export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { env, request } = context;
  const url = new URL(request.url);

  // Only serve landing page for root path
  if (url.pathname !== '/') {
    // Pass through to other handlers or 404
    return context.next();
  }

  try {
    // Fetch the template HTML from assets
    const templateResponse = await env.ASSETS.fetch(new Request('https://placeholder/_index.html'));

    if (!templateResponse.ok) {
      console.error('[INDEX] Failed to fetch template:', templateResponse.status);
      return new Response('Template not found', { status: 500 });
    }

    let html = await templateResponse.text();

    // Replace placeholder with actual Turnstile site key from environment
    const siteKey = env.TURNSTILE_SITE_KEY || '1x00000000000000000000AA'; // Fallback to test key
    html = html.replace('{{TURNSTILE_SITE_KEY}}', siteKey);

    // Return the rendered HTML
    return new Response(html, {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'public, max-age=300', // Cache for 5 minutes
      },
    });
  } catch (error) {
    console.error('[INDEX] Error serving landing page:', error);
    return new Response('Internal Server Error', { status: 500 });
  }
};
