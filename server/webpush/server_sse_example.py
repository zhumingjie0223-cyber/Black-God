#!/usr/bin/env python3
# =============================================================
# Black God · /api/chat 流式(SSE) + 任务确认  后端示例  v3.1
#
# 让前端三件事真正生效：
#   1) 执行过程时间线实时显示（event: step / token）
#   2) 危险操作弹窗等用户批准（event: confirm + POST /api/confirm）
#   3) 任务完成/失败通知（前端按 done 状态 + /api/tasks 对账触发）
#
# 事件契约（前端就认这几种，顺序随意、可交错）：
#   event: step    data: {"id","tool","title","status":"running|completed|failed","detail"}
#   event: token   data: {"text":"增量正文片段"}
#   event: confirm data: {"id","title","detail","danger":true}   # 暂停等批准
#   event: done    data: {"answer","steps":[...]}                 # 收尾（可选）
#
# 没有 SSE 也行：前端自动退回读整包 JSON {"answer","steps"}。
# 用 ThreadingHTTPServer，确认阻塞时 /api/confirm 仍能被另一线程处理。
# =============================================================
import json
import time
import threading

try:
    from server_push_example import push_to_user  # 真·Web Push（App 全关也能收）
except Exception:
    def push_to_user(*a, **k):
        return 0
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def sse(event: str, data: dict) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n".encode("utf-8")


# —— 待确认登记表：cid -> {event, approved} ——
_PENDING = {}


# ------------------------------------------------------------------
# 把这个生成器换成你真实的 Agent 执行循环。
# task_id 由前端传入，用于对账与确认；危险工具先 yield confirm 再阻塞等批准。
# ------------------------------------------------------------------
def run_agent(message, history, capabilities, persona, user_profile, model, task_id):
    plan = []
    if "web" in capabilities:
        plan.append(("web.search", "联网检索相关信息", "命中 6 条结果，排序去重…", False))
    if "code" in capabilities:
        plan.append(("editor.write", "编写并编译验证代码", "已写入 main.py，编译通过 ✓", False))
    if "shell" in capabilities:
        plan.append(("shell.run", "执行命令", "$ rm -rf ./cache && npm run build", True))  # 危险→需确认
    if not plan:
        plan.append(("reason.answer", "理解问题并组织回答", "已检索内部知识", False))

    steps = []
    for i, (tool, title, detail, needs_confirm) in enumerate(plan):
        # —— 危险操作：弹窗等批准 ——
        if needs_confirm:
            cid = f"{task_id}-c{i}"
            ev = threading.Event()
            _PENDING[cid] = {"event": ev, "approved": False}
            yield ("confirm", {"id": cid, "title": "即将执行命令，需要你批准", "detail": detail, "danger": True})
            push_to_user((user_profile or {}).get("id") or (user_profile or {}).get("name"),
                         "需要你确认", "有一个操作在等你批准", url="/", task_id=task_id, danger=True, tag="confirm")
            ev.wait(timeout=300)                      # 阻塞，等 /api/confirm（最多 5 分钟）
            approved = _PENDING.pop(cid, {"approved": False})["approved"]
            if not approved:
                steps.append({"id": f"s{i}", "tool": tool, "title": title + "（已被拒绝）", "status": "failed"})
                yield ("step", dict(steps[-1]))
                continue

        step = {"id": f"s{i}", "tool": tool, "title": title, "status": "running"}
        steps.append(step)
        yield ("step", dict(step))                    # 开始 → 转圈

        detail = real_tool_call(tool, message)        # ← 你的真实工具调用
        time.sleep(0.1)

        step["status"] = "completed"                  # 或 "failed"
        step["detail"] = detail
        yield ("step", dict(step))                    # 结束 → 打勾 + 详情

    name = (user_profile or {}).get("name", "")
    prefix = f"{name}，" if name else ""
    answer = f"{prefix}已根据「{message[:20]}」完成处理，共 {len(steps)} 步。"
    for ch in answer:                                 # 流式正文
        yield ("token", {"text": ch})

    yield ("done", {"answer": answer, "steps": steps})

    # —— 真·Web Push：任务完成/失败（App 完全关闭也能收）——
    uid = (user_profile or {}).get("id") or (user_profile or {}).get("name")
    ok = all(s.get("status") == "completed" for s in steps) if steps else True
    push_to_user(uid, "任务完成 ✓" if ok else "任务失败 ✕", answer[:60],
                 url="/", task_id=task_id, danger=not ok, ttl=86400)  # 失败留存 1 天


def real_tool_call(tool, message):
    return f"[{tool}] 执行完成"


# ==================================================================
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")

        # —— 用户对确认弹窗的决定 ——
        if path == "/api/confirm":
            cid = body.get("id")
            p = _PENDING.get(cid)
            if p:
                p["approved"] = bool(body.get("approve"))
                p["event"].set()
            return self._json({"ok": True})

        if path != "/api/chat":
            self.send_error(404)
            return

        args = (body.get("message", ""), body.get("history", []), body.get("capabilities", []),
                body.get("persona", {}), body.get("userProfile", {}), body.get("model", "auto"),
                body.get("task_id", "t0"))
        wants_stream = "text/event-stream" in (self.headers.get("Accept", ""))

        if wants_stream:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("X-Accel-Buffering", "no")     # 关键：nginx 不缓冲
            self.end_headers()
            try:
                for event, data in run_agent(*args):
                    self.wfile.write(sse(event, data))
                    self.wfile.flush()                       # 关键：逐事件下发
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            steps, answer = [], ""
            for event, data in run_agent(*args):
                if event == "step":
                    steps = [s for s in steps if s["id"] != data["id"]] + [data]
                elif event == "done":
                    answer = data.get("answer", answer)
            self._json({"answer": answer, "steps": steps})

    def _json(self, obj):
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps(obj, ensure_ascii=False).encode("utf-8"))


# ==================================================================
# 用法：必须是 Threading 服务器，确认阻塞时才能并发处理 /api/confirm
# ------------------------------------------------------------------
# if __name__ == "__main__":
#     ThreadingHTTPServer(("0.0.0.0", 8765), Handler).serve_forever()
#
# Flask 版要点：用 stream_with_context 产出 sse()，/api/confirm 单独路由 set() 事件；
# Nginx 反代务必加： proxy_buffering off;   （否则 SSE 被缓冲，时间线/确认都不实时）
#
# 关于"任务完成/失败通知"：服务端不用推送，前端在 done 时已自动通知；
# 若任务很长、用户中途关页，前端下次打开会调 /api/tasks 对账并补发通知，
# 所以你的 /api/tasks 每条任务建议带 {task_id, status} 字段。
# 真正"App 完全关闭也能收推送"才需要 Web Push(VAPID)，可后续再加。
# ==================================================================
