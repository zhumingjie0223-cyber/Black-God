// nexus_capability_growth.mjs
// Cloudflare Workers 兼容 — 无 Node.js API 依赖

export class CapabilityGrowth {
  constructor() {
    this._caps = Object.create(null);
  }

  get(name) {
    return this._caps[name] || { name, successes: 0, failures: 0, score: 0 };
  }

  grow(name, score) {
    const c = this.get(name);
    c.successes++;
    c.score = (c.score * (c.successes - 1) + score) / c.successes;
    this._caps[name] = c;
    return c;
  }

  fail(name) {
    const c = this.get(name);
    c.failures++;
    this._caps[name] = c;
    return c;
  }

  all() {
    return Object.values(this._caps);
  }
}

export default CapabilityGrowth;
