#!/usr/bin/env python3
# ⚠️ DEPRECATED(方案① · 2026-07-13)——本模块属"大脑常驻"能力,已划归 CF 主轨 web/nexus-do。
# 详见 docs/architecture/双轨边界-方案①.md。勿在此扩展 对话/情绪/记忆/偏好/画像 逻辑,统一走 nexus-do;
# Python server/ 已降级为按需重活后端,本文件待 CF 主轨功能对等后归档(现阶段只标记,不删除)。
"""
Black God 技能索引引擎
负责扫描、分类、索引所有技能
"""
import sqlite3
import json
import os
from pathlib import Path
from datetime import datetime

class SkillIndexEngine:
    def __init__(self, db_path="/opt/bg-agent/memory/skills.db"):
        self.db_path = db_path
        self.init_db()
    
    def init_db(self):
        """初始化技能数据库"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        c.execute('''
            CREATE TABLE IF NOT EXISTS skills (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                display_name TEXT,
                category TEXT NOT NULL,
                level TEXT NOT NULL,
                status TEXT NOT NULL,
                description TEXT,
                keywords TEXT,
                trigger_examples TEXT,
                path TEXT,
                safety_level TEXT DEFAULT 'safe',
                verified BOOLEAN DEFAULT 0,
                usage_count INTEGER DEFAULT 0,
                success_count INTEGER DEFAULT 0,
                fail_count INTEGER DEFAULT 0,
                last_used_at TEXT,
                created_at TEXT,
                updated_at TEXT
            )
        ''')
        
        c.execute('CREATE INDEX IF NOT EXISTS idx_category ON skills(category)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_level ON skills(level)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_status ON skills(status)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_safety ON skills(safety_level)')
        
        conn.commit()
        conn.close()
        
    def scan_skills(self, skills_dir="/var/minis/skills"):
        """扫描技能目录"""
        skills = []
        for skill_path in Path(skills_dir).iterdir():
            if not skill_path.is_dir():
                continue
            
            skill_md = skill_path / "SKILL.md"
            if not skill_md.exists():
                continue
                
            skill_data = self.parse_skill(skill_md, skill_path.name)
            if skill_data:
                skills.append(skill_data)
        
        return skills
    
    def parse_skill(self, skill_file, skill_id):
        """解析技能文件"""
        try:
            content = skill_file.read_text(encoding='utf-8')
            
            # 提取技能名称
            name = skill_id
            for line in content.split('\n')[:10]:
                if line.startswith('# '):
                    name = line.lstrip('# ').strip()
                    break
            
            # 自动分类
            category = self.auto_categorize(skill_id, content)
            level = self.auto_level(skill_id, content)
            status = "active"
            safety_level = self.auto_safety(skill_id, content)
            
            # 提取描述
            desc_lines = []
            for line in content.split('\n')[1:20]:
                if line.strip() and not line.startswith('#'):
                    desc_lines.append(line.strip())
                    if len(desc_lines) >= 3:
                        break
            description = ' '.join(desc_lines)[:200]
            
            return {
                'id': skill_id,
                'name': name,
                'display_name': name,
                'category': category,
                'level': level,
                'status': status,
                'description': description,
                'path': str(skill_file.parent),
                'safety_level': safety_level,
                'verified': 1 if level in ['S', 'A'] else 0,
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }
        except Exception as e:
            print(f"解析技能失败 {skill_id}: {e}")
            return None
    
    def auto_categorize(self, skill_id, content):
        """自动分类"""
        content_lower = (skill_id + content[:500]).lower()
        
        # 智能对话
        if any(k in content_lower for k in ['chat', 'conversation', 'dialog', '对话', 'agent', 'hermes']):
            return "智能对话"
        
        # 创作设计
        if any(k in content_lower for k in ['ui', 'design', 'logo', 'poster', 'color', '设计', '海报', '视觉']):
            return "创作设计"
        
        # 信息获取
        if any(k in content_lower for k in ['search', 'web', 'crawler', 'scrape', '搜索', 'bilibili', 'twitter', 'weibo']):
            return "信息获取"
        
        # 开发工程
        if any(k in content_lower for k in ['code', 'git', 'deploy', 'debug', '开发', '部署', 'python', 'js']):
            return "开发工程"
        
        # 数据分析
        if any(k in content_lower for k in ['data', 'analysis', 'stock', 'chart', '分析', '统计', 'sql']):
            return "数据分析"
        
        # 安全工具
        if any(k in content_lower for k in ['security', 'hack', 'penetrate', 'wallet', '安全', '恢复', 'phantom']):
            return "安全工具"
        
        return "其他"
    
    def auto_level(self, skill_id, content):
        """自动评级"""
        content_lower = skill_id.lower()
        
        # S级：核心能力
        s_keywords = ['ui-master', 'web-search', 'skill-creator', 'media-ingest', 'human-understand']
        if any(k in content_lower for k in s_keywords):
            return "S"
        
        # A级：重要技能
        a_keywords = ['hub', 'downloader', 'search', 'design', 'logo', 'poster']
        if any(k in content_lower for k in a_keywords):
            return "A"
        
        # B级：辅助技能
        b_keywords = ['helper', 'tool', 'util']
        if any(k in content_lower for k in b_keywords):
            return "B"
        
        return "C"
    
    def auto_safety(self, skill_id, content):
        """安全评级"""
        content_lower = (skill_id + content[:500]).lower()
        
        # 高危技能
        danger_keywords = [
            'hack', 'penetrate', 'exploit', 'malware', 'backdoor',
            'wallet-recovery', 'keylogger', 'ransomware'
        ]
        if any(k in content_lower for k in danger_keywords):
            return "dangerous"
        
        # 内部专用
        internal_keywords = ['hermes-agent', 'okx-wallet', 'claude-official-caller']
        if any(k in content_lower for k in internal_keywords):
            return "internal_only"
        
        return "safe"
    
    def import_skills(self, skills):
        """导入技能到数据库"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        for skill in skills:
            c.execute('''
                INSERT OR REPLACE INTO skills 
                (id, name, display_name, category, level, status, description, 
                 path, safety_level, verified, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                skill['id'], skill['name'], skill['display_name'],
                skill['category'], skill['level'], skill['status'],
                skill['description'], skill['path'], skill['safety_level'],
                skill['verified'], skill['created_at'], skill['updated_at']
            ))
        
        conn.commit()
        conn.close()
    
    def get_skills(self, category=None, level=None, safety_filter=True):
        """获取技能列表"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        
        query = "SELECT * FROM skills WHERE 1=1"
        params = []
        
        if category:
            query += " AND category = ?"
            params.append(category)
        
        if level:
            query += " AND level = ?"
            params.append(level)
        
        if safety_filter:
            query += " AND safety_level NOT IN ('dangerous', 'internal_only')"
        
        query += " ORDER BY level ASC, usage_count DESC"
        
        c.execute(query, params)
        skills = [dict(row) for row in c.fetchall()]
        conn.close()
        
        return skills
    
    def get_stats(self):
        """获取统计信息"""
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        
        stats = {}
        
        # 总数
        c.execute("SELECT COUNT(*) FROM skills")
        stats['total'] = c.fetchone()[0]
        
        # 分类统计
        c.execute("SELECT category, COUNT(*) FROM skills GROUP BY category")
        stats['by_category'] = dict(c.fetchall())
        
        # 等级统计
        c.execute("SELECT level, COUNT(*) FROM skills GROUP BY level")
        stats['by_level'] = dict(c.fetchall())
        
        # 安全级别统计
        c.execute("SELECT safety_level, COUNT(*) FROM skills GROUP BY safety_level")
        stats['by_safety'] = dict(c.fetchall())
        
        conn.close()
        return stats

if __name__ == "__main__":
    engine = SkillIndexEngine()
    print("扫描技能目录...")
    skills = engine.scan_skills()
    print(f"发现 {len(skills)} 个技能")
    
    print("导入数据库...")
    engine.import_skills(skills)
    
    stats = engine.get_stats()
    print("\n技能统计:")
    print(f"总数: {stats['total']}")
    print(f"分类: {stats['by_category']}")
    print(f"等级: {stats['by_level']}")
    print(f"安全: {stats['by_safety']}")
    
    print("\n✓ 技能索引完成")
