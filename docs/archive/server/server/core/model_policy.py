#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God · 模型策略闸  model_policy.py
================================================
作用：把"模型"约束起来，落地三件事——
  1) 禁止本地模型推理（ollama / lm studio / llama.cpp / 任何 loopback 端点）
     —— 你的原则：本地模型质量不够，一律走远端。
  2) 模型白名单：只允许在册的远端模型，挡掉手滑/被改的低质模型。
  3) 分级路由：light（轻任务/省 Key）/ heavy（重任务/求质量），
     每级都映射到一个"已批准的远端模型"。

零依赖，纯标准库，可直接 import。配置走环境变量，改配置不用改码。

环境变量：
  BG_ALLOWED_MODELS   逗号分隔的允许模型，如 "gpt-4o,claude-3-7-sonnet,deepseek-chat"
  BG_MODEL_LIGHT      轻任务模型（默认取白名单里偏快的）
  BG_MODEL_HEAVY      重任务模型（默认取白名单里偏强的）
  BG_ALLOW_LOCAL=1    显式放开本地模型（默认 0，禁用；仅调试用，生产别开）
"""
import os
import re
from urllib.parse import urlparse


class ModelPolicyError(Exception):
    """模型不合规：本地端点 / 不在白名单。上层应据此拒绝或回退。"""


# ——— 默认允许的远端模型（可被 BG_ALLOWED_MODELS 覆盖）———
_DEFAULT_ALLOWED = [
    "gpt-4o", "gpt-4o-mini", "gpt-4.1", "o3", "o4-mini",
    "claude-opus-4", "claude-sonnet-4", "claude-3-7-sonnet",
    "deepseek-chat", "deepseek-reasoner",
]

# ——— 本地推理端点特征（命中即视为"本地模型"，默认禁用）———
_LOCAL_HOSTS = {"localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"}
_LOCAL_HOST_RE = re.compile(r"\.local$|^127\.|^10\.|^192\.168\.|^169\.254\.|^172\.(1[6-9]|2\d|3[01])\.")
# 常见本地大模型服务端口
_LOCAL_PORTS = {11434, 1234, 8080, 5000, 5001, 8000, 1337, 4891}
# 本地推理框架的标志串
_LOCAL_MARKERS = ("ollama", "lmstudio", "lm-studio", "llama.cpp", "llamacpp",
                  "localai", "koboldcpp", "textgen", "vllm", "jan.ai")


def allowed_models():
    env = os.environ.get("BG_ALLOWED_MODELS", "").strip()
    if env:
        return [m.strip() for m in env.split(",") if m.strip()]
    return list(_DEFAULT_ALLOWED)


def _allow_local():
    return os.environ.get("BG_ALLOW_LOCAL", "0") == "1"


def is_local_endpoint(base_url: str) -> bool:
    """判断一个 base_url 是否指向本地模型推理端点。"""
    if not base_url:
        return False
    u = base_url.lower()
    if any(m in u for m in _LOCAL_MARKERS):
        return True
    try:
        p = urlparse(base_url if "://" in base_url else "http://" + base_url)
        host = (p.hostname or "").lower()
        port = p.port
    except Exception:
        return True  # 解析不了，从严当本地拦
    if host in _LOCAL_HOSTS:
        return True
    if host and _LOCAL_HOST_RE.search(host):
        return True
    if port and port in _LOCAL_PORTS:
        return True
    return False


def assert_remote(base_url: str, model: str):
    """
    入口校验：本地端点 / 不在白名单 → 抛 ModelPolicyError。
    在 create_agent / _call_model 之前调用。
    """
    if is_local_endpoint(base_url) and not _allow_local():
        raise ModelPolicyError(
            f"已拒绝本地模型端点（{base_url}）：本地模型质量不足，请改用远端网关。"
            f"（仅调试可设 BG_ALLOW_LOCAL=1 放开）"
        )
    allow = allowed_models()
    # 允许带 provider 前缀的写法（如 anthropic/claude-sonnet-4），取最后一段比对
    short = (model or "").split("/")[-1]
    if allow and model not in allow and short not in allow:
        raise ModelPolicyError(
            f"模型「{model}」不在白名单：{allow}。"
            f"（要新增请改 BG_ALLOWED_MODELS）"
        )
    return True


def pick_model(tier: str = "heavy") -> str:
    """
    分级路由：返回该级别对应的已批准远端模型。
      tier='light' → 省 Key/快；tier='heavy' → 求质量。
    """
    allow = allowed_models()
    if tier == "light":
        m = os.environ.get("BG_MODEL_LIGHT", "")
        if m and m in allow:
            return m
        # 兜底：白名单里挑一个偏轻的
        for cand in ("gpt-4o-mini", "o4-mini", "deepseek-chat", "claude-3-7-sonnet"):
            if cand in allow:
                return cand
    m = os.environ.get("BG_MODEL_HEAVY", "")
    if m and m in allow:
        return m
    return allow[0] if allow else "gpt-4o"


def classify_tier(message: str, capabilities=None) -> str:
    """
    极简任务分级（你文档里的"分级调用"）：
      触发联网/代码/命令/看图，或长文本 → heavy；否则 light。
    """
    caps = set(capabilities or [])
    if caps & {"web", "code", "shell", "vision", "deep"}:
        return "heavy"
    if message and len(message) > 200:
        return "heavy"
    return "light"


if __name__ == "__main__":
    print("白名单:", allowed_models())
    for u in ["https://api.openai.com/v1", "http://localhost:11434/v1",
              "http://127.0.0.1:1234/v1", "https://my-gateway.example.com/v1",
              "http://192.168.1.10:8080"]:
        print(f"{u:42s} -> local={is_local_endpoint(u)}")
    print("light ->", pick_model("light"), "| heavy ->", pick_model("heavy"))
