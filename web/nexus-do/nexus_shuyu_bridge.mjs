import { interpret, applyToSoul, compile } from '../../shuyu/nexuslang.js';
import { coinFromCoord, coinFromState, autoCoin, decode } from '../../shuyu/lexicon.js';

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
const clampAxis = (v, max) => {
  const n = Math.floor(Number(v));
  return Number.isFinite(n) ? Math.max(0, Math.min(max - 1, n)) : 0;
};
const copy = v => v == null ? v : JSON.parse(JSON.stringify(v));

export class ShuyuBridge {
  constructor(runtime = null, options = {}) {
    this.runtime = runtime; this.clock = options.clock || Date.now;
    this.seq = 0; this.lastTs = -1;
  }
  encode(type, data = {}) {
    const ts = Number(this.clock()) || Date.now();
    this.seq = ts === this.lastTs ? this.seq + 1 : 0; this.lastTs = ts;
    const source = data && typeof data === 'object' ? data : { value: data };
    const coordinate = this.coordinate(source.coordinate || source.coord || source.current_shu_coord, source);
    const word = coinFromCoord(coordinate);
    const node = {
      shu_id: `${String(type || 'event').replace(/[^\w.-]/g, '_')}.${ts}.${this.seq}`,
      type: String(type || 'event'), coordinate, word: word?.词 || null,
      meaning: word?.义 || word?.汉 || null, data: copy(data), timestamp: ts,
    };
    return typeof this.runtime?.create === 'function' ? this.runtime.create(node) : node;
  }
  coordinate(coord, seed = '') {
    if (coord && typeof coord === 'object') return {
      c: clampAxis(coord.c, 1040), m: clampAxis(coord.m, 180), s: clampAxis(coord.s, 80),
      k: clampAxis(coord.k, 64), p: clampAxis(coord.p, 8),
    };
    const h = this.hash(seed);
    return { c: Math.floor(h[0] * 1040), m: Math.floor(h[1] * 180), s: Math.floor(h[2] * 80), k: Math.floor(h[3] * 64), p: Math.floor(h[4] * 8) };
  }
  hash(data) {
    const s = stableStringify(data); let a = 2166136261, b = 0x9e3779b9, c = 0x85ebca6b, d = 0x27d4eb2d, e = 0x165667b1;
    for (let i = 0; i < s.length; i++) { const n = s.charCodeAt(i); a=Math.imul(a^n,16777619)>>>0; b=(Math.imul(b^n,2246822519)+(i+1))>>>0; c=Math.imul(c+n+(c<<6)+(c>>>2),3266489917)>>>0; d=Math.imul(d^n,668265263)>>>0; e=Math.imul(e+n,374761393)>>>0; }
    return [a/0xffffffff,b/0xffffffff,c/0xffffffff,d/0xffffffff,e/0xffffffff];
  }
  interpret(code, soul = {}) { return interpret(String(code || ''), soul || {}); }
  apply(result, soul = {}) { return applyToSoul(result || {}, soul || {}); }
  compile(result) { return compile(result || {}); }
  coin(coord) { return coinFromCoord(this.coordinate(coord)); }
  coinFromState(soul, seed) { return coinFromState(soul || {}, seed); }
  autoCoin(seed) { return autoCoin(seed); }
  decode(id) { return decode(id); }
}
export default ShuyuBridge;
