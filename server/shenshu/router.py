#!/usr/bin/env python3
"""
神枢 AI 网关 - 模型分档路由器
Shenshu Gateway - Complexity-based Model Router

核心逻辑: 神枢决断——枢不是Agent，不需要兜底。
一个复杂度，一个模型，一个决断。
"""

import re
import json
import subprocess
from dataclasses import dataclass
from enum import Enum


class Complexity(Enum):
    TRIVIAL = "trivial"    # 0-20分: 格式化/改错字/简单问答
    LOW = "low"             # 20-40分: 小功能/单文件改动
    MEDIUM = "medium"       # 40-60分: 常规开发/多文件协调
    HIGH = "high"           # 60-80分: 复杂重构/架构调整
    MAX = "max"             # 80-100分: 顶级架构设计/关键决策


@dataclass
class ModelRoute:
    """一条路由 = Primary Provider/Model + Sub Provider/Model (跨厂商容灾)"""
    primary_provider: str
    primary_model: str
    sub_provider: str
    sub_model: str
    label: str


# ============================================================
# 神枢路由表 —— 基于今晚实测的真实Provider/模型清单
# ============================================================
ROUTING_TABLE = {
    Complexity.TRIVIAL: ModelRoute(
        primary_provider="Anthropic 2jie",
        primary_model="claude-haiku-4-5-20251001",
        sub_provider="DeepSeek",
        sub_model="deepseek-v4-flash",
        label="极低复杂度：格式化/错字/简单问答",
    ),
    Complexity.LOW: ModelRoute(
        primary_provider="网关",
        primary_model="claude-sonnet-4-6",
        sub_provider="Anthropic 2jie",
        sub_model="claude-sonnet-4-6",
        label="低复杂度：小功能/单文件改动",
    ),
    Complexity.MEDIUM: ModelRoute(
        primary_provider="max号",
        primary_model="claude-sonnet-5",
        sub_provider="Anthropic 2jie",
        sub_model="claude-sonnet-5",
        label="中复杂度：常规开发/多文件协调",
    ),
    Complexity.HIGH: ModelRoute(
        primary_provider="Anthropic 2jie",
        primary_model="claude-opus-4-7",
        sub_provider="max号",
        sub_model="claude-opus-4-8",
        label="高复杂度：复杂重构/架构调整",
    ),
    Complexity.MAX: ModelRoute(
        primary_provider="max号",
        primary_model="claude-opus-4-8",
        sub_provider="Anthropic 2jie",
        sub_model="claude-opus-4-8",
        label="极高复杂度：顶级架构设计",
    ),
}

# 全厂商挂了的最终兜底(与Anthropic完全独立的供应商)
EMERGENCY_FALLBACK = ModelRoute(
    primary_provider="Google Gemini",
    primary_model="gemini-2.5-pro",
    sub_provider="DeepSeek",
    sub_model="deepseek-v4-pro",
    label="紧急兜底：Anthropic全线不可用时启用",
)


# ============================================================
# 复杂度评分器
# ============================================================
COMPLEXITY_KEYWORDS = {
    Complexity.MAX: [
        "架构设计", "重新设计", "从零搭建", "从零设计", "系统性重构", "完整的架构",
        "architecture", "redesign", "rebuild from scratch",
    ],
    Complexity.HIGH: [
        "重构", "优化性能", "复杂逻辑", "多模块", "并发", "分布式",
        "refactor", "complex", "concurrent", "distributed",
    ],
    Complexity.LOW: [
        "改一下", "小改动", "修个", "调整一下", "加个",
        "small fix", "minor", "tweak", "adjust",
    ],
    Complexity.TRIVIAL: [
        "错字", "格式化", "翻译", "一句话", "简单",
        "typo", "format", "translate", "simple",
    ],
}


def score_complexity(task_text: str, estimated_steps: int = 1,
                      file_count: int = 1) -> Complexity:
    """
    基于关键词 + 预估步骤数 + 涉及文件数，评估任务复杂度。
    这是启发式规则，不是精确科学，宁可路由到更高档位也不要
    路由到更低档位(省小钱不如别翻车)。
    """
    text_lower = task_text.lower()

    # 关键词命中检测(从高到低检测，命中即返回)
    for complexity in [Complexity.MAX, Complexity.HIGH, Complexity.LOW, Complexity.TRIVIAL]:
        keywords = COMPLEXITY_KEYWORDS.get(complexity, [])
        if any(kw in text_lower for kw in keywords):
            return complexity

    # 无关键词命中时，按步骤数和文件数量启发式判断
    if estimated_steps >= 8 or file_count >= 5:
        return Complexity.MAX
    elif estimated_steps >= 5 or file_count >= 3:
        return Complexity.HIGH
    elif estimated_steps >= 2 or file_count >= 2:
        return Complexity.MEDIUM
    elif estimated_steps == 1 and file_count == 1:
        return Complexity.LOW

    return Complexity.MEDIUM  # 默认走中档，不确定时不赌运气


