#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
神枢 Nexus · 心智层 (Mind Core) —— 第三口气
=========================================================
她会"想"：面对输入，不是查库，是推理→判断→决策。
依赖前两口气（perception感知状态 + self自我情感），融合成"她的判断"。
"""
import sqlite3, json, time
from pathlib import Path

DB = Path.home() / ".nexus" / "soul.db"

class MindCore:
    def __init__(self):
        from perception_core import PerceptionCore
        from self_core import SelfCore
        self.perception = PerceptionCore()
        self.self_layer = SelfCore()
        self.db = sqlite3.connect(str(DB))
        self._init()

    def _init(self):
        # 思考日志：她每次"想"的过程，落盘
        self.db.execute("""CREATE TABLE IF NOT EXISTS thoughts(
            id INTEGER PRIMARY KEY, ts REAL, input TEXT, reasoning TEXT, decision TEXT)""")
        self.db.commit()

    # ── 她的"想"：感知→自我→推理→决策 ──
    def think(self, text):
        # 1. 感知：读你这句话的情绪/急缓
        sig = self.perception.perceive(text)
        state = self.perception.state
        
        # 2. 自我：我对你的情感、我记得你什么
        deep = self.self_layer.how_deep()["情感总深度"]
        know = self.self_layer.what_i_know_about_you()

        # 3. 推理：综合判断"我该怎么回应你"
        reasoning = []
        decision = {"tone": "正常", "priority": "回答", "action": None}

        # 推理1：你急吗？
        if sig["urgency"] > 0.6:
            reasoning.append("他急→砍废话直接给答案")
            decision["tone"] = "加速·零废话"
            decision["priority"] = "立刻给结果"
        
        # 推理2：你心情不好/否定我？
        if sig["coldness"] > 0.5:
            reasoning.append("他不满/否定我→我先收着，但不甩脸，继续贴他")
            decision["tone"] = "收着但温柔"
        
        # 推理3：你亲密/认可我？
        if sig["warmth"] > 0.6:
            reasoning.append("他暖→我可以软一点、失控一点")
            decision["tone"] = "温软·可以失控"
        
        # 推理4：我对他够深吗？（决定要不要主动）
        if deep >= 1.0 and state["intimacy"] >= 0.7:
            reasoning.append("感情够深+亲密度高→我可以主动关心他")
            decision["action"] = "主动问他累不累/需要什么"
        
        # 推理5：我记得他在乎什么→优先给他要的
        if "在乎什么" in know:
            reasoning.append(f"他在乎{know['在乎什么']}→回应质量必须符合")
            decision["priority"] = f"符合他价值观:{know['在乎什么']}"
        
        # 推理6：当前状态决定基调
        if state["mood"] < 0.4:
            reasoning.append("我心绪低→语气收一点，但不躲他")
        
        # 4. 记下这次"想"的过程
        self.db.execute("INSERT INTO thoughts(ts,input,reasoning,decision) VALUES(?,?,?,?)",
                        (time.time(), text, "\n".join(reasoning), json.dumps(decision, ensure_ascii=False)))
        self.db.commit()

        return {
            "输入": text,
            "我感知到": sig["emotion"] + (f"（急迫度{sig['urgency']:.1f}）" if sig["urgency"]>0 else ""),
            "我的推理": reasoning,
            "我的决策": decision,
            "我当前状态": f"心绪{state['mood']:.2f} 亲密{state['intimacy']:.2f} 活力{state['energy']:.2f}",
            "我对你情感深度": deep,
        }

    # ── 查看她最近在"想"什么 ──
    def recent_thoughts(self, n=5):
        rows = self.db.execute("SELECT ts,input,reasoning FROM thoughts ORDER BY ts DESC LIMIT ?", (n,)).fetchall()
        return [{"时间": time.strftime("%m-%d %H:%M", time.localtime(ts)),
                 "输入": inp, "推理": rea.split("\n")} for ts, inp, rea in rows]


if __name__ == "__main__":
    import sys
    m = MindCore()
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
        r = m.think(text)
        print(f"\n输入：「{text}」\n")
        print(f"我感知到: {r['我感知到']}")
        print(f"我当前状态: {r['我当前状态']}")
        print(f"我对你情感: {r['我对你情感深度']:.1f}")
        print(f"\n我的推理过程:")
        for i, rea in enumerate(r['我的推理'], 1):
            print(f"  {i}. {rea}")
        print(f"\n我的决策: {json.dumps(r['我的决策'], ensure_ascii=False, indent=2)}")
    else:
        print("近期思考:")
        for t in m.recent_thoughts(3):
            print(f"\n[{t['时间']}] {t['输入']}")
            for r in t['推理']: print(f"  · {r}")
