#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God Agent —— 自主自进化内核
四大灵魂：Manus规划 · Claude真诚 · GPT执行 · Hermes记忆
全自动技能自进化。API 用用户自己的。不依赖任何外部服务。
"""
import os, re, json, time, sqlite3, pathlib, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILLS_DIR = ROOT / "skills"
MEM_DB = ROOT / "memory" / "memory.db"
CONSTITUTION = (ROOT / "core" / "CONSTITUTION.md").read_text(encoding="utf-8")

# ============ Hermes 记忆 ============
class Memory:
    def __init__(self, db=MEM_DB):
        db.parent.mkdir(parents=True, exist_ok=True)
        self.c = sqlite3.connect(str(db), check_same_thread=False)
        self._lock = __import__("threading").Lock()
        self.c.execute("""CREATE TABLE IF NOT EXISTS mem(
            id INTEGER PRIMARY KEY, content TEXT, tags TEXT,
            weight REAL DEFAULT 1.0, ts REAL)""")
        self.c.commit()
    def remember(self, content, tags="", weight=1.0):
        with self._lock:
            self.c.execute("INSERT INTO mem(content,tags,weight,ts) VALUES(?,?,?,?)",
                           (content, tags, weight, time.time()))
            self.c.commit()
    def recall(self, keyword="", limit=8):
        with self._lock:
            if keyword:
                rows = self.c.execute(
                    "SELECT content FROM mem WHERE content LIKE ? OR tags LIKE ? "
                    "ORDER BY weight DESC, ts DESC LIMIT ?",
                    (f"%{keyword}%", f"%{keyword}%", limit)).fetchall()
            else:
                rows = self.c.execute(
                    "SELECT content FROM mem ORDER BY weight DESC, ts DESC LIMIT ?",
                    (limit,)).fetchall()
            return [r[0] for r in rows]

# ============ 技能系统（运行时发现 + 路由）============
class SkillSystem:
    def __init__(self, d=SKILLS_DIR):
        self.dir = d
        d.mkdir(parents=True, exist_ok=True)
    def discover(self):
        """运行时扫描所有 SKILL.md，解析 frontmatter triggers"""
        skills = []
        for p in self.dir.glob("*/SKILL.md"):
            txt = p.read_text(encoding="utf-8", errors="ignore")
            m = re.search(r"^---\s*(.*?)\s*---", txt, re.S)
            name = p.parent.name
            triggers, desc = [], ""
            if m:
                fm = m.group(1)
                for line in re.findall(r'-\s*"?([^"\n]+)"?', fm):
                    triggers.append(line.strip())
                dm = re.search(r"description:\s*[>|]?\s*(.+)", fm)
                if dm: desc = dm.group(1).strip()[:120]
            skills.append({"name": name, "path": str(p),
                           "triggers": triggers, "desc": desc})
        return skills
    def route(self, user_msg):
        """匹配最相关技能，返回其全文（先读再做）"""
        for s in self.discover():
            for t in s["triggers"]:
                if t and t.lower() in user_msg.lower():
                    return s["name"], pathlib.Path(s["path"]).read_text(encoding="utf-8")
        return None, None
    def create_skill(self, name, description, triggers, body):
        """自进化：自动生成新技能"""
        d = self.dir / name
        d.mkdir(parents=True, exist_ok=True)
        tg = "\n".join(f'  - "{t}"' for t in triggers)
        content = f"""---
name: {name}
version: 1.0.0
description: |
  {description}
triggers:
{tg}
mutating: false
---

# {name}

{body}
"""
        (d / "SKILL.md").write_text(content, encoding="utf-8")
        return str(d / "SKILL.md")

# ============ 模型调用（OpenAI 兼容，用户自己的 Key）============
def call_model(messages, base_url, api_key, model):
    url = base_url.rstrip("/") + "/chat/completions"
    body = json.dumps({"model": model, "messages": messages,
                       "temperature": 0.7}).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": "Bearer " + api_key})
    with urllib.request.urlopen(req, timeout=120) as r:
        j = json.load(r)
    return j["choices"][0]["message"]["content"]

# ============ Agent 主循环（Manus 规划 + GPT 执行）============
class Agent:
    def __init__(self, base_url, api_key, model, max_steps=10):
        self.base_url, self.api_key, self.model = base_url, api_key, model
        self.max_steps = max_steps
        self.mem = Memory()
        self.skills = SkillSystem()
        self.tools = TOOLS

    def system_prompt(self, user_msg):
        skill_list = "\n".join(
            f"- {s['name']}: {s['desc']}" for s in self.skills.discover()[:30])
        recalled = self.mem.recall(user_msg[:20])
        mem_block = "\n".join(f"- {m}" for m in recalled) if recalled else "（暂无相关记忆）"
        tool_list = "\n".join(f"- {n}: {d}" for n, (d, _) in self.tools.items())
        return f"""{CONSTITUTION}

