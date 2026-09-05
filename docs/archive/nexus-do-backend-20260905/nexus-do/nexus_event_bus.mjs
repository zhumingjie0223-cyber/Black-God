export class EventBus {
  constructor() { this.listeners = new Map(); }
  on(event, handler) {
    if ((!event && event !== 0) || typeof handler !== 'function') throw new TypeError('invalid event listener');
    let set = this.listeners.get(event); if (!set) this.listeners.set(event, set = new Set());
    const entry = { handler, once: false }; set.add(entry);
    let active = true;
    return () => { if (!active) return false; active = false; const cur = this.listeners.get(event); if (!cur) return false; const ok = cur.delete(entry); if (!cur.size) this.listeners.delete(event); return ok; };
  }
  once(event, handler) {
    const off = this.on(event, handler);
    const set = this.listeners.get(event); const entry = [...set][set.size - 1]; entry.once = true;
    return off;
  }
  off(event, handler) {
    const set = this.listeners.get(event); if (!set) return false;
    let removed = false; for (const e of set) if (!handler || e.handler === handler) { set.delete(e); removed = true; }
    if (!set.size) this.listeners.delete(event); return removed;
  }
  clear(event) { event === undefined ? this.listeners.clear() : this.listeners.delete(event); }
  listenerCount(event) { if (event !== undefined) return this.listeners.get(event)?.size || 0; let n = 0; for (const s of this.listeners.values()) n += s.size; return n; }
  async emit(event, data = {}) {
    const set = this.listeners.get(event); if (!set) return [];
    const snapshot = [...set];
    for (const e of snapshot) if (e.once) set.delete(e);
    if (!set.size) this.listeners.delete(event);
    return Promise.all(snapshot.map(async ({ handler }) => { try { return { status: 'fulfilled', value: await handler(data, event) }; } catch (reason) { return { status: 'rejected', reason }; } }));
  }
}
export default EventBus;
