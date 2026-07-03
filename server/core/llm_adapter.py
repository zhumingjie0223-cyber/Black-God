#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God — 统一 LLM 适配器 (llm_adapter)

这是整个 Agent 的"地基中的地基"：
  - 所有 core 模块（用 call_fn / llm_call 的）→ 统一喂 llm()
  - 模型网关 gateway 的真实后端 → 用 llm() 包装 generate_fn
  - 成本引擎 cost_engine 的 L6 层 → 经 gateway 调到这里

对外两个入口：
  llm(messages, **opts)      -> str    最常用，直接返回文本
  llm_raw(messages, tools)   -> dict   需要 tool calling / 原始响应时用

配置优先级：函数参数 > BG_* 环境变量 > OPENAI_* 环境变量 > 默认值
零第三方依赖，纯标准库 urllib，和 v4 内核保持一致。
"""
from __future__ import annotations

import json
import os
import time
import urllib.request
import urllib.error
from typing import Optional, List, Dict, Any, Callable


class LLMError(Exception):
    """模型调用失败（网络/超时/限流/HTTP 错误）。"""


class LLMRefusal(Exception):
    """模型拒绝执行（留作网关 fallback / 重路由判据）。"""


# --------------------------------------------------------------------------- #
#  配置解析
# --------------------------------------------------------------------------- #
def _cfg(key: Optional[str], base: Optional[str], model: Optional[str]) -> tuple[str, str, str]:
    """解析最终使用的 (api_key, base_url, model)。不打印任何密钥。"""
    api_key = (
        key
        or os.environ.get("BG_KEY")
        or os.environ.get("OPENAI_API_KEY")
        or ""
    )
    base_url = (
        base
        or os.environ.get("BG_BASE")
        or os.environ.get("OPENAI_BASE_URL")
        or "https://api.openai.com/v1"
    ).rstrip("/")
    mdl = (
        model
        or os.environ.get("BG_MODEL")
        or os.environ.get("OPENAI_MODEL")
        or "gpt-4o-mini"
    )
    return api_key, base_url, mdl


def has_key() -> bool:
    """是否已配置可用的 API Key（供上层判断要不要走本地兜底）。"""
    k, _, _ = _cfg(None, None, None)
    return bool(k)


# --------------------------------------------------------------------------- #
#  原始调用：返回完整 OpenAI 兼容 dict（兼容 v4 的 _call_model）
# --------------------------------------------------------------------------- #
def llm_raw(
    messages: List[Dict[str, Any]],
    tools: Optional[List[Dict]] = None,
    *,
    key: Optional[str] = None,
    base: Optional[str] = None,
    model: Optional[str] = None,
    temperature: float = 0.7,
    max_tokens: int = 4096,
    timeout: int = 120,
    retries: int = 2,
) -> Dict[str, Any]:
    api_key, base_url, mdl = _cfg(key, base, model)
    if not api_key:
        raise LLMError("未配置 API Key（设 BG_KEY 或 OPENAI_API_KEY）")

    payload: Dict[str, Any] = {
        "model": mdl,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    if tools:
        payload["tools"] = tools
        payload["tool_choice"] = "auto"

    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    url = f"{base_url}/chat/completions"

    last_err: Optional[Exception] = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(
                url,
                data=data,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {api_key}",
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8", errors="replace"))
        except urllib.error.HTTPError as e:
            body = ""
            try:
                body = e.read().decode("utf-8", errors="replace")[:300]
            except Exception:
                pass
            # 429/5xx 可重试；4xx（除429）直接抛
            if e.code == 429 or e.code >= 500:
                last_err = LLMError(f"HTTP {e.code}: {body}")
                time.sleep(min(2 ** attempt, 8))
                continue
            raise LLMError(f"HTTP {e.code}: {body}")
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = LLMError(f"网络错误: {e}")
            time.sleep(min(2 ** attempt, 8))
            continue
    raise last_err or LLMError("未知调用失败")


# --------------------------------------------------------------------------- #
#  文本调用：直接返回 assistant 文本（core 模块最常用）
# --------------------------------------------------------------------------- #
def llm(messages_or_prompt, **opts) -> str:
    """
    统一文本入口。
    - 传 str：当作单条 user 消息
    - 传 list：当作完整 messages
    返回 assistant 回复文本（取不到内容则返回空串）。
    """
    if isinstance(messages_or_prompt, str):
        messages = [{"role": "user", "content": messages_or_prompt}]
    else:
        messages = messages_or_prompt
    resp = llm_raw(messages, **opts)
    try:
        return resp["choices"][0]["message"].get("content") or ""
    except (KeyError, IndexError):
        return ""


def make_llm(**fixed) -> Callable[[Any], str]:
    """
    生成一个固定配置的 call_fn，喂给 core 模块。
    例：dialog = RealDialogEngine(llm_call=make_llm(model="gpt-4o"))
    """
    def _call(messages_or_prompt) -> str:
        return llm(messages_or_prompt, **fixed)
    return _call


# --------------------------------------------------------------------------- #
#  自检
# --------------------------------------------------------------------------- #
def self_test() -> Dict[str, Any]:
    """轻量自检：配置是否就绪 + 一次真实最小调用。"""
    k, base, mdl = _cfg(None, None, None)
    out: Dict[str, Any] = {
        "has_key": bool(k),
        "base_url": base,
        "model": mdl,
        "live": None,
        "reply": None,
        "error": None,
    }
    if not k:
        out["error"] = "no_key"
        return out
    try:
        txt = llm("只回复两个字：在的", max_tokens=20, timeout=30)
        out["live"] = True
        out["reply"] = txt[:50]
    except Exception as e:
        out["live"] = False
        out["error"] = str(e)[:200]
    return out


if __name__ == "__main__":
    print(json.dumps(self_test(), ensure_ascii=False, indent=2))
