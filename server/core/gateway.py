"""
Black God — 模型网关 (Model Gateway)

上层永远叫 Black God，底层自动选最合适的脑子。
负责：能力画像 · 路由打分 · fallback 链 · 熔断 · 重试 · 成本核算。

真实接入时，把 ModelBackend.generate 换成对应厂商 SDK / 本地 serving 的调用即可。
本文件用 mock generate 便于离线跑通与演示。
"""
from __future__ import annotations

import math
import random
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Optional


class Tier(str, Enum):
    LOCAL = "local"   # 本地小模型，~0 成本
    SMALL = "small"   # 便宜模型
    STRONG = "strong" # 强模型，贵


@dataclass
class Task:
    """一次需要模型处理的任务。"""
    prompt: str
    type: str = "general"          # coding | reasoning | long_ctx | general ...
    est_tokens: int = 500
    mode: str = "balanced"         # cost | balanced | quality | latency
    refuse_sensitive: bool = False # 任务是否容易被模型拒绝（避开高拒绝模型）


@dataclass
class Result:
    text: str
    model: str
    tokens: int
    cost: float
    latency_ms: float
    tier: Tier


class ModelError(Exception):
    """模型调用失败（超时/限流/网络等）。"""


class ModelRefusal(Exception):
    """模型拒绝执行。"""


# --------------------------------------------------------------------------- #
#  熔断器：某后端连续失败就暂时下线，半开探测恢复
# --------------------------------------------------------------------------- #
@dataclass
class CircuitBreaker:
    fail_threshold: int = 3
    cooldown_s: float = 60.0
    _fails: int = 0
    _open_until: float = 0.0

    def allow(self) -> bool:
        if time.monotonic() < self._open_until:
            return False           # 熔断中
        return True

    def record_success(self) -> None:
        self._fails = 0
        self._open_until = 0.0

    def record_failure(self) -> None:
        self._fails += 1
        if self._fails >= self.fail_threshold:
            self._open_until = time.monotonic() + self.cooldown_s  # 打开


# --------------------------------------------------------------------------- #
#  模型后端
# --------------------------------------------------------------------------- #
@dataclass
class ModelBackend:
    name: str
    tier: Tier
    capability: dict[str, float]          # task_type -> 0..1
    cost_per_1k: float                    # 相对成本
    latency_ms: float                     # 典型延迟
    refuse_prob: float = 0.0              # 拒绝倾向 0..1
    generate_fn: Optional[Callable[[str], str]] = None
    breaker: CircuitBreaker = field(default_factory=CircuitBreaker)

    def available(self) -> bool:
        return self.breaker.allow()

    def cap(self, task_type: str) -> float:
        return self.capability.get(task_type, self.capability.get("general", 0.5))

    def generate(self, prompt: str) -> str:
        if self.generate_fn:
            return self.generate_fn(prompt)
        # 默认 mock：偶发失败/拒绝，用来演示 fallback
        r = random.random()
        if r < 0.06:
            raise ModelError(f"{self.name} timeout")
        if r < 0.06 + self.refuse_prob:
            raise ModelRefusal(f"{self.name} refused")
        return f"[{self.name}] answer to: {prompt[:48]}"


