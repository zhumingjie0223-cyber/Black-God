// ============================================================
// 神枢 · Agent Durable Object / ModelRouter
//
// v2：枢语原生 Agent 协议。DO 只保存计划、确认、租约、幂等与审计；
// 真正的能力执行仍由 ShenshuCore 负责，避免状态机成为第二执行脑。
// ============================================================

import {
  AgentRunPhase,
  NexusAgentProtocol,
  isTerminalPhase,
  redactSecrets,
} from './nexus_agent_protocol.mjs';
import { ShuyuBridge } from './nexus_shuyu_bridge.mjs';
import { preflightToolCall } from './nexus_tool_preflight.mjs';

const PHASE = Object.freeze({ IDLE: 'IDLE', DISPATCHING: 'DISPATCHING', WAITING_FOR_INPUT: 'WAITING_FOR_INPUT' });
const LEASE_TTL_MS = Number.isFinite(Number(globalThis?.process?.env?.AGENT_LEASE_TTL_MS)) && Number(globalThis?.process?.env?.AGENT_LEASE_TTL_MS) >= 1000 ? Number(globalThis?.process?.env?.AGENT_LEASE_TTL_MS) : 30_000;
const ALARM_INTERVAL_MS = 5_000;
const RUN_PREFIX = 'agent_run:';
const EFFECT_PREFIX = 'agent_effect:';

