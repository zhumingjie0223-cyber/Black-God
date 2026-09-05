// ═══════════════════════════════════════════════════════════════
// 神枢 · 枢语原生 Agent 协议
//
// 目标：让「模型提出意图」与「神枢真实执行副作用」之间存在可持久、
// 可审批、不可重放、可审计的协议边界。该模块不调用模型、不执行能力。
// ═══════════════════════════════════════════════════════════════

export const AgentRunPhase = Object.freeze({
  PLANNED: 'PLANNED',
  AWAITING_APPROVAL: 'AWAITING_APPROVAL',
  APPROVED: 'APPROVED',
  EXECUTING: 'EXECUTING',
  SUCCEEDED: 'SUCCEEDED',
  FAILED: 'FAILED',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED',
});

export const TERMINAL_RUN_PHASES = new Set([
  AgentRunPhase.SUCCEEDED,
  AgentRunPhase.FAILED,
  AgentRunPhase.CANCELLED,
  AgentRunPhase.EXPIRED,
]);

const TRANSITIONS = Object.freeze({
  [AgentRunPhase.PLANNED]: new Set([AgentRunPhase.EXECUTING, AgentRunPhase.CANCELLED, AgentRunPhase.EXPIRED]),
  [AgentRunPhase.AWAITING_APPROVAL]: new Set([AgentRunPhase.APPROVED, AgentRunPhase.CANCELLED, AgentRunPhase.EXPIRED]),
  [AgentRunPhase.APPROVED]: new Set([AgentRunPhase.EXECUTING, AgentRunPhase.CANCELLED, AgentRunPhase.EXPIRED]),
  [AgentRunPhase.EXECUTING]: new Set([AgentRunPhase.SUCCEEDED, AgentRunPhase.FAILED, AgentRunPhase.EXPIRED]),
  [AgentRunPhase.SUCCEEDED]: new Set(),
  [AgentRunPhase.FAILED]: new Set(),
  [AgentRunPhase.CANCELLED]: new Set(),
  [AgentRunPhase.EXPIRED]: new Set(),
});

const SECRET_KEY = /(?:^|[_-])(token|key|secret|password|authorization|cookie|credential|api[_-]?key)(?:$|[_-])/i;
const MAX_AUDIT_STRING = 240;

export function allowedTransition(from, to) {
  return !!TRANSITIONS[from]?.has(to);
}

export function isTerminalPhase(phase) {
  return TERMINAL_RUN_PHASES.has(phase);
}

export function riskForCapability(id = '') {
  const capability = String(id || '').trim();
  if (['exec', 'apple', 'device_control'].includes(capability)) return 'device';
  if (['push', 'tg'].includes(capability)) return 'communicate';
  if (['watch'].includes(capability)) return 'schedule';
  if (['gen_image', 'gen_voice', 'gen_video'].includes(capability)) return 'create';
  return 'read';
}

export function requiresApprovalForRisk(risk) {
  return risk !== 'read';
}

export function stableStringify(value) {
  const seen = new WeakSet();
  const walk = (v) => {
    if (v === null || typeof v !== 'object') {
      if (typeof v === 'string') return v;
      if (typeof v === 'number' || typeof v === 'boolean') return v;
      return v == null ? null : String(v);
    }
    if (seen.has(v)) return '[Circular]';
    seen.add(v);
    if (Array.isArray(v)) return v.map(walk);
    const out = {};
    for (const key of Object.keys(v).sort()) out[key] = walk(v[key]);
    return out;
  };
  return JSON.stringify(walk(value));
}

// 非密钥型稳定指纹，用于幂等与审计关联；不被当作密码哈希或鉴权凭据。
export function stableHash(value) {
  const text = stableStringify(value);
  let h1 = 0x811c9dc5;
  let h2 = 0x9e3779b9;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193) >>> 0;
    h2 = Math.imul(h2 ^ (c + i), 0x85ebca6b) >>> 0;
  }
  return `${h1.toString(36)}${h2.toString(36)}`;
}