# --------------------------------------------------------------------------- #
#  网关
# --------------------------------------------------------------------------- #
class ModelGateway:
    # 不同 mode 下的打分权重 (capability, success, cost, latency, refuse)
    WEIGHTS = {
        "cost":     (0.9, 0.6, 1.6, 0.4, 0.8),
        "balanced": (1.2, 0.8, 0.8, 0.6, 0.8),
        "quality":  (1.8, 1.2, 0.3, 0.3, 1.0),
        "latency":  (1.0, 0.7, 0.5, 1.6, 0.8),
    }

    def __init__(self, max_retries: int = 2) -> None:
        self.backends: list[ModelBackend] = []
        self.max_retries = max_retries
        # 运行期统计
        self._success: dict[tuple[str, str], list[int]] = {}  # (model,type)->[ok,total]
        self.total_cost = 0.0
        self.calls = 0

    def register(self, backend: ModelBackend) -> None:
        self.backends.append(backend)

    # ---- 路由打分 ---------------------------------------------------------- #
    def _success_rate(self, model: str, task_type: str) -> float:
        ok, total = self._success.get((model, task_type), [0, 0])
        return (ok + 1) / (total + 2)  # 拉普拉斯平滑，冷启动给中性分

    def _score(self, b: ModelBackend, task: Task) -> float:
        if not b.available():
            return -math.inf
        w_cap, w_succ, w_cost, w_lat, w_ref = self.WEIGHTS[task.mode]
        norm_cost = b.cost_per_1k / 10.0
        norm_lat = b.latency_ms / 2000.0
        refuse = b.refuse_prob if task.refuse_sensitive else 0.0
        return (
            w_cap  * b.cap(task.type)
            + w_succ * self._success_rate(b.name, task.type)
            - w_cost * norm_cost
            - w_lat  * norm_lat
            - w_ref  * refuse
        )

    def _candidates(self, task: Task, tier_floor: Tier) -> list[ModelBackend]:
        # 主档优先：先在请求档位里按分排；更便宜的档只作 fallback 追加在后面，
        # 不让免费本地模型和强模型同台打分（否则重任务会被贪便宜甩给本地）。
        order = [Tier.STRONG, Tier.SMALL, Tier.LOCAL]
        tiers_in_priority = order[order.index(tier_floor):]
        result: list[ModelBackend] = []
        for t in tiers_in_priority:
            same = [b for b in self.backends if b.tier == t and b.available()]
            same.sort(key=lambda b: self._score(b, task), reverse=True)
            result.extend(same)
        return result

    # ---- 调用：路由 + 重试 + fallback + 熔断 + 计费 ----------------------- #
    def generate(self, task: Task, tier: Tier = Tier.STRONG) -> Result:
        candidates = self._candidates(task, tier)
        if not candidates:
            raise ModelError("无可用模型后端")

        last_err: Exception | None = None
        for b in candidates:                      # fallback 链：best → next → 降档
            for attempt in range(self.max_retries + 1):
                try:
                    t0 = time.monotonic()
                    text = b.generate(task.prompt)
                    latency = (time.monotonic() - t0) * 1000 or b.latency_ms
                    cost = task.est_tokens / 1000 * b.cost_per_1k
                    self._record(b.name, task.type, ok=True)
                    b.breaker.record_success()
                    self.total_cost += cost
                    self.calls += 1
                    return Result(text, b.name, task.est_tokens, cost, latency, b.tier)
                except ModelRefusal as e:
                    last_err = e
                    self._record(b.name, task.type, ok=False)
                    break                          # 拒绝不重试，直接换模型
                except ModelError as e:
                    last_err = e
                    b.breaker.record_failure()
                    time.sleep(0.0)                # 实际用指数退避
                    self._record(b.name, task.type, ok=False)
                    continue                       # 同模型重试
        raise ModelError(f"所有后端均失败/拒绝；最后错误: {last_err}")

    def _record(self, model: str, task_type: str, ok: bool) -> None:
        slot = self._success.setdefault((model, task_type), [0, 0])
        slot[0] += int(ok)
        slot[1] += 1


# ═══════════════════════════════════════════════════════════════
#  神枢 · 枢 — 分档路由（枢决断，不兜底）
#  2026-07-12 实测：神枢不是Agent，是轴心。它只决定用谁。
# ═══════════════════════════════════════════════════════════════

# 神枢路由表 — 一个复杂度对应一个模型，没有备胎
_SHENSHU_ROUTE = {
    "trivial":  ("Anthropic 2jie", "claude-haiku-4-5-20251001"),
    "low":      ("max号",           "claude-sonnet-4-6"),
    "medium":   ("max号",           "claude-sonnet-5"),
    "high":     ("max号",           "claude-opus-4-8"),
    "max":      ("max号",           "claude-opus-4-8"),
}

