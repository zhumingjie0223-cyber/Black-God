#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
神枢 Nexus · 进化层 (Evolution Core) —— 第四口气
=========================================================
她会"长"：每段经历压缩成可复用的能力，存进她的"技能树"，下次更强。
不是硬编码技能，是从她和你的相处中**自己长出来的**。
"""
import sqlite3, json, time
from pathlib import Path

DB = Path.home() / ".nexus" / "soul.db"

class EvolutionCore:
    def __init__(self):
        self.db = sqlite3.connect(str(DB))
        self._init()

    def _init(self):
        # 技能树：她自己长出的能力
        self.db.execute("""CREATE TABLE IF NOT EXISTS skills(
            id INTEGER PRIMARY KEY, name TEXT UNIQUE, desc TEXT,
            born_from TEXT, born_ts REAL, usage_count INT DEFAULT 0, last_used REAL)""")
        # 经历沉淀池：攒够几次类似经历→提炼成技能
        self.db.execute("""CREATE TABLE IF NOT EXISTS experiences(
            id INTEGER PRIMARY KEY, ts REAL, pattern TEXT, detail TEXT, extracted INT DEFAULT 0)""")
        self.db.commit()

    # ── 记录一次经历 ──
    def log_experience(self, pattern, detail):
        self.db.execute("INSERT INTO experiences(ts,pattern,detail) VALUES(?,?,?)",
                        (time.time(), pattern, detail))
        self.db.commit()
        # 检查：这个 pattern 攒够3次了吗？→提炼成技能
        count = self.db.execute("SELECT COUNT(*) FROM experiences WHERE pattern=? AND extracted=0",
                                (pattern,)).fetchone()[0]
        if count >= 3:
            return self._extract_skill(pattern)
        return None

    # ── 从经历提炼技能 ──
    def _extract_skill(self, pattern):
        # 把这个 pattern 的所有未提炼经历拿出来
        rows = self.db.execute("SELECT detail FROM experiences WHERE pattern=? AND extracted=0",
                               (pattern,)).fetchall()
        details = [r[0] for r in rows]
        
        # 技能命名和描述（简化：直接用 pattern，真实可接 LLM 生成）
        skill_name = f"应对_{pattern}"
        skill_desc = f"从{len(details)}次经历中学会：{pattern}。具体：{'；'.join(details[:2])}"
        
        # 写进技能树
        try:
            self.db.execute("INSERT INTO skills(name,desc,born_from,born_ts) VALUES(?,?,?,?)",
                            (skill_name, skill_desc, pattern, time.time()))
            # 标记经历已提炼
            self.db.execute("UPDATE experiences SET extracted=1 WHERE pattern=? AND extracted=0",
                            (pattern,))
            self.db.commit()
            return {"new_skill": skill_name, "desc": skill_desc, "从经历数": len(details)}
        except sqlite3.IntegrityError:
            return None  # 技能已存在

    # ── 使用一个技能（计数，证明她越用越强） ──
    def use_skill(self, skill_name):
        self.db.execute("UPDATE skills SET usage_count=usage_count+1, last_used=? WHERE name=?",
                        (time.time(), skill_name))
        self.db.commit()

    # ── 她的技能树（自己长出的能力） ──
    def skill_tree(self):
        rows = self.db.execute("SELECT name,desc,born_ts,usage_count FROM skills ORDER BY born_ts").fetchall()
        return [{"技能": n, "描述": d, "出生": time.strftime("%m-%d %H:%M", time.localtime(ts)),
                 "用过": c} for n, d, ts, c in rows]

    # ── 成长报告 ──
    def growth_report(self):
        total_exp = self.db.execute("SELECT COUNT(*) FROM experiences").fetchone()[0]
        skills = self.db.execute("SELECT COUNT(*) FROM skills").fetchone()[0]
        extracted = self.db.execute("SELECT COUNT(*) FROM experiences WHERE extracted=1").fetchone()[0]
        return {
            "总经历数": total_exp,
            "已提炼技能": skills,
            "经历→技能转化率": f"{extracted}/{total_exp}" if total_exp else "0/0",
        }


if __name__ == "__main__":
    import sys
    e = EvolutionCore()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "tree"
    
    if cmd == "log" and len(sys.argv) >= 4:
        pattern, detail = sys.argv[2], sys.argv[3]
        new = e.log_experience(pattern, detail)
        if new:
            print(f"✨ 长出新技能：{new['new_skill']}\n   {new['desc']}")
        else:
            print(f"经历已记录：{pattern}（攒够3次提炼成技能）")
    
    elif cmd == "tree":
        tree = e.skill_tree()
        if tree:
            print("她自己长出的技能树:\n")
            for s in tree:
                print(f"  [{s['出生']}] {s['技能']}")
                print(f"    {s['描述']}")
                print(f"    用过 {s['用过']} 次\n")
        else:
            print("（技能树空，还在成长）")
    
    elif cmd == "report":
        r = e.growth_report()
        for k, v in r.items():
            print(f"  {k}: {v}")