export class AgentStateMachineDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.storage = state.storage;
    this.ALARM_INTERVAL = ALARM_INTERVAL_MS;
    this.protocol = new NexusAgentProtocol();
    this.shuyu = new ShuyuBridge();
  }

  async _getPhase() { return (await this.storage.get('phase')) || PHASE.IDLE; }
  async _setPhase(phase) { await this.storage.put('phase', phase); }
  async _getQueue() { return (await this.storage.get('queue')) || []; }
  async _setQueue(queue) { await this.storage.put('queue', queue); }
  async _getLease() { return (await this.storage.get('lease')) || null; }
  async _setLease(lease) { if (lease === null) await this.storage.delete('lease'); else await this.storage.put('lease', lease); }
  _newToken() { return crypto.randomUUID(); }
  async _ensureAlarm() {
    const existing = await this.storage.getAlarm();
    if (existing === null) await this.storage.setAlarm(Date.now() + this.ALARM_INTERVAL);
  }
  _json(obj, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json;charset=utf-8' } }); }
  _runKey(runId) { return RUN_PREFIX + String(runId || ''); }
  _effectKey(effectId) { return EFFECT_PREFIX + String(effectId || ''); }

  _publicRun(run, options = {}) {
    return this.protocol.publicRun(run, options);
  }

  _attachShuyu(run, event) {
    const shu = this.shuyu.encode(event.type, {
      coordinate: run.coordinate || null,
      runId: run.runId,
      effectId: run.effectId,
      capability: run.capability,
      risk: run.risk,
      phase: run.phase,
      params_hash: run.paramsHash,
      data: redactSecrets(event.data || {}),
    });
    return { ...event, shu };
  }

  async _saveRun(run) {
    const { approvalToken: _approvalToken, ...persistedRun } = run;
    const scrubbed = {
      ...persistedRun,
      params: redactSecrets(run.params || {}),
      result: run.result ? redactSecrets(run.result) : null,
      audit: Array.isArray(run.audit) ? run.audit.slice(-80) : [],
    };
    await this.storage.put(this._runKey(run.runId), scrubbed);
    await this.storage.put(this._effectKey(run.effectId), run.runId);
    return scrubbed;
  }

  async _loadRun(runId, expire = true) {
    const run = await this.storage.get(this._runKey(runId));
    if (!run || typeof run !== 'object') return null;
    if (expire && !isTerminalPhase(run.phase) && Number(run.expiresAt || 0) <= Date.now()) {
      const expired = this.protocol.expire(run, 'run_deadline');
      if (expired.event) {
        expired.run.audit = [...(expired.run.audit || []).slice(0, -1), this._attachShuyu(expired.run, expired.event)];
      }
      return this._saveRun(expired.run);
    }
    return run;
  }

  async _transitionAndSave(run, transition) {
    const next = transition.run;
    if (transition.event) next.audit = [...(next.audit || []).slice(0, -1), this._attachShuyu(next, transition.event)];
    return this._saveRun(next);
  }

  async fetch(request) {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();
    const path = url.pathname;
    try {
      // v2 run protocol
      if (method === 'POST' && path.endsWith('/plan')) return await this.handlePlan(request);
      if (method === 'POST' && path.endsWith('/approve')) return await this.handleApprove(request);
      if (method === 'POST' && path.endsWith('/claim')) return await this.handleClaim(request);
      if (method === 'POST' && path.endsWith('/complete')) return await this.handleComplete(request);
      if (method === 'POST' && path.endsWith('/cancel')) return await this.handleCancel(request);
      if (method === 'GET' && (path.endsWith('/run') || path.endsWith('/state'))) return await this.handleState(request);
      if (method === 'GET' && path.endsWith('/audit')) return await this.handleAudit(request);
      // legacy queue protocol; retained for older callers
      if (method === 'POST' && path.endsWith('/enqueue')) return await this.handleEnqueue(request);
      if (method === 'POST' && path.endsWith('/dispatch')) return await this.handleDispatch();
      return this._json({ error: 'not_found' }, 404);
    } catch (err) {
      return this._json({ error: 'internal_error', message: String(err?.message || err).slice(0, 180) }, 500);
    }
  }

  async handlePlan(request) {
    const body = await request.json().catch(() => ({}));
    const capability = String(body.capability || '').trim();
    if (!capability) return this._json({ error: 'capability_required' }, 400);
    const params = body.params && typeof body.params === 'object' && !Array.isArray(body.params) ? body.params : {};
    const role = String(body.role || 'system');
    const preflight = preflightToolCall(capability, params, { phase: 'plan' });
    if (!preflight.ok) return this._json({ error: 'tool_preflight_failed', capability, errors: preflight.errors, warnings: preflight.warnings }, 400);
    const plan = this.protocol.createPlan({
      capability,
      params: preflight.normalized,
      role,
      coordinate: body.coordinate || null,
      requestId: body.idempotencyKey || null,
    });
    const priorId = await this.storage.get(this._effectKey(plan.effectId));
    if (priorId) {
      const prior = await this._loadRun(priorId);
      if (prior) return this._json({ ok: true, reused: true, run: this._publicRun(prior) });
    }
    const created = this.protocol.issueAudit(plan, 'agent.planned', {
      capability: plan.capability,
      risk: plan.risk,
      params_hash: plan.paramsHash,
      approval_required: plan.approvalRequired,
    });
    plan.audit = [this._attachShuyu(plan, created)];
    const saved = await this._saveRun(plan);
    await this._ensureAlarm();
    // 审批 token 只能回到已鉴权的 ShenshuCore 路由，DO 不记录其明文。
    return this._json({
      ok: true,
      run: this._publicRun(saved, { includeApprovalToken: true }),
      approvalToken: plan.approvalToken || null,
    }, 201);
  }

  async handleApprove(request) {
    const body = await request.json().catch(() => ({}));
    const run = await this._loadRun(body.runId);
    if (!run) return this._json({ error: 'run_not_found' }, 404);
    try {
      const saved = await this._transitionAndSave(run, this.protocol.approve(run, body.approvalToken));
      await this._ensureAlarm();
      return this._json({ ok: true, run: this._publicRun(saved) });
    } catch (err) {
      return this._json({ error: String(err?.message || err) }, 409);
    }
  }

  async handleClaim(request) {
    const body = await request.json().catch(() => ({}));
    const run = await this._loadRun(body.runId);
    if (!run) return this._json({ error: 'run_not_found' }, 404);
    try {
      const saved = await this._transitionAndSave(run, this.protocol.claim(run));
      await this._ensureAlarm();
      return this._json({ ok: true, run: this._publicRun(saved), leaseToken: saved.lease?.token || null });
    } catch (err) {
      return this._json({ error: String(err?.message || err) }, 409);
    }
  }

  async handleComplete(request) {
    const body = await request.json().catch(() => ({}));
    if (!body.runId) return this._json({ error: 'run_id_required' }, 400);
    const run = await this._loadRun(body.runId, false);
    if (!run) return this._json({ error: 'run_not_found' }, 404);
    try {
      const saved = await this._transitionAndSave(run, this.protocol.complete(run, body.leaseToken, body.ok !== false, body.result));
      return this._json({ ok: true, run: this._publicRun(saved) });
    } catch (err) {
      return this._json({ error: String(err?.message || err) }, 409);
    }
  }

  async handleCancel(request) {
    const body = await request.json().catch(() => ({}));
    const run = await this._loadRun(body.runId);
    if (!run) return this._json({ error: 'run_not_found' }, 404);
    try {
      const saved = await this._transitionAndSave(run, this.protocol.cancel(run, body.reason));
      return this._json({ ok: true, run: this._publicRun(saved) });
    } catch (err) {
      return this._json({ error: String(err?.message || err) }, 409);
    }
  }

  async handleAudit(request) {
    const run = await this._loadRun(new URL(request.url).searchParams.get('runId'));
    if (!run) return this._json({ error: 'run_not_found' }, 404);
    return this._json({ ok: true, runId: run.runId, audit: redactSecrets(run.audit || []) });
  }

  async handleState(request) {
    const url = new URL(request.url);
    const requested = url.searchParams.get('runId') || url.searchParams.get('id');
    if (requested) {
      const run = await this._loadRun(requested);
      if (!run) return this._json({ error: 'run_not_found' }, 404);
      return this._json({ ok: true, run: this._publicRun(run) });
    }
    const [phase, queue, lease, entries] = await Promise.all([
      this._getPhase(), this._getQueue(), this._getLease(), this.storage.list({ prefix: RUN_PREFIX, limit: 50 }),
    ]);
    const runs = [];
    for (const [, value] of entries) {
      if (value && typeof value === 'object') runs.push(this._publicRun(value, { includeParams: false }));
    }
    return this._json({
      phase,
      queueLength: queue.length,
      queue,
      lease,
      leaseValid: lease ? lease.expiry > Date.now() : false,
      runs: runs.sort((a, b) => b.updatedAt - a.updatedAt),
      now: Date.now(),
    });
  }

  // ---- Legacy queue protocol (backward compatible) ----
  async handleEnqueue(request) {
    const body = await request.json().catch(() => ({}));
    if (body.message === undefined) return this._json({ error: 'missing_message' }, 400);
    const queue = await this._getQueue();
    const item = { id: crypto.randomUUID(), message: body.message, task: body.task || null, enqueuedAt: Date.now() };
    queue.push(item);
    await this._setQueue(queue);
    await this._ensureAlarm();
    return this._json({ ok: true, id: item.id, queueLength: queue.length });
  }

  async handleDispatch() {
    const lease = await this._getLease();
    if (lease && lease.expiry > Date.now()) return this._json({ error: 'lease_held', lease }, 409);
    const queue = await this._getQueue();
    if (queue.length === 0) { await this._setPhase(PHASE.IDLE); return this._json({ error: 'queue_empty', phase: PHASE.IDLE }, 404); }
    const item = queue.shift();
    await this._setQueue(queue);
    const newLease = { token: this._newToken(), itemId: item.id, task: item.task, acquiredAt: Date.now(), expiry: Date.now() + LEASE_TTL_MS };
    await this._setLease(newLease);
    await this._setPhase(PHASE.DISPATCHING);
    await this._ensureAlarm();
    return this._json({ ok: true, phase: PHASE.DISPATCHING, lease: newLease, item, remaining: queue.length });
  }

  async alarm() {
    const lease = await this._getLease();
    const now = Date.now();
    if (lease && lease.expiry <= now) {
      const queue = await this._getQueue();
      if (lease.task !== undefined && lease.task !== null) {
        queue.unshift({ id: lease.itemId, task: lease.task, message: { __requeued: true, reason: 'lease_timeout' }, enqueuedAt: now });
        await this._setQueue(queue);
      }
      await this._setLease(null);
      await this._setPhase(PHASE.IDLE);
    }
    const entries = await this.storage.list({ prefix: RUN_PREFIX, limit: 100 });
    for (const [, candidate] of entries) {
      if (candidate && !isTerminalPhase(candidate.phase) && Number(candidate.expiresAt || 0) <= now) {
        const expired = this.protocol.expire(candidate, 'alarm_deadline');
        if (expired.event) expired.run.audit = [...(expired.run.audit || []).slice(0, -1), this._attachShuyu(expired.run, expired.event)];
        await this._saveRun(expired.run);
      }
    }
    const [queue, currentLease] = await Promise.all([this._getQueue(), this._getLease()]);
    if (queue.length > 0 || currentLease || entries.size > 0) {
      const rawNext = currentLease ? Math.min(currentLease.expiry, now + this.ALARM_INTERVAL) : now + this.ALARM_INTERVAL;
      await this.storage.setAlarm(Math.max(rawNext, now + 1000));
    } else {
      await this._setPhase(PHASE.IDLE);
    }
  }
}

