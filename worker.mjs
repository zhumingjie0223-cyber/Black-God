/**
 * blackgod88 — 公开版 Worker
 * 用户自带 API key，纯静态托管
 * build: __BUILD_TIME__
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    let res = await env.ASSETS.fetch(request);

    if (res.status === 404) {
      const last = url.pathname.split('/').pop() || '';
      if (last.includes('.')) return res;
      const index = await env.ASSETS.fetch(new Request(new URL('/index.html', url.origin).toString()));
      res = new Response(index.body, { status: 200, headers: index.headers });
    }

    const headers = new Headers(res.headers);
    const isHtml = (headers.get('content-type') || '').includes('text/html');
    headers.set('Cache-Control', isHtml ? 'no-store' : 'public, max-age=31536000, immutable');
    headers.set('X-Content-Type-Options', 'nosniff');
    headers.set('X-Frame-Options', 'SAMEORIGIN');
    return new Response(res.body, { status: res.status, headers });
  },
};
