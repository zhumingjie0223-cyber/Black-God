// ExperienceMemory.mjs

export class ExperienceMemory {
  /**
   * @param {object} [options]
   * @param {number} [options.limit=Infinity] - 最大记录数；0 视为不限（Infinity）
   * @param {object} [options.eventBus] - 可选事件总线（需支持 emit）
   */
  constructor({ limit = Infinity, eventBus = null } = {}) {
    if (limit !== Infinity) {
      if (!Number.isInteger(limit) || limit < 0) {
        throw new RangeError(
          `ExperienceMemory: limit must be a non-negative integer or Infinity, got ${limit}`
        );
      }
      if (limit === 0) limit = Infinity;
    }

    this.limit = limit;
    this.eventBus = eventBus;
    this.records = [];
    this._seq = 0;
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
    if (typeof kind !== 'string' || kind.length === 0) {
      throw new TypeError('ExperienceMemory.remember: kind must be a non-empty string');
    }

    const record = {
      seq: ++this._seq,
      kind,
      payload,
      at: Date.now(),
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
   * 序列化当前记录。
   * @returns {object[]}
   */
  snapshot() {
    return this.records.map((r) => ({ ...r }));
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

    // 同步序号计数器，避免恢复后 seq 冲突
    this._seq = this.records.reduce(
      (max, r) => (Number.isFinite(r.seq) && r.seq > max ? r.seq : max),
      0
    );

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

五处修改说明：

1. **constructor**：`limit` 非整数或负数抛 `RangeError`，`0` 归一化为 `Infinity`（`Infinity` 本身直接放行）。
2. **restore 后 `_seq` 同步**：用指定的 `reduce` 表达式取最大 `seq`，防止恢复后新记录 seq 与旧记录冲突。
3. **valid filter**：增加 `Number.isFinite(r.seq)` 校验，缺失或非法 seq 的条目直接丢弃。
4. **事件顺序**：`memory:remembered` 在淘汰循环之前 emit，保证订阅方先看到写入再看到 `memory:evicted`。
5. **`Number.isFinite`**：全部使用严格版本（不做隐式类型转换），无裸 `isFinite` 残留。
