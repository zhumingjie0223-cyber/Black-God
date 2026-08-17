import test from 'node:test';
import assert from 'node:assert/strict';
import { NexusSQLiteStore, NEXUS_SQL_SCHEMA_VERSION } from './nexus_sqlite_store.mjs';

function makeStorage() {
  const statements = [];
  const rows = [];
  return {
    statements,
    storage: {
      sql: {
        exec(query, ...params) {
          statements.push({ query, params });
          if (query.startsWith('SELECT change_id')) return rows.values();
          return [].values();
        },
      },
    },
    rows,
  };
}

test('SQLite migration 为幂等 DDL，并明确启用 foreign key schema', async () => {
  const { storage, statements } = makeStorage();
  const store = new NexusSQLiteStore(storage, { clock: () => 100 });
  const first = await store.ensureMigrated();
  const count = statements.length;
  const second = await store.ensureMigrated();
  assert.equal(first.version, NEXUS_SQL_SCHEMA_VERSION);
  assert.equal(second.version, NEXUS_SQL_SCHEMA_VERSION);
  assert.equal(statements.length, count, '同一 store 二次迁移不重复执行');
  assert.ok(statements.some((item) => item.query.includes('PRAGMA foreign_keys = ON')));
  assert.ok(statements.some((item) => item.query.includes('nexus_messages')));
  assert.ok(statements.some((item) => item.query.includes('nexus_sync_outbox')));
});

test('history 持久化写入消息、压缩锚点与可同步 outbox，且审计参数脱敏', async () => {
  const { storage, statements } = makeStorage();
  const store = new NexusSQLiteStore(storage, { clock: () => 200 });
  const result = await store.persistHistory('main', {
    compaction: { last_compacted_message_id: 'm0' },
    messages: [{ message_id: 'm1', turn_id: 't1', role: 'user', content: 'hello', api_key: 'secret' }],
  }, { ownerScope: 'owner', revision: 7 });
  assert.equal(result.written, 1);
  const payloadWrite = statements.find((item) => item.query.startsWith('INSERT INTO nexus_messages'));
  assert.ok(payloadWrite);
  assert.equal(payloadWrite.params[4].includes('secret'), false);
  assert.ok(statements.filter((item) => item.query.startsWith('INSERT OR IGNORE INTO nexus_sync_outbox')).length >= 2);
});

test('删除不会立即物理清除：创建带 30 天保留期的 tombstone 与 delete outbox', async () => {
  const { storage, statements } = makeStorage();
  const store = new NexusSQLiteStore(storage, { clock: () => 1000 });
  const result = await store.tombstoneMessage('m1', { revision: 9, retentionMs: 30 });
  assert.equal(result.ok, true);
  assert.equal(result.purge_after, 1030);
  assert.ok(statements.some((item) => item.query.startsWith('UPDATE nexus_messages SET deleted_at')));
  assert.ok(statements.some((item) => item.query.includes('nexus_tombstones')));
  assert.ok(statements.some((item) => item.params.includes('delete')));
});

test('无 SQLite runtime 时如实降级，不伪造已持久化或已同步', async () => {
  const store = new NexusSQLiteStore({});
  assert.deepEqual(await store.ensureMigrated(), { enabled: false, version: 0 });
  assert.deepEqual(await store.persistHistory('main', { messages: [] }), { enabled: false, written: 0 });
  assert.deepEqual(await store.pendingChanges(), { enabled: false, changes: [] });
});
