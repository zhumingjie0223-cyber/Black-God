/**
 * nexus_checkpoint.mjs
 *
 * Cloudflare Durable Object module for session checkpoint management.
 * Provides checkpoint snapshot/restore/list/diff and a mode-based tool gate.
 *
 * Pure ESM, no external dependencies.
 *
 * Storage key formats:
 *   session data:      'sess_' + sessionId + '_' + key
 *   checkpoint chunks: 'ckpt_' + sessionId + '_' + ckptId + '_chunk_' + N
 *   checkpoint index:  'ckptindex_' + sessionId
 */

const BATCH_SIZE = 128;
const INDEX_LIMIT = 20;

/**
 * Build the session key prefix for a given session.
 * @param {string} sessionId session identifier
 * @param {string} [sessPrefixArg] optional override prefix
 * @returns {string} the computed prefix
 */
function sessPrefix(sessionId, sessPrefixArg) {
  if (sessPrefixArg) return sessPrefixArg;
  return 'sess_' + sessionId + '_';
}

/**
 * Build the checkpoint chunk key.
 * @param {string} sessionId session identifier
 * @param {string} ckptId checkpoint identifier
 * @param {number} n chunk index
 * @returns {string} the chunk key
 */
function chunkKey(sessionId, ckptId, n) {
  return 'ckpt_' + sessionId + '_' + ckptId + '_chunk_' + n;
}

/**
 * Build the checkpoint index key for a session.
 * @param {string} sessionId session identifier
 * @returns {string} the index key
 */
function indexKey(sessionId) {
  return 'ckptindex_' + sessionId;
}

/**
 * Split an array into fixed-size chunks.
 * @param {Array<any>} arr the source array
 * @param {number} size chunk size
 * @returns {Array<Array<any>>} array of chunks
 */
function chunkArray(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
}

/**
 * Generate a checkpoint identifier.
 * @returns {string} a new checkpoint id
 */
function genCkptId() {
  const rand = Math.random().toString(36).slice(2, 10);
  return 'ck_' + Date.now().toString(36) + '_' + rand;
}

/**
 * List all keys under a given prefix from Durable Object storage.
 * @param {any} storage the Durable Object storage instance
 * @param {string} prefix the key prefix
 * @returns {Promise<Map<string, any>>} map of key to value
 */
async function listByPrefix(storage, prefix) {
  const result = await storage.list({ prefix });
  if (result instanceof Map) return result;
  const map = new Map();
  for (const [k, v] of Object.entries(result || {})) {
    map.set(k, v);
  }
  return map;
}

/**
 * CheckpointStore provides static methods for managing session checkpoints.
 */
export class CheckpointStore {
  /**
   * Create a snapshot of the current session state.
   * Collects keys by the session prefix, stores them into chunks of 128
   * entries, and updates the checkpoint index (capped at 20 entries).
   *
   * @param {any} storage the Durable Object storage instance
   * @param {string} sessionId session identifier
   * @param {object} [meta] optional metadata to attach to the checkpoint
   * @param {string} [sessPrefixArg] optional session prefix override
   * @returns {Promise<object>} the created checkpoint index entry
   */
  static async snapshot(storage, sessionId, meta, sessPrefixArg) {
    const prefix = sessPrefix(sessionId, sessPrefixArg);
    const entries = await listByPrefix(storage, prefix);

    const pairs = [];
    for (const [key, value] of entries) {
      const relKey = key.startsWith(prefix) ? key.slice(prefix.length) : key;
      pairs.push([relKey, value]);
    }

    const ckptId = genCkptId();
    const chunks = chunkArray(pairs, BATCH_SIZE);

    for (let n = 0; n < chunks.length; n++) {
      await storage.put(chunkKey(sessionId, ckptId, n), chunks[n]);
    }

    const entry = {
      ckptId,
      sessionId,
      createdAt: Date.now(),
      chunkCount: chunks.length,
      keyCount: pairs.length,
      meta: meta || {}
    };

    let index = await storage.get(indexKey(sessionId));
    if (!Array.isArray(index)) index = [];
    index.push(entry);
    index.sort((a, b) => b.createdAt - a.createdAt);

    if (index.length > INDEX_LIMIT) {
      const removed = index.slice(INDEX_LIMIT);
      index = index.slice(0, INDEX_LIMIT);
      for (const old of removed) {
        for (let n = 0; n < old.chunkCount; n++) {
          await storage.delete(chunkKey(sessionId, old.ckptId, n));
        }
      }
    }

    await storage.put(indexKey(sessionId), index);
    return entry;
  }

