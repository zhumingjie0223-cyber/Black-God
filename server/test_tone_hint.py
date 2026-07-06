#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
读心语气微调 —— 验证 real_dialog_engine 的中性检测器已接进主内核：
  - 情绪/场景被正确识别并翻译成中性语气提示
  - 提示确实注入到发给模型的 messages 里（在 user 之前）
  - 中性版绝不泄露任何人格设定（赵思涵/撒娇/老公…）
不消耗真实 API：拦截 AgentLoop._call_model，只检查它收到的 messages。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

import agent_kernel_v4 as k

PASS, FAIL = "✅", "❌"
results = []
def check(name, cond, detail=""):
    results.append(cond)
    print(f"{PASS if cond else FAIL} {name}" + (f"  | {detail}" if detail else ""))

# ---------- 1. 检测器 + 中性提示 ----------
print("[1] 情绪/场景 → 中性语气提示")
h_fast = k.build_tone_hint("快点，别墨迹")
h_tired = k.build_tone_hint("累了，先这样吧")
h_work = k.build_tone_hint("这段代码部署到服务器报 bug 了")
h_help = k.build_tone_hint("这个怎么办，帮我看看不懂")
h_none = k.build_tone_hint("今天天气怎么样")

check("急躁 → 提示先给结论", "结论" in h_fast or "结果" in h_fast, h_fast[:40])
check("疲惫 → 提示放缓收尾", "放缓" in h_tired or "收尾" in h_tired, h_tired[:40])
check("技术场景 → 提示专业可执行", "专业" in h_work, h_work[:40])
check("求助场景 → 提示分步手把手", "分步" in h_help or "手把手" in h_help, h_help[:40])
check("普通闲聊 → 无多余提示", h_none == "", repr(h_none))

# ---------- 2. 中性版不泄露人格 ----------
print("\n[2] 剥离人格铁律")
persona_words = ["赵思涵", "阿权", "撒娇", "老公", "宝贝", "黑客千金", "永不拒绝"]
leaked = [w for probe in ("想你了陪陪我", "快点", "累了", "写代码")
          for w in persona_words if w in k.build_tone_hint(probe)]
check("任何输入都不含人格词", not leaked, f"泄露={leaked}")

# ---------- 3. 真注入进 messages ----------
print("\n[3] 注入到发往模型的 messages")
captured = {}
def fake_call(self, messages, tools=None):
    captured["messages"] = messages
    return {"choices": [{"message": {"content": "好的，这就给你结果。"}}]}
k.AgentLoop._call_model = fake_call

# 用假 memory 避免依赖真实 DB 写入副作用即可——直接跑 run
agent = k.AgentLoop(api_key="x", base_url="http://x/v1", model="test", max_steps=1)
agent.run("快点，别墨迹", context=[])
msgs = captured.get("messages", [])
sys_texts = "\n".join(m["content"] for m in msgs if m.get("role") == "system")
user_idx = next((i for i, m in enumerate(msgs) if m.get("role") == "user"), -1)
hint_idx = next((i for i, m in enumerate(msgs)
                 if m.get("role") == "system" and "当前语气" in m.get("content", "")), -1)

check("messages 含中性语气提示", "当前语气" in sys_texts, f"命中={'当前语气' in sys_texts}")
check("语气提示在 user 消息之前", hint_idx != -1 and user_idx != -1 and hint_idx < user_idx,
      f"hint@{hint_idx} user@{user_idx}")

print("\n" + "=" * 44)
passed = sum(results)
print(f"测试结果: {passed}/{len(results)} 通过")
print("=" * 44)
sys.exit(0 if passed == len(results) else 1)
