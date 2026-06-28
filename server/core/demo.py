"""
Black God — 级联引擎演示 (离线可跑)

提供各层的 mock 实现，跑一组请求，打印每条走了哪一层、成本，
并在重复请求时展示缓存命中导致成本下降（"越用越省"）。

运行: python demo.py
"""
from __future__ import annotations

import random
from collections import Counter

from cost_engine import (CostEngine, Layer, normalize, build_engine)
from gateway import default_gateway


# --------------------------------------------------------------------------- #
#  各层 mock 实现
# --------------------------------------------------------------------------- #
class DemoRules:
    """L0：确定性任务直接本地出结果。"""
    def try_handle(self, req: str):
        r = req.strip()
        # 纯算术
        if all(c in "0123456789+-*/(). " for c in r) and any(c.isdigit() for c in r):
            try:
                return f"= {eval(r)}"          # 演示用；真实环境用安全表达式求值
            except Exception:
                return None
        if "状态" in r or "status" in r.lower():
            return "系统状态: 全部正常 (本地查询)"
        return None


class DemoExactCache:
    """L1：归一化精确命中。"""
    def __init__(self):
        self.store: dict[str, str] = {}
    def get(self, key: str):
        return self.store.get(key)
    def put(self, key: str, value: str):
        self.store[key] = value


class DemoSemanticCache:
    """L2：用词袋 Jaccard 近似语义相似（真实环境换 embedding + 向量库）。"""
    def __init__(self):
        self.items: list[tuple[set[str], str]] = []
    @staticmethod
    def _toks(s: str) -> set[str]:
        return set(normalize(s).split())
    def get(self, req: str, threshold: float):
        q = self._toks(req)
        best, best_sim = None, 0.0
        for toks, val in self.items:
            inter = len(q & toks); union = len(q | toks) or 1
            sim = inter / union
            if sim > best_sim:
                best, best_sim = val, sim
        if best is not None and best_sim >= threshold:
            return best                        # 真实环境此处会再 refine 一次
        return None
    def put(self, req: str, value: str):
        self.items.append((self._toks(req), value))


class DemoMemory:
    """L3：种了几条事实，关键词命中。"""
    def __init__(self):
        self.facts = {
            "称呼": "你的称呼: 思涵",
            "服务器": "禁碰清单: prod-01 不可写操作",
            "公开仓库": "black-god-public 是公开版仓库",
        }
    def answer(self, req: str):
        for kw, val in self.facts.items():
            if kw in req:
                return f"(记忆) {val}"
        return None
    def remember(self, req: str, value: str):
        pass


class _GitSkill:
    name = "git-workflow"
    def run(self, req: str) -> str:
        return "(技能 git-workflow) 已生成提交/分支流程"

class _SearchSkill:
    name = "web-search"
    def run(self, req: str) -> str:
        return "(技能 web-search) 已搜索并整理结果"

class DemoSkillRouter:
    """L4：关键词→技能（真实环境加语义质心触发）。"""
    def __init__(self):
        self.skills = {
            ("git", "提交", "分支", "merge"): _GitSkill(),
            ("搜索", "查一下", "search", "最新"): _SearchSkill(),
        }
    def match(self, req: str):
        low = req.lower()
        for kws, skill in self.skills.items():
            if any(k in low for k in kws):
                return skill
        return None


# --------------------------------------------------------------------------- #
#  跑演示
# --------------------------------------------------------------------------- #
def run():
    random.seed(7)
    engine = CostEngine(
        rules=DemoRules(),
        exact=DemoExactCache(),
        semantic=DemoSemanticCache(),
        memory=DemoMemory(),
        skills=DemoSkillRouter(),
        gateway=default_gateway(),
    )

    requests = [
        "12 * (3 + 4)",                       # L0 规则
        "系统状态怎么样",                       # L0 规则
        "我的称呼是什么",                       # L3 记忆
        "prod 服务器能动吗",                    # L3 记忆
        "帮我 git 提交并建个分支",              # L4 技能
        "搜索一下最新的 agent 框架",            # L4 技能
        "重构整个项目的鉴权模块",               # L6 强模型(reasoning)
        "写个快速排序的代码",                   # L6 小模型(coding)
        "12 * (3 + 4)",                       # 重复 → L1 精确缓存
        "帮我 git 提交再建分支",                # 近似 → L2 语义缓存
        "写个快速排序的代码",                   # 重复 → L1 精确缓存
    ]

    print("=" * 64)
    print("请求级联演示")
    print("=" * 64)
    for i, req in enumerate(requests, 1):
        ans = engine.handle(req)
        tag = ans.model or "-"
        print(f"{i:2d}. [{ans.layer.value:18s}] cost={ans.cost:5.3f} via={tag}")
        print(f"      Q: {req}")
        print(f"      A: {ans.text}")
    print()
    print(engine.report())

    # 成本对比：全部强制走模型 vs 走级联
    forced = len(requests) * (400 / 1000 * 9.0)   # 粗略：每条都上强模型
    print()
    print(f"若每条都直上强模型，估算成本 ≈ {forced:.2f}")
    print(f"走级联后的实际模型成本   = {engine.total_cost:.2f}")
    if forced > 0:
        print(f"节省 ≈ {(1 - engine.total_cost / forced) * 100:.1f}%")


if __name__ == "__main__":
    run()
