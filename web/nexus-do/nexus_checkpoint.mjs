```javascript
// nexus_checkpoint.mjs
// Cloudflare Durable Object checkpoint + mode-gating module.
// Pure ES Module, no external dependencies.

const CKPT_PREFIX = 'ckpt_';
const INDEX_KEY = 'ckpt_index_'; // + sessionId
const MAX_INDEX_ENTRIES = 20;
const PUT_BATCH_SIZE = 128;
const DELETE_BATCH_SIZE = 128;

function makeCkptId() {
  return Date.now() + '_' + Math.random().toString(36).slice(2, 6);
}

function ckptKey(sessionId, ckptId) {
  return CKPT_PREFIX + sessionId + '_' + ckptId;
}

function indexKey(sessionId) {
  return INDEX_KEY + sessionId;
}

function sessPrefix(sessionId) {
  return 'sess_' + sessionId + '_';
}

// -------------------------------------------------------------
// Batch helpers (storage.put / storage.delete cap at 128 entries)
// -------------------------------------------------------------

/**
 * Put an object of key/value pairs in batches of at most 128.
 * @param {DurableObjectStorage} storage
 * @param {object} obj
 */
async function putInBatches(storage, obj) {
  const entries = Object.entries(obj);
  for (let i = 0; i < entries.length; i += PUT_BATCH_SIZE) {
    const slice = entries.slice(i, i + PUT_BATCH_SIZE);
    const batch = {};
    for (const [k, v] of slice) batch[k] = v;
    await storage.put(batch);
  }
}

/**
 * Delete an array of keys in batches of at most 128.
 * @param {DurableObjectStorage} storage
 * @param {string[]} keys
 */
async function deleteInBatches(storage, keys) {
  for (let i = 0; i < keys.length; i += DELETE_BATCH_SIZE) {
    const slice = keys.slice(i, i + DELETE_BATCH_SIZE);
    if (slice.length) await storage.delete(slice);
  }
}

// -------------------------------------------------------------
// CheckpointStore
// -------------------------------------------------------------
export class CheckpointStore {
  /**
   * Serialize current storage state into a snapshot.
   * State is sharded across multiple keys to stay under the 128KiB
   * per-value limit. Chunk keys: ckpt_{sid}_{ckptId}_chunk_N
   *
   * Only keys under `sessPrefix` (e.g. `sess_<sessionId>_`) are captured,
   * so data belonging to other sessions in the same Durable Object is
   * never collected into this session's snapshot.
   * @param {DurableObjectStorage} storage
   * @param {string} sessionId
   * @param {object} [meta]
   * @param {string} sessPrefixArg  namespace prefix, e.g. `sess_<sessionId>_`
   * @returns {Promise<string>} ckptId
   */
  static async snapshot(storage, sessionId, meta = {}, sessPrefixArg) {
    const prefix = sessPrefixArg || sessPrefix(sessionId);

    // Grab this session's state directly by prefix to avoid read amplification.
    const all = await storage.list({ prefix });
    const state = {};
    for (const [k, v] of all) {
      state[k] = v;
    }

    const ckptId = makeCkptId();
    const baseKey = ckptKey(sessionId, ckptId);

    // Shard state into chunks that each stay well under 128KiB.
    const entries = Object.entries(state);
    const chunks = shardEntries(entries);

    // Build the shard writes plus the manifest record.
    const writes = {};
    for (let i = 0; i < chunks.length; i++) {
      writes[baseKey + '_chunk_' + i] = chunks[i];
    }

    const record = {
      ckptId,
      sessionId,
      createdAt: Date.now(),
      meta: meta || {},
      chunkCount: chunks.length,
      keyCount: entries.length,
    };
    writes[baseKey] = record;

    await putInBatches(storage, writes);

    // Update index timeline (cap at MAX_INDEX_ENTRIES, newest kept).
    let idx = (await storage.get(indexKey(sessionId))) || [];
    idx.push({
      ckptId,
      createdAt: record.createdAt,
      meta: record.meta,
      keyCount: entries.length,
    });
    if (idx.length > MAX_INDEX_ENTRIES) {
      // Keep the newest MAX_INDEX_ENTRIES entries.
      idx = idx
        .slice()
        .sort((a, b) => b.createdAt - a.createdAt)
        .slice(0, MAX_INDEX_ENTRIES);
    }
    await storage.put(indexKey(sessionId), idx);

    return ckptId;
  }


  static async restore(storage, ckptId, sessionId) {
    const record = await storage.get(ckptKey(sessionId, ckptId));
    if (!record) {
      throw new Error('Checkpoint not found: ' + ckptId);
    }

    const state = await CheckpointStore._loadState(storage, sessionId, record);
    const prefix = sessPrefix(sessionId);

    // Only restore keys that actually belong to this session's namespace.
    const entries = Object.entries(state).filter(([k]) => k.startsWith(prefix));
    const restoredKeys = new Set(entries.map(([k]) => k));

    // Determine which existing session keys are stale (not in the snapshot).
    const existing = await storage.list({ prefix });
    const toDelete = [];
    for (const [k] of existing) {
      if (restoredKeys.has(k)) continue;
      toDelete.push(k);
    }

    const putObj = {};
    for (const [k, v] of entries) putObj[k] = v;

    // Prefer an atomic transaction so delete + put commit together.
    if (typeof storage.transaction === 'function') {
      await storage.transaction(async (txn) => {
        if (entries.length) await putInBatches(txn, putObj);
        if (toDelete.length) await deleteInBatches(txn, toDelete);
      });
    } else {
      // Fallback: write-first strategy. Put restored state before deleting
      // stale keys so a mid-operation failure never loses data. Surface any
      // error to the caller so a partial restore is not silently swallowed.
      try {
        if (entries.length) await putInBatches(storage, putObj);
        if (toDelete.length) await deleteInBatches(storage, toDelete);
      } catch (err) {
        throw new Error('Restore failed: ' + String(err?.message ?? err));
      }
    }

    return { restored: entries.length, deleted: toDelete.length };
  }

  /**
   * Return the snapshot timeline for a session.
   * @param {DurableObjectStorage} storage
   * @param {string} sessionId
   * @returns {Promise<Array>}
   */
  static async list(storage, sessionId) {
    const idx = (await storage.get(indexKey(sessionId))) || [];
    // Return sorted newest-first, defensively copied.
    return [...idx].sort((a, b) => b.createdAt - a.createdAt);
  }

  /**
   * Structured diff between two snapshots.
   * @param {DurableObjectStorage} storage
   * @param {string} ckptIdA
   * @param {string} ckptIdB
   * @param {string} sessionId
   * @returns {Promise<{added:object, removed:object, changed:object, unchanged:string[]}>}
   */
  static async diff(storage, ckptIdA, ckptIdB, sessionId) {
    const recA = await storage.get(ckptKey(sessionId, ckptIdA));
    const recB = await storage.get(ckptKey(sessionId, ckptIdB));
    if (!recA) throw new Error('Checkpoint not found: ' + ckptIdA);
    if (!recB) throw new Error('Checkpoint not found: ' + ckptIdB);

    const a = await CheckpointStore._loadState(storage, sessionId, recA);
    const b = await CheckpointStore._loadState(storage, sessionId, recB);

    const added = {};
    const removed = {};
    const changed = {};
    const unchanged = [];

    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of keys) {
      const inA = Object.prototype.hasOwnProperty.call(a, k);
      const inB = Object.prototype.hasOwnProperty.call(b, k);
      if (!inA && inB) {
        added[k] = b[k];
      } else if (inA && !inB) {
        removed[k] = a[k];
      } else {
        const sa = stableStringify(a[k]);
        const sb = stableStringify(b[k]);
        if (sa !== sb) {
          changed[k] = { from: a[k], to: b[k] };
        } else {
          unchanged.push(k);
        }
      }
    }

    return { added, removed, changed, unchanged };
  }
}

/**
 * Split state entries into chunks that each stay under ~100KiB serialized,
 * leaving headroom below the 128KiB per-value limit.
 * @param {Array<[string, any]>} entries
 * @returns {Array<object>} array of chunk objects
 */
function shardEntries(entries) {
  const MAX_CHUNK_BYTES = 100 * 1024; // ~100KiB headroom under 128KiB.
  const chunks = [];
  let current = {};
  let currentSize = 2; // account for "{}"

  for (const [k, v] of entries) {
    const piece = JSON.stringify({ [k]: v });
    const pieceSize = piece.length;
    if (Object.keys(current).length > 0 && currentSize + pieceSize > MAX_CHUNK_BYTES) {
      chunks.push(current);
      current = {};
      currentSize = 2;
    }
    current[k] = v;
    currentSize += pieceSize;
  }
  if (Object.keys(current).length > 0) chunks.push(current);
  if (chunks.length === 0) chunks.push({});
  return chunks;
}

function stableStringify(v) {
  const seen = new WeakSet();
  const norm = (x) => {
    if (x === null || typeof x !== 'object') return x;

export async function handleCheckpointSnapshot(req, storage) {
  try {
    const { sessionId, meta, sessPrefix } = await req.json();
    if (!sessionId) return json({ ok: false, error: 'sessionId required' }, 400);
    const ckptId = await CheckpointStore.snapshot(storage, sessionId, meta, sessPrefix);
    return json({ ok: true, ckptId });
  } catch (err) {
    return json({ ok: false, error: String(err?.message || err) }, 500);
  }
}

export async function handleCheckpointRestore(req, storage) {
  try {
    const { sessionId, ckptId, sessPrefix } = await req.json();
    if (!sessionId || !ckptId) return json({ ok: false, error: 'sessionId and ckptId required' }, 400);
    const result = await CheckpointStore.restore(storage, ckptId, sessionId, sessPrefix);
    return json({ ok: true, ...result });
  } catch (err) {
    return json({ ok: false, error: String(err?.message || err) }, 500);
  }
}

export async function handleCheckpointList(req, storage) {
  try {
    let sessionId;
    if (req.method === 'GET') {
      sessionId = new URL(req.url).searchParams.get('sessionId');
    } else {
      ({ sessionId } = await req.json());
    }
    if (!sessionId) return json({ ok: false, error: 'sessionId required' }, 400);
    const checkpoints = await CheckpointStore.list(storage, sessionId);
    return json({ ok: true, checkpoints });
  } catch (err) {
    return json({ ok: false, error: String(err?.message || err) }, 500);
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
}