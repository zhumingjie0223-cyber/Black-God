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

# 按权哥要求：Black God 内部安装 Minis 的 Legend Coordinator v2 作为唯一模型后端
# Minis API: http://47.236.124.97/v1, Key: sk-local, Model: auto
# Black God 上层永远叫 Black God，底层走 Minis 的智能路由（62 模型 + 12 路由 + 6 平台）

零依赖，纯标准库，可直接 import。配置走环境变量，改配置不用改码。

环境变量：
  BG_BASE              Minis 接入点（默认 http://47.236.124.97/v1）
  BG_KEY               Minis 接入 Key（默认 sk-local）
  BG_MODEL             Minis 智能路由（默认 auto）
  BG_ALLOWED_MODELS   逗号分隔的允许模型，如 "auto,default"
  BG_MODEL_LIGHT      轻任务模型（默认 auto）
  BG_MODEL_HEAVY      重任务模型（默认 auto）
  BG_ALLOW_LOCAL=1    显式放开本地模型（默认 0，禁用；仅调试用，生产别开）
"""
import os
import re
from urllib.parse import urlparse


class ModelPolicyError(Exception):
    """模型不合规：本地端点 / 不在白名单。上层应据此拒绝或回退。"""


# ——— 默认接入 Minis 的 Legend Coordinator v2（按权哥要求安装）———
DEFAULT_MINIS_BASE = "http://47.236.124.97/v1"
DEFAULT_MINIS_KEY = "sk-local"
DEFAULT_MINIS_MODEL = "auto"  # Minis 智能路由（62模型+12路由）

# ——— 默认允许的远端模型（可被 BG_ALLOWED_MODELS 覆盖）———
_DEFAULT_ALLOWED = [
    "auto",  # Minis 智能路由
    "default",  # 通用默认
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
        allow = [m.strip() for m in env.split(",") if m.strip()]
    else:
        allow = list(_DEFAULT_ALLOWED)
    # 自动纳入当前配置的轻/重/默认模型，避免设置 BG_MODEL_LIGHT 后忘记同步白名单
    for key in ("BG_MODEL", "BG_MODEL_LIGHT", "BG_MODEL_HEAVY"):
        v = os.environ.get(key, "").strip()
        if v and v not in allow:
            allow.append(v)
    return allow


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
      tier='light' → 省 Key/快：BG_MODEL_LIGHT
      tier='heavy' → 求质量：BG_MODEL_HEAVY

    注意：不在代码里写死具体供应商模型名，避免污染品牌/仓库。
    默认都回退到 BG_MODEL / auto；真正便宜模型由环境变量配置。
    """
    base = os.environ.get("BG_MODEL", DEFAULT_MINIS_MODEL).strip() or DEFAULT_MINIS_MODEL
    if (tier or "").lower() == "light":
        return os.environ.get("BG_MODEL_LIGHT", base).strip() or base
    return os.environ.get("BG_MODEL_HEAVY", base).strip() or base


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
