-- Black God 本地用户系统数据库
-- 2026-06-25
-- 所有数据仅存本地，不上传云端

-- 1. 用户画像表
CREATE TABLE IF NOT EXISTS user_profile (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT UNIQUE NOT NULL,           -- 设备唯一标识
    nickname TEXT,                             -- 用户昵称/称呼偏好
    occupation TEXT,                           -- 职业
    use_scenario TEXT,                         -- 主要使用场景
    language TEXT DEFAULT 'zh-CN',             -- 语言偏好
    answer_style TEXT DEFAULT 'balanced',      -- 回答风格: short/balanced/detailed
    formality TEXT DEFAULT 'formal',           -- 正式度: formal(您)/casual(你)
    risk_tolerance TEXT DEFAULT 'safe',        -- 风险偏好: safe/moderate/aggressive
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 2. 用户行为事件表
CREATE TABLE IF NOT EXISTS user_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,                  -- app_open/message_sent/tool_used/file_uploaded/copy_clicked等
    event_data TEXT,                           -- JSON: {tool_name, task_type, category等}
    session_id TEXT,                           -- 会话ID
    timestamp TEXT NOT NULL
);

-- 3. 常用任务类型统计
CREATE TABLE IF NOT EXISTS task_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_category TEXT NOT NULL,               -- code/search/design/analysis/document
    task_intent TEXT,                          -- 具体意图
    frequency INTEGER DEFAULT 1,               -- 频次
    success_count INTEGER DEFAULT 0,           -- 成功次数
    last_used_at TEXT,
    created_at TEXT NOT NULL
);

-- 4. 工具使用偏好
CREATE TABLE IF NOT EXISTS tool_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_name TEXT NOT NULL UNIQUE,            -- python/search/calculator/file_write等
    usage_count INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    avg_duration_seconds REAL,
    last_used_at TEXT,
    preference_score REAL DEFAULT 0.5          -- 0-1: 偏好分数
);

-- 5. iOS 系统权限状态
CREATE TABLE IF NOT EXISTS permissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    permission_name TEXT NOT NULL UNIQUE,      -- photos/contacts/calendar/location等
    status TEXT NOT NULL,                      -- granted/denied/not_requested
    requested_at TEXT,
    granted_at TEXT
);

-- 6. 本地记忆索引
CREATE TABLE IF NOT EXISTS local_memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_type TEXT NOT NULL,                 -- profile/preference/knowledge/task_result
    key TEXT NOT NULL,
    value TEXT,
    tags TEXT,                                 -- JSON数组
    embedding BLOB,                            -- 可选：本地向量
    importance REAL DEFAULT 0.5,               -- 重要度 0-1
    access_count INTEGER DEFAULT 0,
    last_accessed_at TEXT,
    created_at TEXT NOT NULL
);

-- 7. 授权同意记录
CREATE TABLE IF NOT EXISTS consent_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    consent_type TEXT NOT NULL,                -- data_collection/permissions/analytics
    status TEXT NOT NULL,                      -- accepted/rejected
    version TEXT,                              -- 同意的版本号
    timestamp TEXT NOT NULL
);

-- 8. 敏感数据标记（不上传云端）
CREATE TABLE IF NOT EXISTS sensitive_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    data_type TEXT NOT NULL,                   -- password/api_key/personal_info
    content_hash TEXT NOT NULL,                -- 内容哈希（不存原文）
    category TEXT,
    created_at TEXT NOT NULL
);

-- 索引优化
CREATE INDEX IF NOT EXISTS idx_events_type ON user_events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON user_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_task_category ON task_patterns(task_category);
CREATE INDEX IF NOT EXISTS idx_tool_name ON tool_preferences(tool_name);
CREATE INDEX IF NOT EXISTS idx_memory_type ON local_memory(memory_type);
CREATE INDEX IF NOT EXISTS idx_memory_tags ON local_memory(tags);
