"""Task Contract v2 — 任务合同数据结构定义。

一个"任务合同"是规划者(Planner)与执行者(Executor Agent)之间的正式约定,
包含: 输入/输出 schema、三层验收标准、失败处理策略、验收成本预算。

设计原则:
1. 验收标准分层且字段分离: HardCheck / SoftCheck / HumanReview 不混在同一列表。
2. 失败原因显式区分: 任务定义有问题(回退规划者) vs 执行质量不够(换Agent重做),
   使用不同枚举值,拒绝用单一 retry 计数器糊过去。
3. 软标准的裁判模型独立于执行模型配置,避免"自己给自己打分"。
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, model_validator


# ---------------------------------------------------------------------------
# 基础枚举
# ---------------------------------------------------------------------------

class TriggerMode(str, Enum):
    """验收检查的触发时机。

    - BLOCKING: 阻断式。任务产出后必须通过该检查才能标记完成。
    - SAMPLING: 抽检式。按采样率事后抽查,不阻断任务流转,但抽检失败会追溯。
    """

    BLOCKING = "blocking"
    SAMPLING = "sampling"


class FailureCause(str, Enum):
    """失败根因分类 — 两类失败走完全不同的处理路径,禁止混用。

    - TASK_DEFINITION_DEFECT: 任务描述本身有问题(需求含糊/schema矛盾/目标不可达),
      重试无意义,必须回退给规划者(Planner)重新定义任务。
    - EXECUTION_QUALITY_DEFECT: 任务定义没问题,但执行结果质量不够,
      应换一个 Agent(或换模型/换策略)重做。
    """

    TASK_DEFINITION_DEFECT = "task_definition_defect"
    EXECUTION_QUALITY_DEFECT = "execution_quality_defect"


class EscalationTarget(str, Enum):
    """失败升级路径的目标。"""

    REPLAN = "replan"                  # 回退规划者重新定义任务
    REASSIGN_AGENT = "reassign_agent"  # 换执行 Agent 重做
    HUMAN_TAKEOVER = "human_takeover"  # 升级到人工接管
    ABORT = "abort"                    # 放弃任务


class InspectionMode(str, Enum):
    """验收覆盖模式: 全检 or 抽检。"""

    FULL = "full"          # 全检: 每个产出都走完整验收
    SAMPLE = "sample"       # 抽检: 按预算/采样率抽查


class HardCheckKind(str, Enum):
    """硬标准的机器可判定类型。"""

    UNIT_TEST = "unit_test"              # 测试套件通过
    SCHEMA_VALIDATION = "schema_validation"  # 输出符合 output_schema
    LINT = "lint"                        # 静态检查通过
    EXIT_CODE = "exit_code"              # 命令退出码为 0
    REGEX_MATCH = "regex_match"          # 输出匹配指定模式
    CUSTOM_SCRIPT = "custom_script"      # 自定义校验脚本


# ---------------------------------------------------------------------------
# 验收标准三层结构 (字段分离,不共用列表)
# ---------------------------------------------------------------------------

class HardCheck(BaseModel):
    """硬标准: 机器可判定,结果为确定性的 pass/fail。默认阻断式。"""

    check_id: str = Field(..., description="硬检查的唯一标识")
    kind: HardCheckKind = Field(..., description="检查类型")
    command: Optional[str] = Field(
        None, description="执行的命令/脚本, 如 'pytest tests/ -x'"
    )
    expected: Optional[Dict[str, Any]] = Field(
        None, description="期望结果描述, 如 {'exit_code': 0}"
    )
    trigger: TriggerMode = Field(
        TriggerMode.BLOCKING,
        description="触发时机。硬标准通常是阻断式。",
    )
    timeout_seconds: float = Field(300.0, gt=0, description="单次检查超时")


class JudgeModelConfig(BaseModel):
    """LLM 裁判模型配置 — 必须独立于执行模型,可单独指定 provider/model/温度。"""

    provider: str = Field(..., description="裁判模型提供方, 如 'anthropic'")
    model: str = Field(..., description="裁判模型名, 独立于执行模型配置")
    temperature: float = Field(0.0, ge=0.0, le=2.0, description="裁判温度,默认确定性")
    max_tokens: int = Field(2048, gt=0)
    system_prompt_override: Optional[str] = Field(
        None, description="覆盖默认裁判 system prompt"
    )
    num_votes: int = Field(
        1, ge=1, description="多数投票次数, >1 时取多次裁决的多数结果"
    )


class SoftCheck(BaseModel):
    """软标准: 需要 LLM 裁判打分的定性标准。可阻断也可抽检。"""

    check_id: str = Field(..., description="软检查的唯一标识")
    rubric: str = Field(..., description="裁判评分细则(自然语言 rubric)")
    judge: JudgeModelConfig = Field(
        ..., description="裁判模型配置, 与执行模型解耦"
    )
    pass_threshold: float = Field(
        0.7, ge=0.0, le=1.0, description="归一化得分及格线"
    )
    trigger: TriggerMode = Field(
        TriggerMode.BLOCKING,
        description="阻断式=产出必须过裁判; 抽检式=事后抽查",
    )
    sample_rate: Optional[float] = Field(
        None,
        ge=0.0,
        le=1.0,
        description="仅当 trigger=sampling 时有效的抽检采样率",
    )

    @model_validator(mode="after")
    def _validate_sample_rate(self) -> "SoftCheck":
        if self.trigger == TriggerMode.SAMPLING and self.sample_rate is None:
            raise ValueError(
                f"SoftCheck '{self.check_id}': trigger=sampling 时必须提供 sample_rate"
            )
        if self.trigger == TriggerMode.BLOCKING and self.sample_rate is not None:
            raise ValueError(
                f"SoftCheck '{self.check_id}': trigger=blocking 时不应设置 sample_rate"
            )
        return self


class HumanReview(BaseModel):
    """人工抽检: 带采样率的人工审核。典型为抽检式,不阻断主流程。"""

    check_id: str = Field(..., description="人工审核项的唯一标识")
    instruction: str = Field(..., description="给审核人的检查指引")
    sample_rate: float = Field(
        ..., ge=0.0, le=1.0, description="人工抽检采样率, 如 0.05 表示抽 5%"
    )
    trigger: TriggerMode = Field(
        TriggerMode.SAMPLING,
        description="通常为抽检式; 高危任务可设为阻断式(每单必审)",
    )
    reviewer_role: Optional[str] = Field(
        None, description="要求的审核人角色, 如 'senior_engineer'"
    )
    sla_hours: Optional[float] = Field(
        None, gt=0, description="人工审核的响应时限(小时)"
    )


class Verification(BaseModel):
    """三层验收标准 — 字段分离,禁止混装在一个列表里。"""

    hard_checks: List[HardCheck] = Field(
        default_factory=list, description="第一层: 机器可判定的硬标准"
    )
    soft_checks: List[SoftCheck] = Field(
        default_factory=list, description="第二层: LLM 裁判的软标准"
    )
    human_reviews: List[HumanReview] = Field(
        default_factory=list, description="第三层: 人工抽检"
    )

    @model_validator(mode="after")
    def _at_least_one_check(self) -> "Verification":
        if not (self.hard_checks or self.soft_checks or self.human_reviews):
            raise ValueError("Verification 至少需要一层验收标准, 不允许无验收的任务合同")
        return self

    @property
    def blocking_checks_count(self) -> int:
        """阻断式检查总数(用于估算验收关键路径)。"""
        return (
            sum(1 for c in self.hard_checks if c.trigger == TriggerMode.BLOCKING)
            + sum(1 for c in self.soft_checks if c.trigger == TriggerMode.BLOCKING)
            + sum(1 for c in self.human_reviews if c.trigger == TriggerMode.BLOCKING)
        )

    @property
    def total_checks_count(self) -> int:
        """全部检查总数(不分层),用于日志摘要。"""
        return len(self.hard_checks) + len(self.soft_checks) + len(self.human_reviews)


# ---------------------------------------------------------------------------
# 失败处理策略
# ---------------------------------------------------------------------------

class FailureRoute(BaseModel):
    """某一种失败根因对应的处理路线。"""

    max_retries: int = Field(
        ..., ge=0, description="该根因下允许的重试上限(0 表示不重试直接升级)"
    )
    escalate_to: EscalationTarget = Field(
        ..., description="重试耗尽后的升级目标"
    )
    cooldown_seconds: float = Field(
        0.0, ge=0.0, description="每次重试前的冷却时间"
    )


class OnFailPolicy(BaseModel):
    """失败处理策略 — 按失败根因分流,不用单一 retry 计数器糊弄。

    - definition_defect_route: 任务定义有缺陷 → 默认升级回规划者(replan),
      对同一份坏定义重试执行是浪费,故默认 max_retries=0。
    - quality_defect_route: 执行质量不够 → 换 Agent 重做若干次,
      耗尽后再升级。
    """

    definition_defect_route: FailureRoute = Field(
        default_factory=lambda: FailureRoute(
            max_retries=0, escalate_to=EscalationTarget.REPLAN
        ),
        description="FailureCause.TASK_DEFINITION_DEFECT 的处理路线",
    )
    quality_defect_route: FailureRoute = Field(
        default_factory=lambda: FailureRoute(
            max_retries=2, escalate_to=EscalationTarget.REASSIGN_AGENT
        ),
        description="FailureCause.EXECUTION_QUALITY_DEFECT 的处理路线",
    )
    final_escalation: EscalationTarget = Field(
        EscalationTarget.HUMAN_TAKEOVER,
        description="所有路线均耗尽后的兜底升级目标",
    )

    def route_for(self, cause: FailureCause) -> FailureRoute:
        """按失败根因取对应路线。"""
        if cause == FailureCause.TASK_DEFINITION_DEFECT:
            return self.definition_defect_route
        return self.quality_defect_route

    @model_validator(mode="after")
    def _sanity(self) -> "OnFailPolicy":
        if self.definition_defect_route.escalate_to == EscalationTarget.REASSIGN_AGENT:
            raise ValueError(
                "任务定义有缺陷时换 Agent 无意义: definition_defect_route "
                "不应升级到 reassign_agent, 应回退 replan 或人工接管"
            )
        return self


# ---------------------------------------------------------------------------
# 验收成本预算
# ---------------------------------------------------------------------------

class CostBudget(BaseModel):
    """验收成本预算: 控制"验证本身"的开销, 避免验收比干活还贵。"""

    inspection_mode: InspectionMode = Field(
        default=InspectionMode.FULL,
        description="验收模式: 全检 / 抽检",
    )
    sample_rate: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="抽检比例, 仅在 inspection_mode=SAMPLE 时生效",
    )
    max_verification_cost_usd: float = Field(
        default=0.05,
        ge=0.0,
        description="单任务验收预算上限 (美元), 超出则降级验收策略",
    )

    @model_validator(mode="after")
    def _sanity(self) -> "CostBudget":
        if self.inspection_mode == InspectionMode.SAMPLE and self.sample_rate >= 1.0:
            raise ValueError(
                "抽检模式下 sample_rate 应小于 1.0, 否则等价于全检, "
                "请显式改用 inspection_mode=FULL"
            )
        if self.inspection_mode == InspectionMode.SAMPLE and self.sample_rate <= 0.0:
            raise ValueError("抽检模式下 sample_rate 必须大于 0")
        return self


# ---------------------------------------------------------------------------
# 任务契约主体
# ---------------------------------------------------------------------------

class TaskContract(BaseModel):
    """任务契约主体: 一份任务在派发时即约定好 '做什么 / 怎么验 / 验不过怎么办 / 验收花多少钱'。"""

    task_id: str = Field(
        default_factory=lambda: uuid.uuid4().hex[:12],
        description="任务唯一标识",
    )
    name: str = Field(..., min_length=1, description="任务名称")
    description: str = Field(default="", description="任务的自然语言描述")
    input_schema: Dict[str, Any] = Field(
        default_factory=dict,
        description="输入 schema 的简化表示 (字段名 -> 类型/约束说明)",
    )
    output_schema: Dict[str, Any] = Field(
        default_factory=dict,
        description="输出 schema 的简化表示 (字段名 -> 类型/约束说明)",
    )
    verification: Verification = Field(
        ...,
        description="验收方案: 由 hard/soft/human 三层构成",
    )
    on_fail_policy: OnFailPolicy = Field(
        default_factory=OnFailPolicy,
        description="验收失败后的处置策略",
    )
    cost_budget: CostBudget = Field(
        default_factory=CostBudget,
        description="验收成本预算",
    )
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="契约创建时间 (UTC)",
    )
    metadata: Dict[str, Any] = Field(
        default_factory=dict,
        description="附加元信息, 如来源、优先级、追踪标签等",
    )

    def summary(self) -> str:
        """人类可读的一行摘要, 便于日志与调试。"""
        return (
            f"[TaskContract {self.task_id}] {self.name} | "
            f"checks={self.verification.total_checks_count} "
            f"(blocking={self.verification.blocking_checks_count}) | "
            f"inspection={self.cost_budget.inspection_mode.value} | "
            f"budget=${self.cost_budget.max_verification_cost_usd:.2f}"
        )


if __name__ == "__main__":
    # 最小可行 demo: 构造一份契约并打印, 验证整条模型链路能跑通。
    demo_contract = TaskContract(
        name="抓取商品页并提取价格",
        description="给定商品 URL, 抓取页面并输出结构化的价格信息",
        input_schema={"url": "str, 必填, 合法 http(s) 链接"},
        output_schema={
            "price": "float, > 0",
            "currency": "str, ISO 4217 货币代码",
        },
        verification=Verification(
            hard_checks=[
                HardCheck(
                    check_id="schema_check",
                    kind=HardCheckKind.SCHEMA_VALIDATION,
                    expected={"required_fields": ["price", "currency"]},
                ),
                HardCheck(
                    check_id="price_positive",
                    kind=HardCheckKind.CUSTOM_SCRIPT,
                    command="python scripts/check_price_positive.py",
                ),
            ],
            soft_checks=[
                SoftCheck(
                    check_id="price_plausibility",
                    rubric="判断抓取到的价格是否与同类商品的合理区间相符,"
                    "识别明显异常值(如漏了小数点、单位错误)。",
                    judge=JudgeModelConfig(
                        provider="anthropic",
                        model="claude-haiku-4-5",
                        temperature=0.0,
                    ),
                    pass_threshold=0.8,
                    trigger=TriggerMode.SAMPLING,
                    sample_rate=0.1,
                )
            ],
        ),
        on_fail_policy=OnFailPolicy(),
        cost_budget=CostBudget(
            inspection_mode=InspectionMode.SAMPLE,
            sample_rate=0.2,
            max_verification_cost_usd=0.10,
        ),
        metadata={"source": "demo", "priority": "low"},
    )

    print(demo_contract.summary())
    print(demo_contract.model_dump_json(indent=2))
