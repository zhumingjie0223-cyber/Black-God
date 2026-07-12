#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God 语音 API 路由
挂载到 server.py 的 HTTP handler

使用方式（在 server.py 中）:
    from core.voice_api import VoiceAPI
    voice_api = VoiceAPI()
    # GET /api/voice → voice_api.handle_get(path, params)
    # POST /api/voice/synthesize → voice_api.handle_post(path, body)
"""
import json, pathlib, mimetypes
from typing import Dict, Any

class VoiceAPI:
    def __init__(self):
        from core.voice_engine_v2 import get_voice_engine, VOICE_CACHE_DIR
        self.engine = get_voice_engine()
        self.cache_dir = VOICE_CACHE_DIR

    # ============================================================
    # GET 路由
    # ============================================================
    def handle_get(self, path: str, params: dict) -> Any:
        # /api/voice → 能力查询
        if path == "/api/voice" or path == "/api/voice/":
            return {"code": 0, "data": self.engine.get_capabilities()}

        # /api/voice/emotions → 情绪列表
        if path == "/api/voice/emotions":
            caps = self.engine.get_capabilities()
            return {"code": 0, "data": caps["emotions"]}

        # /api/voice/file/{filename} → 音频文件
        if path.startswith("/api/voice/file/"):
            filename = path.replace("/api/voice/file/", "")
            fpath = self.cache_dir / filename
            if fpath.exists():
                return fpath  # 返回 Path 对象，server.py 判断后直接读二进制
            return {"code": 404, "error": "音频不存在"}

        return {"code": 404, "error": f"未知路由: {path}"}

    # ============================================================
    # POST 路由
    # ============================================================
    def handle_post(self, path: str, body: dict) -> Any:
        # /api/voice/synthesize → 合成语音
        if path == "/api/voice/synthesize":
            text = body.get("text", "").strip()
            emotion = body.get("emotion", "serious")
            voice = body.get("voice")
            fmt = body.get("format", "mp3")
            if not text:
                return {"code": 1, "error": "text 不能为空"}
            if len(text) > 500:
                return {"code": 1, "error": "text 超过 500 字"}
            result = asyncio_run(self.engine.synthesize(text, emotion, voice, fmt))
            if result.get("ok"):
                return {"code": 0, "data": result}
            return {"code": 1, "error": result.get("error", "合成失败"), "detail": result}

        # /api/voice/external → 配置外接 API
        if path == "/api/voice/external":
            url = body.get("url", "").strip()
            key = body.get("key", "").strip()
            model = body.get("model", "").strip()
            voice = body.get("voice", "").strip()
            if not url or not key:
                return {"code": 1, "error": "url 和 key 必填"}
            result = self.engine.configure_external_api(url, key, model, voice)
            return {"code": 0, "data": result}

        # /api/voice/train → 训练接口（占位）
        if path == "/api/voice/train":
            backend = body.get("backend", "gpt-sovits")
            emotion = body.get("emotion")
            samples_dir = body.get("samples_dir", "")
            model_name = body.get("model_name", "custom_voice")
            epochs = body.get("epochs", 100)
            result = self.engine.train(backend, emotion, samples_dir, model_name, epochs)
            if result.get("ok"):
                return {"code": 0, "data": result}
            return {"code": 1, "error": result.get("error"), "detail": result}

        # /api/voice/load-model → 加载模型
        if path == "/api/voice/load-model":
            model_path = body.get("model_path", "")
            result = self.engine.load_model(model_path)
            if result.get("ok"):
                return {"code": 0, "data": result}
            return {"code": 1, "error": result.get("error")}

        return {"code": 404, "error": f"未知路由: {path}"}


def asyncio_run(coro):
    """安全执行异步函数"""
    import asyncio
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as pool:
                return pool.submit(lambda: asyncio.run(coro)).result()
        return loop.run_until_complete(coro)
    except RuntimeError:
        return asyncio.run(coro)