export function redactSecrets(value, depth = 0) {
  if (depth > 8) return '[Truncated]';
  if (value == null || typeof value === 'boolean' || typeof value === 'number') return value;
  if (typeof value === 'string') return value.length > MAX_AUDIT_STRING ? `${value.slice(0, MAX_AUDIT_STRING)}…` : value;
  if (Array.isArray(value)) return value.slice(0, 40).map((item) => redactSecrets(item, depth + 1));
  if (typeof value !== 'object') return String(value);
  const out = {};
  for (const [key, item] of Object.entries(value)) {
    out[key] = SECRET_KEY.test(key) ? '[REDACTED]' : redactSecrets(item, depth + 1);
  }
  return out;
}

export function compactResult(value) {
  const safe = redactSecrets(value);
  const text = stableStringify(safe);
  return text.length > 1200 ? `${text.slice(0, 1200)}…` : safe;
}

export class NexusAgentProtocol {
  constructor(options = {}) {
    this.clock = options.clock || Date.now;
    this.randomId = options.randomId || (() => crypto.randomUUID());
    this.approvalTtlMs = Math.max(30_000, options.approvalTtlMs || 5 * 60_000);
    this.executionLeaseMs = Math.max(15_000, options.executionLeaseMs || 2 * 60_000);
  }

  createPlan({ capability, params = {}, role = 'system', coordinate = null, requestId = null } = {}) {
    const now = Number(this.clock()) || Date.now();
    const cap = String(capability || '').trim();
    if (!cap) throw new Error('capability_required');
    if (!params || typeof params !== 'object' || Array.isArray(params)) throw new Error('params_must_be_object');
    const risk = riskForCapability(cap);
    const approvalRequired = requiresApprovalForRisk(risk);
    const runId = `run_${this.randomId()}`;
    const paramsHash = stableHash({ capability: cap, params });
    const effectId = `eff_${stableHash({ role, capability: cap, params, requestId: requestId || runId })}`;
    const approvalToken = approvalRequired ? `apr_${this.randomId()}${this.randomId().replace(/-/g, '')}` : null;
    const phase = approvalRequired ? AgentRunPhase.AWAITING_APPROVAL : AgentRunPhase.PLANNED;
    return {
      version: 1,
      runId,
      effectId,
      capability: cap,
      role: String(role || 'anon'),
      risk,
      approvalRequired,
      phase,
      createdAt: now,
      updatedAt: now,
      expiresAt: approvalRequired ? now + this.approvalTtlMs : now + this.executionLeaseMs,
      coordinate: coordinate && typeof coordinate === 'object' ? coordinate : null,
      params,
      paramsHash,
      // approvalToken 只在 plan 响应中交付给已鉴权调用方；持久态只留校验指纹。
      approvalToken,
      approval: approvalRequired ? {
        tokenHash: stableHash(approvalToken),
        expiresAt: now + this.approvalTtlMs,
        consumedAt: null,
      } : null,
      lease: null,
      result: null,
      audit: [],
    };
  }

  issueAudit(run, type, data = {}) {
    const now = Number(this.clock()) || Date.now();
    return {
      auditId: `aud_${this.randomId()}`,
      type: String(type || 'agent.event'),
      runId: run.runId,
      effectId: run.effectId,
      capability: run.capability,
      risk: run.risk,
      phase: run.phase,
      timestamp: now,
      coordinate: run.coordinate || null,
      data: redactSecrets(data),
    };
  }

  transition(run, to, data = {}) {
    if (!allowedTransition(run.phase, to)) throw new Error(`invalid_transition:${run.phase}:${to}`);
    const now = Number(this.clock()) || Date.now();
    const next = { ...run, phase: to, updatedAt: now };
    const event = this.issueAudit(next, `agent.${String(to).toLowerCase()}`, data);
    next.audit = [...(Array.isArray(run.audit) ? run.audit : []), event].slice(-80);
    return { run: next, event };
  }

