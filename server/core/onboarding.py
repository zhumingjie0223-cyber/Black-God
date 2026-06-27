#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
onboarding.py — Black God 首次使用引导 + 本地数据采集 + 行为分析

核心理念：「一个懂你生活工作方式的助理」
- 首次使用：逐项申请权限，说清楚为什么要、用来干什么
- 数据采集：全部本地存储（SQLite），绝不上云
- 行为分析：分析使用习惯 → 生成用户画像 → 喂给 Black God
- 自动适应：Black God 根据画像调整语气、风格、主动推送内容
"""
import json
import time
import sqlite3
import pathlib
import os

ROOT = pathlib.Path(__file__).parent.parent
LOCAL_DB = ROOT / "memory" / "user_local.db"

# ─────────────────────────────────────────
# 权限清单（逐项引导，说清楚为什么）
# ─────────────────────────────────────────
PERMISSIONS = [
    {
        "id": "device",
        "name": "设备状态",
        "icon": "📱",
        "why": "了解你的电量和存储，在你快没电时提醒你保存工作，避免任务中断",
        "data": ["电量", "存储空间", "网络状态"],
        "required": False
    },
    {
        "id": "location",
        "name": "位置信息",
        "icon": "📍",
        "why": "记住你的常驻地点（家/公司），在正确的地点给你推送相关信息",
        "data": ["当前位置", "常驻地点"],
        "required": False
    },
    {
        "id": "health",
        "name": "健康数据",
        "icon": "❤️",
        "why": "了解你的作息规律，在你状态最好的时间给你安排重要任务",
        "data": ["步数", "睡眠时间", "心率趋势"],
        "required": False
    },
    {
        "id": "calendar",
        "name": "日历与提醒",
        "icon": "📅",
        "why": "了解你的日程，主动在合适时间提醒你，不在你开会时打扰你",
        "data": ["日程事件", "空闲时间段"],
        "required": False
    },
    {
        "id": "clipboard",
        "name": "剪贴板",
        "icon": "📋",
        "why": "当你复制了内容，主动帮你分析或处理，不用重复粘贴",
        "data": ["复制的文字内容"],
        "required": False
    },
    {
        "id": "behavior",
        "name": "使用行为",
        "icon": "📊",
        "why": "分析你最常用的功能和使用时间，自动优化界面和回复风格",
        "data": ["使用时间", "常用功能", "对话风格偏好"],
        "required": True  # 这个必须，没有它无法「懂你」
    }
]


# ─────────────────────────────────────────
# 本地数据存储（全部在设备上，不上云）
# ─────────────────────────────────────────
class LocalDataStore:
    """本地数据存储 — 所有数据只存在设备本地"""

    def __init__(self, db_path=LOCAL_DB):
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(db_path), check_same_thread=False)
        self._init_tables()

    def _init_tables(self):
        self.conn.executescript("""
            -- 权限授权记录
            CREATE TABLE IF NOT EXISTS permissions (
                id TEXT PRIMARY KEY,
                granted INTEGER DEFAULT 0,
                granted_at REAL,
                reason TEXT
            );

            -- 行为日志（每次交互）
            CREATE TABLE IF NOT EXISTS behavior_log (
                id INTEGER PRIMARY KEY,
                ts REAL,
                action TEXT,       -- 'chat' / 'tool_use' / 'skill_trigger'
                detail TEXT,       -- 具体内容
                duration REAL,     -- 耗时秒
                satisfaction INTEGER  -- 1=好 0=差 NULL=未评
            );

            -- 设备快照（定期采集，不实时上传）
            CREATE TABLE IF NOT EXISTS device_snapshots (
                id INTEGER PRIMARY KEY,
                ts REAL,
                battery_pct INTEGER,
                storage_free_gb REAL,
                network TEXT
            );

            -- 位置习惯（只存常驻地点，不存轨迹）
            CREATE TABLE IF NOT EXISTS location_habits (
                id INTEGER PRIMARY KEY,
                label TEXT,        -- '家' / '公司' / '咖啡馆'
                visit_count INTEGER DEFAULT 0,
                typical_hours TEXT  -- JSON: [9, 10, 11]
            );

            -- 健康规律（只存规律，不存原始数据）
            CREATE TABLE IF NOT EXISTS health_patterns (
                id INTEGER PRIMARY KEY,
                date TEXT,
                sleep_start TEXT,  -- '23:30'
                sleep_end TEXT,    -- '07:00'
                peak_hour INTEGER, -- 效率最高的小时
                steps INTEGER
            );

            -- 用户画像（分析结果，定期更新）
            CREATE TABLE IF NOT EXISTS user_profile (
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at REAL
            );
        """)
        self.conn.commit()

    def save_permission(self, perm_id, granted, reason=""):
        self.conn.execute(
            "INSERT OR REPLACE INTO permissions VALUES (?,?,?,?)",
            (perm_id, 1 if granted else 0, time.time(), reason)
        )
        self.conn.commit()

    def get_permissions(self):
        rows = self.conn.execute("SELECT id, granted FROM permissions").fetchall()
        return {r[0]: bool(r[1]) for r in rows}

    def log_behavior(self, action, detail="", duration=0.0):
        self.conn.execute(
            "INSERT INTO behavior_log(ts,action,detail,duration) VALUES(?,?,?,?)",
            (time.time(), action, detail[:200], duration)
        )
        self.conn.commit()

    def save_device_snapshot(self, battery_pct, storage_free_gb, network):
        self.conn.execute(
            "INSERT INTO device_snapshots(ts,battery_pct,storage_free_gb,network) VALUES(?,?,?,?)",
            (time.time(), battery_pct, storage_free_gb, network)
        )
        self.conn.commit()

    def update_profile(self, key, value):
        self.conn.execute(
            "INSERT OR REPLACE INTO user_profile VALUES(?,?,?)",
            (key, json.dumps(value, ensure_ascii=False), time.time())
        )
        self.conn.commit()

    def get_profile(self):
        rows = self.conn.execute("SELECT key, value FROM user_profile").fetchall()
        return {r[0]: json.loads(r[1]) for r in rows}

    def get_behavior_stats(self, days=7):
        since = time.time() - days * 86400
        rows = self.conn.execute(
            "SELECT action, detail, ts FROM behavior_log WHERE ts > ? ORDER BY ts DESC",
            (since,)
        ).fetchall()
        return rows


# ─────────────────────────────────────────
# 行为分析引擎（本地运行，不上云）
# ─────────────────────────────────────────
class BehaviorAnalyzer:
    """分析本地行为数据 → 生成用户画像 → 喂给 Black God"""

    def __init__(self, store: LocalDataStore):
        self.store = store

    def analyze(self) -> dict:
        """
        分析最近 7 天行为，生成用户画像
        返回：画像 dict，直接注入 Black God 第 8 层 Context
        """
        stats = self.store.get_behavior_stats(days=7)
        existing = self.store.get_profile()  # 已有的持久化画像

        insights = {}

        # 1. 使用时间规律（直接从数据库聚合，更准确）
        if stats:
            hours = [int(time.strftime('%H', time.localtime(r[2]))) for r in stats]
            from collections import Counter
            hour_counter = Counter(hours)
            peak = hour_counter.most_common(1)[0][0] if hour_counter else 10
            insights["active_hour"] = peak
            insights["active_period"] = (
                "深夜型" if peak >= 22 or peak <= 2
                else "夜猫子" if peak >= 20
                else "晚间型" if peak >= 18
                else "下午型" if peak >= 14
                else "上午型" if peak >= 9
                else "早起型"
            )

        # 2. 最常用功能（全量统计，不分页）
        if stats:
            from collections import Counter
            action_counter = Counter(r[0] for r in stats)
            insights["top_actions"] = action_counter.most_common(3)

        # 3. 对话风格偏好（从 detail 里分析消息长度）
        chat_logs = [r[1] for r in stats if r[0] == 'chat']
        if chat_logs:
            avg_len = sum(len(c) for c in chat_logs) / len(chat_logs)
            insights["chat_style"] = (
                "简洁型" if avg_len < 15
                else "正常型" if avg_len < 50
                else "详细型"
            )
        elif existing.get("chat_style"):
            insights["chat_style"] = existing["chat_style"]

        # 4. 保留用户基础信息（不被分析结果覆盖）
        for key in ["name", "self_desc", "onboarded_at", "first_seen"]:
            if key in existing:
                insights[key] = existing[key]

        # 5. 生成 Black God 适应指令
        adapt = self._generate_adaptation(insights)
        insights["adaptation"] = adapt

        # 存回数据库（覆盖更新）
        for key, val in insights.items():
            self.store.update_profile(key, val)

        return insights
        insights["adaptation"] = adapt

        # 存回数据库
        for key, val in insights.items():
            self.store.update_profile(key, val)

        return insights

    def _generate_adaptation(self, insights: dict) -> dict:
        """
        根据用户画像，生成 Black God 的自适应配置
        这会直接注入 CONSTITUTION 第 8 层
        """
        adapt = {}

        # 回复风格
        style = insights.get("chat_style", "正常型")
        if style == "简洁型":
            adapt["reply_style"] = "极简：每条回复不超过 3 句话，不解释废话"
        elif style == "详细型":
            adapt["reply_style"] = "详尽：给出完整背景、步骤、注意事项"
        else:
            adapt["reply_style"] = "平衡：关键信息完整，不啰嗦"

        # 主动提醒时机
        peak = insights.get("active_hour", 10)
        adapt["best_notify_hour"] = peak
        adapt["avoid_notify_hours"] = list(range(0, 7))  # 凌晨不打扰

        # 常用功能优先展示
        top = insights.get("top_actions", [])
        if top:
            adapt["priority_features"] = [t[0] for t in top[:3]]

        return adapt


# ─────────────────────────────────────────
# 首次使用引导（返回 JSON 给前端渲染）
# ─────────────────────────────────────────
class OnboardingManager:
    """首次使用引导 — 权限申请 + 初始化本地数据库"""

    def __init__(self):
        self.store = LocalDataStore()

    def is_onboarded(self) -> bool:
        """是否已完成引导"""
        perms = self.store.get_permissions()
        return "behavior" in perms  # behavior 是必须权限，有了就算完成

    def get_onboarding_flow(self) -> dict:
        """返回引导流程配置（给前端渲染）"""
        return {
            "title": "在我真正懂你之前，需要先认识你",
            "subtitle": "你授权的数据只存在你的手机本地，永远不会上传到云端",
            "privacy_promise": [
                "✅ 所有数据只存在你的设备上",
                "✅ 不传云端，不发给任何第三方",
                "✅ 你可以随时查看或删除所有数据",
                "✅ 你可以选择不授权，但部分「懂你」功能会降级"
            ],
            "permissions": PERMISSIONS,
            "default_rule": "如果你不同意授权，Black God 仍然可以使用，但只能根据你当前对话来理解你，无法记住你的生活习惯"
        }

    def apply_permission(self, perm_id: str, granted: bool, reason: str = "") -> dict:
        """用户授权某个权限"""
        self.store.save_permission(perm_id, granted, reason)
        return {
            "ok": True,
            "perm_id": perm_id,
            "granted": granted,
            "message": f"✅ 已{'授权' if granted else '跳过'} {perm_id}"
        }

    def complete_onboarding(self, user_name: str = "", user_desc: str = "") -> dict:
        """完成引导，初始化用户画像"""
        # 存入基础信息
        if user_name:
            self.store.update_profile("name", user_name)
        if user_desc:
            self.store.update_profile("self_desc", user_desc)

        self.store.update_profile("onboarded_at", time.time())
        self.store.update_profile("first_seen", time.strftime("%Y-%m-%d"))

        # 标记 behavior 权限（必须项，完成引导即默认授权）
        self.store.save_permission("behavior", True, "完成引导流程")

        return {
            "ok": True,
            "message": "Black God 已初始化，开始了解你的习惯",
            "next": "开始对话，我会在使用中慢慢了解你"
        }


# ─────────────────────────────────────────
# 对外接口：生成第 8 层 Context（注入 CONSTITUTION）
# ─────────────────────────────────────────
_store = None
_analyzer = None

def get_store():
    global _store
    if not _store:
        _store = LocalDataStore()
    return _store

def get_behavior_context() -> str:
    """
    生成第 8 层动态 Context，注入 CONSTITUTION
    每次对话开始时调用，把用户画像和行为洞察注入给模型
    """
    global _analyzer
    store = get_store()
    if not _analyzer:
        _analyzer = BehaviorAnalyzer(store)

    try:
        profile = _analyzer.analyze()
    except Exception:
        profile = {}

    if not profile:
        return "（用户画像：暂无数据，正在通过对话了解中）"

    lines = ["【用户画像 — Black God 行为分析结果】"]

    if "active_period" in profile:
        lines.append(f"使用习惯：{profile['active_period']}（高峰 {profile.get('active_hour', '?')}点）")

    if "chat_style" in profile:
        lines.append(f"对话风格：{profile['chat_style']}")

    if "adaptation" in profile:
        adapt = profile["adaptation"]
        if isinstance(adapt, dict):
            if "reply_style" in adapt:
                lines.append(f"回复要求：{adapt['reply_style']}")

    if "name" in profile:
        lines.append(f"用户称呼：{profile['name']}")

    if "self_desc" in profile:
        lines.append(f"用户自述：{profile['self_desc']}")

    lines.append("\n根据以上画像，自动调整你的回复风格和主动推送策略。")

    return "\n".join(lines)


def log_interaction(action: str, detail: str = "", duration: float = 0.0):
    """记录一次交互行为（供 openai_agent 调用）"""
    try:
        get_store().log_behavior(action, detail, duration)
    except Exception:
        pass