  /**
   * Restore a checkpoint into the session.
   * Uses a write-then-delete (write-over) strategy: first writes all
   * checkpoint entries, then deletes any leftover session keys that are
   * not part of the checkpoint. Operations are batched at 128 entries.
   *
   * @param {any} storage the Durable Object storage instance
   * @param {string} ckptId checkpoint identifier to restore
   * @param {string} sessionId session identifier
   * @param {string} [sessPrefixArg] optional session prefix override
   * @returns {Promise<object>} result summary
   */
  static async restore(storage, ckptId, sessionId, sessPrefixArg) {
    const prefix = sessPrefix(sessionId, sessPrefixArg);

    let index = await storage.get(indexKey(sessionId));
    if (!Array.isArray(index)) index = [];
    const entry = index.find((e) => e.ckptId === ckptId);
    if (!entry) {
      throw new Error('checkpoint not found: ' + ckptId);
    }

    const restoredKeys = new Set();
    let writeBuffer = {};
    let bufferCount = 0;

    const flushWrites = async () => {
      if (bufferCount > 0) {
        await storage.put(writeBuffer);
        writeBuffer = {};
        bufferCount = 0;
      }
    };

    for (let n = 0; n < entry.chunkCount; n++) {
      const chunk = await storage.get(chunkKey(sessionId, ckptId, n));
      if (!Array.isArray(chunk)) continue;
      for (const [relKey, value] of chunk) {
        const fullKey = prefix + relKey;
        restoredKeys.add(fullKey);
        writeBuffer[fullKey] = value;
        bufferCount++;
        if (bufferCount >= BATCH_SIZE) {
          await flushWrites();
        }
      }
    }
    await flushWrites();

    const current = await listByPrefix(storage, prefix);
    const toDelete = [];
    for (const key of current.keys()) {
      if (!restoredKeys.has(key)) {
        toDelete.push(key);
      }
    }

    let deleted = 0;
    const delChunks = chunkArray(toDelete, BATCH_SIZE);
    for (const batch of delChunks) {
      if (batch.length > 0) {
        await storage.delete(batch);
        deleted += batch.length;
      }
    }

    return {
      ckptId,
      sessionId,
      restored: restoredKeys.size,
      deleted
    };
  }

