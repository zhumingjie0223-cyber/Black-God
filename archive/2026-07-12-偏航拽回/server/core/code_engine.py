#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
黑神编码引擎 — Black God 888 自有内核
代码理解 → 生成 → 自动调试 → 重构 完整闭环

能力：
  1. 理解需求 → 拆技术方案
  2. 生成代码 → 多语言
  3. 自动运行 → 捕获错误
  4. 自动调试 → 错误修复循环
  5. 重构优化 → 可读性/性能
"""
import json
import re
import subprocess
import tempfile
import os
from pathlib import Path


class CodeEngine:
    """黑神编码引擎：写代码 → 跑 → 错了自己修 → 再跑，直到通过"""

    def __init__(self, call_fn, max_debug_rounds=3, sandbox=None):
        self.call_fn = call_fn
        self.max_debug_rounds = max_debug_rounds
        self.sandbox = sandbox

    def understand(self, requirement: str) -> dict:
        """第1步：理解需求，拆技术方案"""
        prompt = f"""分析这个编码需求，输出技术方案（JSON）：

需求：{requirement}

输出格式：
{{"language": "python", "approach": "实现思路", "key_points": ["要点1"], "potential_issues": ["可能的坑"]}}"""
        raw = self.call_fn([{"role": "user", "content": prompt}])
        return _parse_json(raw) or {"language": "python", "approach": raw[:200]}

    def generate(self, requirement: str, plan: dict = None) -> str:
        """第2步：生成代码"""
        plan_ctx = ""
        if plan:
            plan_ctx = f"\n思路：{plan.get('approach','')}\n要点：{plan.get('key_points',[])}"
        prompt = f"""写出完整、可运行的代码。

需求：{requirement}{plan_ctx}

要求：完整可直接运行、含错误处理、只输出代码（```语言```包裹），不要解释。"""
        raw = self.call_fn([{"role": "user", "content": prompt}])
        return _extract_code(raw)

    def run_code(self, code: str, language: str = "python") -> tuple:
        """第3步：执行代码 → (成功?, 输出/错误)"""
        if self.sandbox:
            try:
                r = self.sandbox.execute(code, language)
                return r.get("success", False), r.get("output", "")
            except Exception as e:
                return False, str(e)

        if language == "python":
            with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False) as f:
                f.write(code)
                path = f.name
            try:
                r = subprocess.run(["python3", path], capture_output=True, text=True, timeout=30)
                os.unlink(path)
                return (r.returncode == 0,
                        r.stdout if r.returncode == 0 else r.stderr)
            except Exception as e:
                try: os.unlink(path)
                except: pass
                return False, str(e)
        return False, f"暂不支持本地执行 {language}"

    def debug(self, code: str, error: str, requirement: str) -> str:
        """第4步：根据错误修复"""
        prompt = f"""代码运行出错，修复它。

需求：{requirement}

代码：
```
{code}
```

错误：
{error}

输出修复后完整代码（```语言```包裹），不要解释。"""
        raw = self.call_fn([{"role": "user", "content": prompt}])
        return _extract_code(raw)

    def refactor(self, code: str) -> str:
        """第5步：重构优化"""
        prompt = f"""重构这段代码，提升可读性和性能，功能不变。

```
{code}
```

输出重构后完整代码（```语言```包裹）。"""
        raw = self.call_fn([{"role": "user", "content": prompt}])
        return _extract_code(raw)

    def solve(self, requirement: str, auto_refactor=False) -> dict:
        """完整闭环：理解→生成→跑→自动修→通过→(可选)重构"""
        trace = {"requirement": requirement, "rounds": [], "success": False}
        plan = self.understand(requirement)
        trace["plan"] = plan
        lang = plan.get("language", "python")
        code = self.generate(requirement, plan)
        trace["initial_code"] = code

        for rn in range(self.max_debug_rounds + 1):
            success, output = self.run_code(code, lang)
            trace["rounds"].append({"round": rn, "success": success,
                                   "output": output[:300]})
            if success:
                trace["success"] = True
                trace["final_code"] = code
                trace["result"] = output
                break
            if rn < self.max_debug_rounds:
                code = self.debug(code, output, requirement)

        if trace["success"] and auto_refactor:
            trace["refactored_code"] = self.refactor(trace["final_code"])
        return trace


def _extract_code(text: str) -> str:
    if not text:
        return ""
    m = re.search(r"```[a-zA-Z]*\n?(.*?)```", text, re.S)
    return m.group(1).strip() if m else text.strip()


def _parse_json(raw: str) -> dict:
    if not raw:
        return None
    try:
        return json.loads(raw.strip())
    except Exception:
        pass
    try:
        s, e = raw.find("{"), raw.rfind("}")
        if s != -1 and e != -1:
            return json.loads(raw[s:e+1])
    except Exception:
        pass
    return None


def code_tool(args, call_fn=None, **kw):
    """Agent 工具：code(requirement=...)"""
    req = args.get("requirement", "")
    if not req or not call_fn:
        return "缺少 requirement 或 call_fn"
    engine = CodeEngine(call_fn)
    trace = engine.solve(req)
    if trace["success"]:
        return f"✅ 代码完成（{len(trace['rounds'])}轮）:\n{trace['final_code']}\n\n输出:\n{trace['result'][:200]}"
    return f"⚠️ 调试未通过，最后代码:\n{trace.get('initial_code','')[:300]}"
