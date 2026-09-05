## CheckpointManager.js（升级版）

```js
// CheckpointManager.js — Replit-style tri-state snapshot on CF Workers KV
// ============================================================================
// 升级要点（详见代码内 [FIX-n] / [NEW-n] 标注）：
// [FIX-1]  构造函数未校验 KV 绑定 → 运行时才炸；现在 fail-fast
// [FIX-2]  agentId / checkpointId 未转义，含 ':' 会与 __index 键冲突/越权
// [FIX-3]  id 生成用 Math.random 有碰撞风险 → crypto.randomUUID
// [FIX-4]  JSON.parse 裸调用，数据损坏直接抛 SyntaxError → 安全解析 + 类型校验
// [FIX-5]  索引读写非原子，并发 save 会丢条目 → isolate 内 per-agent 互斥锁
// [FIX-6]  save 写快照成功但写索引失败 → 产生孤儿；现在回滚删除
// [FIX-7]  prune(keep=-1 / NaN / 小数) → slice(0,-1) 误删；现在做 clamp
// [FIX-8]  prune 删除失败仍从索引移除 → 永久孤儿；改为 allSettled + 保留失败项
// [FIX-9]  restore 未兜底字段，缺失即 undefined 污染下游 → 归一化默认值
// [FIX-10] 无 KV 25MiB / 512B 键长限制校验 → 提前抛出可读错误
// [FIX-11] list 排序无 tie-break，同毫秒创建顺序不稳定 → 次级按 id 排序
// [NEW-1]  统一 CheckpointError（code + cause），所有 KV 调用带重试
// [NEW-2]  索引丢失/损坏时可从 kv.list() 自愈重建（rebuildIndex）
// [NEW-3]  新增 get / has / delete / clear / rebuildIndex API
// [NEW-4]  支持 TTL、label、schema version、索引条目上限
// ============================================================================

const SCHEMA_VERSION = 1;

const LIMITS = {
  MAX_VALUE_BYTES: 25 * 1024 * 1024, // KV 单值上限 25 MiB
  MAX_KEY_BYTES: 512,                // KV 键上限 512 字节
  MAX_INDEX_ENTRIES: 1000,           // 索引条目硬上限，防止索引本身超限
  MIN_TTL_SECONDS: 60,               // KV expirationTtl 最小值
};

/** [NEW-1] 统一错误类型，携带机器可读 code 与原始 cause */
export class CheckpointError extends Error {
  constructor(message, code = 'CHECKPOINT_ERROR', cause) {
    super(message);
    this.name = 'CheckpointError';
    this.code = code;
    if (cause !== undefined) this.cause = cause;
  }
}

// ---------------------------------------------------------------------------
// 内部工具
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();
const byteLen = (s) => encoder.encode(s).length;

function assertId(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new CheckpointError(`${field} must be a non-empty string`, 'INVALID_ARGUMENT');
  }
  if (value.length > 256) {
    throw new CheckpointError(`${field} too long (max 256 chars)`, 'INVALID_ARGUMENT');
  }
  return value.trim();
}

/** [FIX-2] 转义键段，杜绝 ':' 注入导致的键冲突 / 跨 agent 越权 */
function seg(value) {
  return encodeURIComponent(value);
}

/** [FIX-4] 安全 JSON 解析：损坏数据返回 null 而不是抛 SyntaxError */
function safeParse(raw) {
  if (typeof raw !== 'string' || raw === '') return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

const isPlainObject = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);

/** [NEW-1] KV 瞬时故障重试（指数退避 + 抖动） */
async function withRetry(fn, { attempts = 3, baseDelay = 60, op = 'kv' } = {}) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      // 参数类错误无需重试
      if (err instanceof CheckpointError && err.code === 'INVALID_ARGUMENT') throw err;
      if (i === attempts - 1) break;
      const delay = baseDelay * 2 ** i + Math.floor(Math.random() * 40);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new CheckpointError(`KV operation "${op}" failed after ${attempts} attempts`, 'KV_FAILURE', lastErr);
}

// ---------------------------------------------------------------------------

export class CheckpointManager {
  /** [FIX-5] isolate 内 per-agent 串行锁，避免索引 read-modify-write 竞态 */
  #locks = new Map();

  /**
   * @param {object} env               Worker env
   * @param {object} [options]
   * @param {string} [options.binding]  KV 绑定名，默认 'KV'
   * @param {string} [options.namespace] 键前缀，默认 'ckpt'
   * @param {number} [options.defaultKeep] prune 默认保留数
   * @param {number|null} [options.ttlSeconds] 快照 TTL（秒），null = 永不过期
   */
  constructor(env, options = {}) {
    const {
      binding = 'KV',
      namespace = 'ckpt',
      defaultKeep = 5,
      ttlSeconds = null,
    } = options;

    // [FIX-1] fail-fast：绑定缺失或不是合法 KV namespace 时立即报错
    const kv = env?.[binding];
    if (!kv || typeof kv.get !== 'function' || typeof kv.put !== 'function' ||
        typeof kv.delete !== 'function') {
      throw new CheckpointError(
        `KV binding "${binding}" is missing or invalid on env`,
        'MISSING_BINDING',
      );
    }
    if (ttlSeconds !== null &&
        (!Number.isFinite(ttlSeconds) || ttlSeconds < LIMITS.MIN_TTL_SECONDS)) {
      throw new CheckpointError(
        `ttlSeconds must be null or >= ${LIMITS.MIN_TTL_S