  approve(run, approvalToken) {
    const now = Number(this.clock()) || Date.now();
    if (run.phase !== AgentRunPhase.AWAITING_APPROVAL) throw new Error('run_not_awaiting_approval');
    if (!run.approval || run.approval.consumedAt) throw new Error('approval_already_consumed');
    if (run.approval.expiresAt <= now) throw new Error('approval_expired');
    if (stableHash(String(approvalToken || '')) !== String(run.approval.tokenHash || '')) throw new Error('invalid_approval_token');
    const advanced = this.transition(run, AgentRunPhase.APPROVED, { approval: 'owner_confirmed' });
    advanced.run.approval = { ...advanced.run.approval, consumedAt: now, tokenHash: null };
    delete advanced.run.approvalToken;
    return advanced;
  }

  claim(run) {
    const now = Number(this.clock()) || Date.now();
    if (run.phase === AgentRunPhase.AWAITING_APPROVAL) throw new Error('approval_required');
    if (![AgentRunPhase.PLANNED, AgentRunPhase.APPROVED].includes(run.phase)) throw new Error(`run_not_executable:${run.phase}`);
    if (run.expiresAt <= now) throw new Error('run_expired');
    const advanced = this.transition(run, AgentRunPhase.EXECUTING, { execution: 'claimed' });
    advanced.run.lease = {
      token: `lease_${this.randomId()}${this.randomId().replace(/-/g, '')}`,
      expiresAt: now + this.executionLeaseMs,
    };
    return advanced;
  }

  complete(run, leaseToken, ok, result) {
    const now = Number(this.clock()) || Date.now();
    if (run.phase !== AgentRunPhase.EXECUTING) throw new Error('run_not_executing');
    if (!run.lease || run.lease.expiresAt <= now) throw new Error('execution_lease_expired');
    if (String(leaseToken || '') !== String(run.lease.token || '')) throw new Error('invalid_execution_lease');
    const to = ok ? AgentRunPhase.SUCCEEDED : AgentRunPhase.FAILED;
    const advanced = this.transition(run, to, { ok: !!ok, result: compactResult(result) });
    advanced.run.lease = null;
    advanced.run.result = { ok: !!ok, summary: compactResult(result), completedAt: now };
    return advanced;
  }

  cancel(run, reason = 'cancelled') {
    if (isTerminalPhase(run.phase)) throw new Error('run_already_terminal');
    if (run.phase === AgentRunPhase.EXECUTING) throw new Error('run_executing_cannot_cancel');
    const advanced = this.transition(run, AgentRunPhase.CANCELLED, { reason: String(reason).slice(0, 160) });
    advanced.run.lease = null;
    return advanced;
  }

  expire(run, reason = 'deadline') {
    if (isTerminalPhase(run.phase)) return { run, event: null };
    const advanced = this.transition(run, AgentRunPhase.EXPIRED, { reason });
    advanced.run.lease = null;
    return advanced;
  }

  publicRun(run, { includeApprovalToken = false, includeParams = true } = {}) {
    const output = {
      version: run.version,
      runId: run.runId,
      effectId: run.effectId,
      capability: run.capability,
      role: run.role,
      risk: run.risk,
      approvalRequired: run.approvalRequired,
      phase: run.phase,
      createdAt: run.createdAt,
      updatedAt: run.updatedAt,
      expiresAt: run.expiresAt,
      coordinate: run.coordinate || null,
      paramsHash: run.paramsHash,
      result: run.result ? redactSecrets(run.result) : null,
      approval: run.approval ? {
        expiresAt: run.approval.expiresAt,
        consumedAt: run.approval.consumedAt,
        // 令牌仅来自刚创建 plan 的瞬时响应；持久 run 不回显 token 或其 hash。
        ...(includeApprovalToken && run.approvalToken ? { token: run.approvalToken } : {}),
      } : null,
    };
    if (includeParams) output.params = redactSecrets(run.params);
    return output;
  }
}
