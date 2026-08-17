import { CapabilityGrowth } from './capabilities.mjs';

export class SelfImprove {
  constructor(opts = {}) {
    this.threshold = opts.threshold ?? 0.7;
    this.capabilities = opts.capabilities || new CapabilityGrowth();
    this.bus = opts.bus || opts.eventBus || null;
    this.memory = opts.memory || null;
  }

  _emit(event, payload) {
    if (!this.bus) return;
    if (typeof this.bus.emit === 'function') {
      this.bus.emit(event, payload);
    } else if (typeof this.bus.dispatchEvent === 'function') {
      try { this.bus.dispatchEvent(new CustomEvent(event, { detail: payload })); } catch (_) {}
    }
  }

  async improve(err, context = {}) {
    const { result, capability } = context;
    const score = Number(result?.score);

    if (!Number.isFinite(score)) {
      this._emit('improvement.skipped', { capability, reason: 'invalid-score' });
      return { applied: false, reason: 'invalid-score' };
    }

    if (score >= this.threshold) {
      const state = this.capabilities?.recordGrowth({ capability, score });
      const record = {
        applied: true,
        capability,
        score,
        state,
        error: err ? String(err?.message ?? err) : null,
        at: Date.now(),
      };
      if (this.memory?.remember) {
        try { this.memory.remember('improvement', { capability, score, error: record.error }); } catch (_) {}
      }
      this._emit('improvement.applied', record);
      return record;
    }

    this._emit('improvement.rejected', { capability, score, threshold: this.threshold });
    return { applied: false, reason: 'below-threshold', score, threshold: this.threshold };
  }
}

export default SelfImprove;