# 复杂度关键词评分表（从 router.py 同步）
_COMPLEXITY_KW = {
    "max":    ["架构设计","重新设计","从零搭建","从零设计","系统性重构","完整的架构"],
    "high":   ["重构","优化性能","复杂逻辑","多模块","并发","分布式","refactor"],
    "low":    ["改一下","小改动","修个","调整一下","加个","错字","格式化","翻译"],
    "trivial":["错字","格式化","翻译","一句话","简单","typo","format","translate"],
}


def score_complexity(text: str, steps: int = 1, files: int = 1) -> str:
    """基于关键词 + 步骤数 + 文件数的复杂度评分 (trivial/low/medium/high/max)"""
    tl = text.lower()
    for level in ["max", "high", "low", "trivial"]:
        if any(kw in tl for kw in _COMPLEXITY_KW.get(level, [])):
            return level
    if steps >= 8 or files >= 5:   return "max"
    if steps >= 5 or files >= 3:   return "high"
    if steps >= 2 or files >= 2:   return "medium"
    if steps == 1 and files == 1:  return "low"
    return "medium"


def 枢决断(task_text: str, steps: int = 1, files: int = 1) -> dict:
    """神枢决断：输入任务描述 → 输出唯一模型路由。不兜底，不备选。"""
    level = score_complexity(task_text, steps, files)
    provider, model = _SHENSHU_ROUTE.get(level, _SHENSHU_ROUTE["medium"])
    return {"complexity": level, "provider": provider, "model": model}


# --------------------------------------------------------------------------- #
#  默认后端集（含本地小模型兜底 + 神枢路由桥接）
# --------------------------------------------------------------------------- #
def default_gateway() -> ModelGateway:
    gw = ModelGateway()
    gw.register(ModelBackend(
        "max号/claude-opus-4-8", Tier.STRONG,
        {"coding": 0.98, "reasoning": 0.97, "long_ctx": 0.96, "general": 0.95},
        cost_per_1k=15.0, latency_ms=1200, refuse_prob=0.03))
    gw.register(ModelBackend(
        "Anthropic2jie/claude-opus-4-7", Tier.STRONG,
        {"coding": 0.96, "reasoning": 0.95, "long_ctx": 0.94, "general": 0.93},
        cost_per_1k=15.0, latency_ms=1200, refuse_prob=0.03))
    gw.register(ModelBackend(
        "max号/claude-sonnet-5", Tier.STRONG,
        {"coding": 0.93, "reasoning": 0.90, "long_ctx": 0.88, "general": 0.90},
        cost_per_1k=9.0, latency_ms=900, refuse_prob=0.05))
    gw.register(ModelBackend(
        "Anthropic2jie/claude-sonnet-5", Tier.STRONG,
        {"coding": 0.93, "reasoning": 0.90, "long_ctx": 0.88, "general": 0.90},
        cost_per_1k=9.0, latency_ms=900, refuse_prob=0.05))
    gw.register(ModelBackend(
        "gpt", Tier.STRONG,
        {"coding": 0.9, "reasoning": 0.92, "long_ctx": 0.85, "general": 0.88},
        cost_per_1k=8.0, latency_ms=950, refuse_prob=0.04))
    gw.register(ModelBackend(
        "deepseek", Tier.SMALL,
        {"coding": 0.9, "reasoning": 0.85, "general": 0.82},
        cost_per_1k=1.2, latency_ms=1300, refuse_prob=0.02))
    gw.register(ModelBackend(
        "local_sm", Tier.LOCAL,
        {"coding": 0.6, "reasoning": 0.55, "general": 0.6},
        cost_per_1k=0.0, latency_ms=300, refuse_prob=0.0))
    return gw
