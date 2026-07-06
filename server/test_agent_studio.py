#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""自主智能体端到端冒烟测试（离线）。

用本地 Mock 网关驱动真实链路：规划 → 工具调用 → 交付，
验证 /api/agent/stream 的 SSE 事件序列与 /api/task/<id> 的时间线回放。
无需真实 API Key，`python3 server/test_agent_studio.py` 即可跑。
"""
import json
import os
import sys
import tempfile
import threading
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent))

# ── 1) 启动 Mock LLM 网关 ──
import mock_gateway  # noqa: E402

mock_srv = ThreadingHTTPServer(("127.0.0.1", 0), mock_gateway.MockHandler)
mock_port = mock_srv.server_address[1]
threading.Thread(target=mock_srv.serve_forever, daemon=True).start()

# ── 2) 指向 Mock，再导入内核 ──
os.environ["BG_BASE"] = f"http://127.0.0.1:{mock_port}/v1"
os.environ["BG_KEY"] = "test-key"
os.environ["BG_MODEL"] = "auto"

import agent_kernel_v4 as k  # noqa: E402

# 用临时库，避免污染仓库 data/
tmp_db = Path(tempfile.mkdtemp()) / "test_memory.db"
k.memory.db_path = tmp_db
k.memory._init_db()

# ── 3) 启动内核服务器（临时端口） ──
srv = ThreadingHTTPServer(("127.0.0.1", 0), k.AgentHandler)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{port}"


def sse_events(goal):
    """POST 目标并解析 SSE 事件列表。"""
    req = urllib.request.Request(
        f"{BASE}/api/agent/stream",
        data=json.dumps({"goal": goal}).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    events, buf = [], ""
    with urllib.request.urlopen(req, timeout=30) as resp:
        for raw in resp:
            buf += raw.decode("utf-8", "replace")
            while "\n\n" in buf:
                chunk, buf = buf.split("\n\n", 1)
                for ln in chunk.split("\n"):
                    if ln.startswith("data:"):
                        events.append(json.loads(ln[5:].strip()))
    return events


def check(cond, label):
    mark = "✓" if cond else "✗"
    print(f"  {mark} {label}")
    return cond


def main():
    print("自主智能体端到端冒烟测试")
    print(f"  Mock 网关 :{mock_port}  内核 :{port}")
    print("-" * 44)

    # 健康检查
    with urllib.request.urlopen(f"{BASE}/api/health", timeout=5) as r:
        health = json.loads(r.read())
    passed = check(health.get("status") == "ok", "健康检查 /api/health")

    # 端到端流式执行
    evs = sse_events("写一个能跑的示例并自测")
    kinds = [e.get("event") for e in evs]
    passed &= check("plan" in kinds, "收到执行计划 plan")
    passed &= check("token" in kinds, "收到流式 token")
    passed &= check("tool_call" in kinds, "触发工具调用 tool_call")
    passed &= check("tool_result" in kinds, "返回工具结果 tool_result")
    passed &= check("artifact" in kinds, "产出可下载交付文件 artifact")
    passed &= check("deliverable" in kinds, "产出交付物 deliverable")
    passed &= check(kinds[-1] == "done", "以 done 收尾")

    plan_ev = next((e for e in evs if e.get("event") == "plan"), {})
    passed &= check(len(plan_ev.get("steps", [])) >= 1, "计划含可执行步骤")

    tokens = [e["text"] for e in evs if e.get("event") == "token"]
    passed &= check(len(tokens) >= 2, f"token 分多段流式（{len(tokens)} 段）")

    art_ev = next((e for e in evs if e.get("event") == "artifact"), {})
    art_url = art_ev.get("url")
    passed &= check(bool(art_url), "artifact 带下载 URL")

    done_ev = next((e for e in evs if e.get("event") == "done"), {})
    task_id = done_ev.get("task_id")
    passed &= check(bool(task_id), "拿到 task_id")

    # 下载交付文件
    if art_url:
        with urllib.request.urlopen(f"{BASE}{art_url}", timeout=5) as r:
            body = r.read().decode("utf-8", "replace")
        passed &= check(len(body) > 0 and r.status == 200, "交付文件可下载")

    # 时间线回放
    with urllib.request.urlopen(f"{BASE}/api/task/{task_id}", timeout=5) as r:
        task = json.loads(r.read())
    passed &= check(task.get("status") == "completed", "任务落库为 completed")
    passed &= check(bool(task.get("result")), "交付物已持久化")
    passed &= check(bool(task.get("meta", {}).get("events")), "执行时间线已持久化")
    passed &= check(bool(task.get("meta", {}).get("artifacts")), "交付文件已持久化")

    # 任务列表
    with urllib.request.urlopen(f"{BASE}/api/tasks", timeout=5) as r:
        tasks = json.loads(r.read()).get("tasks", [])
    passed &= check(any(t["id"] == task_id for t in tasks), "任务出现在 /api/tasks")

    print("-" * 44)
    print("✅ 全部通过" if passed else "❌ 存在失败")
    return 0 if passed else 1


if __name__ == "__main__":
    code = main()
    mock_srv.shutdown()
    srv.shutdown()
    sys.exit(code)