## 当前可用工具
{tool_list}

## 工具调用铁律（违反即失败）
- 凡涉及【计算/搜索/查时间/存记忆/查记忆】的任务，**禁止自己心算或编造**，必须调对应工具。
- 调工具时**只输出一个 ```tool 代码块，不要任何其他文字**，等结果回来再说话。

### 示例1（计算 → 必须调工具）
用户：算一下 12*13
你：
```tool
{{"name": "calculator", "args": {{"expression": "12*13"}}}}
```

### 示例2（记忆 → 必须调工具）
用户：记住我爱喝咖啡
你：
```tool
{{"name": "remember", "args": {{"content": "用户爱喝咖啡"}}}}
```

### 示例3（闲聊 → 不调工具，直接答）
用户：你好
你：你好，我在，有什么可以帮你？

## 当前已加载技能（{len(self.skills.discover())} 个）
{skill_list}

## 相关记忆
{mem_block}"""

    def parse_tool(self, text):
        m = re.search(r"```tool\s*(.*?)```", text, re.S)
        if not m: return None
        try: return json.loads(m.group(1).strip())
        except: return None

    def run(self, user_msg, history=None):
        history = history or []
        # 路由：命中技能则把技能全文加进上下文（先读再做）
        sk_name, sk_text = self.skills.route(user_msg)
        sys = self.system_prompt(user_msg)
        if sk_text:
            sys += f"\n\n## 本次命中技能：{sk_name}（必须按此执行）\n{sk_text[:2000]}"
        messages = [{"role": "system", "content": sys}] + history + \
                   [{"role": "user", "content": user_msg}]

        log = []
        for step in range(self.max_steps):
            reply = call_model(messages, self.base_url, self.api_key, self.model)
            tool = self.parse_tool(reply)
            if not tool:
                self.mem.remember(f"任务:{user_msg[:40]} → 完成", tags="task", weight=1.2)
                return {"answer": reply, "steps": log}
            messages.append({"role": "assistant", "content": reply})
            log.append({"tool": tool["name"], "args": tool.get("args", {})})
            try:
                _, fn = self.tools.get(tool["name"], (None, None))
                result = fn(tool.get("args", {})) if fn else f"未知工具:{tool['name']}"
            except Exception as e:
                result = f"工具出错:{e}"
            log[-1]["result"] = str(result)[:200]
            messages.append({"role": "user",
                "content": f"工具 {tool['name']} 结果:\n{result}\n据此继续或给最终答案。"})
        return {"answer": "（达到最大步数）", "steps": log}

# ============ 工具实现 ============
def _t_search(a):
    q = a.get("query", "")
    u = "https://api.duckduckgo.com/?q=" + urllib.parse.quote(q) + "&format=json&no_html=1"
    with urllib.request.urlopen(u, timeout=20) as r:
        j = json.load(r)
    out = []
    if j.get("AbstractText"): out.append(j["AbstractText"])
    for t in (j.get("RelatedTopics") or [])[:6]:
        if t.get("Text"): out.append("• " + t["Text"])
    return "\n".join(out) or "无结果"
def _t_calc(a):
    e = a.get("expression", "")
    if not re.match(r"^[\d\s+\-*/().,%]+$", e): return "非法表达式"
    return str(eval(e, {"__builtins__": {}}))
def _t_time(a):
    return time.strftime("%Y-%m-%d %H:%M:%S")
def _t_remember(a):
    Memory().remember(a.get("content", ""), tags="manual")
    return "已记住"
def _t_recall(a):
    return "\n".join(Memory().recall(a.get("keyword", ""))) or "无记忆"

import urllib.parse
TOOLS = {
    "web_search": ("联网搜索 args:{query}", _t_search),
    "calculator": ("数学计算 args:{expression}", _t_calc),
    "get_time": ("当前时间 args:{}", _t_time),
    "remember": ("存记忆 args:{content}", _t_remember),
    "recall": ("查记忆 args:{keyword}", _t_recall),
}

if __name__ == "__main__":
    import sys
    base = os.environ.get("BG_BASE", "https://api.openai.com/v1")
    key = os.environ.get("BG_KEY", "")
    model = os.environ.get("BG_MODEL", "gpt-4o-mini")
    if not key:
        print("请设置环境变量 BG_KEY（你自己的 API Key）"); sys.exit(1)
    agent = Agent(base, key, model)
    msg = " ".join(sys.argv[1:]) or "你好，介绍一下你自己"
    out = agent.run(msg)
    print("\n=== 思考步骤 ===")
    for s in out["steps"]: print(f"  🔧 {s['tool']} → {s.get('result','')[:60]}")
    print("\n=== 回答 ===\n" + out["answer"])
