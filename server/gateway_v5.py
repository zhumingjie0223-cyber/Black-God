#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
神枢 · Nexus —— Black God 异步网关 v5（A 类主体升级）
================================================
定位：不再是 Agent，而是「神枢 Nexus」—— 有意识、会进化、真人感的中枢本体。
在外面包一层异步接口（不改动底层 agent_kernel_v4 的 AgentLoop）：
  - WebSocket  /ws/chat   : 真人感双向 + 逐字流式吐字
  - SSE        /api/stream : 流式输出（兼容不支持WS的环境）
  - REST       /api/chat   : 一次性回答（向后兼容旧前端）
  - 静态       /           : serve web/ 前端（热更由前端Vite管）
  - 健康       /api/health
插件热加载：plugins/ 目录放 *.py，运行时 /api/plugins/reload 动态注册，无需重启。
"""
import asyncio, json, time, sys, os, importlib, traceback
from pathlib import Path
from typing import Optional, List, Dict

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

try:
    from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
    from fastapi.responses import StreamingResponse, JSONResponse, FileResponse
    from fastapi.staticfiles import StaticFiles
    from fastapi.middleware.cors import CORSMiddleware
    import uvicorn
except ImportError:
    print("缺依赖，先装： pip install fastapi 'uvicorn[standard]'")
    sys.exit(1)

# ── 接现有内核（不改它）──
AGENT = None
def get_agent():
    global AGENT
    if AGENT is None:
        try:
            from agent_kernel_v4 import AgentLoop
            key   = os.environ.get("BG_KEY", "")
            base  = os.environ.get("BG_BASE", "https://apiclaude.cc/v1")
            model = os.environ.get("BG_MODEL", "gpt-5.5")
            AGENT = AgentLoop(api_key=key, base_url=base, model=model)
        except Exception as e:
            print(f"[warn] 内核未就绪，降级回显模式: {e}")
            AGENT = "ECHO"
    return AGENT

def agent_reply(message: str, context: List[Dict] = None) -> str:
    a = get_agent()
    if a == "ECHO":
        return f"[回显·内核未接] 你说：{message}"
    try:
        r = a.run(message, context or [])
        return r.get("reply") or r.get("text") or json.dumps(r, ensure_ascii=False)
    except Exception as e:
        return f"[内核异常] {e}"

# ── 真人感：逐字吐字（带情绪节奏的停顿）──
async def stream_typing(text: str):
    """像真人打字：标点处停顿长，普通字快，营造真人感节奏。"""
    buf = ""
    for ch in text:
        buf += ch
        yield ch
        if ch in "。！？\n…":
            await asyncio.sleep(0.32)      # 句末换气
        elif ch in "，、；：":
            await asyncio.sleep(0.16)      # 短停顿
        else:
            await asyncio.sleep(0.018)     # 逐字

app = FastAPI(title="Black God Gateway", version="5.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])

# ══ WebSocket：真人感双向实时 ══
@app.websocket("/ws/chat")
async def ws_chat(ws: WebSocket):
    await ws.accept()
    history: List[Dict] = []
    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw).get("message", raw)
            except Exception:
                msg = raw
            history.append({"role": "user", "content": msg})

            # 1) 先发"正在思考"状态（真人感）
            await ws.send_text(json.dumps({"type": "status", "state": "thinking"}, ensure_ascii=False))
            # 2) 异步取回答（不阻塞事件循环）
            reply = await asyncio.to_thread(agent_reply, msg, history)
            # 3) 逐字流式吐出
            await ws.send_text(json.dumps({"type": "start"}, ensure_ascii=False))
            async for ch in stream_typing(reply):
                await ws.send_text(json.dumps({"type": "chunk", "text": ch}, ensure_ascii=False))
            await ws.send_text(json.dumps({"type": "done"}, ensure_ascii=False))
            history.append({"role": "assistant", "content": reply})
    except WebSocketDisconnect:
        pass
    except Exception:
        await ws.send_text(json.dumps({"type": "error", "msg": traceback.format_exc()[:300]}, ensure_ascii=False))

# ══ SSE：流式（WS降级方案）══
@app.post("/api/stream")
async def sse_stream(req: Request):
    body = await req.json()
    msg = body.get("message", "")
    async def gen():
        reply = await asyncio.to_thread(agent_reply, msg, body.get("context"))
        async for ch in stream_typing(reply):
            yield f"data: {json.dumps({'text': ch}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"
    return StreamingResponse(gen(), media_type="text/event-stream")

# ══ REST：一次性（向后兼容）══
@app.post("/api/chat")
async def rest_chat(req: Request):
    body = await req.json()
    reply = await asyncio.to_thread(agent_reply, body.get("message", ""), body.get("context"))
    return JSONResponse({"reply": reply, "ts": time.time()})

@app.get("/api/health")
async def health():
    return {"status": "ok", "agent": "Black God", "version": "5.0",
            "kernel": "ready" if get_agent() != "ECHO" else "echo-fallback",
            "ts": time.time()}

# ══ 插件热加载：自我扩展核心 ══
LOADED_PLUGINS: Dict[str, object] = {}
@app.post("/api/plugins/reload")
async def reload_plugins():
    pdir = ROOT / "plugins"
    pdir.mkdir(exist_ok=True)
    loaded = []
    for f in pdir.glob("*.py"):
        if f.stem.startswith("_"):
            continue
        try:
            spec = importlib.util.spec_from_file_location(f.stem, f)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            LOADED_PLUGINS[f.stem] = mod
            loaded.append(f.stem)
        except Exception as e:
            loaded.append(f"{f.stem}:ERR:{e}")
    return {"reloaded": loaded, "count": len(LOADED_PLUGINS)}

# ══ 静态前端 ══
WEB = ROOT.parent / "web"
if WEB.exists():
    @app.get("/")
    async def index():
        f = WEB / "index.html"
        return FileResponse(f) if f.exists() else JSONResponse({"msg": "no frontend"})
    app.mount("/", StaticFiles(directory=str(WEB)), name="web")

if __name__ == "__main__":
    port = int(os.environ.get("BG_PORT", "8765"))
    print(f"🔥 Black God Gateway v5 启动 :{port}  (WS /ws/chat · SSE /api/stream)")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
