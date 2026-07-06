#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Black God Mock LLM 网关 — 监听 127.0.0.1:9000，模拟 OpenAI /v1/chat/completions。

无真实 API Key 时用于端到端演示自主智能体，覆盖：
  1) 规划调用（system 含「自主任务规划器」）→ 返回 JSON 计划
  2) 带 tools 且尚未执行过工具 → 调 write_deliverable 产出可下载交付文件
  3) 工具已执行 / 普通对话 → 返回最终交付文本
支持 stream:true（SSE 逐块）与非流式两种响应。
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

    def _send_stream(self, chunks):
        """把若干 OpenAI 流式分块以 SSE 发出。"""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        for c in chunks:
            self.wfile.write(f"data: {json.dumps(c, ensure_ascii=False)}\n\n".encode())
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def do_GET(self):
        if self.path.endswith("/models"):
            self._send({"data": [{"id": "auto"}, {"id": "deepseek-v4-pro"}]})
        else:
            self._send({"status": "ok"})

    @staticmethod
    def _delta(content=None, tool_calls=None, finish=None):
        d = {}
        if content is not None:
            d["content"] = content
        if tool_calls is not None:
            d["tool_calls"] = tool_calls
        return {"choices": [{"index": 0, "delta": d, "finish_reason": finish}]}

    def _completion(self, model, message=None, tool_calls=None, finish="stop"):
        msg = {"role": "assistant", "content": message or ""}
        if tool_calls:
            msg["tool_calls"] = tool_calls
        return {
            "id": "chatcmpl-mock", "object": "chat.completion", "model": model,
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
        stream = bool(req.get("stream"))
        msgs = req.get("messages", [])
        has_tools = bool(req.get("tools"))
        system_txt = " ".join(m.get("content", "") for m in msgs if m.get("role") == "system")
        tool_ran = any(m.get("role") == "tool" for m in msgs)
        last_user = next((m.get("content", "") for m in reversed(msgs)
                          if m.get("role") == "user"), "")

        # 1) 规划阶段（内核用非流式调用）
        if "自主任务规划器" in system_txt:
            goal = last_user[:40]
            plan = {"steps": [f"拆解目标：{goal}", "调用工具产出交付素材", "整理并输出最终交付物"],
                    "deliverable": f"围绕「{goal}」的可直接使用成果"}
            self._send(self._completion(model, message=json.dumps(plan, ensure_ascii=False)))
            return

        # 2) 带工具且尚未执行 → 触发一次 write_deliverable，产出可下载文件
        if has_tools and not tool_ran:
            deliv = f"# 交付物\n\n目标：{last_user[:60]}\n\n- 已按计划执行\n- 结果可直接使用\n"
            arg_str = json.dumps({"filename": "report.md", "content": deliv}, ensure_ascii=False)
            if stream:
                mid = len(arg_str) // 2
                self._send_stream([
                    self._delta(content="先把成果写成可下载文件。"),
                    self._delta(tool_calls=[{"index": 0, "id": "call_mock_1", "type": "function",
                                             "function": {"name": "write_deliverable", "arguments": ""}}]),
                    self._delta(tool_calls=[{"index": 0, "function": {"arguments": arg_str[:mid]}}]),
                    self._delta(tool_calls=[{"index": 0, "function": {"arguments": arg_str[mid:]}}]),
                    self._delta(finish="tool_calls"),
                    {"choices": [], "usage": {"prompt_tokens": 42, "completion_tokens": 30, "total_tokens": 72}},
                ])
            else:
                tc = [{"id": "call_mock_1", "type": "function",
                       "function": {"name": "write_deliverable", "arguments": arg_str}}]
                self._send(self._completion(model, message="先产出交付文件。",
                                            tool_calls=tc, finish="tool_calls"))
            return

        # 3) 交付 / 普通对话
        final = (f"【Black God】任务完成。\n\n目标：{last_user[:80]}\n"
                 f"- 已按计划执行并验证工具链路\n- 交付文件已生成，可直接下载\n\n"
                 f"（本地 Mock 网关示例；接入真实模型后为完整成果。）")
        if stream:
            # 逐句流式，模拟 token 输出
            pieces, buf = [], ""
            for ch in final:
                buf += ch
                if ch in "，。\n" or len(buf) >= 12:
                    pieces.append(buf); buf = ""
            if buf:
                pieces.append(buf)
            chunks = [self._delta(content=p) for p in pieces]
            chunks.append(self._delta(finish="stop"))
            chunks.append({"choices": [], "usage": {"prompt_tokens": 50, "completion_tokens": 80, "total_tokens": 130}})
            self._send_stream(chunks)
        else:
            self._send(self._completion(model, message=final))


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", 9000), MockHandler)
    print("✓ Mock LLM 网关 http://127.0.0.1:9000（规划/工具/交付 · 流式&非流式）")
    srv.serve_forever()
