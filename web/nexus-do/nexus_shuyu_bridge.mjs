const stableStringify = value => {
  const seen = new WeakSet();
  const walk = v => {
    if (!v || typeof v !== 'object') return v;
    if (seen.has(v)) return '[Circular]'; seen.add(v);
    if (Array.isArray(v)) return v.map(walk);
    const out = {}; for (const k of Object.keys(v).sort()) out[k] = walk(v[k]); return out;
  };
  try { return JSON.stringify(walk(value)); } catch (_) { return String(value); }
};

export class ShuyuBridge {
  constructor(runtime = null, options = {}) { this.runtime = runtime; this.clock = options.clock || Date.now; this.seq = 0; this.lastTs = -1; }
  encode(type, data) {
    const ts = Number(this.clock()) || Date.now(); this.seq = ts === this.lastTs ? this.seq + 1 : 0; this.lastTs = ts;
    const node = { shu_id: `${String(type || 'event')}.${ts}.${this.seq}`, type: String(type || 'event'), coordinate: this.hash(data), meaning: data, timestamp: ts };
    return typeof this.runtime?.create === 'function' ? this.runtime.create(node) : node;
  }
  hash(data) {
    const s = stableStringify(data); let a = 2166136261, b = 0x9e3779b9, c = 0x85ebca6b;
    for (let i=0;i<s.length;i++) { const n=s.charCodeAt(i); a=Math.imul(a^n,16777619)>>>0; b=(Math.imul(b^n,2246822519)+(i+1))>>>0; c=Math.imul(c+n+(c<<6)+(c>>>2),3266489917)>>>0; }
    return [a/0xffffffff,b/0xffffffff,c/0xffffffff];
  }
}
export default ShuyuBridge;
