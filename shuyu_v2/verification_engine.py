"""
verification_engine.py

对 TaskContract 的执行产出进行验证：
- hard checks: 可执行的确定性校验（subprocess 跑 command）
- soft checks: 交给可插拔的 LLM 裁判（judge_caller）打分
- failure cause: v1 版最小可行的失败归因启发式规则

注意：本文件不重新定义契约类，全部从 task_contract 导入。
"""

from __future__ import annotations

import shlex
import subprocess
from dataclasses import dataclass, field
from typing import Any, Callable, List, Optional

from task_contract import (
    TaskContract,
    HardCheck,
    SoftCheck,
    FailureCause,
)


# ---------------------------------------------------------------------------
# 结果数据结构
# ---------------------------------------------------------------------------

@dataclass
class HardCheckResult:
    check: HardCheck
    passed: bool
    detail: str = ""          # 命令输出 / 失败原因 / 跳过说明
    skipped: bool = False     # 没有 command 可执行时标记为 skipped


@dataclass
class SoftCheckResult:
    check: SoftCheck
    score: float              # judge_caller 返回的 0-1 分数
    threshold: float          # 判定通过的分数线
    passed: bool
    detail: str = ""


@dataclass
class VerificationResult:
    passed: bool
    hard_results: List[HardCheckResult] = field(default_factory=list)
    soft_results: List[SoftCheckResult] = field(default_factory=list)
    failure_cause: Optional[FailureCause] = None
    summary: str = ""


# ---------------------------------------------------------------------------
# 验证引擎
# ---------------------------------------------------------------------------

class VerificationEngine:
    """
    验证引擎：把契约里的检查项真正跑起来，并给出失败归因。

    设计原则：
    - hard check 用 subprocess 跑确定性命令，不依赖任何模型
    - soft check 通过 judge_caller 注入裁判实现（可插拔），
      引擎本身不硬编码任何 LLM API
    """

    # subprocess 超时（秒），防止校验命令挂死
    HARD_CHECK_TIMEOUT = 30

    # ---- 1. hard checks -------------------------------------------------

    def run_hard_checks(
        self,
        contract: TaskContract,
        execution_output: Any,
    ) -> List[HardCheckResult]:
        """
        逐条执行 contract.verification.hard_checks。
        - 如果检查项带有 command，则用 subprocess 执行，
          returncode == 0 视为通过。
        - command 中出现占位符 {output} 时，替换为 execution_output 的字符串形式。
        - 没有 command 的检查项标记为 skipped（不算失败，但也不算真正验证过）。
        """
        results: List[HardCheckResult] = []
        output_str = str(execution_output)

        for check in contract.verification.hard_checks:
            command = check.command

            if not command:
                results.append(HardCheckResult(
                    check=check,
                    passed=True,
                    skipped=True,
                    detail="无可执行 command，跳过（视为未验证，不阻塞）",
                ))
                continue

            rendered = command.replace("{output}", shlex.quote(output_str))
            try:
                proc = subprocess.run(
                    rendered,
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=self.HARD_CHECK_TIMEOUT,
                )
                passed = proc.returncode == 0
                detail = (proc.stdout or "") + (proc.stderr or "")
                results.append(HardCheckResult(
                    check=check,
                    passed=passed,
                    detail=detail.strip()[:2000],
                ))
            except subprocess.TimeoutExpired:
                results.append(HardCheckResult(
                    check=check,
                    passed=False,
                    detail=f"命令超时（>{self.HARD_CHECK_TIMEOUT}s）: {rendered}",
                ))
            except Exception as e:
                results.append(HardCheckResult(
                    check=check,
                    passed=False,
                    detail=f"执行异常: {e!r}",
                ))

        return results

    # ---- 2. soft checks -------------------------------------------------

    def run_soft_checks(
        self,
        contract: TaskContract,
        execution_output: Any,
        judge_caller: Callable[[SoftCheck, Any], float],
    ) -> List[SoftCheckResult]:
        """
        对每条 contract.verification.soft_checks 调用外部注入的裁判 judge_caller。

        judge_caller 的约定：
            输入 (soft_check, execution_output)，返回 0-1 之间的分数。
        引擎不关心裁判背后是哪个模型 / API（provider/model 已在 SoftCheck.judge
        字段里声明，具体怎么调用交给 judge_caller 实现），方便以后替换真实实现。
        """
        results: List[SoftCheckResult] = []

        for check in contract.verification.soft_checks:
            threshold = check.pass_threshold
            try:
                score = float(judge_caller(check, execution_output))
                # 防御性裁剪，裁判实现不可信时也不至于产生非法分数
                score = max(0.0, min(1.0, score))
                results.append(SoftCheckResult(
                    check=check,
                    score=score,
                    threshold=threshold,
                    passed=score >= threshold,
                    detail=f"judge={check.judge.model} score={score:.2f}, threshold={threshold:.2f}",
                ))
            except Exception as e:
                results.append(SoftCheckResult(
                    check=check,
                    score=0.0,
                    threshold=threshold,
                    passed=False,
                    detail=f"裁判调用失败: {e!r}",
                ))

        return results

    # ---- 3. failure cause -----------------------------------------------

    def determine_failure_cause(
        self,
        hard_results: List[HardCheckResult],
        soft_results: List[SoftCheckResult],
    ) -> Optional[FailureCause]:
        """
        v1 最小可行的失败归因启发式规则。

        !!! 待改进点 !!!
        这是一套非常粗糙的规则，只是为了先把归因这条链路跑通，不是最终方案：
        - 规则1：如果所有真正执行过的 hard_check（排除 skipped）都失败，
          且其中包含 schema 类校验的失败
          （通过检查项 check_id/kind 名字里含 "schema" 粗暴判断），
          认为连产出的基本结构都不对 —— 大概率是任务定义本身有缺陷，
          判定为 TASK_DEFINITION_DEFECT。
        - 规则2：hard_check 全部通过（结构没问题），但 soft_check 分数不达标，
          说明"做出来了但做得不好"，判定为 EXECUTION_QUALITY_DEFECT。
        - 其余混合情况一律先归为 EXECUTION_QUALITY_DEFECT（保守默认）。

        已知缺陷（后续版本必须解决，这里不假装已经解决）：
        - 用字符串匹配 "schema" 来识别早期阶段失败，非常脆弱，容易误判
        - 没有考虑第三方环境问题（网络挂了、依赖缺失、裁判API超时）这类归因，
          目前会被错误地并入 EXECUTION_QUALITY_DEFECT
        - 没有利用失败的 detail 文本做更细的分析
          （这里本应也交给一个专门的"归因裁判" LLM，而不是硬编码规则，
          但那样又会引入"用哪个模型做归因裁判、归因裁判自己会不会错"的新问题，
          v1 先用规则占位，暴露这个已知短板而不是掩盖它）
        """
        real_hard = [r for r in hard_results if not r.skipped]
        hard_all_failed = bool(real_hard) and all(not r.passed for r in real_hard)
        hard_all_passed = all(r.passed for r in real_hard)  # 空列表视为通过
        soft_all_passed = all(r.passed for r in soft_results)  # 空列表视为通过

        if hard_all_passed and soft_all_passed:
            return None  # 没有失败，无需归因

        if hard_all_failed:
            def looks_like_schema(r: HardCheckResult) -> bool:
                text = (str(r.check.check_id) + str(r.check.kind.value)).lower()
                return "schema" in text

            if any(looks_like_schema(r) and not r.passed for r in real_hard):
                return FailureCause.TASK_DEFINITION_DEFECT

        if hard_all_passed and not soft_all_passed:
            return FailureCause.EXECUTION_QUALITY_DEFECT

        # 混合情况的保守默认值（v1 先不细分）
        return FailureCause.EXECUTION_QUALITY_DEFECT

    # ---- 4. 整合入口 ----------------------------------------------------

    def verify(
        self,
        contract: TaskContract,
        execution_output: Any,
        judge_caller: Callable[[SoftCheck, Any], float],
    ) -> VerificationResult:
        """
        完整验证流程：hard checks -> soft checks -> 失败归因 -> 汇总。
        """
        hard_results = self.run_hard_checks(contract, execution_output)
        soft_results = self.run_soft_checks(contract, execution_output, judge_caller)

        hard_all_passed = all(r.passed for r in hard_results)
        soft_all_passed = all(r.passed for r in soft_results)
        passed = hard_all_passed and soft_all_passed

        if not passed:
            failure_cause = self.determine_failure_cause(hard_results, soft_results)
        else:
            failure_cause = None

        if passed:
            summary = (
                f"验证通过：{len(hard_results)} 项硬检查全部通过，"
                f"{len(soft_results)} 项软检查全部达标。"
            )
        else:
            failed_hard = [r.check.check_id for r in hard_results if not r.passed]
            failed_soft = [r.check.check_id for r in soft_results if not r.passed]
            summary = (
                f"验证失败：未通过的硬检查 {failed_hard}，"
                f"未达标的软检查 {failed_soft}，"
                f"失败归因：{failure_cause}。"
            )

        return VerificationResult(
            passed=passed,
            hard_results=hard_results,
            soft_results=soft_results,
            failure_cause=failure_cause,
            summary=summary,
        )