  /**
   * List the checkpoint timeline for a session.
   * @param {any} storage the Durable Object storage instance
   * @param {string} sessionId session identifier
   * @returns {Promise<Array<object>>} the checkpoint timeline, newest first
   */
  static async list(storage, sessionId) {
    let index = await storage.get(indexKey(sessionId));
    if (!Array.isArray(index)) index = [];
    return index
      .slice()
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  /**
   * Load all key/value pairs of a checkpoint into a plain object.
   * @param {any} storage the Durable Object storage instance
   * @param {string} sessionId session identifier
   * @param {object} entry the checkpoint index entry
   * @returns {Promise<object>} map of relative key to value
   */
  static async _loadCheckpoint(storage, sessionId, entry) {
    const out = {};
    if (!entry) return out;
    for (let n = 0; n < entry.chunkCount; n++) {
      const chunk = await storage.get(chunkKey(sessionId, entry.ckptId, n));
      if (!Array.isArray(chunk)) continue;
      for (const [relKey, value] of chunk) {
        out[relKey] = value;
      }
    }
    return out;
  }

  /**
   * Compute a structured diff between two checkpoints.
   * @param {any} storage the Durable Object storage instance
   * @param {string} ckptIdA the base checkpoint identifier
   * @param {string} ckptIdB the target checkpoint identifier
   * @param {string} sessionId session identifier
   * @returns {Promise<object>} structured diff with added, removed, changed
   */
  static async diff(storage, ckptIdA, ckptIdB, sessionId) {
    let index = await storage.get(indexKey(sessionId));
    if (!Array.isArray(index)) index = [];

    const entryA = index.find((e) => e.ckptId === ckptIdA);
    const entryB = index.find((e) => e.ckptId === ckptIdB);

    if (!entryA) throw new Error('checkpoint not found: ' + ckptIdA);
    if (!entryB) throw new Error('checkpoint not found: ' + ckptIdB);

    const mapA = await CheckpointStore._loadCheckpoint(storage, sessionId, entryA);
    const mapB = await CheckpointStore._loadCheckpoint(storage, sessionId, entryB);

    const added = [];
    const removed = [];
    const changed = [];

    for (const key of Object.keys(mapB)) {
      if (!(key in mapA)) {
        added.push({ key, value: mapB[key] });
      } else if (JSON.stringify(mapA[key]) !== JSON.stringify(mapB[key])) {
        changed.push({ key, from: mapA[key], to: mapB[key] });
      }
    }

    for (const key of Object.keys(mapA)) {
      if (!(key in mapB)) {
        removed.push({ key, value: mapA[key] });
      }
    }

    return {
      sessionId,
      a: ckptIdA,
      b: ckptIdB,
      added,
      removed,
      changed,
      summary: {
        added: added.length,
        removed: removed.length,
        changed: changed.length
      }
    };
  }
}

/**
 * ModeGate controls which tools are permitted in a given mode.
 */

// nexus_checkpoint_tail.mjs

// ── 批量工具函数 ──

/**
 * 将对象的键值对分批写入 storage。
 * DO storage.put 的批量形式每次最多接受一定数量的键，
 * 因此这里按 size 切分后逐批写入。
 * @param {DurableObjectStorage} storage - DO 存储实例
 * @param {Object} obj - 要写入的键值对象
 * @param {number} [size=128] - 每批最大键数量
 * @returns {Promise<void>}
 */
async function putInBatches(storage, obj, size = 128) {
  const entries = Object.entries(obj);
  for (let i = 0; i < entries.length; i += size) {
    const chunk = entries.slice(i, i + size);
    const batch = {};
    for (const [k, v] of chunk) batch[k] = v;
    await storage.put(batch);
  }
}

/**
 * 分批删除 storage 中的键。
 * @param {DurableObjectStorage} storage - DO 存储实例
 * @param {string[]} keys - 要删除的键列表
 * @param {number} [size=128] - 每批最大键数量
 * @returns {Promise<number>} 实际删除的键数量
 */
async function deleteInBatches(storage, keys, size = 128) {
  let deleted = 0;
  for (let i = 0; i < keys.length; i += size) {
    const chunk = keys.slice(i, i + size);
    const res = await storage.delete(chunk);
    // storage.delete 返回删除的键数量（数字）或布尔
    deleted += typeof res === 'number' ? res : (res ? chunk.length : 0);
  }
  return deleted;
}

// ── ModeGate ──

/**
 * 模式门控：根据当前 agent 所处的模式判断某个工具是否被允许调用。
 * PLAN 模式只允许只读类工具；ACT 模式允许全部工具。
 */
export class ModeGate {
  /** PLAN 模式下允许的（只读）工具 */
  static PLAN_TOOLS = [
    'read_file',
    'search',
    'list_dir',
    'ask_user',
    'get_diagnostics',
  ];

  /** ACT 模式下允许的工具（包含 PLAN 工具 + 写入类工具） */
  static ACT_TOOLS = [
    ...ModeGate.PLAN_TOOLS,
    'write_file',
    'run_command',
    'apply_patch',
    'delete_file',
    'create_file',
  ];

