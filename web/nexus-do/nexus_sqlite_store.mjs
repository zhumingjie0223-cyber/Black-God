// 神枢 · Durable Object SQLite 聊天存储
//
// Cloudflare DO SQLite 的日志/WAL 实现由平台托管，应用层不可也不应擅自执行 PRAGMA journal_mode。
// 本模块显式维护 schema version、foreign key、幂等 CREATE/ALTER 等价迁移、outbox 与 tombstone。

import { redactSecrets } from './nexus_agent_protocol.mjs';

const asJson = (value) => JSON.stringify(value ?? null);
const now = () => Date.now();

export const NEXUS_SQL_SCHEMA_VERSION = 1;

function hasSql(storage) { return !!storage?.sql && typeof storage.sql.exec === 'function'; }

export class NexusSQLiteStore {
  constructor(storage, options = {}) {
    this.storage = storage;
    this.clock = options.clock || now;
    this.ready = false;
    this.enabled = hasSql(storage);
  }

  exec(query, ...params) {
    if (!this.enabled) return null;
    return this.storage.sql.exec(query, ...params);
  }

  async ensureMigrated() {
    if (!this.enabled || this.ready) return { enabled: this.enabled, version: this.enabled ? NEXUS_SQL_SCHEMA_VERSION : 0 };
    // 每条 DDL 都是幂等的；Worker 重启、闹钟与并发 fetch 不会重复破坏 schema。
    this.exec('PRAGMA foreign_keys = ON');
    this.exec('CREATE TABLE IF NOT EXISTS nexus_schema_migrations (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)');
    this.exec('CREATE TABLE IF NOT EXISTS nexus_conversations (conversation_id TEXT PRIMARY KEY, owner_scope TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, last_compacted_message_id TEXT)');
    this.exec('CREATE TABLE IF NOT EXISTS nexus_messages (message_id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, turn_id TEXT, role TEXT NOT NULL, payload_json TEXT NOT NULL, created_at INTEGER NOT NULL, deleted_at INTEGER, FOREIGN KEY(conversation_id) REFERENCES nexus_conversations(conversation_id))');
    this.exec('CREATE INDEX IF NOT EXISTS idx_nexus_messages_conversation_created ON nexus_messages(conversation_id, created_at)');
    this.exec('CREATE TABLE IF NOT EXISTS nexus_sync_outbox (change_id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, operation TEXT NOT NULL, payload_json TEXT, revision INTEGER NOT NULL, created_at INTEGER NOT NULL, acknowledged_at INTEGER)');
    this.exec('CREATE INDEX IF NOT EXISTS idx_nexus_sync_outbox_pending ON nexus_sync_outbox(acknowledged_at, created_at)');
    this.exec('CREATE TABLE IF NOT EXISTS nexus_tombstones (entity_type TEXT NOT NULL, entity_id TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL, purge_after INTEGER NOT NULL, revision INTEGER NOT NULL)');
    this.exec('INSERT OR IGNORE INTO nexus_schema_migrations(version, applied_at) VALUES (?, ?)', NEXUS_SQL_SCHEMA_VERSION, this.clock());
    this.ready = true;
    return { enabled: true, version: NEXUS_SQL_SCHEMA_VERSION };
  }

