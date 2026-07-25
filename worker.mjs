/**
 * blackgod88 · Worker 入口 v2
 * /nx/* → 反向代理到 nexus-do，OWNER_TOKEN 只存 secret
 * 其余 → 转发到自身静态资产（不依赖 ASSETS binding）
 * build: __BUILD_TIME__
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    /* ═══ /nx/* → nexus-do 代理 ═══ */
    if (url.pathname.startsWith('/nx/')) {
      const upstream = 'https://nexus-do.jjiebbay.workers.dev'
                     + url.pathname.slice(3) + url.search;

      const init = {
        method: request.method,
        headers: {
          'authorization': 'Bearer ' + (env.OWNER_TOKEN || ''),
          'content-type': request.headers.get('content-type') || 'application/json',
        },
      };
      if (!['GET', 'HEAD'].includes(request.method)) {
        init.body = await request.text();
      }

      const r = await fetch(upstream, init);
      return new Response(await r.text(), {
        status: r.status,
        headers: {
          'content-type': r.headers.get('content-type') || 'application/json; charset=utf-8',
          'access-control-allow-origin': '*',
          'cache-control': 'no-store',
        },
      });
    }

    /* 其余交给 ASSETS */
    return env.ASSETS.fetch(request);
  },
};
