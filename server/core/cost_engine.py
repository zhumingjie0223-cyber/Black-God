"""
Black God — 成本级联引擎 (Cost Cascade Engine)

核心思想：每一次"到达昂贵模型"的请求，都是上一层没拦住的失败。
请求自上而下穿过 L0~L6，越往下成本越高，尽量在上层解决。

L0 规则/确定性  → L1 精确缓存 → L2 语义缓存 → L3 记忆检索
→ L4 技能命中  → L5 复杂度分类 → L6 模型网关

各层组件用 Protocol 定义接口，真实实现（向量库、embedding、技能引擎）按需替换。
"""
from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Protocol

from gateway import ModelGateway, Task, Tier, default_gateway


class Layer(str, Enum):
    RULES = "L0_rules"
    EXACT = "L1_exact_cache"
    SEMANTIC = "L2_semantic_cache"
    MEMORY = "L3_memory"
    SKILL = "L4_skill"
    MODEL = "L6_model"


@dataclass
class Answer:
    text: str
    layer: Layer
    cost: float = 0.0
    model: Optional[str] = None


@dataclass
class TaskBudget:
    max_tokens: int = 8000
    max_cost: float = 1.0
    used_tokens: int = 0
    used_cost: float = 0.0

    def would_exceed(self, tokens: int, cost: float) -> bool:
        return (self.used_tokens + tokens > self.max_tokens or
                self.used_cost + cost > self.max_cost)

    def charge(self, tokens: int, cost: float) -> None:
        self.used_tokens += tokens
        self.used_cost += cost


# --------------------------------------------------------------------------- #
#  各层接口 (Protocol) —— 真实实现替换这些即可
# --------------------------------------------------------------------------- #
class RulesEngine(Protocol):
    def try_handle(self, req: str) -> Optional[str]: ...

class ExactCache(Protocol):
    def get(self, key: str) -> Optional[str]: ...
    def put(self, key: str, value: str) -> None: ...

class SemanticCache(Protocol):
    def get(self, req: str, threshold: float) -> Optional[str]: ...
    def put(self, req: str, value: str) -> None: ...

class Memory(Protocol):
    def answer(self, req: str) -> Optional[str]: ...
    def remember(self, req: str, value: str) -> None: ...

class Skill(Protocol):
    name: str
    def run(self, req: str) -> str: ...

class SkillRouter(Protocol):
    def match(self, req: str) -> Optional[Skill]: ...


def normalize(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


# --------------------------------------------------------------------------- #
#  引擎
# --------------------------------------------------------------------------- #
class CostEngine:
    def __init__(
        self,
        rules: RulesEngine,
        exact: ExactCache,
        semantic: SemanticCache,
        memory: Memory,
        skills: SkillRouter,
        gateway: ModelGateway,
        semantic_threshold: float = 0.82,
    ) -> None:
        self.rules = rules
        self.exact = exact
        self.semantic = semantic
        self.memory = memory
        self.skills = skills
        self.gateway = gateway
        self.theta = semantic_threshold
        self.telemetry: Counter[str] = Counter()  # 各层命中计数
        self.total_cost = 0.0

    # -- 复杂度分类：决定到 L6 时用哪个档（本身不烧强模型）------------------- #
    @staticmethod
    def classify(req: str) -> tuple[Tier, str]:
        low = req.lower()
        if any(k in low for k in ("部署", "deploy", "重构", "refactor", "架构", "分析整个")):
            return Tier.STRONG, "reasoning"
        if any(k in low for k in ("代码", "code", "脚本", "函数", "bug")):
            return Tier.SMALL, "coding"
        if len(req) < 40:
            return Tier.LOCAL, "general"
        return Tier.SMALL, "general"

    # -- 主入口：级联 ------------------------------------------------------- #
    def handle(self, req: str, budget: Optional[TaskBudget] = None) -> Answer:
        budget = budget or TaskBudget()
        key = normalize(req)

        # L0 规则/确定性
        if (r := self.rules.try_handle(req)) is not None:
            return self._hit(Layer.RULES, r)

        # L1 精确缓存
        if (r := self.exact.get(key)) is not None:
            return self._hit(Layer.EXACT, r)

        # L2 语义缓存（命中后做一次轻量 refine，避免"相似但答错"）
        if (r := self.semantic.get(req, self.theta)) is not None:
            return self._hit(Layer.SEMANTIC, r)

        # L3 记忆检索
        if (r := self.memory.answer(req)) is not None:
            self._learn(key, req, r)          # 记忆命中也回填缓存
            return self._hit(Layer.MEMORY, r)

        # L4 技能命中
        if (skill := self.skills.match(req)) is not None:
            r = skill.run(req)
            self._learn(key, req, r)
            return self._hit(Layer.SKILL, r, model=f"skill:{skill.name}")

        # L5 分类 → L6 模型
        tier, ttype = self.classify(req)
        mode = {Tier.STRONG: "quality", Tier.SMALL: "balanced",
                Tier.LOCAL: "cost"}[tier]     # 强任务抬质量权重，别贪便宜
        task = Task(prompt=req, type=ttype, mode=mode,
                    est_tokens=max(200, len(req) * 2))

        # 预算护栏：估算成本，超预算先降档
        est_cost = task.est_tokens / 1000 * 9.0
        if budget.would_exceed(task.est_tokens, est_cost) and tier == Tier.STRONG:
            tier = Tier.SMALL                 # 降级而非直接放弃

        res = self.gateway.generate(task, tier)
        budget.charge(res.tokens, res.cost)
        self.total_cost += res.cost
        self._learn(key, req, res.text)       # 沉淀：缓存 + 记忆 → 下次更省
        return self._hit(Layer.MODEL, res.text, cost=res.cost, model=res.model)

    # -- 回写学习：把这次结果沉淀回缓存/记忆 -------------------------------- #
    def _learn(self, key: str, req: str, value: str) -> None:
        self.exact.put(key, value)
        self.semantic.put(req, value)

    def _hit(self, layer: Layer, text: str, cost: float = 0.0,
             model: Optional[str] = None) -> Answer:
        self.telemetry[layer.value] += 1
        return Answer(text=text, layer=layer, cost=cost, model=model)

    # -- 命中率/成本报告 ---------------------------------------------------- #
    def report(self) -> str:
        total = sum(self.telemetry.values()) or 1
        lines = ["层级命中分布:"]
        for layer in Layer:
            n = self.telemetry.get(layer.value, 0)
            bar = "█" * round(n / total * 30)
            lines.append(f"  {layer.value:18s} {n:3d}  {n/total*100:5.1f}%  {bar}")
        local_rate = (total - self.telemetry.get(Layer.MODEL.value, 0)) / total
        lines.append(f"本地拦截率(未到强模型): {local_rate*100:.1f}%")
        lines.append(f"总模型成本: {self.total_cost:.3f}")
        return "\n".join(lines)


def build_engine(gateway: Optional[ModelGateway] = None) -> CostEngine:
    """用演示用 mock 组件装配一个可跑的引擎（见 demo.py 里的实现）。"""
    from demo import (DemoRules, DemoExactCache, DemoSemanticCache,
                      DemoMemory, DemoSkillRouter)
    return CostEngine(
        rules=DemoRules(),
        exact=DemoExactCache(),
        semantic=DemoSemanticCache(),
        memory=DemoMemory(),
        skills=DemoSkillRouter(),
        gateway=gateway or default_gateway(),
    )
