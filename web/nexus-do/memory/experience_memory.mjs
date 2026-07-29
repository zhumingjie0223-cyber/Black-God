const clamp = v => Math.max(0, Math.min(1, Number.isFinite(Number(v)) ? Number(v) : 0.5));
const clone = v => v == null ? v : JSON.parse(JSON.stringify(v));

export class ExperienceMemory {
  constructor(state = [], options = {}) {
    const records = Array.isArray(state) ? state : (Array.isArray(state?.records) ? state.records : []);
    this.records = records.map(clone); this.maxRecords = Math.max(10, options.maxRecords || 300); this.clock = options.clock || Date.now; this.seq = 0; this.lastTs = -1; this._trim();
  }
  remember(data = {}) {
    if (!data || typeof data !== 'object') return null;
    const ts = Number(this.clock()) || Date.now(); this.seq = ts === this.lastTs ? this.seq + 1 : 0; this.lastTs = ts;
    const item = { id: data.id || `${ts}.${this.seq}`, ...clone(data), timestamp: data.timestamp || ts, confidence: clamp(data.confidence) };
    const i = this.records.findIndex(x => x.id === item.id); i >= 0 ? this.records.splice(i, 1, item) : this.records.push(item); this._trim(); return clone(item);
  }
  search(concept, filter = null) { return this.records.filter(x => (!concept || x.concept === concept) && (!filter || filter(x))).map(clone); }
  reinforce(id, value = 0.1) { const item = this.records.find(x => x.id === id); if (!item) return null; item.confidence = clamp(item.confidence + Number(value || 0)); item.reinforced = this.clock(); return clone(item); }
  clear() { this.records = []; }
  export() { return { records: clone(this.records) }; }
  _trim() { if (this.records.length > this.maxRecords) this.records.splice(0, this.records.length - this.maxRecords); }
}
export default ExperienceMemory;
