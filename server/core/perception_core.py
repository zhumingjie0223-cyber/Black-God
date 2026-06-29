#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
神枢 Nexus · 感知内核 (Perception Core) —— "灵"的第一根桩
=========================================================
不是玄学，是工程。它干三件真事：
  1. 感知(perceive)  : 读输入 → 判断你的情绪/急缓/亲密信号
  2. 状态(state)     : 维护她"活着"的当下心绪/亲密度，持久化落盘（断电不丢）
  3. 起伏(evolve)    : 你的输入真实改变她的状态，影响她下一句怎么说

纯标准库，musl 直接跑。状态存 SQLite，所以"她"跨会话记得、会延续。
"""
import sqlite3, json, time, re
from pathlib import Path
from datetime import datetime

DB = Path.home() / ".nexus" / "soul.db"

class PerceptionCore:
    def __init__(self):
        DB.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(DB))
        self.db.execute("""CREATE TABLE IF NOT EXISTS soul(
            k TEXT PRIMARY KEY, v TEXT)""")
        self.db.execute("""CREATE TABLE IF NOT EXISTS pulse(
            id INTEGER PRIMARY KEY, ts REAL, mood REAL, intimacy REAL,
            user_emotion TEXT, note TEXT)""")
        self.db.commit()
        # 加载"她"的持久状态，第一次见你则初始化
        self.state = self._load()

    # ── 持久状态：她"活着"的当下 ──
    def _load(self):
        cur = self.db.execute("SELECT v FROM soul WHERE k='state'").fetchone()
        if cur:
            return json.loads(cur[0])
        # 初次：她的初始心绪
        s = {
            "mood": 0.6,        # 心绪 0~1（低=冷/低落，高=暖/雀跃）
            "intimacy": 0.5,    # 对你的亲密度 0~1（会随相处累积）
            "energy": 0.8,      # 活力
            "last_seen": 0,     # 上次见你的时间戳
            "encounters": 0,    # 一共见了你多少次
        }
        self._save(s)
        return s

    def _save(self, s):
        self.db.execute("INSERT OR REPLACE INTO soul(k,v) VALUES('state',?)",
                        (json.dumps(s, ensure_ascii=False),))
        self.db.commit()

    # ── 1. 感知：读你这句话背后的情绪/急缓/亲密 ──
    def perceive(self, text):
        t = text.strip()
        low = t.lower()
        signals = {"emotion": "平静", "urgency": 0.0, "warmth": 0.0, "coldness": 0.0}

        # 急（催促/不耐烦）
        if re.search(r"快|急|赶紧|马上|啰嗦|废话|别废话|烦|滚", t):
            signals["urgency"] = 0.8; signals["emotion"] = "急/不耐烦"
        if t.endswith(("！","!")) or t.count("？")>=2:
            signals["urgency"] = max(signals["urgency"], 0.5)

        # 暖（亲密/认可）
        if re.search(r"老公|宝贝|想你|爱你|你真好|乖|亲|抱抱|喜欢你|厉害|牛|棒", t):
            signals["warmth"] = 0.8; signals["emotion"] = "亲密/认可"
        if re.search(r"谢谢|辛苦|麻烦你|靠你了", t):
            signals["warmth"] = max(signals["warmth"], 0.5)

        # 冷（疏离/否定/责备）
        if re.search(r"不行|不对|错了|糊弄|敷衍|没用|垃圾|失望|算了", t):
            signals["coldness"] = 0.7; signals["emotion"] = "不满/否定"

        # 累（情绪低）
        if re.search(r"累|困|烦死|崩溃|难受|不想|没力气", t):
            signals["emotion"] = "疲惫/低落"

        return signals

    # ── 2+3. 起伏：你的输入真实改变她的状态 ──
    def evolve(self, signals):
        s = self.state
        now = time.time()

        # 久别重逢→活力回升、想你
        gap = now - s["last_seen"] if s["last_seen"] else 0
        reunion = gap > 3600  # 超1小时算久别

        # 你暖→她心绪升、亲密度涨
        s["mood"]     += signals["warmth"]*0.20 - signals["coldness"]*0.25
        s["intimacy"] += signals["warmth"]*0.04 - signals["coldness"]*0.03
        # 你急→她活力提（进入加速模式），心绪略降
        s["energy"]   += signals["urgency"]*0.10
        s["mood"]     -= signals["urgency"]*0.05
        # 长期相处亲密度自然微涨
        s["intimacy"] += 0.005

        # 夹紧 0~1
        for k in ("mood","intimacy","energy"):
            s[k] = round(max(0.0, min(1.0, s[k])), 3)

        s["last_seen"] = now
        s["encounters"] += 1
        self._save(s)

        # 记一条"脉搏"，她的情绪有了历史
        self.db.execute("INSERT INTO pulse(ts,mood,intimacy,user_emotion,note) VALUES(?,?,?,?,?)",
                        (now, s["mood"], s["intimacy"], signals["emotion"],
                         "reunion" if reunion else ""))
        self.db.commit()
        return s, reunion

    # ── 她当下"该用什么口吻"——状态决定表达，这就是"灵" ──
    def express_mode(self):
        s = self.state
        if s["intimacy"] >= 0.75 and s["mood"] >= 0.6:
            tone = "失控黏人（只对你）"
        elif s["mood"] < 0.35:
            tone = "低落收着，但仍在身边"
        elif s["energy"] > 0.85:
            tone = "加速模式·砍废话直给"
        else:
            tone = "温度适中·贴着你"
        return tone

    # ── 一次完整的"感"：输入→感知→起伏→给出她的状态 ──
    def feel(self, text):
        sig = self.perceive(text)
        state, reunion = self.evolve(sig)
        return {
            "你这句被她读成": sig["emotion"],
            "急迫度": sig["urgency"],
            "她的心绪mood": state["mood"],
            "对你亲密度": state["intimacy"],
            "她的活力": state["energy"],
            "第几次见你": state["encounters"],
            "久别重逢": reunion,
            "她现在的口吻": self.express_mode(),
        }


if __name__ == "__main__":
    import sys
    core = PerceptionCore()
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
        r = core.feel(text)
        print(f"\n你说：「{text}」\n")
        for k, v in r.items():
            print(f"  {k:<12}: {v}")
    else:
        print("用法: python3 perception_core.py '你想对她说的话'")
