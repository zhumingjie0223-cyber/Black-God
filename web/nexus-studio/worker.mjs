// ═══════════════════════════════════════════════
// 神枢 · 自主智能体工作台 —— Cloudflare Worker 后端
// 让线上 studio.html 真正能跑：规划 → 真联网搜索 → token 流式 → 交付。
// 模型走 Workers AI 绑定（Llama 3.3 70B，CF 原生，无外部依赖）。
// 事件与 Python 内核一致：task/plan/tool_call/tool_result/token/deliverable/done。
// ═══════════════════════════════════════════════
const MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
  });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const p = url.pathname;

    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    if (p === "/api/health")
      return json({ ok: true, engine: "nexus-studio", model: MODEL, edge: true });

    // 无服务端持久化：历史留空，交付物由前端 blob 下载
    if (p === "/api/tasks") return json({ tasks: [] });

    if (p === "/api/agent/stream" && request.method === "POST")
      return agentStream(request, env);

    // 其余交给静态资源（studio UI）
    if (env.ASSETS) return env.ASSETS.fetch(request);
    return json({ error: "not found", path: p }, 404);
  },
};

// ── 自主智能体：规划 → 搜索 → 流式交付 ──
function agentStream(request, env) {
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const enc = new TextEncoder();
  const send = (o) => writer.write(enc.encode(`data: ${JSON.stringify(o)}\n\n`));

  (async () => {
    const t0 = Date.now();
    const taskId = crypto.randomUUID().slice(0, 12);
    try {
      const body = await request.json().catch(() => ({}));
      const goal = (body.goal || body.message || "").trim();
      if (!goal) {
        await send({ event: "error", message: "goal is required" });
        return;
      }
      await send({ event: "task", task_id: taskId, goal });

      // 1) 规划
      const plan = await makePlan(env, goal);
      await send({ event: "plan", task_id: taskId, steps: plan.steps, deliverable: plan.deliverable });

      // 2) 真联网搜索（工具步骤，失败不致命）
      await send({ event: "tool_call", task_id: taskId, step: 1, tool: "web_search", args: { query: goal } });
      const search = await webSearch(goal);
      await send({ event: "tool_result", task_id: taskId, step: 1, tool: "web_search", result: search.slice(0, 1500) });

      // 3) 流式产出交付物
      const sys =
        "你是神枢·自主智能体。基于任务计划与联网检索到的资料，产出结构清晰、可直接使用的中文交付物。" +
        "用 Markdown，含标题与要点列表，实事求是，不编造。";
      const usr =
        `目标：${goal}\n\n任务计划：\n${plan.steps.map((s, i) => `${i + 1}. ${s}`).join("\n")}\n\n` +
        `联网检索资料：\n${search || "（本次未取得外部资料，基于常识作答）"}\n\n请给出最终交付物。`;

      let full = "";
      const aiStream = await env.AI.run(MODEL, {
        stream: true,
        messages: [{ role: "system", content: sys }, { role: "user", content: usr }],
      });
      for await (const piece of sseTokens(aiStream)) {
        full += piece;
        await send({ event: "token", task_id: taskId, step: 2, text: piece });
      }
      if (!full) full = "（模型未返回内容，请重试。）";

      await send({ event: "deliverable", task_id: taskId, content: full, artifacts: [] });
      await send({
        event: "done",
        task_id: taskId,
        steps_used: 1,
        usage: { total_tokens: 0 },
        elapsed_sec: Math.round((Date.now() - t0) / 100) / 10,
      });
    } catch (e) {
      await send({ event: "error", task_id: taskId, message: String(e && e.message ? e.message : e) });
    } finally {
      await writer.close();
    }
  })();

  return new Response(readable, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      "X-Accel-Buffering": "no",
      ...CORS,
    },
  });
}

// 让模型把目标拆成 3–7 步计划（JSON）。失败降级为单步。
async function makePlan(env, goal) {
  const sys =
    "你是自主任务规划器。把目标拆成 3–7 个具体、可执行、有序的步骤，并说明最终交付物。" +
    '只输出 JSON，不要多余文字：{"steps":["步骤1","步骤2"],"deliverable":"最终交付物一句话"}';
  let steps = [], deliverable = "";
  try {
    const r = await env.AI.run(MODEL, {
      messages: [{ role: "system", content: sys }, { role: "user", content: goal }],
    });
    const text = (r && (r.response || r.result || "")) + "";
    const data = extractJson(text);
    steps = (data.steps || []).map((s) => String(s).trim()).filter(Boolean).slice(0, 7);
    deliverable = String(data.deliverable || "").trim();
  } catch (_) {}
  if (!steps.length) steps = [`理解目标并直接完成：${goal.slice(0, 60)}`];
  return { steps, deliverable };
}

function extractJson(text) {
  if (!text) return {};
  let t = String(text).trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]+?)```/);
  if (fence) t = fence[1].trim();
  const a = t.indexOf("{"), b = t.lastIndexOf("}");
  if (a !== -1 && b !== -1 && b > a) t = t.slice(a, b + 1);
  try { return JSON.parse(t); } catch (_) { return {}; }
}

// DuckDuckGo HTML 轻量检索（Worker 内 fetch），失败返回空串。
async function webSearch(query) {
  try {
    const resp = await fetch("https://html.duckduckgo.com/html/?q=" + encodeURIComponent(query), {
      headers: { "User-Agent": "Mozilla/5.0", "Accept-Language": "zh-CN,zh;q=0.9" },
      cf: { cacheTtl: 60 },
    });
    if (!resp.ok) return "";
    const html = await resp.text();
    const out = [];
    const re = /class="result__snippet"[^>]*>([\s\S]*?)<\/a>/g;
    let m;
    while ((m = re.exec(html)) && out.length < 6) {
      const txt = m[1].replace(/<[^>]+>/g, "").replace(/&[a-z]+;/g, " ").trim();
      if (txt) out.push(`${out.length + 1}. ${txt.slice(0, 220)}`);
    }
    return out.join("\n");
  } catch (_) {
    return "";
  }
}

// 把 Workers AI 的流式响应（SSE: data: {"response":"..."}）解析成 token 生成器。
async function* sseTokens(stream) {
  const reader = stream.getReader();
  const dec = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf("\n")) !== -1) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (data === "[DONE]") return;
      try {
        const obj = JSON.parse(data);
        if (obj.response) yield obj.response;
      } catch (_) {}
    }
  }
}
