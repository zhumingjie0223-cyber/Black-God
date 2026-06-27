#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God Agent 服务端 v2.2 — 完整版
补全所有缺失路由，修复黑屏问题
"""
import os, sys, json, pathlib, urllib.parse, time, sqlite3, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, str(pathlib.Path(__file__).parent / "core"))

# 导入核心模块（容错）
try:
    from user_profile_engine import UserProfileEngine
    profile_engine = UserProfileEngine()
    print("✓ 用户画像引擎")
except Exception as e:
    print(f"⚠ 用户画像引擎: {e}")
    profile_engine = None

try:
    from skill_index import SkillIndexEngine
    from task_engine import TaskEngine
    from simple_chat import SimpleChat
    from cloudflare_mcp import CloudflareIntegration
    skill_engine = SkillIndexEngine()
    task_engine = TaskEngine()
    KEY = os.environ.get("BG_KEY", "sk-blackgod-quan-2026")
    BASE = os.environ.get("BG_BASE", "http://127.0.0.1:9000/v1")
    MODEL = os.environ.get("BG_MODEL", "auto")
    chat_engine = SimpleChat(KEY, BASE, MODEL)
    
    # 加载 Cloudflare 配置
    env_file = pathlib.Path(__file__).parent.parent / ".env.cloudflare"
    if env_file.exists():
        for line in env_file.read_text().strip().split("\n"):
            if line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ[k.strip()] = v.strip()
    
    cf_integration = CloudflareIntegration()
    print("✓ 核心引擎")
    if os.environ.get("CLOUDFLARE_API_TOKEN"):
        print("✓ Cloudflare MCP 集成")
except Exception as e:
    print(f"⚠ 核心引擎: {e}")
    skill_engine = None
    task_engine = None
    chat_engine = None
    cf_integration = None

ROOT = pathlib.Path(__file__).parent
# WEB_ROOT 指向项目根目录（server/ 的上一级），前端文件在 blackgod/web/
WEB_ROOT = ROOT.parent if (ROOT.parent / "web" / "index.html").exists() else ROOT
PORT = int(os.environ.get("BG_PORT", "8765"))
MEM_DB = ROOT / "memory" / "memory.db"
TASKS_JSONL = ROOT / "memory" / "tasks.jsonl"
_mem_lock = threading.Lock()

CATEGORIES = [
    {"id": "intelligent_dialog", "name": "智能对话", "icon": "💬", "desc": "对话理解、任务分析、智能规划"},
    {"id": "creative_design", "name": "创作设计", "icon": "🎨", "desc": "UI设计、Logo创作、海报生成"},
    {"id": "info_retrieval", "name": "信息获取", "icon": "🔍", "desc": "网页搜索、资料整理、内容提取"},
    {"id": "dev_engineering", "name": "开发工程", "icon": "⚙️", "desc": "代码生成、调试部署、Git管理"},
    {"id": "data_analysis", "name": "数据分析", "icon": "📊", "desc": "数据处理、图表生成、统计分析"},
    {"id": "security_recovery", "name": "安全工具", "icon": "🔐", "desc": "安全检查、系统恢复、权限管理"}
]

TOOL_MATRIX = {
    "tools": [
        {"name": "shell", "status": "live", "evidence": "bash 命令实时执行"},
        {"name": "python", "status": "live", "evidence": "Python 3 代码沙箱"},
        {"name": "write_file", "status": "live", "evidence": "文件读写操作"},
        {"name": "web_search", "status": "live", "evidence": "联网搜索信息"},
        {"name": "browser", "status": "live", "evidence": "浏览器自动化"},
        {"name": "memory", "status": "live", "evidence": "SQLite 长期记忆"},
        {"name": "vision", "status": "ready", "evidence": "图像 OCR 识别"},
        {"name": "ssh", "status": "live", "evidence": "SSH 远程执行"},
        {"name": "calculator", "status": "live", "evidence": "精确数学计算"},
        {"name": "get_time", "status": "live", "evidence": "时间日期工具"},
        {"name": "install_pkg", "status": "live", "evidence": "pip/apk 自动装包"},
        {"name": "upload", "status": "ready", "evidence": "文件上传解析"},
        {"name": "schedule", "status": "ready", "evidence": "crontab 定时任务"},
        {"name": "auto_evolve", "status": "live", "evidence": "失败自动造技能"},
        {"name": "compress_ctx", "status": "live", "evidence": "对话自动压缩"}
    ],
    "agents": [
        {"name": "黑神规划引擎", "id": "planner", "scope": "任务分解、步骤规划、意图识别", "tools": ["memory", "calculator", "get_time"]},
        {"name": "黑神执行引擎", "id": "coder", "scope": "代码生成、调试、运行验证", "tools": ["python", "shell", "write_file", "install_pkg"]},
        {"name": "黑神联网引擎", "id": "web", "scope": "搜索、抓取、内容整理", "tools": ["web_search", "browser"]},
        {"name": "黑神视觉引擎", "id": "vision", "scope": "图像识别、OCR、内容提取", "tools": ["vision", "upload"]},
        {"name": "黑神运维引擎", "id": "ops", "scope": "部署、服务管理、系统监控", "tools": ["ssh", "shell", "schedule"]},
        {"name": "黑神记忆引擎", "id": "memory", "scope": "长期记忆、偏好学习、历史回顾", "tools": ["memory", "auto_evolve"]}
    ]
}


class BlackGodHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def _file(self, path):
        try:
            with open(path, "rb") as f:
                content = f.read()
            ext = pathlib.Path(path).suffix.lower()
            mime = {".html": "text/html", ".css": "text/css", ".js": "application/javascript",
                    ".json": "application/json", ".svg": "image/svg+xml",
                    ".png": "image/png", ".jpg": "image/jpeg", ".ico": "image/x-icon"}.get(ext, "application/octet-stream")
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", len(content))
            self.end_headers()
            self.wfile.write(content)
        except FileNotFoundError:
            self._json({"error": "not found"}, 404)

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_HEAD(self):
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/html")
        self.end_headers()

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        routes = {
            "/api/health": self._health,
            "/api/categories": self._categories,
            "/api/skills": self._skills,
            "/api/tasks": self._tasks,
            "/api/stats": self._stats,
            "/api/memory": self._memory,
            "/api/tool-matrix": self._tool_matrix,
            "/api/capabilities": self._capabilities,
            "/api/preferences": self._get_preferences,
            "/api/apps": self._apps,
            "/api/schedules": self._get_schedules,
            "/api/onboarding": self._onboarding_flow,
            "/api/profile": self._user_profile,
            "/api/cloudflare/capabilities": self._cloudflare_capabilities,
            "/showcase": lambda: self._file(WEB_ROOT / "web" / "showcase.html"),
        }
        if path in routes:
            routes[path]()
        elif path == "/" or path == "/index.html":
            self._file(WEB_ROOT / "web" / "index.html")
        elif path.startswith("/web/") or path.startswith("/ics/"):
            self._file(WEB_ROOT / path.lstrip("/"))
        elif (WEB_ROOT / "web" / path.lstrip("/")).is_file():
            # 兜底：根路径静态资源（manifest.json/icon-192.png/theme.css/logo.png/sw.js 等）实际在 web/ 下
            self._file(WEB_ROOT / "web" / path.lstrip("/"))
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode()) if length > 0 else {}
        except Exception:
            self._json({"error": "bad request"}, 400)
            return
        routes = {
            "/api/chat": lambda: self._chat(body),
            "/api/task/create": lambda: self._task_create(body),
            "/api/preferences": lambda: self._set_preferences(body),
            "/api/events": lambda: self._events(body),
            "/api/event": lambda: self._events(body),
            "/api/consent": lambda: self._consent(body),
            "/api/onboarding/complete": lambda: self._onboarding_complete(body),
            "/api/upload": self._upload,
            "/api/schedules": lambda: self._add_schedule(body),
            "/api/cloudflare": lambda: self._cloudflare_api(body),
        }
        if path in routes:
            routes[path]()
        else:
            self._json({"error": "not found"}, 404)

    # ── GET 路由处理 ──

    def _health(self):
        self._json({"status": "ok", "version": "2.2", "timestamp": time.time()})

    def _categories(self):
        result = []
        for cat in CATEGORIES:
            c = cat.copy()
            if skill_engine:
                cn_map = {"intelligent_dialog": "智能对话", "creative_design": "创作设计",
                          "info_retrieval": "信息获取", "dev_engineering": "开发工程",
                          "data_analysis": "数据分析", "security_recovery": "安全工具"}
                cn = cn_map.get(cat["id"], cat["name"])
                stats = skill_engine.get_stats()
                c["skill_count"] = stats.get("by_category", {}).get(cn, 0)
            else:
                c["skill_count"] = 0
            result.append(c)
        self._json({"categories": result})

    def _skills(self):
        if not skill_engine:
            self._json({"skills": [], "total": 0})
            return
        q = urllib.parse.urlparse(self.path).query
        p = urllib.parse.parse_qs(q)
        cat = p.get("category", [None])[0]
        lvl = p.get("level", [None])[0]
        skills = skill_engine.get_skills(category=cat, level=lvl, safety_filter=True)
        self._json({"skills": skills, "total": len(skills)})

    def _tasks(self):
        if not task_engine:
            # fallback: 读 tasks.jsonl
            tasks = self._read_tasks_jsonl(20)
            self._json({"tasks": tasks, "total": len(tasks)})
            return
        q = urllib.parse.urlparse(self.path).query
        p = urllib.parse.parse_qs(q)
        limit = int(p.get("limit", ["20"])[0])
        tasks = task_engine.get_tasks(limit=limit)
        self._json({"tasks": tasks, "total": len(tasks)})

    def _read_tasks_jsonl(self, limit=20):
        tasks = []
        if not TASKS_JSONL.exists():
            return tasks
        seen = set()
        lines = TASKS_JSONL.read_text().strip().splitlines()
        for line in reversed(lines):
            try:
                t = json.loads(line)
                tid = t.get("task_id", "")
                if tid in seen:
                    continue
                seen.add(tid)
                tasks.append(t)
                if len(tasks) >= limit:
                    break
            except Exception:
                pass
        return tasks

    def _stats(self):
        data = {"version": "2.2", "timestamp": time.time()}
        if skill_engine:
            data["skills"] = skill_engine.get_stats()
        tasks = self._read_tasks_jsonl(100)
        data["tasks"] = {
            "total": len(tasks),
            "completed": sum(1 for t in tasks if t.get("status") == "completed"),
            "failed": sum(1 for t in tasks if t.get("status") == "failed"),
        }
        mems = self._read_memories(100)
        data["memories"] = {"total": len(mems)}
        self._json(data)

    def _memory(self):
        mems = self._read_memories(50)
        self._json({"memories": mems, "total": len(mems)})

    def _read_memories(self, limit=50):
        if not MEM_DB.exists():
            return []
        try:
            with _mem_lock:
                conn = sqlite3.connect(str(MEM_DB), check_same_thread=False)
                cur = conn.cursor()
                cur.execute("SELECT content, tags, ts FROM mem ORDER BY ts DESC LIMIT ?", (limit,))
                rows = cur.fetchall()
                conn.close()
            return [{"content": r[0], "tags": r[1], "ts": r[2]} for r in rows]
        except Exception:
            return []

    def _tool_matrix(self):
        self._json(TOOL_MATRIX)

    def _capabilities(self):
        self._json({"capabilities": CATEGORIES, "tools": TOOL_MATRIX["tools"]})

    def _get_preferences(self):
        if profile_engine:
            try:
                prefs = profile_engine.get_profile()
                self._json(prefs)
                return
            except Exception:
                pass
        self._json({"enabled": False, "event_count": 0, "answer_style": "balanced",
                    "copy_usage": "normal", "agent_hint": ""})

    def _apps(self):
        self._json({"apps": [
            {"name": "Black God PWA", "tag": "PWA", "desc": "Web 直接安装，无需应用商店", "platform": "全平台", "version": "2.2"},
            {"name": "Black God iOS", "tag": "iOS", "desc": "原生 iOS App，审核中", "platform": "iPhone", "version": "1.0"},
            {"name": "Black God APK", "tag": "Android", "desc": "Android 直装包，测试版", "platform": "Android", "version": "1.0"},
        ]})

    def _get_schedules(self):
        import subprocess
        try:
            r = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
            lines = [l for l in r.stdout.splitlines() if "bg-agent" in l or "blackgod" in l or "BG" in l]
            self._json({"schedules": lines, "note": "仅显示 Black God 相关定时任务"})
        except Exception:
            self._json({"schedules": [], "note": "读取失败"})

    # ── POST 路由处理 ──

    def _chat(self, body):
        message = body.get("message", "")
        history = body.get("history", [])
        device_id = body.get("device_id") or "default"
        if not message:
            self._json({"error": "消息不能为空"}, 400)
            return
        if not chat_engine:
            self._json({"error": "对话引擎未启用"}, 503)
            return
        try:
            if profile_engine:
                try:
                    profile_engine.log_event("message_sent", {"length": len(message), "device_id": device_id})
                except Exception:
                    pass
            task_id = f"task_{int(time.time())}"
            if task_engine:
                task = task_engine.create_task(message)
                task_id = task.get("task_id", task_id)
            result = chat_engine.chat(message, history)
            plan_steps = [
                {"type": "analyze", "status": "completed", "title": "分析需求"},
                {"type": "execute", "status": "completed" if result.get("ok") else "failed", "title": "执行任务"}
            ]
            if task_engine and result.get("ok"):
                try:
                    task["status"] = "completed"
                    task["success"] = True
                    task["steps"] = plan_steps
                    task["result"] = result
                    task_engine._save_task(task)
                except Exception:
                    pass
            self._json({
                "answer": result.get("answer", ""),
                "steps": result.get("steps", []),
                "plan_steps": plan_steps,
                "task_id": task_id,
                "status": "completed" if result.get("ok") else "failed",
                "success": result.get("ok", False),
                "timestamp": time.time()
            })
        except Exception as e:
            import traceback
            traceback.print_exc()
            self._json({"error": str(e), "answer": f"系统错误: {str(e)}", "task_id": task_id if "task_id" in locals() else None, "status": "failed", "success": False}, 500)

    def _task_create(self, body):
        if not task_engine:
            self._json({"error": "任务引擎未启用"}, 503)
            return
        message = body.get("message", "")
        if not message:
            self._json({"error": "消息不能为空"}, 400)
            return
        task = task_engine.create_task(message)
        self._json({"task": task})

    def _set_preferences(self, body):
        if not profile_engine:
            self._json({"enabled": False, "message": "画像引擎未启用"})
            return
        try:
            if body.get("clear"):
                profile_engine.clear_profile()
                self._json({"enabled": False, "event_count": 0, "answer_style": "balanced", "copy_usage": "normal", "agent_hint": ""})
            else:
                enabled = body.get("enabled", True)
                profile_engine.log_event("preference_changed", {"enabled": enabled})
                prefs = profile_engine.get_profile()
                self._json(prefs)
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _events(self, body):
        event = body.get("event") or body.get("event_type", "")
        payload = body.get("payload") or body.get("event_data", {})
        if profile_engine and event:
            try:
                profile_engine.log_event(event, payload)
            except Exception:
                pass
        self._json({"success": True})

    def _consent(self, body):
        """处理权限授权（接入 onboarding 模块）"""
        try:
            sys.path.insert(0, str(ROOT / "core"))
            from onboarding import OnboardingManager
            mgr = OnboardingManager()
            perm_id = body.get("perm_id", "")
            granted = body.get("granted", False)
            reason = body.get("reason", "")
            if perm_id:
                result = mgr.apply_permission(perm_id, granted, reason)
            else:
                result = {"success": False, "error": "缺少 perm_id"}
            self._json(result)
        except Exception as e:
            self._json({"success": False, "error": str(e)})

    def _onboarding_flow(self):
        """获取首次引导流程配置"""
        try:
            sys.path.insert(0, str(ROOT / "core"))
            from onboarding import OnboardingManager
            mgr = OnboardingManager()
            self._json({
                "onboarded": mgr.is_onboarded(),
                "flow": mgr.get_onboarding_flow()
            })
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _onboarding_complete(self, body):
        """完成引导"""
        try:
            sys.path.insert(0, str(ROOT / "core"))
            from onboarding import OnboardingManager
            mgr = OnboardingManager()
            result = mgr.complete_onboarding(
                user_name=body.get("name", ""),
                user_desc=body.get("desc", "")
            )
            self._json(result)
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _user_profile(self):
        """获取本地用户画像（行为分析结果）"""
        try:
            sys.path.insert(0, str(ROOT / "core"))
            from onboarding import LocalDataStore, BehaviorAnalyzer
            store = LocalDataStore()
            analyzer = BehaviorAnalyzer(store)
            profile = analyzer.analyze()
            self._json({"profile": profile, "ok": True})
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _upload(self):
        self._json({"ok": False, "error": "请使用 multipart 上传"})

    def _add_schedule(self, body):
        schedule = body.get("schedule", "")
        command = body.get("command", "")
        if not schedule or not command:
            self._json({"error": "缺少 schedule 或 command"}, 400)
            return
        import subprocess
        try:
            r = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
            existing = r.stdout.strip()
            new_line = f"{schedule} {command}"
            new_cron = existing + "\n" + new_line if existing else new_line
            subprocess.run(["crontab", "-"], input=new_cron, text=True, check=True)
            self._json({"success": True, "schedules": [new_line]})
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _cloudflare_api(self, body):
        """Cloudflare MCP API 代理"""
        if not cf_integration:
            self._json({"error": "Cloudflare 集成未启用"}, 503)
            return
        
        try:
            import asyncio
            command = body.get("command", "")
            params = body.get("params", {})
            
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(
                cf_integration.handle_command(command, params)
            )
            loop.close()
            
            self._json({"result": result, "ok": True})
        except Exception as e:
            self._json({"error": str(e)}, 500)

    def _cloudflare_capabilities(self):
        """获取 Cloudflare 集成能力"""
        if not cf_integration:
            self._json({"error": "Cloudflare 集成未启用"}, 503)
            return
        
        self._json({
            "capabilities": cf_integration.capabilities,
            "mcp_url": "https://mcp.cloudflare.com/mcp",
            "ok": True
        })


def run_server():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), BlackGodHandler)
    skill_count = skill_engine.get_stats()["total"] if skill_engine else 0
    print(f"""
Black God Agent v2.2 — http://0.0.0.0:{PORT}
技能: {skill_count} | 模型: {os.environ.get("BG_MODEL","auto")} | 网关: {os.environ.get("BG_BASE","?")}
""")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()

if __name__ == "__main__":
    run_server()
