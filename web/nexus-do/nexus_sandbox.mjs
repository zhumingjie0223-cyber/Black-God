/**
 * 神枢 Nexus · E2B 沙箱执行层
 * nexus_sandbox.mjs
 *
 * 底座：E2B SDK (@e2b/code-interpreter 或 e2b)
 * 部署：Cloudflare Workers — 在 package.json 加 "e2b": "^2.35.0"
 *
 * wrangler.toml 里要有：
 *   [vars]
 *   E2B_API_KEY = ""   # 用 wrangler secret put E2B_API_KEY 注入
 */

// ─── CF Workers 兼容的 E2B REST 封装（管理层走 REST，执行层走 envd）───
// E2B management API: https://api.e2b.dev（REST，X-API-Key 认证）
// E2B envd API: https://49983-{sandboxID}.e2b.dev（connectrpc，Authorization: Basic）

const MGMT_API   = 'https://api.e2b.dev';
const ENVD_PORT  = 49983;
const DOMAIN     = 'e2b.dev';

/**
 * 管理层：创建/列出/删除沙箱（纯 REST，CF Workers 直接 fetch）
 */
async function mgmtReq(apiKey, method, path, body) {
  const resp = await fetch(`${MGMT_API}${path}`, {
    method,
    headers: {
      'X-API-Key':    apiKey,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await resp.text();
  if (!resp.ok) throw new Error(`E2B API ${resp.status}: ${text}`);
  return text ? JSON.parse(text) : {};
}

/**
 * envd 执行层：走 connectrpc JSON 协议（CF Workers 支持）
 * Content-Type: application/connect+json
 */
async function envdReq(sandboxId, rpcPath, body) {
  const url = `https://${ENVD_PORT}-${sandboxId}.${DOMAIN}${rpcPath}`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type':              'application/connect+json',
      'Connect-Protocol-Version': '1',
      'Authorization':             'Basic dXNlcjo=',  // base64("user:")
    },
    body: JSON.stringify(body ?? {}),
  });
  // connectrpc 流式响应：按行读
  const text = await resp.text();
  if (!resp.ok) throw new Error(`envd ${resp.status}: ${text}`);
  return text;
}

/**
 * 执行命令并收集输出（轮询 connectrpc 流式结果）
 * process.Process/Start → 服务端流，每行一个 JSON 事件
 */
async function execCommand(sandboxId, cmd, timeoutMs = 30000) {
  const url = `https://${ENVD_PORT}-${sandboxId}.${DOMAIN}/process.Process/Start`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type':              'application/connect+json',
      'Connect-Protocol-Version': '1',
      'Authorization':             'Basic dXNlcjo=',
    },
    body: JSON.stringify({ tag: { cmd }, envs: {}, user: 'user' }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  const text = await resp.text();
  // 每行是一个 JSON 事件，收集 stdout/stderr/exit
  const stdout = [], stderr = [];
  let exitCode = 0;

  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const ev = JSON.parse(line);
      const event = ev.event;
      if (!event) continue;
      if (event.data?.stdout) stdout.push(event.data.stdout);
      if (event.data?.stderr) stderr.push(event.data.stderr);
      if (event.end?.exitCode !== undefined) exitCode = event.end.exitCode;
      if (event.start?.pid) {}  // 进程起来了
    } catch { /* 忽略非 JSON 行（connectrpc 帧头等）*/ }
  }

  return {
    stdout:   stdout.join(''),
    stderr:   stderr.join(''),
    exitCode,
    rawLines: text.split('\n').filter(Boolean).length,
  };
}

/**
 * 写文件（filesystem.Filesystem/Write）
 */
async function writeFile(sandboxId, path, content) {
  const url = `https://${ENVD_PORT}-${sandboxId}.${DOMAIN}/filesystem.Filesystem/Write`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type':              'application/connect+json',
      'Connect-Protocol-Version': '1',
      'Authorization':             'Basic dXNlcjo=',
    },
    body: JSON.stringify({ path, content: btoa(content) }),  // content = base64
  });
  return resp.ok;
}

/**
 * 读文件（filesystem.Filesystem/Read）
 */
async function readFile(sandboxId, path) {
  const url = `https://${ENVD_PORT}-${sandboxId}.${DOMAIN}/filesystem.Filesystem/Read`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type':              'application/connect+json',
      'Connect-Protocol-Version': '1',
      'Authorization':             'Basic dXNlcjo=',
    },
    body: JSON.stringify({ path }),
  });
  const data = await resp.json();
  // content 是 base64
  return data.content ? atob(data.content) : '';
}

/**
 * NexusSandboxPool：沙箱池（按 session 复用）
 */
export class NexusSandboxPool {
  #pool   = new Map();  // sessionId → sandboxId
  #apiKey;

  constructor(apiKey) {
    this.#apiKey = apiKey;
  }

