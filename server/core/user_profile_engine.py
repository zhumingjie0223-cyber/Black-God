#!/usr/bin/env python3
"""
Black God 用户画像引擎
仅在本地学习与存储，不上传云端
"""
import sqlite3
import json
import time
from datetime import datetime
from pathlib import Path

class UserProfileEngine:
    def __init__(self, db_path="/opt/bg-agent/memory/user_profile.db"):
        self.db_path = db_path
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self.init_db()
    
    def init_db(self):
        """初始化数据库"""
        schema_sql = Path(__file__).parent.parent / "user_profile_schema.sql"
        
        conn = sqlite3.connect(self.db_path)
        
        # 如果有schema文件，执行它
        if schema_sql.exists():
            with open(schema_sql) as f:
                conn.executescript(f.read())
        else:
            # 最小化schema
            conn.execute('''
                CREATE TABLE IF NOT EXISTS user_profile (
                    id INTEGER PRIMARY KEY,
                    device_id TEXT UNIQUE NOT NULL,
                    nickname TEXT,
                    occupation TEXT,
                    formality TEXT DEFAULT 'formal',
                    answer_style TEXT DEFAULT 'balanced',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            ''')
            conn.execute('''
                CREATE TABLE IF NOT EXISTS user_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_type TEXT NOT NULL,
                    event_data TEXT,
                    timestamp TEXT NOT NULL
                )
            ''')
            conn.execute('''
                CREATE TABLE IF NOT EXISTS consent_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    consent_type TEXT NOT NULL,
                    status TEXT NOT NULL,
                    version TEXT,
                    timestamp TEXT NOT NULL
                )
            ''')
        
        conn.commit()
        conn.close()
    
    def check_consent(self):
        """检查用户是否同意数据采集"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        c.execute('''
            SELECT status FROM consent_log 
            WHERE consent_type = 'data_collection' 
            ORDER BY timestamp DESC LIMIT 1
        ''')
        
        result = c.fetchone()
        conn.close()
        
        if not result:
            return None  # 未询问
        
        return result[0] == 'accepted'
    
    def record_consent(self, consent_type, status, version="1.0"):
        """记录用户同意状态"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        c.execute('''
            INSERT INTO consent_log (consent_type, status, version, timestamp)
            VALUES (?, ?, ?, ?)
        ''', (consent_type, status, version, datetime.now().isoformat()))
        
        conn.commit()
        conn.close()
    
    def get_or_create_profile(self, device_id):
        """获取或创建用户画像"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        c.execute('SELECT * FROM user_profile WHERE device_id = ?', (device_id,))
        profile = c.fetchone()
        
        if not profile:
            now = datetime.now().isoformat()
            c.execute('''
                INSERT INTO user_profile 
                (device_id, formality, answer_style, created_at, updated_at)
                VALUES (?, 'formal', 'balanced', ?, ?)
            ''', (device_id, now, now))
            conn.commit()
            
            c.execute('SELECT * FROM user_profile WHERE device_id = ?', (device_id,))
            profile = c.fetchone()
        
        conn.close()
        return dict(profile) if profile else None
    
    def update_profile(self, device_id, **kwargs):
        """更新用户画像"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        fields = []
        values = []
        for key, value in kwargs.items():
            fields.append(f"{key} = ?")
            values.append(value)
        
        if fields:
            fields.append("updated_at = ?")
            values.append(datetime.now().isoformat())
            values.append(device_id)
            
            sql = f"UPDATE user_profile SET {', '.join(fields)} WHERE device_id = ?"
            c.execute(sql, values)
            conn.commit()
        
        conn.close()
    
    def log_event(self, event_type, event_data=None):
        """记录用户行为事件（本地）"""
        # 先检查是否同意
        if not self.check_consent():
            return False
        
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        c.execute('''
            INSERT INTO user_events (event_type, event_data, timestamp)
            VALUES (?, ?, ?)
        ''', (event_type, json.dumps(event_data) if event_data else None, datetime.now().isoformat()))
        
        conn.commit()
        conn.close()
        return True
    
    def analyze_preferences(self, device_id):
        """分析用户偏好（基于本地事件）"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        # 分析最近100条事件
        c.execute('''
            SELECT event_type, event_data FROM user_events 
            ORDER BY timestamp DESC LIMIT 100
        ''')
        
        events = c.fetchall()
        conn.close()
        
        if not events:
            return {}
        
        # 统计
        preferences = {
            'message_count': 0,
            'tool_usage': {},
            'copy_count': 0,
            'upload_count': 0,
            'task_categories': {}
        }
        
        for event_type, event_data_str in events:
            event_data = json.loads(event_data_str) if event_data_str else {}
            
            if event_type == 'message_sent':
                preferences['message_count'] += 1
            elif event_type == 'tool_used':
                tool = event_data.get('tool_name', 'unknown')
                preferences['tool_usage'][tool] = preferences['tool_usage'].get(tool, 0) + 1
            elif event_type == 'copy_clicked':
                preferences['copy_count'] += 1
            elif event_type == 'file_uploaded':
                preferences['upload_count'] += 1
            
            # 任务类型
            category = event_data.get('category')
            if category:
                preferences['task_categories'][category] = preferences['task_categories'].get(category, 0) + 1
        
        return preferences
    
    def get_agent_hint(self, device_id):
        """生成给 Agent 的用户画像提示（本地生成，不上传原始数据）"""
        profile = self.get_or_create_profile(device_id)
        if not profile:
            return ""
        
        prefs = self.analyze_preferences(device_id)
        
        hints = []
        
        # 称呼方式
        formality = profile.get('formality', 'formal')
        if formality == 'formal':
            hints.append("称呼用户为'您'")
        else:
            hints.append("称呼用户为'你'")
        
        # 回答风格
        style = profile.get('answer_style', 'balanced')
        if style == 'short':
            hints.append("回答简短直接")
        elif style == 'detailed':
            hints.append("回答详细完整")
        
        # 常用工具
        top_tools = sorted(prefs.get('tool_usage', {}).items(), key=lambda x: x[1], reverse=True)[:3]
        if top_tools:
            tool_names = [t[0] for t in top_tools]
            hints.append(f"常用工具: {', '.join(tool_names)}")
        
        # 任务类型
        top_cats = sorted(prefs.get('task_categories', {}).items(), key=lambda x: x[1], reverse=True)[:2]
        if top_cats:
            cat_names = [c[0] for c in top_cats]
            hints.append(f"常做任务: {', '.join(cat_names)}")
        
        # 复制习惯
        if prefs.get('copy_count', 0) > 10:
            hints.append("用户喜欢复制结果，重要内容突出展示")
        
        return " | ".join(hints) if hints else ""

if __name__ == "__main__":
    # 测试
    engine = UserProfileEngine("/tmp/test_profile.db")
    
    # 模拟首次同意
    engine.record_consent('data_collection', 'accepted')
    
    # 创建画像
    profile = engine.get_or_create_profile('test_device_001')
    print(f"画像: {profile}")
    
    # 更新画像
    engine.update_profile('test_device_001', nickname='测试用户', occupation='开发者')
    
    # 记录事件
    engine.log_event('message_sent', {'category': 'coding'})
    engine.log_event('tool_used', {'tool_name': 'python', 'category': 'coding'})
    engine.log_event('copy_clicked', {})
    
    # 生成提示
    hint = engine.get_agent_hint('test_device_001')
    print(f"Agent提示: {hint}")
    
    print("\n✓ 用户画像引擎测试通过")
