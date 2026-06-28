#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Black God Mock LLM 网关 — 监听 127.0.0.1:9000，模拟 OpenAI /v1/chat/completions"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class MockHandler(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj, code=200):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(b))
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        if self.path.endswith("/models"):
            self._send({"data":[{"id":"auto"},{"id":"deepseek-v4-pro"}]})
        else:
            self._send({"status":"ok"})
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode() if n else "{}"
        try:
            req = json.loads(raw)
        except Exception:
            req = {}
        # 取最后一条用户消息
        msgs = req.get("messages", [])
        last = ""
        for m in reversed(msgs):
            if m.get("role") == "user":
                last = m.get("content", "")
                break
        reply = f"【Black God Mock】已收到：{last[:60]}。服务链路正常，这是本地 Mock 网关的回复。"
        self._send({
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "model": req.get("model", "auto"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": reply},
                "finish_reason": "stop"
            }],
            "usage": {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30}
        })

if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", 9000), MockHandler)
    print("✓ Mock LLM 网关 http://127.0.0.1:9000")
    srv.serve_forever()
