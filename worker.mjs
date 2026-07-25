/**
 * blackgod88 · Worker 入口
 * 职责：
 *   1. /nx/* → 反向代理到 nexus-do，token 只存 secret，永不下发前端
 *   2. 其余请求 → 交给 CF Assets（静态文件）
 * deploy: 2026-07-25
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    /* ═══ /nx/* → nexus-do 代理；token 只存 secret ═══ */
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

    /* 其余交给静态资产 */
    return env.ASSETS.fetch(request);
  },
};
