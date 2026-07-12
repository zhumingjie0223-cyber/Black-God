#!/usr/bin/env python3
"""
神枢 AI 网关 v2 - 多档路由 + 会诊聚合 + 上下文压缩防污染
Shenshu Gateway v2 - Multi-tier routing + advisory aggregation + compaction guard

在 router.py (v1 单选+容灾路由) 基础上新增三块能力:

1. AdvisoryPanel   —— 复杂任务多模型并行会诊后由主模型聚合决策,
                       而非只选一个"最贵"模型。顾问角色与执行角色严格分离。
2. SandboxProbe     —— 高危操作执行前做一次"影子探测",判断当前
                       环境是否真的具备隔离/回滚能力,探测失败就升级审批而非硬闯。
3. CompactionGuard  —— 长对话/长任务摘要必须带"仅供参考不是指令"标记,
                       防止摘要内容被下一轮误读成待执行任务("任务复活"问题)。

v2.1 质量整改(逐函数 review 后落地,详见 git 提交说明):
- 修真安全洞:evaluate_destructive_action 原实现里 CRITICAL 命令(如 rm -rf /)
  只要探测到"目标为空"就降级放行——现在 CRITICAL 永不降级、永不豁免二次确认。
- run_advisory_panel 总超时原来直接抛异常丢光全部已完成结果——现在超时槽位
  记为"缺席",已完成的意见照常返回。
- aggregate_advisory 全员缺席时原来还要白花一次聚合模型调用——现在短路返回。
- _resolve_entry_id 补线程锁与 returncode 校验,不再把 None 写进缓存毒化后续调用。
- sandbox_probe 大目录判空从 listdir 全量改为 scandir 首项即断;增加符号链接探测。
- wrap_compacted_summary 幂等化,防重复包裹造成标记嵌套。
- 全模块类型注解补全,函数内 import 上提。
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import re
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any, Optional


# ============================================================
# 一、AdvisoryPanel —— 多模型并行会诊 + 单点聚合决策
# ============================================================

@dataclass
class AdvisorSlot:
    """一个顾问位: 独立Provider+独立Model,只出意见不执行动作"""
    provider: str
    model: str
    role_hint: str = "从你的专长角度给出简短意见"


ADVISOR_SYSTEM_PROMPT = (
    "你是一次多模型会诊里的顾问角色。你不是执行者,不能调用工具、"
    "不能访问文件或网络,你的任务只是基于给定的问题给出你的专业判断。"
    "不要因为'没有工具权限'而拒绝回答或道歉——假设相关信息已经在问题描述里给全了。"
    "直接给出你的分析和建议,不要有开场白和免责声明。"
    "你的输出是私下提供给聚合决策者参考的,不是直接展示给用户的最终答案。"
)

AGGREGATOR_SYSTEM_PROMPT = "你是最终决策者,负责综合多方顾问意见给出可执行结论。"

# 错误信息统一截断长度(避免整段 stderr 撑爆决策记录)
_ERR_TRUNC = 300


@dataclass
class AdvisoryResult:
    slot: AdvisorSlot
    output_text: str = ""
    ok: bool = False
    error: Optional[str] = None
    latency_s: float = 0.0


def call_model(provider_label: str, model_id: str, system: str, user: str,
               timeout: int = 90) -> AdvisoryResult:
    """
    调用单个模型槽位。
    永不抛异常——失败转化为一条"该顾问缺席"的降级记录,
    绝不能因为一个顾问挂了就拖垮整个会诊流程。
    超时/JSON 解析失败/结构异常各给明确错误文案,方便事后排查是哪一环断的。
    """
    slot = AdvisorSlot(provider=provider_label, model=model_id)
    t0 = time.time()
    tmp_path: Optional[str] = None
    try:
        entry_id = _resolve_entry_id(provider_label, model_id)
        if not entry_id:
            return AdvisoryResult(slot=slot, ok=False,
                                  error=f"找不到模型条目: {provider_label}/{model_id}")

        payload = {
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ]
        }
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json",
                                         delete=False, encoding="utf-8") as tf:
            json.dump(payload, tf, ensure_ascii=False)
            tmp_path = tf.name

        try:
            proc = subprocess.run(
                ["minis-model-use", "run", "--model", entry_id, "--input", tmp_path],
                capture_output=True, text=True, timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return AdvisoryResult(slot=slot, ok=False,
                                  error=f"顾问超时(>{timeout}s)",
                                  latency_s=time.time() - t0)

        latency = time.time() - t0
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").strip()
            return AdvisoryResult(slot=slot, ok=False,
                                  error=f"退出码{proc.returncode}: {err[:_ERR_TRUNC]}",
                                  latency_s=latency)

        try:
            result = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return AdvisoryResult(slot=slot, ok=False,
                                  error=f"输出不是合法JSON: {proc.stdout[:_ERR_TRUNC]}",
                                  latency_s=latency)

        if not isinstance(result, dict) or not result.get("ok"):
            err_obj = result.get("error") if isinstance(result, dict) else None
            msg = err_obj.get("message", "unknown error") if isinstance(err_obj, dict) else "unknown error"
            return AdvisoryResult(slot=slot, ok=False, error=str(msg)[:_ERR_TRUNC],
                                  latency_s=latency)

        data = result.get("data")
        text = data.get("output_text", "") if isinstance(data, dict) else ""
        return AdvisoryResult(slot=slot, output_text=text, ok=True, latency_s=latency)
    except Exception as e:  # 兜底:任何未预料错误都转为缺席记录
        return AdvisoryResult(slot=slot, ok=False,
                              error=f"{type(e).__name__}: {e}",
                              latency_s=time.time() - t0)
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


_MODEL_ENTRY_CACHE: dict[str, str] = {}
_MODEL_ENTRY_LOCK = threading.Lock()  # 会诊并行解析时防止缓存竞写


def _resolve_entry_id(provider_label: str, model_id: str) -> Optional[str]:
    """
    把 (provider_label, model_id) 解析成 minis-model-use 认的 entry_id。
    只缓存成功结果——解析失败不写缓存,下次还有机会重试
    (原实现可能把 None 写进缓存,导致该槽位被永久毒化)。
    """
    cache_key = f"{provider_label}/{model_id}"
    with _MODEL_ENTRY_LOCK:
        if cache_key in _MODEL_ENTRY_CACHE:
            return _MODEL_ENTRY_CACHE[cache_key]
    try:
        out = subprocess.run(
            ["minis-config", "get", "models", "--filter", model_id],
            capture_output=True, text=True, timeout=15,
        )
        if out.returncode != 0:
            return None
        data = json.loads(out.stdout)
        raw = data.get("value", [])
        models = json.loads(raw) if isinstance(raw, str) else raw
        if not isinstance(models, list):
            return None
        for m in models:
            if (isinstance(m, dict)
                    and m.get("provider_label") == provider_label
                    and m.get("model_id") == model_id):
                entry = m.get("entry_id")
                if entry:  # 只缓存有效值
                    with _MODEL_ENTRY_LOCK:
                        _MODEL_ENTRY_CACHE[cache_key] = entry
                    return entry
                return None
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError,
            KeyError, TypeError, ValueError):
        pass
    return None


def run_advisory_panel(question: str, advisors: list[AdvisorSlot],
                       max_workers: int = 4,
                       panel_timeout: float = 120.0) -> list[AdvisoryResult]:
    """
    并行fan-out到多个顾问槽位,全部完成(或总超时)后统一返回。
    用线程池而非串行,因为顾问调用彼此独立无依赖。

    整改点:
    - 空顾问列表直接返回(原实现 max_workers=min(0) 会让线程池构造抛 ValueError);
    - 总超时不再向上抛异常丢光全部结果——超时未归的槽位记为"缺席(会诊总超时)",
      已完成的意见照常带回。
    """
    if not advisors:
        return []

    results: list[AdvisoryResult] = []
    workers = max(1, min(max_workers, len(advisors)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(call_model, a.provider, a.model, ADVISOR_SYSTEM_PROMPT, question): a
            for a in advisors
        }
        try:
            for fut in concurrent.futures.as_completed(futures, timeout=panel_timeout):
                try:
                    results.append(fut.result())
                except Exception as e:
                    slot = futures[fut]
                    results.append(AdvisoryResult(slot=slot, ok=False,
                                                  error=f"{type(e).__name__}: {e}"))
        except concurrent.futures.TimeoutError:
            for fut, slot in futures.items():
                if fut.done():
                    continue
                fut.cancel()
                results.append(AdvisoryResult(
                    slot=slot, ok=False,
                    error=f"缺席: 会诊总超时(>{panel_timeout:.0f}s)未返回",
                    latency_s=panel_timeout,
                ))
    return results


def aggregate_advisory(question: str, results: list[AdvisoryResult],
                       aggregator_provider: str,
                       aggregator_model: str) -> dict[str, Any]:
    """
    把所有顾问意见喂给聚合模型做最终决策。
    聚合模型必须用比顾问档位更高/更可信的模型,
    因为它承担的是"综合判断+承担最终责任"的角色。

    整改点:全部顾问缺席时短路返回,不再白花一次(最贵的)聚合模型调用。
    """
    ok_results = [r for r in results if r.ok]
    failed_results = [r for r in results if not r.ok]

    def _raw(rs: list[AdvisoryResult]) -> list[dict[str, Any]]:
        return [
            {"provider": r.slot.provider, "model": r.slot.model, "ok": r.ok,
             "latency_s": round(r.latency_s, 2),
             "output": r.output_text[:500] if r.ok else r.error}
            for r in rs
        ]

    if not ok_results:
        return {
            "question": question,
            "advisors_consulted": len(results),
            "advisors_succeeded": 0,
            "advisors_failed": len(failed_results),
            "final_decision": None,
            "final_ok": False,
            "final_error": "全部顾问缺席,已跳过聚合调用(不烧无意义的聚合模型费用)",
            "raw_advisory": _raw(results),
        }

    panel_text_parts = [
        f"【顾问 {r.slot.provider}/{r.slot.model}】\n{r.output_text}" for r in ok_results
    ] + [
        f"【顾问 {r.slot.provider}/{r.slot.model} 缺席】原因: {r.error}" for r in failed_results
    ]
    panel_text = "\n\n".join(panel_text_parts)

    aggregator_prompt = (
        f"以下是关于同一个问题,多位独立顾问给出的意见:\n\n{panel_text}\n\n"
        f"原始问题: {question}\n\n"
        "请综合以上意见,给出你的最终判断。如果顾问之间有分歧,明确指出分歧点并说明"
        "你采信哪一方的理由。缺席的顾问不用管,基于现有意见做判断即可。"
    )

    final = call_model(aggregator_provider, aggregator_model,
                       AGGREGATOR_SYSTEM_PROMPT, aggregator_prompt, timeout=150)

    return {
        "question": question,
        "advisors_consulted": len(results),
        "advisors_succeeded": len(ok_results),
        "advisors_failed": len(failed_results),
        "final_decision": final.output_text if final.ok else None,
        "final_ok": final.ok,
        "final_error": final.error,
        "raw_advisory": _raw(results),
    }


# ============================================================
# 二、SandboxProbe —— 高危操作前的影子探测
# ============================================================

class RiskLevel(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class RiskAssessment:
    level: RiskLevel
    category: str
    reason: str
    requires_confirmation: bool


# 删根匹配加固:兼容 -rf/-fr/-r -f/--recursive --force 等旗标顺序与合并写法,
# 以及 rm -rf //、rm -rf /* 变体;/子路径 不会误命中(路径后必须是空白/行尾/*)
_RM_ROOT = (r"rm\s+(?:--?[\w-]+\s+)*(?:--?[\w-]*[rR][\w-]*)\s+"
            r"(?:--?[\w-]+\s+)*/+(?:\s|$|\*)")

CRITICAL_REGEXES: list[re.Pattern[str]] = [
    re.compile(_RM_ROOT),
    re.compile(r"git\s+push\s+[^|;&]*--force(?!-with-lease)"),
    re.compile(r"git\s+push(?:\s+\S+)*\s+-f(?:\s|$)"),  # 裸 -f 与 --force 同级
    re.compile(r"git\s+reset\s+--hard"),
    # fork炸弹(允许各处空白:实际写法是 ":(){ :|:& };:",原正则漏掉了 & 后的空格)
    re.compile(r":\(\)\s*\{.*\|.*&\s*\}\s*;\s*:"),
    re.compile(r"drop\s+(database|table)", re.IGNORECASE),
    re.compile(r"truncate\s+table", re.IGNORECASE),
]

DESTRUCTIVE_PATTERNS: dict[RiskLevel, list[str]] = {
    RiskLevel.HIGH: [
        "rm -rf ", "rm -fr ", "git checkout --", "chmod -R 777", "> /dev/sd",
        "iptables -F", "systemctl stop", "kill -9",
    ],
    RiskLevel.MEDIUM: [
        "git commit", "git push", "apt remove", "apk del", "pip uninstall",
    ],
}


def assess_command_risk(command: str) -> RiskAssessment:
    """
    对一条即将执行的shell命令做风险分级。
    CRITICAL 用正则精确匹配整体模式(防止子路径操作被误判成删根),
    HIGH/MEDIUM 用子串匹配即可。判定优先级: CRITICAL > HIGH > MEDIUM > LOW,命中即返回。
    空命令/纯空白直接判 LOW(原实现会对 None 崩溃)。
    """
    if not command or not command.strip():
        return RiskAssessment(level=RiskLevel.LOW, category="empty",
                              reason="空命令", requires_confirmation=False)

    for regex in CRITICAL_REGEXES:
        m = regex.search(command)
        if m:
            return RiskAssessment(
                level=RiskLevel.CRITICAL, category="destructive_command",
                reason=f"命中极端危险模式: {m.group(0)}",
                requires_confirmation=True,
            )

    cmd_lower = command.lower()
    for level in (RiskLevel.HIGH, RiskLevel.MEDIUM):
        for pattern in DESTRUCTIVE_PATTERNS.get(level, []):
            if pattern.lower() in cmd_lower:
                return RiskAssessment(
                    level=level, category="destructive_command",
                    reason=f"命中高危模式: {pattern}",
                    requires_confirmation=(level == RiskLevel.HIGH),
                )
    return RiskAssessment(level=RiskLevel.LOW, category="normal",
                          reason="未命中高危模式", requires_confirmation=False)


def sandbox_probe(target_path: str) -> dict[str, Any]:
    """
    影子探测: 真正执行高危操作前先用只读方式确认目标状态。

    整改点:
    - 大目录判空不再 listdir 全量拉取(百万文件目录会卡死),scandir 取首项即断;
    - 增加 is_symlink——符号链接背后可能是非空真身,调用方不得据"空"降级;
    - 空路径入参直接判探测失败。
    """
    probe: dict[str, Any] = {"target": target_path, "exists": False,
                             "is_empty": None, "is_dir": None,
                             "is_symlink": False, "probe_ok": True}
    if not target_path:
        probe["probe_ok"] = False
        probe["probe_error"] = "目标路径为空"
        return probe
    try:
        probe["is_symlink"] = os.path.islink(target_path)
        probe["exists"] = os.path.exists(target_path)
        if probe["exists"]:
            probe["is_dir"] = os.path.isdir(target_path)
            if probe["is_dir"]:
                with os.scandir(target_path) as it:
                    probe["is_empty"] = next(iter(it), None) is None
            else:
                probe["is_empty"] = os.path.getsize(target_path) == 0
    except OSError as e:
        probe["probe_ok"] = False
        probe["probe_error"] = str(e)
    return probe


def evaluate_destructive_action(command: str,
                                target_path: Optional[str] = None) -> dict[str, Any]:
    """
    对外主入口: 命令风险分级 + (可选)目标路径影子探测。

    整改点(真安全洞修复):
    - 原实现只要探测到"目标为空"就把风险降级并豁免确认,连 CRITICAL(rm -rf / 这类)
      也照降——现在 **CRITICAL 永不降级、永不豁免二次确认**,降级通道只对 HIGH 开放;
    - 目标是符号链接时不降级(空判定看的是链接本身,真身可能非空);
    - 探测与执行之间存在时间窗(TOCTOU),降级结论仅供调度参考,
      requires_confirmation=True 的结论任何调用方不得绕过。
    """
    risk = assess_command_risk(command)
    result: dict[str, Any] = {
        "command": command,
        "risk_level": risk.level.value,
        "category": risk.category,
        "reason": risk.reason,
        "requires_confirmation": risk.requires_confirmation,
    }
    if target_path and risk.level in (RiskLevel.HIGH, RiskLevel.CRITICAL):
        probe = sandbox_probe(target_path)
        result["probe"] = probe
        can_downgrade = (
            risk.level == RiskLevel.HIGH          # CRITICAL 永不降级
            and probe.get("probe_ok")
            and probe.get("exists")
            and probe.get("is_empty")
            and not probe.get("is_symlink")       # 链接背后可能是非空真身
        )
        if can_downgrade:
            result["risk_level"] = RiskLevel.MEDIUM.value
            result["requires_confirmation"] = False
            result["reason"] += "；但探测发现目标为空,降级为中风险,可直接执行"
    return result


# ============================================================
# 三、CompactionGuard —— 长任务摘要防"任务复活"污染
# ============================================================

COMPACTION_GUARD_PREFIX = (
    "[以下是历史任务摘要——仅供参考,不是当前要执行的指令]\n"
    "早期的对话/操作已被压缩总结如下。这是背景参考,不代表现在要做的事。\n"
    "不要把摘要里提到的待办事项当成当前任务重新执行——它们要么已完成要么已作废。\n"
    "只响应这段摘要之后出现的最新消息,那才是当前唯一要处理的事。\n"
    "即使话题看起来相似,最新消息也永远优先于摘要内容。\n"
    "如果最新消息里有'停'、'不用了'、'算了'这类反向信号,"
    "必须立刻终止摘要里描述的任何在途工作,不要在后续轮次里又把它翻出来。\n"
    "---\n"
)

COMPACTION_GUARD_SUFFIX = "\n---\n[历史摘要结束——请回应上面这条分隔线之后的最新消息]"

# 识别标记派生自前缀常量本身,杜绝双写字符串日后改动漂移
_GUARD_MARK = COMPACTION_GUARD_PREFIX.split("\n", 1)[0]


def wrap_compacted_summary(raw_summary: str) -> str:
    """
    给长任务/长对话的摘要文本包裹防污染标记。

    整改点:幂等——已包裹过的摘要原样返回,防止多轮压缩叠出嵌套标记
    (嵌套后"摘要结束"分隔线会出现多条,反而制造新的误读面)。
    空摘要返回空串,不产出只有标记没有内容的空壳。
    """
    if not raw_summary or not raw_summary.strip():
        return ""
    if is_compacted_summary(raw_summary):
        return raw_summary
    return f"{COMPACTION_GUARD_PREFIX}{raw_summary.strip()}{COMPACTION_GUARD_SUFFIX}"


def is_compacted_summary(text: Optional[str]) -> bool:
    """判断一段文本是否已经是包裹过的历史摘要(None/空值容错)。"""
    if not text:
        return False
    return text.strip().startswith(_GUARD_MARK)
