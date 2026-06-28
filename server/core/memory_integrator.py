#!/usr/bin/env python3
"""
Black God 记忆自动整合系统（修复版）
"""
import sqlite3, json, time
from pathlib import Path

MEM_DB = Path("/opt/bg-agent/memory/memory.db")
TASKS_LOG = Path("/opt/bg-agent/memory/tasks.jsonl")

def init_memory_db():
    conn = sqlite3.connect(MEM_DB)
    
    # 创建基础表
    conn.execute("""
        CREATE TABLE IF NOT EXISTS mem(
            id INTEGER PRIMARY KEY, 
            content TEXT, 
            tags TEXT,
            weight REAL DEFAULT 1.0, 
            ts REAL
        )
    """)
    
    # 添加新列（如果不存在）
    try:
        conn.execute("ALTER TABLE mem ADD COLUMN source TEXT")
    except sqlite3.OperationalError:
        pass  # 列已存在
    
    try:
        conn.execute("ALTER TABLE mem ADD COLUMN task_id TEXT")
    except sqlite3.OperationalError:
        pass  # 列已存在
    
    # 创建索引
    conn.execute("CREATE INDEX IF NOT EXISTS idx_tags ON mem(tags)")
    try:
        conn.execute("CREATE INDEX IF NOT EXISTS idx_task ON mem(task_id)")
    except:
        pass
    
    conn.commit()
    return conn

def extract_key_info(task, answer, steps):
    """从任务中提取关键信息"""
    memories = []
    
    # 1. 代码执行
    if any(s.get('tool') == 'python' for s in steps):
        code_results = [s['result'] for s in steps if s.get('tool') == 'python']
        if code_results:
            memories.append({
                'content': f"代码: {task[:50]}... = {code_results[0][:50]}",
                'tags': 'code',
                'weight': 1.2
            })
    
    # 2. 用户偏好
    if any(k in task.lower() for k in ['喜欢', '偏好', '记住']):
        memories.append({
            'content': f"偏好: {task}",
            'tags': 'preference',
            'weight': 2.0
        })
    
    # 3. 重要操作
    if any(k in task.lower() for k in ['部署', '删除', '修改']):
        memories.append({
            'content': f"操作: {task} → {answer[:50]}",
            'tags': 'ops',
            'weight': 1.5
        })
    
    return memories

def auto_remember():
    """自动记忆整合"""
    if not TASKS_LOG.exists():
        return 0
    
    conn = init_memory_db()
    cursor = conn.cursor()
    
    tasks = []
    with open(TASKS_LOG, 'r') as f:
        for line in f:
            try:
                tasks.append(json.loads(line))
            except:
                pass
    
    count = 0
    for t in tasks[-50:]:
        task_id = t.get('id', '')
        
        # 检查是否已处理
        exists = cursor.execute(
            "SELECT 1 FROM mem WHERE task_id=? LIMIT 1", 
            (task_id,)
        ).fetchone()
        if exists:
            continue
        
        memories = extract_key_info(
            t.get('task', ''),
            t.get('answer', ''),
            t.get('steps', [])
        )
        
        for mem in memories:
            cursor.execute("""
                INSERT INTO mem(content, tags, weight, ts, source, task_id)
                VALUES (?, ?, ?, ?, 'auto', ?)
            """, (
                mem['content'],
                mem['tags'],
                mem['weight'],
                t.get('ts', time.time()),
                task_id
            ))
            count += 1
    
    conn.commit()
    conn.close()
    return count

if __name__ == "__main__":
    print("🧠 修复并运行记忆整合...")
    count = auto_remember()
    print(f"✅ 完成！新增 {count} 条记忆")
