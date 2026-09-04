/**
 * blackgod88 — 公开版 Worker
 * 用户自带 API key，纯静态托管
 * build: __BUILD_TIME__
 */

const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'SAMEORIGIN',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'geolocation=(), microphone=(), camera=()',
  'Content-Security-Policy': [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "font-src 'self' data:",
    "connect-src 'self' https:",
    "frame-ancestors 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
    "upgrade-insecure-requests",
  ].join('; '),
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', {
        status: 405,
        headers: { Allow: 'GET, HEAD' },
      });
    }

    let res = await env.ASSETS.fetch(request);

    if (res.status === 404) {
      const last = url.pathname.split('/').pop() || '';
      if (last.includes('.')) {
        return withHeaders(res, res.status);
      }
      const indexUrl = new URL('/index.html', url.origin).toString();
      const index = await env.ASSETS.fetch(new Request(indexUrl, { method: request.method }));
      res = new Response(index.body, {
        status: index.ok ? 200 : index.status,
        headers: index.headers,
      });
    }

    return withHeaders(res, res.status);
  },
};

function withHeaders(res, status) {
  const headers = new Headers(res.headers);
  const contentType = headers.get('content-type') || '';
  const isHtml = contentType.includes('text/html');
  headers.set('Cache-Control', isHtml ? 'no-store' : 'public, max-age=31536000, immutable');
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(res.body, { status, headers });
}