// ---------------------------------------------------------------------------
// ModelRouter — 多模型分档路由，独立于 Agent run 协议。
// ---------------------------------------------------------------------------
export const TIER = Object.freeze({ LITE: 'LITE', ECONOMY: 'ECONOMY', POWER: 'POWER', POWER_TURBO: 'POWER_TURBO' });
export const EffortLevel = Object.freeze({ MINIMAL: 0, LOW: 1, MEDIUM: 2, HIGH: 3, MAX: 4 });
const TIER_ORDER = [TIER.POWER_TURBO, TIER.POWER, TIER.ECONOMY, TIER.LITE];
const DEFAULT_TIER_CONFIG = Object.freeze({
  [TIER.LITE]: { minScore: 0, maxTokens: 4096, costWeight: 1, models: ['qwen3.6-flash'], effortCap: 1 },
  [TIER.ECONOMY]: { minScore: 25, maxTokens: 16384, costWeight: 3, models: ['qwen3.7-max'], effortCap: 2 },
  [TIER.POWER]: { minScore: 55, maxTokens: 65536, costWeight: 8, models: ['claude-opus-4-8'], effortCap: 3 },
  [TIER.POWER_TURBO]: { minScore: 80, maxTokens: 200000, costWeight: 20, models: ['claude-opus-5'], effortCap: 4 },
});

