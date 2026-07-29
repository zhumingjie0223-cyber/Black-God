const clamp = v => Math.max(0, Math.min(1, Number.isFinite(Number(v)) ? Number(v) : 0));
export class SelfImprove {
  constructor(options = {}) { Object.assign(this, { eventBus: null, memory: null, capabilities: null, threshold: 0.8, clock: Date.now }, options); }
  reflect(error, context = {}) { return { problem: String(error?.message || error || 'unknown'), context, timestamp: this.clock() }; }
  propose(issue) { return { target: issue.problem, action: 'strategy_update', hypothesis: issue.context?.hypothesis || `avoid:${issue.problem.slice(0,80)}`, confidence: 0.5, issue }; }
  async test(plan, verifier) {
    try {
      const raw = typeof verifier === 'function' ? await verifier(plan) : verifier;
      const score = typeof raw === 'number' ? raw : (raw?.score ?? (raw?.ok === true ? 1 : 0));
      return { ...plan, score: clamp(score), verified: !!raw, evidence: raw && typeof raw === 'object' ? raw : null };
    } catch (error) { return { ...plan, score: 0, verified: false, error: String(error?.message || error) }; }
  }
  async improve(error, options = {}) {
    const issue = this.reflect(error, options.context || {}), plan = this.propose(issue), result = await this.test(plan, options.verifier ?? options.result);
    const applied = result.verified && result.score >= this.threshold;
    const record = { concept: 'self_improvement', problem: issue.problem, action: plan.action, applied, score: result.score, confidence: result.score, timestamp: this.clock() };
    try { this.memory?.remember(record); } catch (_) {}
    if (applied) { try { await this.capabilities?.recordGrowth?.({ capability: options.capability || plan.target, score: result.score, evidence: result.evidence }); } catch (_) {} }
    try { await this.eventBus?.emit(applied ? 'improvement.applied' : 'improvement.rejected', { ...result, applied }); } catch (_) {}
    return { applied, issue, plan, result };
  }
}
export default SelfImprove;
