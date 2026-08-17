// ExperienceMemory.mjs

export class ExperienceMemory {
  /**
   * @param {object} [options]
   * @param {number} [options.limit=Infinity] - 最大记录数；0 视为不限（Infinity）
   * @param {object} [options.eventBus] - 可选事件总线（需支持 emit）
   */
  constructor(recordsOrOpts = [], opts = {}) {
    let initialRecords = [];
    let options = {};
    if (Array.isArray(recordsOrOpts)) {
      initialRecords = recordsOrOpts;
      options = opts;
    } else if (recordsOrOpts && typeof recordsOrOpts === 'object') {
      options = recordsOrOpts;
    }

    let { limit = Infinity, eventBus = null, maxRecords, clock } = options;
    if (maxRecords != null && limit === Infinity) limit = maxRecords;

    if (limit !== Infinity) {
      if (!Number.isInteger(limit) || limit < 0) {
        throw new RangeError(`ExperienceMemory: limit must be a non-negative integer or Infinity, got ${limit}`);
      }
      if (limit === 0) limit = Infinity;
    }

    this.limit = limit;
    this.eventBus = eventBus;
    this._clock = typeof clock === 'function' ? clock : () => Date.now();
    this.records = [];
    this._seq = 0;

    if (initialRecords.length > 0) this.restore(initialRecords);
  }

  get size() {
    return this.records.length;
  }

  /**
   * 记录一条经验。
   * @param {string} kind
   * @param {object} [payload]
   * @returns {object} record
   */
  remember(kind, payload = {}) {
    if (kind == null) kind = 'experience';
    if (typeof kind !== 'string' || kind.length === 0) {
      throw new TypeError('ExperienceMemory.remember: kind must be a non-empty string');
    }

    const seq = ++this._seq;
    const at = this._clock();
    const record = {
      id: `em-${at}-${seq}`,
      seq,
      kind,
      payload,
      at,
      confidence: 0,
    };

    this.records.push(record);

    // 先通知记忆写入，再执行淘汰
    this.eventBus?.emit('memory:remembered', record);

    while (this.records.length > this.limit) {
      const evicted = this.records.shift();
      this.eventBus?.emit('memory:evicted', evicted);
    }

    return record;
  }

  /**
   * 强化一条经验记录。
   * @param {number|string} ref - seq 编号、record id（如 "em-7-1"）或 kind
   * @param {number} [_confidence] - 已废弃，忽略；confidence 固定设为 1
   * @returns {object|null} record
   */
  reinforce(ref, _confidence) {
    let record = null;
    if (Number.isFinite(ref)) {
      record = this.records.find((r) => r.seq === ref) ?? null;
    } else if (typeof ref === 'string' && ref.length > 0) {
      // 先按 id 精确匹配，再按 kind 匹配最近一条
      record = this.records.find((r) => r.id === ref) ?? null;
      if (!record) {
        for (let i = this.records.length - 1; i >= 0; i--) {
          if (this.records[i].kind === ref) { record = this.records[i]; break; }
        }
      }
    } else {
      throw new TypeError('ExperienceMemory.reinforce: ref must be a seq number or non-empty id/kind string');
    }
    if (!record) return null;
    record.reinforcedCount = (record.reinforcedCount || 0) + 1;
    record.lastReinforcedAt = this._clock();
    record.confidence = 1;
    this.eventBus?.emit('memory:reinforced', record);
    return record;
  }

  /**
   * 检索经验记录。
   * @param {object} [query]
   * @param {string} [query.kind] - 按 kind 过滤
   * @param {number} [query.count] - 返回最近 count 条
   * @returns {object[]}
   */
  recall({ kind, count } = {}) {
    let result = this.records;

    if (typeof kind === 'string') {
      result = result.filter((r) => r.kind === kind);
    }

    if (Number.isFinite(count) && count > 0) {
      result = result.slice(-count);
    }

    return result.slice();
  }

  /**
   * 全文搜索：匹配 kind 及 payload 中所有嵌套字段，结果按 confidence 降序排列。
   * @param {string} query
   * @param {object} [opts]
   * @param {number} [opts.count=20]
   * @returns {object[]}
   */
  search(query, opts = {}) {
    if (typeof query !== 'string' || query.length === 0) return [];
    const q = query.toLowerCase();

    const deepMatch = (value, seen = new Set()) => {
      if (value == null) return false;
      if (typeof value === 'string') return value.toLowerCase().includes(q);
      if (typeof value === 'number' || typeof value === 'boolean') {
        return String(value).toLowerCase().includes(q);
      }
      if (typeof value === 'object') {
        if (seen.has(value)) return false;
        seen.add(value);
        const values = Array.isArray(value) ? value : Object.values(value);
        return values.some((v) => deepMatch(v, seen));
      }
      return false;
    };

    return this.records
      .filter((r) => {
        if (r.kind && r.kind.toLowerCase().includes(q)) return true;
        return deepMatch(r.payload);
      })
      .sort((a, b) => (b.confidence ?? 0) - (a.confidence ?? 0))
      .slice(0, opts.count || 20)
      .map((r) => r.payload?.shu != null ? { ...r, shu: r.payload.shu } : r);
  }

  /**
   * 序列化当前记录。
   * @returns {object[]}
   */
  export() {
    return this.records.map((r) => ({ ...r }));
  }

  /**
   * export() 的别名。
   * @returns {object[]}
   */
  snapshot() {
    return this.export();
  }

  /**
   * 从快照恢复记录，无效条目会被丢弃，超限部分保留最近的记录。
   * @param {object[]} records
   * @returns {number} 恢复的记录数
   */
  restore(records) {
    if (!Array.isArray(records)) {
      throw new TypeError('ExperienceMemory.restore: records must be an array');
    }

    const valid = records.filter(
      (r) => r != null && typeof r.kind === 'string' && Number.isFinite(r.seq)
    );

    this.records =
      this.limit === Infinity ? valid.slice() : valid.slice(-this.limit);

    // 同步序号计数器为所有记录的最大 seq，避免恢复后新 remember 的 seq 冲突
    this._seq = valid.length > 0 ? Math.max(...valid.map((r) => r.seq)) : 0;

    this.eventBus?.emit('memory:restored', { count: this.records.length });

    return this.records.length;
  }

  /**
   * 清空所有记录。
   */
  clear() {
    const count = this.records.length;
    this.records = [];
    this.eventBus?.emit('memory:cleared', { count });
  }
}