  async persistHistory(conversationId, history, { ownerScope = 'system', revision = this.clock() } = {}) {
    await this.ensureMigrated();
    if (!this.enabled) return { enabled: false, written: 0 };
    const at = this.clock();
    const conversation = String(conversationId || 'default');
    const messages = Array.isArray(history?.messages) ? history.messages : [];
    const marker = history?.compaction?.last_compacted_message_id || null;
    this.exec('INSERT INTO nexus_conversations(conversation_id, owner_scope, created_at, updated_at, last_compacted_message_id) VALUES (?, ?, ?, ?, ?) ON CONFLICT(conversation_id) DO UPDATE SET updated_at=excluded.updated_at, last_compacted_message_id=excluded.last_compacted_message_id', conversation, String(ownerScope), at, at, marker);
    let written = 0;
    for (const message of messages) {
      if (!message?.message_id || !message?.role) continue;
      const payload = redactSecrets(message);
      this.exec('INSERT INTO nexus_messages(message_id, conversation_id, turn_id, role, payload_json, created_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, NULL) ON CONFLICT(message_id) DO UPDATE SET payload_json=excluded.payload_json, deleted_at=NULL', String(message.message_id), conversation, message.turn_id ? String(message.turn_id) : null, String(message.role), asJson(payload), Number(message.created_at || at), at);
      const changeId = `msg:${message.message_id}:${revision}`;
      this.exec('INSERT OR IGNORE INTO nexus_sync_outbox(change_id, entity_type, entity_id, operation, payload_json, revision, created_at, acknowledged_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)', changeId, 'message', String(message.message_id), 'upsert', asJson(payload), Number(revision), at);
      written++;
    }
    if (marker) {
      const changeId = `marker:${conversation}:${revision}`;
      this.exec('INSERT OR IGNORE INTO nexus_sync_outbox(change_id, entity_type, entity_id, operation, payload_json, revision, created_at, acknowledged_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)', changeId, 'conversation', conversation, 'compact_marker', asJson({ last_compacted_message_id: marker }), Number(revision), at);
    }
    return { enabled: true, written, marker };
  }

  async tombstoneMessage(messageId, { revision = this.clock(), retentionMs = 30 * 24 * 3600_000 } = {}) {
    await this.ensureMigrated();
    if (!this.enabled) return { enabled: false };
    const at = this.clock();
    const id = String(messageId || '');
    if (!id) return { enabled: true, ok: false, error: 'message_id_required' };
    this.exec('UPDATE nexus_messages SET deleted_at=? WHERE message_id=?', at, id);
    this.exec('INSERT INTO nexus_tombstones(entity_type, entity_id, deleted_at, purge_after, revision) VALUES (?, ?, ?, ?, ?) ON CONFLICT(entity_id) DO UPDATE SET deleted_at=excluded.deleted_at, purge_after=excluded.purge_after, revision=excluded.revision', 'message', id, at, at + Math.max(0, Number(retentionMs) || 0), Number(revision));
    this.exec('INSERT OR IGNORE INTO nexus_sync_outbox(change_id, entity_type, entity_id, operation, payload_json, revision, created_at, acknowledged_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)', `delete:${id}:${revision}`, 'message', id, 'delete', null, Number(revision), at);
    return { enabled: true, ok: true, deleted_at: at, purge_after: at + Math.max(0, Number(retentionMs) || 0) };
  }

  async pendingChanges(limit = 100) {
    await this.ensureMigrated();
    if (!this.enabled) return { enabled: false, changes: [] };
    const rows = [...this.exec('SELECT change_id, entity_type, entity_id, operation, payload_json, revision, created_at FROM nexus_sync_outbox WHERE acknowledged_at IS NULL ORDER BY created_at ASC LIMIT ?', Math.max(1, Math.min(500, Number(limit) || 100)))];
    return { enabled: true, changes: rows.map((row) => ({ ...row, payload: row.payload_json ? JSON.parse(row.payload_json) : null })) };
  }

  async acknowledgeChanges(changeIds = []) {
    await this.ensureMigrated();
    if (!this.enabled) return { enabled: false, acknowledged: 0 };
    const ids = [...new Set((Array.isArray(changeIds) ? changeIds : []).map(String).filter(Boolean))].slice(0, 500);
    const at = this.clock();
    for (const id of ids) this.exec('UPDATE nexus_sync_outbox SET acknowledged_at=? WHERE change_id=? AND acknowledged_at IS NULL', at, id);
    return { enabled: true, acknowledged: ids.length, acknowledged_at: at };
  }
}
