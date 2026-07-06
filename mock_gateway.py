#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Black God Mock LLM 网关 — 监听 127.0.0.1:9000，模拟 OpenAI /v1/chat/completions。

支持三种链路，方便在无真实 API Key 时端到端演示自主智能体：
  1) 规划调用（system 含「自主任务规划器」）→ 返回 JSON 计划
  2) 带 tools 且尚未执行过工具 → 返回一次 tool_calls（真实执行 shell echo）
  3) 工具已执行 / 普通对话 → 返回最终文本（交付物）
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class MockHandler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, obj, code=200):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(b))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.endswith("/models"):
            self._send({"data": [{"id": "auto"}, {"id": "deepseek-v4-pro"}]})
        else:
            self._send({"status": "ok"})

    def _completion(self, model, message=None, tool_calls=None, finish="stop"):
        msg = {"role": "assistant", "content": message or ""}
        if tool_calls:
            msg["tool_calls"] = tool_calls
        return {
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "model": model,
            "choices": [{"index": 0, "message": msg, "finish_reason": finish}],
            "usage": {"prompt_tokens": 42, "completion_tokens": 64, "total_tokens": 106},
        }

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode() if n else "{}"
        try:
            req = json.loads(raw)
        except Exception:
            req = {}

        model = req.get("model", "auto")
        msgs = req.get("messages", [])
        has_tools = bool(req.get("tools"))
        system_txt = " ".join(m.get("content", "") for m in msgs if m.get("role") == "system")
        tool_ran = any(m.get("role") == "tool" for m in msgs)
        last_user = ""
        for m in reversed(msgs):
            if m.get("role") == "user":
                last_user = m.get("content", "")
                break

        # 1) 规划阶段
        if "自主任务规划器" in system_txt:
            goal = last_user[:40]
            plan = {
                "steps": [
                    f"拆解目标：{goal}",
                    "调用工具收集/生成所需素材",
                    "整理结果并产出最终交付物",
                ],
                "deliverable": f"围绕「{goal}」的可直接使用成果",
            }
            self._send(self._completion(model, message=json.dumps(plan, ensure_ascii=False)))
            return

        # 2) 带工具且尚未执行 → 触发一次真实工具调用
        if has_tools and not tool_ran:
            tc = [{
                "id": "call_mock_1",
                "type": "function",
                "function": {
                    "name": "shell_execute",
                    "arguments": json.dumps({"command": "echo 'Nexus 自主智能体正在执行任务'"}),
                },
            }]
            self._send(self._completion(
                model, message="先执行一步命令验证环境。", tool_calls=tc, finish="tool_calls"))
            return

        # 3) 交付 / 普通对话
        reply = (
            f"【Black God】任务已完成。\n\n"
            f"目标：{last_user[:80]}\n"
            f"- 已按计划执行并验证工具链路\n"
            f"- 结果可直接使用\n\n"
            f"（本地 Mock 网关生成的示例交付物；接入真实模型后为完整成果。）"
        )
        self._send(self._completion(model, message=reply))


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", 9000), MockHandler)
    print("✓ Mock LLM 网关 http://127.0.0.1:9000（支持规划/工具/交付三段链路）")
    srv.serve_forever()