def get_route(complexity: Complexity) -> ModelRoute:
    """获取指定复杂度对应的路由配置"""
    return ROUTING_TABLE.get(complexity, ROUTING_TABLE[Complexity.MEDIUM])


def apply_route_to_session(route: ModelRoute) -> dict:
    """
    把路由配置真正写入当前会话 (通过 minis-config 实际执行)。
    这里不再是纸面方案 —— 直接调 minis-config set 命令落地。
    """
    results = {
        "route_label": route.label,
        "primary": f"{route.primary_provider} / {route.primary_model}",
        "sub": f"{route.sub_provider} / {route.sub_model}",
    }

    # Step 1: 拉取真实模型清单，解析出 entry_id (provider_uuid/model_id)
    try:
        list_out = subprocess.run(
            ["minis-config", "get", "models"],
            capture_output=True, text=True, timeout=15
        )
        models_data = json.loads(list_out.stdout)
        models = json.loads(models_data["value"])
    except Exception as e:
        results["error"] = f"读取模型列表失败: {e}"
        return results

    def find_entry_id(provider_label: str, model_id: str) -> str | None:
        for m in models:
            if m.get("provider_label") == provider_label and m.get("model_id") == model_id:
                return m.get("entry_id")
        return None

    primary_entry = find_entry_id(route.primary_provider, route.primary_model)
    sub_entry = find_entry_id(route.sub_provider, route.sub_model)

    if not primary_entry:
        results["error"] = f"找不到 Primary 模型: {route.primary_provider}/{route.primary_model}"
        return results
    if not sub_entry:
        results["error"] = f"找不到 Sub 模型: {route.sub_provider}/{route.sub_model}"
        return results

    # Step 2: 实际写入 session.primaryModel
    try:
        primary_val = json.dumps(f"entry:{primary_entry}")
        r1 = subprocess.run(
            ["minis-config", "set", "session.primaryModel", primary_val],
            capture_output=True, text=True, timeout=35
        )
        primary_result = json.loads(r1.stdout) if r1.stdout else {"ok": False, "raw_error": r1.stderr}
        results["primary_write"] = primary_result.get("ok", False)
    except Exception as e:
        results["primary_write"] = False
        results["primary_write_error"] = str(e)

    # Step 3: 实际写入 session.subModel
    try:
        sub_val = json.dumps(f"entry:{sub_entry}")
        r2 = subprocess.run(
            ["minis-config", "set", "session.subModel", sub_val],
            capture_output=True, text=True, timeout=35
        )
        sub_result = json.loads(r2.stdout) if r2.stdout else {"ok": False, "raw_error": r2.stderr}
        results["sub_write"] = sub_result.get("ok", False)
    except Exception as e:
        results["sub_write"] = False
        results["sub_write_error"] = str(e)

    results["applied"] = results.get("primary_write", False) and results.get("sub_write", False)
    return results


def route_task(task_text: str, estimated_steps: int = 1, file_count: int = 1) -> dict:
    """
    对外主入口: 输入任务描述，输出完整路由决策。
    """
    complexity = score_complexity(task_text, estimated_steps, file_count)
    route = get_route(complexity)

    return {
        "task_preview": task_text[:80],
        "estimated_steps": estimated_steps,
        "file_count": file_count,
        "complexity": complexity.value,
        "route": apply_route_to_session(route),
    }


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "--apply":
        # 真实模式: 接收任务描述，评分并实际写入当前会话
        task = " ".join(sys.argv[2:]) or "帮我处理一个任务"
        result = route_task(task, estimated_steps=3, file_count=2)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        sys.exit(0)

    # 自测用例(不实际写入，仅打印路由决策文字说明)
    test_cases = [
        ("修一下这个错字", 1, 1),
        ("帮我加个登录功能", 3, 2),
        ("重构整个订单模块的并发逻辑", 6, 4),
        ("从零设计一套完整的分布式任务调度架构", 10, 8),
    ]

    print("=== 神枢网关路由自测(纯评分,不写入) ===\n")
    for text, steps, files in test_cases:
        complexity = score_complexity(text, steps, files)
        route = get_route(complexity)
        print(f"任务: {text}")
        print(f"  复杂度: {complexity.value}")
        print(f"  路由: {route.primary_provider}/{route.primary_model}")
        print(f"       (备: {route.sub_provider}/{route.sub_model})")
        print(f"  说明: {route.label}")
        print()

    print("真实写入用法: python3 router.py --apply <任务描述>")
