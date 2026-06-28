#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God — 真实后端工厂 (real_backends)

把 gateway.py 的 mock 后端换成走 llm_adapter 的真实调用。
- 有可用 Key  → ModelBackend.generate_fn 走真实 llm()
- 无可用 Key  → 自动回退到 mock（gateway 默认行为），保证离线可跑

用法：
    from real_backends import real_gateway
    gw = real_gateway()          # 自动探测 Key，决定真/mock
    from cost_engine import CostEngine ...   # gateway 传 gw 即可
"""
from __future__ import annotations

import os
from typing import Optional, Callable

from gateway import ModelGateway, ModelBackend, Tier
import llm_adapter as la


# --------------------------------------------------------------------------- #
#  后端注册表：name -> (tier, 能力画像, 成本, 延迟, 拒绝率, base, model 解析)
#  base/model 用环境变量覆盖，缺省给合理默认。
# --------------------------------------------------------------------------- #
BACKEND_SPECS = [
    # 强模型档
    {
        "name": "claude", "tier": Tier.STRONG,
        "cap": {"coding": 0.95, "reasoning": 0.93, "long_ctx": 0.9, "general": 0.9},
        "cost": 9.0, "latency": 900, "refuse": 0.05,
        "env_key": "ANTHROPIC_API_KEY",
        "base": "https://api.anthropic.com/v1",        # 经兼容层时改这里
        "model_env": "BG_CLAUDE_MODEL", "model": "claude-3-5-sonnet-20241022",
    },
    {
        "name": "gpt", "tier": Tier.STRONG,
        "cap": {"coding": 0.9, "reasoning": 0.92, "long_ctx": 0.85, "general": 0.88},
        "cost": 8.0, "latency": 950, "refuse": 0.04,
        "env_key": "OPENAI_API_KEY",
        "base": "https://api.openai.com/v1",
        "model_env": "BG_GPT_MODEL", "model": "gpt-4o",
    },
    # 便宜档
    {
        "name": "deepseek", "tier": Tier.SMALL,
        "cap": {"coding": 0.9, "reasoning": 0.85, "general": 0.82},
        "cost": 1.2, "latency": 1300, "refuse": 0.02,
        "env_key": "DEEPSEEK_API_KEY",
        "base": "https://api.deepseek.com/v1",
        "model_env": "BG_DEEPSEEK_MODEL", "model": "deepseek-chat",
    },
    {
        "name": "gemini", "tier": Tier.SMALL,
        "cap": {"coding": 0.85, "reasoning": 0.86, "long_ctx": 0.9, "general": 0.85},
        "cost": 0.5, "latency": 800, "refuse": 0.03,
        "env_key": "GEMINI_API_KEY",
        "base": "https://generativelanguage.googleapis.com/v1beta/openai",
        "model_env": "BG_GEMINI_MODEL", "model": "gemini-2.0-flash",
    },
    # 网关聚合（Legend Coordinator 等，一个 key 路由多模型）
    {
        "name": "gateway", "tier": Tier.SMALL,
        "cap": {"coding": 0.85, "reasoning": 0.85, "general": 0.85},
        "cost": 0.3, "latency": 1000, "refuse": 0.0,
        "env_key": "BG_KEY",
        "base_env": "BG_BASE", "base": "http://47.236.124.97/v1",
        "model_env": "BG_MODEL", "model": "auto",
    },
]


def _make_generate_fn(api_key: str, base: str, model: str) -> Callable[[str], str]:
    """生成一个真实调用闭包，绑定到具体后端的 key/base/model。"""
    def _gen(prompt: str) -> str:
        # llm() 内部会按 refusal/error 抛异常，gateway 会据此 fallback/熔断
        return la.llm(prompt, key=api_key, base=base, model=model,
                      max_tokens=2048, timeout=90)
    return _gen


def real_gateway(force_mock: bool = False) -> ModelGateway:
    """
    构建网关：
    - 对每个 spec，若其 env_key 有值 → 注册真实后端（generate_fn=真实调用）
    - 否则 → 注册同画像的 mock 后端（generate_fn=None，gateway 用内置 mock）
    - 一个真实后端都没有 → 全 mock，保证离线可跑
    """
    gw = ModelGateway()
    real_count = 0

    for s in BACKEND_SPECS:
        api_key = "" if force_mock else os.environ.get(s["env_key"], "")
        base = os.environ.get(s.get("base_env", ""), "") or s["base"]
        model = os.environ.get(s.get("model_env", ""), "") or s["model"]

        gen_fn = None
        if api_key:
            gen_fn = _make_generate_fn(api_key, base, model)
            real_count += 1

        gw.register(ModelBackend(
            s["name"], s["tier"], s["cap"],
            cost_per_1k=s["cost"], latency_ms=s["latency"],
            refuse_prob=s["refuse"], generate_fn=gen_fn,
        ))

    # 永远挂一个本地兜底（mock，~0 成本），保证 fallback 链不断
    gw.register(ModelBackend(
        "local_sm", Tier.LOCAL,
        {"coding": 0.6, "reasoning": 0.55, "general": 0.6},
        cost_per_1k=0.0, latency_ms=300, refuse_prob=0.0,
    ))

    gw._real_backend_count = real_count  # 供上层探测
    return gw


def status() -> dict:
    """报告哪些后端有真实 key（不输出 key 值）。"""
    out = {"real": [], "mock": [], "live_check": None}
    for s in BACKEND_SPECS:
        if os.environ.get(s["env_key"], ""):
            out["real"].append(s["name"])
        else:
            out["mock"].append(s["name"])
    out["has_any_key"] = len(out["real"]) > 0
    return out


if __name__ == "__main__":
    import json
    print(json.dumps(status(), ensure_ascii=False, indent=2))
