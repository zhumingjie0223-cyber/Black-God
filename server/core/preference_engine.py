#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Black God Preference Engine：越用越懂你（用户同意后启用）"""
import sqlite3, time, json, pathlib, collections
ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = ROOT / "memory" / "preferences.db"
DB.parent.mkdir(exist_ok=True)

def conn():
    c=sqlite3.connect(str(DB), check_same_thread=False)
    c.execute("CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY, event TEXT, payload TEXT, ts REAL)")
    c.execute("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)")
    c.commit(); return c

def enabled():
    c=conn(); r=c.execute("SELECT value FROM settings WHERE key='enabled'").fetchone(); c.close()
    return (r and r[0]=='1')

def set_enabled(v):
    c=conn(); c.execute("INSERT OR REPLACE INTO settings(key,value) VALUES('enabled',?)",('1' if v else '0',)); c.commit(); c.close()

def log_event(event, payload=None):
    if not enabled(): return False
    c=conn(); c.execute("INSERT INTO events(event,payload,ts) VALUES(?,?,?)",(event,json.dumps(payload or {},ensure_ascii=False),time.time())); c.commit(); c.close(); return True

def clear():
    c=conn(); c.execute("DELETE FROM events"); c.commit(); c.close()

def profile(limit=500):
    c=conn(); rows=c.execute("SELECT event,payload,ts FROM events ORDER BY id DESC LIMIT ?",(limit,)).fetchall(); c.close()
    events=[]
    for e,p,t in rows:
        try: payload=json.loads(p or '{}')
        except: payload={}
        events.append((e,payload,t))
    cnt=collections.Counter(e for e,_,__ in events)
    tools=collections.Counter(p.get('tool') for e,p,t in events if p.get('tool'))
    tasks=collections.Counter(p.get('task_type') for e,p,t in events if p.get('task_type'))
    copies=cnt.get('copy_clicked',0)
    style='short_direct' if copies>=3 else 'balanced'
    return {
        'enabled': enabled(),
        'event_count': len(events),
        'top_events': cnt.most_common(8),
        'favorite_tools': tools.most_common(8),
        'favorite_tasks': tasks.most_common(8),
        'copy_usage': 'high' if copies>=3 else 'normal',
        'answer_style': style,
        'agent_hint': build_hint(style, tools, tasks)
    }

def build_hint(style, tools, tasks):
    parts=[]
    if style=='short_direct': parts.append('用户偏好简短直接，先给结论和可复制结果。')
    if tools: parts.append('用户常用工具：'+ '、'.join(t for t,_ in tools.most_common(3) if t))
    if tasks: parts.append('用户常做任务：'+ '、'.join(t for t,_ in tasks.most_common(3) if t))
    return '\n'.join(parts) or '暂无明显偏好，保持清晰、直接、可验证。'
