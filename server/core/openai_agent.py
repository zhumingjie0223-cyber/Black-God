#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God Agent —— OpenAI 兼容驱动（适配中转站 apiclaude.cc）
用 OpenAI tools 协议调真 Claude。工具调用 + 多步 loop + 路2强制路由。
"""
import os, re, json, time, urllib.request, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from agent_kernel import Memory, SkillSystem, CONSTITUTION
from power_tools import POWER_TOOLS
from heavy_tools import HEAVY_TOOLS
import reflexion
import multi_agent
import adaptive_reasoning
import self_evolving
try:
    from preference_engine import profile as preference_profile
except Exception:
    preference_profile = None

# 记忆工具
def _t_remember(a):
    Memory().remember(a.get("content", ""), tags="agent"); return "已记住"
def _t_recall(a):
    return "\n".join(Memory().recall(a.get("keyword", ""))) or "无记忆"

ALL_TOOLS = dict(POWER_TOOLS); ALL_TOOLS.update(HEAVY_TOOLS)
ALL_TOOLS["remember"] = ("存长期记忆", _t_remember,
    {"type": "object", "properties": {"content": {"type": "string"}}, "required": ["content"]})
ALL_TOOLS["recall"] = ("查长期记忆", _t_recall,
    {"type": "object", "properties": {"keyword": {"type": "string"}}, "required": ["keyword"]})

# OpenAI tools 格式
OPENAI_TOOLS = [{"type": "function", "function": {
    "name": n, "description": d, "parameters": s}} for n, (d, f, s) in ALL_TOOLS.items()]

def run_tool(name, args):
    item = ALL_TOOLS.get(name)
    return item[1](args or {}) if item else f"未知工具:{name}"

def safe_json_args(raw):
    """中转站可能返回脏 arguments，如 '{}{...}'，做兜底解析。
    code 等字段可能含花括号，用括号配平而非简单正则。"""
    if isinstance(raw, dict): return raw
    if not raw or not raw.strip(): return {}
    raw = raw.strip()
    # 直接尝试
    try:
        d = json.loads(raw)
        if isinstance(d, dict) and d: return d
    except: pass
    # 处理 '{}{...}' 这类：找所有顶层 JSON 对象，取最后一个非空的
    objs, depth, start = [], 0, -1
    for i, ch in enumerate(raw):
        if ch == '{':
            if depth == 0: start = i
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0 and start >= 0:
                objs.append(raw[start:i+1]); start = -1
    for o in reversed(objs):
        for candidate in (o, o.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")):
            try:
                d = json.loads(candidate)
                if isinstance(d, dict) and d: return d
            except: pass
    return {}

def call_openai(messages, base_url, api_key, model, tools=None):
    """OpenAI兼容调用：自动重试，503/429时短暂退避。"""
    last_err = None
    for attempt in range(3):
        body = {"model": model, "messages": messages, "max_tokens": 2000, "temperature": 0.7}
        if tools: body["tools"] = tools; body["tool_choice"] = "auto"
        req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions",
            data=json.dumps(body).encode(),
            headers={"Authorization": "Bearer " + api_key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "ignore")[:300]
            last_err = f"HTTP {e.code}: {detail}"
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(1.5 * (attempt + 1))
                continue
            raise RuntimeError(last_err)
        except Exception as e:
            last_err = str(e)
            time.sleep(1.0 * (attempt + 1))
    raise RuntimeError(last_err or "model call failed")

# 路2：强制工具路由
FORCE = [
    (re.compile(r"[\d\.]+\s*[\+\-\*/×÷]\s*[\d\.]+|算一?下|计算|等于多少"), "calculator"),
    (re.compile(r"搜索|查一下|搜一下|最新|新闻"), "web_search"),
    (re.compile(r"跑.*命令|执行.*shell|装.*包|ls |pwd|系统信息"), "shell"),
    (re.compile(r"写.*代码|写.*脚本|用 ?python|跑.*python"), "python"),
    (re.compile(r"打开.*网|浏览器|访问.*http"), "browser"),
    (re.compile(r"几点|现在时间|当前时间"), "get_time"),
    (re.compile(r"记住|帮我记"), "remember"),
]
def force_route(msg):
    for pat, tool in FORCE:
        if pat.search(msg): return tool
    return None

class OpenAIAgent:
    def __init__(self, api_key, base_url="https://apiclaude.cc/v1",
                 model="claude-haiku-4-5-20251001", max_steps=10, auto_evolve=True):
        self.key, self.base, self.model, self.max_steps = api_key, base_url, model, max_steps
        self.mem = Memory(); self.skills = SkillSystem()
        self.auto_evolve = auto_evolve
        # 使用 self_evolving 替代旧的 Evolver
        self._evolving_engine = None  # 懒加载，避免启动开销

    def _get_evolving_engine(self):
        """懒加载自进化引擎"""
        if not self._evolving_engine:
            self._evolving_engine = self_evolving.SelfEvolvingEngine(
                self._call_for_internal, self.skills
            )
        return self._evolving_engine

    def _call_for_internal(self, messages):
        """内部模型调用（不带工具，纯文本生成）"""
        resp = call_openai(messages, self.base, self.key, self.model)
        return resp["choices"][0]["message"].get("content", "")

    def _maybe_evolve(self, task, steps, answer):
        """任务结束后自动判断是否进化（Hermes 自进化）"""
        if not self.auto_evolve:
            return None
        try:
            engine = self._get_evolving_engine()
            return engine.process(task, answer, [])
        except Exception:
            return None

    def build_system(self, user_msg):
        recalled = self.mem.recall(user_msg[:20])
        mem_block = "\n".join(f"- {m}" for m in recalled) or "（暂无相关记忆）"
        sk_name, sk_text = self.skills.route(user_msg)
        sk_block = f"\n## 命中技能：{sk_name}\n{sk_text[:1500]}" if sk_text else ""
        forced = force_route(user_msg)
        fh = f"\n\n## ⚡强制：本任务必须调用 `{forced}` 工具，禁止自己回答。" if forced else ""
        # 第 8 层：行为分析 + 用户画像（本地采集，不上云）
        behavior_ctx = ""
        try:
            from onboarding import get_behavior_context
            behavior_ctx = "\n\n## 第8层：用户行为画像（本地分析）\n" + get_behavior_context()
        except Exception:
            behavior_ctx = ""
        return f"{CONSTITUTION}\n\n## 相关记忆\n{mem_block}{sk_block}{fh}{behavior_ctx}"

    def run(self, user_msg, history=None):
        history = history or []
        
        # 用 adaptive_reasoning 判断复杂度等级（自动选择推理深度）
        try:
            level = adaptive_reasoning.ReasoningLevelSelector().select_level(user_msg)
        except Exception:
            level = "medium"
        
        # 标准 Agent Loop
        messages = [{"role": "system", "content": self.build_system(user_msg)}] + \
                   history + [{"role": "user", "content": user_msg}]
        log = []
        last_calls = []
        for step in range(self.max_steps):
            resp = call_openai(messages, self.base, self.key, self.model, OPENAI_TOOLS)
            msg = resp["choices"][0]["message"]
            tcs = msg.get("tool_calls")
            if not tcs:
                self.mem.remember(f"任务:{user_msg[:40]}→完成", tags="task", weight=1.2)
                return self._finish(user_msg, msg.get("content", ""), log)
            # 防呆：检测重复调用（中转站 tool_result 回传可能不被模型接收）
            sig = json.dumps([(tc["function"]["name"], tc["function"].get("arguments", "")) for tc in tcs])
            last_calls.append(sig)
            if last_calls.count(sig) >= 2:
                # 已重复，强制让模型基于已有结果作答
                results_summary = "\n".join(f"{s['tool']}: {s['result']}" for s in log[-3:])
                messages.append({"role": "user", "content":
                    f"你已经拿到工具结果了，不要再调用工具，直接用中文回答用户问题。已有结果：\n{results_summary}"})
                resp2 = call_openai(messages, self.base, self.key, self.model)  # 不带 tools
                return self._finish(user_msg, resp2["choices"][0]["message"].get("content", ""), log)
            messages.append(msg)
            for tc in tcs:
                fn = tc["function"]
                name = fn["name"]
                args = safe_json_args(fn.get("arguments", "{}"))
                try: result = run_tool(name, args)
                except Exception as e: result = f"出错:{e}"
                log.append({"tool": name, "args": args, "result": str(result)[:120]})
                messages.append({"role": "tool", "tool_call_id": tc.get("id", name),
                                 "content": str(result)[:3000]})
        return self._finish(user_msg, "（达到最大步数）", log)

    def _finish(self, task, answer, log):
        """统一收口：自动进化判断 + 反思"""
        # 第一步：自我反思（内置思维强化）
        def _call_for_reflection(messages):
            """供反思模块调用的模型接口"""
            resp = call_openai(messages, self.base, self.key, self.model)
            return resp["choices"][0]["message"].get("content", "")
        
        refined_answer, reflection_info = reflexion.reflect(
            user_msg=task, answer=answer, log=log, call_fn=_call_for_reflection
        )
        
        # 如果反思发现问题并重做了，用新答案；否则用原答案
        final_answer = refined_answer if reflection_info.get("reflected") else answer
        
        result = {"answer": final_answer, "steps": log, "reflection": reflection_info}
        evo = self._maybe_evolve(task, log, final_answer)
        if evo:
            result["evolved"] = evo
        return result

if __name__ == "__main__":
    key = os.environ.get("BG_KEY", "")
    if not key: print("设置 BG_KEY"); sys.exit(1)
    agent = OpenAIAgent(key)
    out = agent.run(" ".join(sys.argv[1:]) or "你好")
    print("\n=== 🧠 工具调用 ===")
    for s in out["steps"]: print(f"  🔧 {s['tool']}({s['args']}) → {s['result'][:60]}")
    if not out["steps"]: print("  （闲聊）")
    print("\n=== 🌊 回答 ===\n" + out["answer"])