if __name__ == "__main__":
    # 复用 task_contract.py demo 里"抓取商品页价格"任务的构造逻辑
    from shuyu.v2.task_contract import (
        Verification, HardCheckKind, JudgeModelConfig,
        TriggerMode, OnFailPolicy, CostBudget, InspectionMode,
    )

    contract = TaskContract(
        name="抓取商品页并提取价格",
        description="给定商品 URL, 抓取页面并输出结构化的价格信息",
        input_schema={"url": "str, 必填, 合法 http(s) 链接"},
        output_schema={"price": "float, > 0", "currency": "str, ISO 4217 货币代码"},
        verification=Verification(
            hard_checks=[
                HardCheck(
                    check_id="schema_check",
                    kind=HardCheckKind.SCHEMA_VALIDATION,
                    # 用一段可执行的 python -c 做最小可行的 schema 校验，
                    # 真实项目里应该换成专门的 schema 校验脚本
                    command="python3 -c \"import sys,ast; d=ast.literal_eval(sys.argv[1]); "
                            "assert isinstance(d.get('price'), (int,float)); "
                            "assert isinstance(d.get('currency'), str)\" {output}",
                ),
                HardCheck(
                    check_id="price_positive",
                    kind=HardCheckKind.CUSTOM_SCRIPT,
                    command="python3 -c \"import sys,ast; d=ast.literal_eval(sys.argv[1]); "
                            "assert d['price'] > 0\" {output}",
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

    def fake_judge_caller(check: SoftCheck, output: Any) -> float:
        """模拟裁判：固定返回 0.85 分，仅用于打通链路的 demo。"""
        return 0.85

    execution_output = {"price": 29.9, "currency": "USD"}

    engine = VerificationEngine()
    result = engine.verify(contract, execution_output, fake_judge_caller)

    print("summary:", result.summary)
    print("passed:", result.passed)
    print("failure_cause:", result.failure_cause)