  async acquire(sessionId, templateId = 'base') {
    if (this.#pool.has(sessionId)) {
      const sid = this.#pool.get(sessionId);
      // 验证还活着
      try {
        const list = await mgmtReq(this.#apiKey, 'GET', '/sandboxes');
        if (list.some(s => s.sandboxID === sid)) {
          // 续命
          await mgmtReq(this.#apiKey, 'POST', `/sandboxes/${sid}/refreshes`, { duration: 300 });
          return sid;
        }
      } catch { /* 死了，重建 */ }
      this.#pool.delete(sessionId);
    }

    const sb = await mgmtReq(this.#apiKey, 'POST', '/sandboxes', {
      templateID: templateId,
      timeout:    300,
    });
    this.#pool.set(sessionId, sb.sandboxID);
    return sb.sandboxID;
  }

  async release(sessionId) {
    const sid = this.#pool.get(sessionId);
    if (sid) {
      await mgmtReq(this.#apiKey, 'DELETE', `/sandboxes/${sid}`).catch(() => {});
      this.#pool.delete(sessionId);
    }
  }

  async listAll() {
    return mgmtReq(this.#apiKey, 'GET', '/sandboxes');
  }
}

// ─── CF Workers HTTP 路由 ────────────────────────────────────────────────────
//
// nexus_do.core.mjs 里接入：
//   import { NexusSandboxPool, handleSandboxExec, handleSandboxFile,
//            handleSandboxList, handleSandboxKill, handleSandboxRunning } from './nexus_sandbox.mjs';
//
//   // DO 类构造函数里：
//   this.sandbox = new NexusSandboxPool(env.E2B_API_KEY);
//
//   // 路由 switch 里加：
//   case '/sandbox/exec':    return handleSandboxExec(request, env, ctx, this.sandbox);
//   case '/sandbox/file':    return handleSandboxFile(request, env, ctx, this.sandbox);
//   case '/sandbox/list':    return handleSandboxList(request, env, ctx, this.sandbox);
//   case '/sandbox/kill':    return handleSandboxKill(request, env, ctx, this.sandbox);
//   case '/sandbox/running': return handleSandboxRunning(request, env, ctx, this.sandbox);

function getSessionId(request) {
  return request.headers.get('X-Session-Id') ?? 'owner-default';
}

/** POST /sandbox/exec  { cmd, template?, timeout? } */
export async function handleSandboxExec(request, env, ctx, pool) {
  const { cmd, template, timeout } = await request.json();
  if (!cmd) return new Response('cmd required', { status: 400 });

  const sessionId = getSessionId(request);
  const sandboxId = await pool.acquire(sessionId, template);
  const result    = await execCommand(sandboxId, cmd, timeout ?? 30000);

  return Response.json({ sandboxId, ...result });
}

/** POST /sandbox/file { path, content } 写 | GET /sandbox/file?path=xxx 读 */
export async function handleSandboxFile(request, env, ctx, pool) {
  const sessionId = getSessionId(request);
  const sandboxId = await pool.acquire(sessionId);

  if (request.method === 'GET') {
    const path    = new URL(request.url).searchParams.get('path') ?? '/';
    const content = await readFile(sandboxId, path);
    return new Response(content, { headers: { 'Content-Type': 'text/plain' } });
  }

  const { path, content } = await request.json();
  if (!path) return new Response('path required', { status: 400 });
  await writeFile(sandboxId, path, content ?? '');
  return Response.json({ ok: true, sandboxId, path });
}

/** GET /sandbox/list?path=/ */
export async function handleSandboxList(request, env, ctx, pool) {
  const path      = new URL(request.url).searchParams.get('path') ?? '/home/user';
  const sessionId = getSessionId(request);
  const sandboxId = await pool.acquire(sessionId);

  const url  = `https://${ENVD_PORT}-${sandboxId}.${DOMAIN}/filesystem.Filesystem/ListDir`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/connect+json',
      'Connect-Protocol-Version': '1',
      'Authorization': 'Basic dXNlcjo=',
    },
    body: JSON.stringify({ path }),
  });
  const data = await resp.json();
  return Response.json({ sandboxId, files: data.entries ?? data });
}

/** DELETE /sandbox/kill */
export async function handleSandboxKill(request, env, ctx, pool) {
  const sessionId = getSessionId(request);
  await pool.release(sessionId);
  return Response.json({ ok: true });
}

/** GET /sandbox/running */
export async function handleSandboxRunning(request, env, ctx, pool) {
  return Response.json(await pool.listAll());
}

// ─── wrangler secret 配置说明 ────────────────────────────────────────────────
// wrangler secret put E2B_API_KEY
// 输入：e2b_a735c6a59efc53b0acf22c74f468810459cf6bbd
//
// wrangler.toml 加路由白名单（如有 capsec）：
// PRIVATE_PATHS = [..., "/sandbox/exec", "/sandbox/file", "/sandbox/list",
//                  "/sandbox/kill", "/sandbox/running"]
