const clamp = v => Math.max(0, Math.min(1, Number.isFinite(Number(v)) ? Number(v) : 0.5));
const safeId = v => { const s = String(v ?? '').trim(); return s && s !== '__proto__' && s !== 'prototype' && s !== 'constructor' ? s : ''; };
const clone = v => v == null ? v : JSON.parse(JSON.stringify(v));

export class WorldGraph {
  constructor(state = {}, options = {}) {
    this.maxEntities = Math.max(10, options.maxEntities || 300);
    this.maxRelations = Math.max(10, options.maxRelations || 600);
    this.clock = options.clock || Date.now;
    this.entities = Object.create(null); this.relations = [];
    const entities = state?.entities && typeof state.entities === 'object' ? state.entities : {};
    for (const [id, entity] of Object.entries(entities)) if (safeId(id)) this.entities[id] = clone(entity);
    if (Array.isArray(state?.relations)) this.relations = state.relations.filter(x => safeId(x?.from) && safeId(x?.to) && safeId(x?.relation)).map(clone);
    this._trim();
  }
  addEntity(entity = {}) {
    const id = safeId(entity.id); if (!id) return null;
    const old = this.entities[id] || {};
    this.entities[id] = { ...old, ...clone(entity), id, confidence: clamp(entity.confidence ?? old.confidence), updated: this.clock() };
    this._trim(); return clone(this.entities[id]);
  }
  connect(from, to, relation, confidence = 0.5, meta = {}) {
    from = safeId(from); to = safeId(to); relation = safeId(relation); if (!from || !to || !relation) return null;
    const key = x => x.from === from && x.to === to && x.relation === relation;
    const item = this.relations.find(key); const next = { ...(item || {}), ...clone(meta), from, to, relation, confidence: clamp(confidence), updated: this.clock() };
    if (item) Object.assign(item, next); else this.relations.push(next);
    this._trim(); return clone(next);
  }
  removeEntity(id) { id = safeId(id); if (!id || !this.entities[id]) return false; delete this.entities[id]; this.relations = this.relations.filter(x => x.from !== id && x.to !== id); return true; }
  findCause(target) { target = safeId(target); return this.relations.filter(x => x.to === target).sort((a,b) => b.confidence-a.confidence || b.updated-a.updated).map(clone); }
  predict(id) { id = safeId(id); return this.entities[id] ? clone(this.entities[id]) : null; }
  clear() { this.entities = Object.create(null); this.relations = []; }
  get size() { return { entities: Object.keys(this.entities).length, relations: this.relations.length }; }
  export() { return clone({ entities: this.entities, relations: this.relations }); }
  _trim() {
    const ids = Object.keys(this.entities); if (ids.length > this.maxEntities) for (const id of ids.sort((a,b) => (this.entities[a].updated||0)-(this.entities[b].updated||0)).slice(0, ids.length-this.maxEntities)) this.removeEntity(id);
    if (this.relations.length > this.maxRelations) this.relations.sort((a,b)=>(a.updated||0)-(b.updated||0)).splice(0, this.relations.length-this.maxRelations);
  }
}
export default WorldGraph;
