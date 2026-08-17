// Nexus Blackboard — Cloudflare Durable Object compatible, pure ESM, no deps.

export class Blackboard {
  constructor() {
    this.entries = [];
  }

  write(key, { value, source, confidence, agentId, timestamp } = {}) {
    const entry = {
      key,
      value,
      source: source ?? null,
      confidence: typeof confidence === "number" ? confidence : 0.5,
      agentId: agentId ?? "anonymous",
      timestamp: timestamp ?? Date.now(),
    };
    this.entries.push(entry);
    return entry;
  }

  read(predFn) {
    if (typeof predFn !== "function") return this.getAll();
    return this.entries.filter(predFn);
  }

  getAll() {
    return this.entries.slice();
  }

  // Returns entries sharing a key but written by different agents.
  conflict(key) {
    const forKey = this.entries.filter((e) => e.key === key);
    const agents = new Set(forKey.map((e) => e.agentId));
    if (agents.size <= 1) return [];
    return forKey;
  }

  // Convenience: all keys that have cross-agent conflicts.
  allConflicts() {
    const byKey = new Map();
    for (const e of this.entries) {
      if (!byKey.has(e.key)) byKey.set(e.key, []);
      byKey.get(e.key).push(e);
    }
    const out = {};
    for (const [key, list] of byKey) {
      const agents = new Set(list.map((e) => e.agentId));
      if (agents.size > 1) out[key] = list;
    }
    return out;
  }
}

export class TaskGraphRunner {
  constructor({ lowConfidence = 0.4 } = {}) {
    this.lowConfidence = lowConfidence;
  }

  // Break a goal into a four-stage graph.
  plan(goal) {
    const facets = this._facets(goal);
    return {
      goal,
      planner: {
        stage: "planner",
        goal,
        createdAt: Date.now(),
      },
      workers: facets.map((facet, i) => ({
        stage: "worker",
        id: `worker-${i}`,
        facet,
        run: async (blackboard) => {
          const confidence = 0.5 + ((i * 7) % 5) / 10; // deterministic-ish spread
          const result = {
            key: facet,
            value: `Findings on "${facet}" for goal: ${goal}`,
            source: `worker-${i}`,
            confidence: Math.min(0.95, confidence),
            agentId: `worker-${i}`,
            timestamp: Date.now(),
          };
          blackboard.write(result.key, result);
          return result;
        },
      })),
      verifier: { stage: "verifier" },
      synthesizer: { stage: "synthesizer" },
    };
  }

  _facets(goal) {
    const base = String(goal || "goal").trim();
    const words = base.split(/\s+/).filter(Boolean);
    const facets = [
      `context: ${base}`,
      `evidence: ${base}`,
      `risks: ${base}`,
    ];
    if (words.length > 3) facets.push(`alternatives: ${base}`);
    return facets;
  }

  // Run all workers in parallel; results land on the blackboard.
  async dispatch(workers, blackboard) {
    const results = await Promise.all(
      workers.map((w) =>
        Promise.resolve()
          .then(() => w.run(blackboard))
          .catch((err) => ({ error: String(err), id: w.id }))
      )
    );
    return results;
  }

  // Inspect the blackboard for conflicts and low-confidence entries.
  verify(blackboard) {
    const all = blackboard.getAll();
    const conflicts = blackboard.allConflicts();
    const lowConfidence = all.filter((e) => e.confidence < this.lowConfidence);
    return {
      ok: Object.keys(conflicts).length === 0 && lowConfidence.length === 0,
      conflicts,
      lowConfidence,
      total: all.length,
    };
  }

  // Merge blackboard content into a final answer.
  synthesize(blackboard) {
    const all = blackboard.getAll();
    const byKey = new Map();
    for (const e of all) {
      const prev = byKey.get(e.key);
      if (!prev || e.confidence > prev.confidence) byKey.set(e.key, e);
    }
    const sections = [...byKey.values()].sort(
      (a, b) => b.confidence - a.confidence
    );
    const answer = sections
      .map((s) => `• [${s.confidence.toFixed(2)}] ${s.key}: ${s.value}`)
      .join("\n");
    const avg =
      sections.length === 0
        ? 0
        : sections.reduce((s, e) => s + e.confidence, 0) / sections.length;
    return {
      answer,
      sections,
      confidence: Number(avg.toFixed(3)),
      timestamp: Date.now(),
    };
  }

  async runGoal(goal) {
    const blackboard = new Blackboard();
    const graph = this.plan(goal);
    const dispatched = await this.dispatch(graph.workers, blackboard);
    const verification = this.verify(blackboard);
    const synthesis = this.synthesize(blackboard);
    return { goal, dispatched, verification, synthesis };
  }
}

// ---- HTTP handlers ----

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function readJson(req) {
  try {
    return await req.json();
  } catch {
    return {};
  }
}

// Shared blackboard singleton per DO instance module scope fallback.
const _sharedBoard = new Blackboard();

export async function handleBlackboardWrite(req, env, board = _sharedBoard) {
  const { key, value, source, confidence, agentId, timestamp } =
    await readJson(req);
  if (!key) return json({ error: "missing key" }, 400);
  const entry = board.write(key, {
    value,
    source,
    confidence,
    agentId,
    timestamp,
  });
  return json({ ok: true, entry });
}

export async function handleBlackboardRead(req, env, board = _sharedBoard) {
  const url = new URL(req.url);
  const key = url.searchParams.get("key");
  const minConf = url.searchParams.get("minConfidence");
  const agentId = url.searchParams.get("agentId");
  const pred = (e) => {
    if (key && e.key !== key) return false;
    if (agentId && e.agentId !== agentId) return false;
    if (minConf != null && e.confidence < Number(minConf)) return false;
    return true;
  };
  const entries = board.read(pred);
  const conflicts = key ? board.conflict(key) : board.allConflicts();
  return json({ ok: true, entries, conflicts });
}

export async function handleTaskRun(req, env) {
  const { goal } = await readJson(req);
  if (!goal) return json({ error: "missing goal" }, 400);
  const runner = new TaskGraphRunner();
  const result = await runner.runGoal(goal);
  return json({ ok: true, ...result });
}