#!/usr/bin/env python3
# ⚠️ DEPRECATED(方案① · 2026-07-13)——本模块属"大脑常驻"能力,已划归 CF 主轨 web/nexus-do。
# 详见 docs/architecture/双轨边界-方案①.md。勿在此扩展 对话/情绪/记忆/偏好/画像 逻辑,统一走 nexus-do;
# Python server/ 已降级为按需重活后端,本文件待 CF 主轨功能对等后归档(现阶段只标记,不删除)。
"""
简化版对话处理 - 用于快速响应
"""
import json
import signal
from contextlib import contextmanager

class TimeoutException(Exception):
    pass

@contextmanager
def timeout(seconds):
    def signal_handler(signum, frame):
        raise TimeoutException("操作超时")
    signal.signal(signal.SIGALRM, signal_handler)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)

import time
from openai_agent import OpenAIAgent

class SimpleChat:
    def __init__(self, api_key, base_url, model):
        self.agent = OpenAIAgent(
            api_key=api_key,
            base_url=base_url,
            model=model,
            max_steps=3,
            auto_evolve=False
        )
    
    def chat(self, message, history=None):
        """简化版对话"""
        history = history or []
        
        try:
            result = self.agent.run(message, history=history)
            
            return {
                "ok": True,
                "answer": result.get("answer", ""),
                "steps": result.get("steps", []),
                "timestamp": time.time()
            }
        except Exception as e:
            return {
                "ok": False,
                "error": str(e),
                "answer": f"执行出错: {str(e)}",
                "steps": [],
                "timestamp": time.time()
            }

if __name__ == "__main__":
    chat = SimpleChat(
        api_key="sk-your-api-key-here",
        base_url="http://127.0.0.1:9000/v1",
        model="auto"
    )
    
    result = chat.chat("1+1等于几？")
    print(json.dumps(result, ensure_ascii=False, indent=2))
