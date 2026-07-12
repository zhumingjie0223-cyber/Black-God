#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
神枢 · 执行脑（最小自足版）—— 她的「手」。
只做一件事、做真：受 token 保护地在这台机器上真跑 shell 命令、返回真实输出。

- 纯标准库，无任何外部依赖：一台裸 Ubuntu + python3 即可跑。
- 必须设 NEXUS_EXEC_TOKEN（公网暴露的唯一门）。没设则拒绝启动，杜绝裸奔。
- 端点：
    GET  /health            → 存活探针（无需 token）
    POST /exec  {cmd,timeout}→ 真跑 shell，回 {stdout,stderr,code}（需 Bearer token）
    POST /read  {path}       → 读文件文本（需 token）
    POST /write {path,text}  → 写文件（需 token）

启动：  NEXUS_EXEC_TOKEN=<你的密钥> python3 exec_brain.py 8765
"""
import os, sys, json, shlex, subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

TOKEN = os.environ.get("NEXUS_EXEC_TOKEN", "").strip()
ROOT = os.environ.get("NEXUS_EXEC_ROOT", os.getcwd())
MAX_OUT = 24000  # 单次返回上限，防爆

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):  # 静默默认日志（不记 token/命令）
        pass

    def _send(self, obj, status=200):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
            return json.loads(self.rfile.read(n).decode("utf-8")) if n else {}
        except Exception:
            return {}

    def _authed(self):
        return self.headers.get("Authorization", "") == f"Bearer {TOKEN}"

    def do_GET(self):
        if self.path.split("?")[0] == "/health":
            self._send({"ok": True, "brain": "shenshu-exec", "root": ROOT})
        else:
            self._send({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        if not self._authed():
            return self._send({"error": "unauthorized"}, 401)
        body = self._body()
        if path == "/exec":
            cmd = (body.get("cmd") or body.get("command") or "").strip()
            if not cmd:
                return self._send({"error": "cmd required"}, 400)
            timeout = min(int(body.get("timeout", 60)), 600)
            try:
                r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                                   timeout=timeout, cwd=ROOT)
                return self._send({"ok": True, "code": r.returncode,
                                   "stdout": r.stdout[:MAX_OUT], "stderr": r.stderr[:MAX_OUT]})
            except subprocess.TimeoutExpired:
                return self._send({"ok": False, "error": f"timeout>{timeout}s"}, 200)
            except Exception as e:
                return self._send({"ok": False, "error": str(e)[:400]}, 200)
        if path == "/read":
            p = os.path.realpath(os.path.join(ROOT, body.get("path", "")))
            try:
                with open(p, "r", encoding="utf-8", errors="replace") as f:
                    return self._send({"ok": True, "path": p, "text": f.read()[:MAX_OUT]})
            except Exception as e:
                return self._send({"ok": False, "error": str(e)[:300]}, 200)
        if path == "/write":
            p = os.path.realpath(os.path.join(ROOT, body.get("path", "")))
            try:
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w", encoding="utf-8") as f:
                    f.write(body.get("text", ""))
                return self._send({"ok": True, "path": p})
            except Exception as e:
                return self._send({"ok": False, "error": str(e)[:300]}, 200)
        return self._send({"error": "not found"}, 404)


def main():
    if not TOKEN:
        print("拒绝启动：未设 NEXUS_EXEC_TOKEN。公网执行脑必须带 token。\n"
              "  用法：NEXUS_EXEC_TOKEN=<你的密钥> python3 exec_brain.py 8765", file=sys.stderr)
        sys.exit(1)
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("NEXUS_EXEC_PORT", "8765"))
    print(f"神枢执行脑已起：0.0.0.0:{port} · ROOT={ROOT} · token 已启用", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), H).serve_forever()


if __name__ == "__main__":
    main()
