/**
 * blackgod88 — 公开版 Worker（合规版）
 * - 速率限制：每 IP+API key 每分钟 20 次
 * - 内容过滤：关键词黑名单
 * - 静态托管：ASSETS binding
 * - build: __BUILD_TIME__
 */

const RL_LIMIT = 20;
const RL_WINDOW = 60;
const BLOCKLIST = [
  /\b(制造|购买|贩卖)\s*(枪支|毒品|爆炸物)/i,
  /(勒索软件|ransomware\s+source)/i,
  /(儿童|未成年).{0,6}(色情|性)/i,
  /(自杀|自残).{0,6}(方法|教程|步骤)/i,
];

async function rlKey(req, apiKey) {
  const ip = req.headers.get('CF-Connecting-IP') || '0.0.0.0';
  const raw = new TextEncoder().encode(`${ip}|${apiKey || 'anon'}`);
  const buf = await crypto.subtle.digest('SHA-256', raw);
  return 'rl:' + [...new Uint8Array(buf)].slice(0, 12).map(b => b.toString(16).padStart(2, '0')).join('');
}

function screenContent(text) {
  const t = String(text || '');
  for (const re of BLOCKLIST) if (re.test(t)) return { blocked: true };
  return { blocked: false };
}

async function guard(request, env, ctx, body, apiKey) {
  if (!env.RATE_LIMIT) return { pass: true, rlHeaders: {} };
  const key = await rlKey(request, apiKey);
  const now = Math.floor(Date.now() / 1000);
  const rec = await env.RATE_LIMIT.get(key, 'json');
  let count = 1, start = now;
  if (rec && now - rec.start < RL_WINDOW) { count = rec.count + 1; start = rec.start; }
  const reset = start + RL_WINDOW;
  await env.RATE_LIMIT.put(key, JSON.stringify({ count, start }), { expirationTtl: RL_WINDOW + 5 });
  const rlHeaders = {
    'X-RateLimit-Limit': String(RL_LIMIT),
    'X-RateLimit-Remaining': String(Math.max(0, RL_LIMIT - count)),
    'X-RateLimit-Reset': String(reset),
  };
  if (count > RL_LIMIT) {
    return new Response(JSON.stringify({ error: { code: 'rate_limited', message: '请求过于频繁，请稍后再试。' } }),
      { status: 429, headers: { 'Content-Type': 'application/json', 'Retry-After': String(Math.max(1, reset - now)), ...rlHeaders } });
  }
  const userText = (body?.messages || []).filter(m => m.role === 'user')
    .map(m => typeof m.content === 'string' ? m.content : (m.content || []).map(p => p.text || '').join(' ')).join('\n');
  if (screenContent(userText).blocked) {
    return new Response(JSON.stringify({ error: { code: 'content_blocked', message: '该请求内容不符合使用政策。' } }),
      { status: 403, headers: { 'Content-Type': 'application/json', ...rlHeaders } });
  }
  return { pass: true, rlHeaders };
}

const HTML_CACHE = 'no-store, must-revalidate';
const ASSET_CACHE = 'public, max-age=31536000, immutable';
const BUILD_TIME = '__BUILD_TIME__';

function decorate(res, { spa = false } = {}) {
  const headers = new Headers(res.headers);
  const isHtml = (res.headers.get('content-type') || '').includes('text/html');
  headers.set('Cache-Control', isHtml || spa ? HTML_CACHE : ASSET_CACHE);
  headers.set('X-Build-Time', BUILD_TIME);
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('X-Frame-Options', 'SAMEORIGIN');
  return new Response(res.body, { status: spa ? 200 : res.status, headers });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // API 代理端点（用户自带key，转发到用户填写的API地址，不暴露任何服务器key）
    if (url.pathname === '/api/chat' && request.method === 'POST') {
      let body;
      try { body = await request.json(); } catch { return new Response('Bad Request', { status: 400 }); }
      const apiKey = request.headers.get('X-Api-Key') || body?.apiKey;
      const g = await guard(request, env, ctx, body, apiKey);
      if (g instanceof Response) return g;
      // 公开版：直接透传到用户自己的API（不经过神枢服务器）
      return new Response(JSON.stringify({ error: { code: 'byok', message: '公开版请直接从前端调用您自己的API。' } }),
        { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    // 静态资源
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405 });
    }
    let asset = await env.ASSETS.fetch(request);
    if (asset.status !== 404) return decorate(asset);
    const last = url.pathname.split('/').pop() || '';
    if (last.includes('.')) return decorate(asset);
    const index = await env.ASSETS.fetch(new Request(new URL('/index.html', url.origin).toString()));
    if (index.status === 404) return decorate(asset);
    return decorate(index, { spa: true });
  },
};