  /**
   * 判断指定模式下某工具是否被允许。
   * @param {string} mode - 当前模式，"plan" 或 "act"（大小写不敏感）
   * @param {string} toolName - 工具名称
   * @returns {boolean} 允许则返回 true
   */
  static allow(mode, toolName) {
    const m = String(mode || '').toLowerCase();
    if (m === 'act') return ModeGate.ACT_TOOLS.includes(toolName);
    if (m === 'plan') return ModeGate.PLAN_TOOLS.includes(toolName);
    // 未知模式默认按最严格的 PLAN 处理
    return ModeGate.PLAN_TOOLS.includes(toolName);
  }
}

// ── HTTP handlers ──

/**
 * 构造 JSON 响应。
 * @param {*} data - 要序列化的数据
 * @param {number} [status=200] - HTTP 状态码
 * @returns {Response}
 */
function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/**
 * 安全解析请求体为 JSON，失败返回空对象。
 * @param {Request} req
 * @returns {Promise<Object>}
 */
async function readJson(req) {
  try {
    return await req.json();
  } catch {
    return {};
  }
}

/**
 * 创建一个检查点快照。
 * POST body: {sessionId, meta?, sessPrefixArg?}
 * 会读取属于该 session 的所有键（前缀为 sessPrefixArg 或默认 "sess:{sessionId}:"），
 * 将其内容打包写入一个新的 checkpoint 记录。
 * @param {Request} req
 * @param {DurableObjectStorage} storage
 * @returns {Promise<Response>}
 */
export async function handleCheckpointSnapshot(req, storage) {
  const body = await readJson(req);
  const { sessionId, meta, sessPrefixArg } = body;

  if (!sessionId) {
    return json({ ok: false, error: 'missing sessionId' }, 400);
  }

  const sessPrefix = sessPrefixArg || 'sess:' + sessionId + ':';

  // 读取该 session 的所有键值
  const map = await storage.list({ prefix: sessPrefix });
  const data = {};
  for (const [k, v] of map) {
    // 存储时去掉前缀，恢复时再补回
    data[k.slice(sessPrefix.length)] = v;
  }

  const ckptId = 'ckpt_' + Date.now().toString(36) + '_' +
    Math.random().toString(36).slice(2, 8);

  const record = {
    ckptId,
    sessionId,
    createdAt: new Date().toISOString(),
    keyCount: Object.keys(data).length,
    meta: meta || null,
    data,
  };

  // 检查点记录本身与索引条目
  const ckptKey = 'ckpt:' + sessionId + ':' + ckptId;
  const indexKey = 'ckptidx:' + sessionId + ':' + ckptId;

  await putInBatches(storage, {
    [ckptKey]: record,
    [indexKey]: {
      ckptId,
      createdAt: record.createdAt,
      keyCount: record.keyCount,
      meta: record.meta,
    },
  });

  return json({
    ok: true,
    ckptId,
    createdAt: record.createdAt,
    keyCount: record.keyCount,
  });
}

/**
 * 从指定检查点恢复 session 状态。
 * POST body: {sessionId, ckptId, sessPrefixArg?}
 * 会先清除当前 session 前缀下的所有键，再写入检查点中保存的键值。
 * @param {Request} req
 * @param {DurableObjectStorage} storage
 * @returns {Promise<Response>}
 */
export async function handleCheckpointRestore(req, storage) {
  const body = await readJson(req);
  const { sessionId, ckptId, sessPrefixArg } = body;

  if (!sessionId || !ckptId) {
    return json({ ok: false, error: 'missing sessionId or ckptId' }, 400);
  }

  const ckptKey = 'ckpt:' + sessionId + ':' + ckptId;
  const record = await storage.get(ckptKey);

  if (!record) {
    return json({ ok: false, error: 'checkpoint not found' }, 404);
  }

  const sessPrefix = sessPrefixArg || 'sess:' + sessionId + ':';

  // 1. 清除当前 session 键
  const existing = await storage.list({ prefix: sessPrefix });
  const staleKeys = [...existing.keys()];
  const removed = await deleteInBatches(storage, staleKeys);

  // 2. 写回检查点数据
  const restoreObj = {};
  const data = record.data || {};
  for (const [k, v] of Object.entries(data)) {
    restoreObj[sessPrefix + k] = v;
  }
  await putInBatches(storage, restoreObj);

  return json({
    ok: true,
    ckptId,
    restoredKeys: Object.keys(restoreObj).length,
    removedKeys: removed,
    createdAt: record.createdAt || null,
  });
}

/**
 * 列出某个 session 的所有检查点（按创建时间倒序）。
 * 支持 GET 带 sessionId 查询参数，或 POST body {sessionId}。
 * @param {Request} req
 * @param {DurableObjectStorage} storage
 * @returns {Promise<Response>}
 */
export async function handleCheckpointList(req, storage) {
  let sessionId;

  if (req.method === 'GET') {
    const url = new URL(req.url);
    sessionId = url.searchParams.get('sessionId');
  } else {
    const body = await readJson(req);
    sessionId = body.sessionId;
  }

  if (!sessionId) {
    return json({ ok: false, error: 'missing sessionId' }, 400);
  }

  const indexPrefix = 'ckptidx:' + sessionId + ':';
  const map = await storage.list({ prefix: indexPrefix });

  const checkpoints = [];
  for (const [, v] of map) {
    checkpoints.push(v);
  }

  // 按创建时间倒序（最新在前）
  checkpoints.sort((a, b) => {
    const ta = a && a.createdAt ? a.createdAt : '';
    const tb = b && b.createdAt ? b.createdAt : '';
    return tb < ta ? -1 : tb > ta ? 1 : 0;
  });

  return json({
    ok: true,
    sessionId,
    count: checkpoints.length,
    checkpoints,
  });
}