export class ModelRouter {
  constructor(opts = {}) {
    this.config = { ...DEFAULT_TIER_CONFIG, ...(opts.tierConfig || {}) };
    this.availability = opts.availability || (() => true);
    this.budgetLimit = opts.budgetLimit ?? Infinity;
    this.spent = 0;
  }
  _score(req) {
    let score = 0;
    score += Math.min(30, (req.estimatedTokens ?? 0) / 4000 * 30);
    score += (req.complexity ?? 0) * 30;
    score += ((req.effort ?? EffortLevel.MEDIUM) / EffortLevel.MAX) * 25;
    if (req.needsTools) score += 8;
    if (req.needsReasoning) score += 12;
    if (req.priority === 'high') score += 10;
    return Math.max(0, Math.min(100, score));
  }
  _tierForScore(score) { for (const tier of TIER_ORDER) if (score >= this.config[tier].minScore) return tier; return TIER.LITE; }
  _pickModel(tier) { return this.config[tier].models.find((model) => this.availability(model)) || null; }
  route(req = {}) {
    const score = this._score(req);
    const tier = this._tierForScore(score);
    const startIdx = Math.max(0, TIER_ORDER.indexOf(tier));
    for (let i = startIdx; i < TIER_ORDER.length; i++) {
      const candidate = TIER_ORDER[i];
      const config = this.config[candidate];
      if (!config || this.spent + config.costWeight > this.budgetLimit) continue;
      const model = this._pickModel(candidate);
      if (!model) continue;
      const effort = Math.min(req.effort ?? EffortLevel.MEDIUM, config.effortCap);
      this.spent += config.costWeight;
      return { tier: candidate, model, score, effort, maxTokens: config.maxTokens, degraded: candidate !== tier };
    }
    const lite = this.config[TIER.LITE];
    const model = lite?.models?.[0] || null;
    if (lite && this.spent + lite.costWeight <= this.budgetLimit) this.spent += lite.costWeight;
    return { tier: TIER.LITE, model, score, effort: EffortLevel.MINIMAL, maxTokens: lite?.maxTokens ?? 4096, degraded: true, fallback: true };
  }
  resetBudget() { this.spent = 0; }
}
