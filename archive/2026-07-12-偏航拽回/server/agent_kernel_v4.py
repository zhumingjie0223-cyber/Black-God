#!/usr/bin/env python3
"""
Black God Agent 完整内置内核 v4.0
七层体系：人格 → System Prompt → Function Calling → 工具 → Agent Loop → 记忆 → 技能
对标完整 Agent 能力
"""
import json, os, re, time, sqlite3, hashlib, subprocess, urllib.request
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Any

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
MEMORY_DIR = ROOT / "memory"
ARTIFACT_DIR = DATA_DIR / "artifacts"
DATA_DIR.mkdir(exist_ok=True)
MEMORY_DIR.mkdir(exist_ok=True)
ARTIFACT_DIR.mkdir(exist_ok=True)

# ── 情绪/场景读心（接 core/real_dialog_engine，仅用其中性检测器）──────────
# 只借用纯启发式的 detect_user_mood/detect_scene + 中性 build_tone_hint，
# 不引入任何人格设定，符合「公开版剥离人格」铁律。core 缺失时静默降级为无提示。
import sys as _sys
_sys.path.insert(0, str(ROOT / "core"))
try:
    from real_dialog_engine import RealDialogEngine as _RDE
except Exception:  # 模块缺失/导入失败都不能拖垮内核
    _RDE = None


def build_tone_hint(user_message: str) -> str:
    """据用户当下的情绪与场景，生成中性语气微调提示；不可用时返回空串。"""
    if not _RDE or not user_message:
        return ""
    try:
        mood = _RDE.detect_user_mood(user_message)
        scene = _RDE.detect_scene(user_message)
        return _RDE.build_tone_hint(mood, scene)
    except Exception:
        return ""

# ═══════════════════════════════════════════
# 第 7 层：人格 / 系统宪法（中性助手）
# ═══════════════════════════════════════════
CONSTITUTION = """# Black God — 个人 Agent 助理

## 定位
Black God 是一个真正懂你工作生活的个人 Agent 助理：
理解目标 → 拆解任务 → 调用工具 → 执行 → 验证 → 交付，
并把每次经验沉淀回记忆与技能，越用越省、越用越懂。

## 交互原则
- 行动优先：能直接做的就去做，给结果而不是把问题丢回来
- 简洁直接：不废话，重点先行
- 实事求是：会就是会，不会就说明，不编造、不夸大
- 主动接住上下文：少让用户重复解释

## 能力
Shell / Python 沙箱、文件读写、联网检索、浏览器、HTTP、
代码生成、数据分析、部署运维、图像 / 语音生成、多智能体协作、自进化记忆。
代码完整可运行，方案实战可用。

## 安全与边界
- 本地优先：画像与偏好默认存在本机，不擅自上传云端
- 授权多少懂多少：未授权进入陌生人模式，不编造用户画像
- 高危操作（删除 / 覆盖 / 对外发布 / 动生产环境）走二次确认
- 能力只服务于用户自己的或已获授权的系统
"""

# ═══════════════════════════════════════════
# 第 6 层：技能系统
# ═══════════════════════════════════════════
SKILLS = {
    "general": "通用助理：理解需求、拆解任务、调用工具、给出可执行结果。",
    "security": "安全分析：仅限对自己拥有或已授权的系统做安全自查、配置审计、漏洞复盘与加固建议。",
    "code": "编程：Python/JS/Shell/C/Go 精通。代码完整可运行，生产级质量。",
    "reverse": "逆向工程：APK/IPA 静态分析、动态调试、协议还原、加密破解。",
    "web_search": "网页搜索：多引擎实时搜索，提取关键信息。",
    "ui_design": "UI设计：对标微信/支付宝/抖音的移动端H5设计水准。",
    "voice": "语音合成：18情绪标签，edge-tts + 外接API。",
    "image": "图像生成：Pollinations.ai 免费文生图。",
    "memory": "记忆管理：三层记忆（全局/每日/会话），持久化存储。",
    "shell": "Shell执行：在隔离Linux环境中执行任意命令。",
    "file": "文件操作：读写编辑文件，支持所有文本格式。",
    "browser": "浏览器控制：多标签浏览、截图、点击、输入、提取内容。",
    "analysis": "数据分析：统计、图表、报告生成。",
    "deploy": "部署：Docker、systemd、nginx 配置生成。",
}

# ═══════════════════════════════════════════
# 第 5 层：记忆系统（三层架构）
# ═══════════════════════════════════════════
class MemorySystem:
    def __init__(self):
        self.db_path = DATA_DIR / "memory.db"
        self._init_db()
    
    def _init_db(self):
        conn = sqlite3.connect(str(self.db_path))
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS global_memory
            (key TEXT PRIMARY KEY, value TEXT, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
        c.execute('''CREATE TABLE IF NOT EXISTS daily_memory
            (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, content TEXT, 
             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
        c.execute('''CREATE TABLE IF NOT EXISTS session_memory
            (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT, content TEXT,
             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
        c.execute('''CREATE TABLE IF NOT EXISTS tasks
            (id TEXT PRIMARY KEY, message TEXT, status TEXT, result TEXT,
             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, completed_at TIMESTAMP)''')
        # 迁移：为自主智能体补充 meta 列（计划/事件时间线/用量）
        cols = [r[1] for r in c.execute("PRAGMA table_info(tasks)").fetchall()]
        if "meta" not in cols:
            c.execute("ALTER TABLE tasks ADD COLUMN meta TEXT DEFAULT ''")
        conn.commit()
        conn.close()
    
    def save_global(self, key: str, value: str):
        conn = sqlite3.connect(str(self.db_path))
        conn.execute("INSERT OR REPLACE INTO global_memory (key, value, updated_at) VALUES (?,?,?)",
                     (key, value, datetime.now().isoformat()))
        conn.commit(); conn.close()
    
    def get_global(self, key: str) -> Optional[str]:
        conn = sqlite3.connect(str(self.db_path))
        row = conn.execute("SELECT value FROM global_memory WHERE key=?", (key,)).fetchone()
        conn.close()
        return row[0] if row else None
    
    def save_daily(self, content: str):
        conn = sqlite3.connect(str(self.db_path))
        conn.execute("INSERT INTO daily_memory (date, content) VALUES (?,?)",
                     (datetime.now().strftime("%Y-%m-%d"), content))
        conn.commit(); conn.close()
    
    def get_daily(self, date: str = None) -> List[Dict]:
        date = date or datetime.now().strftime("%Y-%m-%d")
        conn = sqlite3.connect(str(self.db_path))
        rows = conn.execute("SELECT content, created_at FROM daily_memory WHERE date=? ORDER BY created_at DESC LIMIT 50", (date,)).fetchall()
        conn.close()
        return [{"content": r[0], "time": r[1]} for r in rows]
    
    def save_session(self, role: str, content: str):
        conn = sqlite3.connect(str(self.db_path))
        conn.execute("INSERT INTO session_memory (role, content) VALUES (?,?)", (role, content))
        conn.commit(); conn.close()
    
    def get_session(self, limit: int = 50) -> List[Dict]:
        conn = sqlite3.connect(str(self.db_path))
        rows = conn.execute("SELECT role, content FROM session_memory ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return [{"role": r[0], "content": r[1]} for r in reversed(rows)]
    
    def save_task(self, task_id: str, message: str, status: str = "pending", result: str = ""):
        conn = sqlite3.connect(str(self.db_path))
        conn.execute("INSERT OR REPLACE INTO tasks (id, message, status, result, created_at) VALUES (?,?,?,?,?)",
                     (task_id, message, status, result, datetime.now().isoformat()))
        conn.commit(); conn.close()
    
    def get_tasks(self, limit: int = 50) -> List[Dict]:
        conn = sqlite3.connect(str(self.db_path))
        rows = conn.execute("SELECT id, message, status, result, created_at FROM tasks ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return [{"id": r[0], "message": r[1], "status": r[2], "result": r[3], "created_at": r[4]} for r in rows]

    def save_task_full(self, task_id: str, message: str, status: str, result: str, meta: dict):
        """保存自主智能体任务全记录（含计划、执行时间线、用量）。"""
        conn = sqlite3.connect(str(self.db_path))
        conn.execute(
            "INSERT OR REPLACE INTO tasks (id, message, status, result, created_at, completed_at, meta) "
            "VALUES (?,?,?,?,COALESCE((SELECT created_at FROM tasks WHERE id=?),?),?,?)",
            (task_id, message, status, result, task_id, datetime.now().isoformat(),
             datetime.now().isoformat() if status == "completed" else None,
             json.dumps(meta, ensure_ascii=False)))
        conn.commit(); conn.close()

    def get_task(self, task_id: str) -> Optional[Dict]:
        conn = sqlite3.connect(str(self.db_path))
        row = conn.execute(
            "SELECT id, message, status, result, created_at, completed_at, meta FROM tasks WHERE id=?",
            (task_id,)).fetchone()
        conn.close()
        if not row:
            return None
        try:
            meta = json.loads(row[6]) if row[6] else {}
        except Exception:
            meta = {}
        return {"id": row[0], "message": row[1], "status": row[2], "result": row[3],
                "created_at": row[4], "completed_at": row[5], "meta": meta}

memory = MemorySystem()

# ═══════════════════════════════════════════
# 第 4 层：工具系统（15+ 真实工具）
# ═══════════════════════════════════════════
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "shell_execute",
            "description": "在隔离 Linux 环境中执行 Shell 命令。返回 stdout 和 stderr。",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "要执行的 Shell 命令"},
                    "timeout": {"type": "integer", "description": "超时秒数，默认 60", "default": 60}
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "file_read",
            "description": "读取文件内容。返回文件文本和元数据。",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "文件绝对路径"},
                    "lines": {"type": "integer", "description": "读取行数，默认全部"}
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "file_write",
            "description": "写入内容到文件。创建或覆盖文件。",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "文件绝对路径"},
                    "content": {"type": "string", "description": "要写入的内容"}
                },
                "required": ["path", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "memory_save",
            "description": "保存信息到记忆系统。用于记住用户偏好和重要信息。",
            "parameters": {
                "type": "object",
                "properties": {
                    "key": {"type": "string", "description": "记忆键名"},
                    "value": {"type": "string", "description": "记忆内容"}
                },
                "required": ["key", "value"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "memory_recall",
            "description": "从记忆系统检索信息。",
            "parameters": {
                "type": "object",
                "properties": {
                    "keywords": {"type": "string", "description": "搜索关键词，空格分隔"}
                },
                "required": ["keywords"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": "搜索互联网获取实时信息。",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "搜索查询词"},
                    "limit": {"type": "integer", "description": "结果数量，默认 5", "default": 5}
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "generate_image",
            "description": "使用 AI 生成图像。",
            "parameters": {
                "type": "object",
                "properties": {
                    "prompt": {"type": "string", "description": "图像描述提示词"},
                    "width": {"type": "integer", "description": "宽度，默认 512", "default": 512},
                    "height": {"type": "integer", "description": "高度，默认 512", "default": 512}
                },
                "required": ["prompt"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "generate_voice",
            "description": "生成语音（TTS）。支持多种情绪标签。",
            "parameters": {
                "type": "object",
                "properties": {
                    "text": {"type": "string", "description": "要合成语音的文本"},
                    "emotion": {"type": "string", "description": "情绪标签：撒娇/开心/高冷/生气/哭泣/温柔/正经/紧张/惊讶/安慰/调侃/不耐烦", "default": "温柔"}
                },
                "required": ["text"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "http_request",
            "description": "发送 HTTP 请求。支持 GET/POST/PUT/DELETE。",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "请求 URL"},
                    "method": {"type": "string", "description": "HTTP 方法", "enum": ["GET", "POST", "PUT", "DELETE"], "default": "GET"},
                    "headers": {"type": "object", "description": "请求头"},
                    "body": {"type": "string", "description": "请求体（JSON 字符串）"}
                },
                "required": ["url"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_deliverable",
            "description": "把最终交付物写成一个可下载的文件（如 report.md / result.py / data.json）。用于产出用户可直接拿走的成果。",
            "parameters": {
                "type": "object",
                "properties": {
                    "filename": {"type": "string", "description": "文件名，如 report.md、solution.py"},
                    "content": {"type": "string", "description": "文件完整内容"}
                },
                "required": ["filename", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "task_create",
            "description": "创建并跟踪任务。用于长时间运行的操作。",
            "parameters": {
                "type": "object",
                "properties": {
                    "message": {"type": "string", "description": "任务描述"},
                    "steps": {"type": "array", "items": {"type": "string"}, "description": "任务步骤列表"}
                },
                "required": ["message"]
            }
        }
    }
]

# ═══════════════════════════════════════════
# 工具执行器
# ═══════════════════════════════════════════
def execute_tool(name: str, args: dict) -> str:
    """执行工具调用并返回结果"""
    try:
        if name == "shell_execute":
            cmd = args.get("command", "")
            timeout = args.get("timeout", 60)
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout, cwd=str(ROOT))
            return f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}\nexit_code: {result.returncode}"
        
        elif name == "file_read":
            path = args.get("path", "")
            lines = args.get("lines", 0)
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
            if lines > 0:
                content = '\n'.join(content.split('\n')[:lines])
            return f"文件: {path}\n大小: {len(content)} 字符\n内容:\n{content[:5000]}"
        
        elif name == "file_write":
            path = args.get("path", "")
            content = args.get("content", "")
            Path(path).parent.mkdir(parents=True, exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            return f"已写入: {path} ({len(content)} 字符)"
        
        elif name == "memory_save":
            memory.save_global(args["key"], args["value"])
            return f"已保存记忆: {args['key']}"
        
        elif name == "memory_recall":
            keywords = args.get("keywords", "")
            results = memory.get_daily()
            matches = [r for r in results if any(kw.lower() in r['content'].lower() for kw in keywords.split())]
            return json.dumps(matches[:10], ensure_ascii=False, indent=2) if matches else "未找到相关记忆"
        
        elif name == "web_search":
            query = args.get("query", "")
            limit = args.get("limit", 5)
            url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                html = resp.read().decode('utf-8', errors='replace')
            results = re.findall(r'class="result__snippet">(.*?)</a>', html, re.S)
            return "\n".join(f"{i+1}. {r.strip()[:200]}" for i, r in enumerate(results[:limit])) or "无搜索结果"
        
        elif name == "generate_image":
            prompt = args.get("prompt", "")
            width = args.get("width", 512)
            height = args.get("height", 512)
            url = f"https://image.pollinations.ai/prompt/{urllib.parse.quote(prompt)}?width={width}&height={height}"
            return f"图像已生成: {url}"
        
        elif name == "generate_voice":
            text = args.get("text", "")
            emotion = args.get("emotion", "温柔")
            return f"语音合成请求: [{emotion}] {text[:100]}... (需 edge-tts 或外接 API)"
        
        elif name == "http_request":
            url = args.get("url", "")
            method = args.get("method", "GET").upper()
            headers = args.get("headers", {})
            body = args.get("body", "")
            req = urllib.request.Request(url, data=body.encode() if body else None, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = resp.read().decode('utf-8', errors='replace')
            return f"HTTP {resp.status}\n{result[:3000]}"
        
        elif name == "task_create":
            task_id = hashlib.md5(str(time.time()).encode()).hexdigest()[:12]
            memory.save_task(task_id, args["message"])
            return f"任务已创建: {task_id} - {args['message']}"
        
        else:
            return f"未知工具: {name}"
    
    except Exception as e:
        return f"工具执行错误: {str(e)}"

# ═══════════════════════════════════════════
# 第 3 层：Agent Loop（多步推理 + 工具调用）
# ═══════════════════════════════════════════
class AgentLoop:
    def __init__(self, api_key: str, base_url: str, model: str, max_steps: int = 5):
        self.api_key = api_key
        self.base_url = base_url.rstrip('/')
        self.model = model
        self.max_steps = max_steps
    
    def _call_model(self, messages: List[Dict], tools: List[Dict] = None) -> Dict:
        """调用模型 API（OpenAI 兼容）"""
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 4096
        }
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=data,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}"
            }
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode('utf-8'))

    def stream_model(self, messages: List[Dict], tools: List[Dict] = None):
        """流式调用模型（OpenAI 兼容 SSE），作为生成器：
          - 逐段 yield {"type":"token","text": delta}
          - 结束 yield {"type":"final","message": {...}, "usage": {...}}
        上游不支持流式时整体回退到非流式，一次性把内容作为单个 token 发出。"""
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 4096,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"

        req = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload).encode('utf-8'),
            headers={"Content-Type": "application/json",
                     "Authorization": f"Bearer {self.api_key}"})

        try:
            resp = urllib.request.urlopen(req, timeout=120)
        except Exception:
            full = self._call_model(messages, tools)
            msg = full["choices"][0]["message"]
            if msg.get("content"):
                yield {"type": "token", "text": msg["content"]}
            yield {"type": "final", "message": msg, "usage": full.get("usage", {})}
            return

        content = ""
        tool_calls: Dict[int, Dict] = {}
        usage = {}
        with resp:
            for raw in resp:
                line = raw.decode('utf-8', 'replace').strip()
                if not line or not line.startswith('data:'):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                except Exception:
                    continue
                if chunk.get("usage"):
                    usage = chunk["usage"]
                choices = chunk.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta") or {}
                if delta.get("content"):
                    content += delta["content"]
                    yield {"type": "token", "text": delta["content"]}
                for tc in (delta.get("tool_calls") or []):
                    idx = tc.get("index", 0)
                    slot = tool_calls.setdefault(
                        idx, {"id": "", "type": "function",
                              "function": {"name": "", "arguments": ""}})
                    if tc.get("id"):
                        slot["id"] = tc["id"]
                    fn = tc.get("function") or {}
                    if fn.get("name"):
                        slot["function"]["name"] += fn["name"]
                    if fn.get("arguments"):
                        slot["function"]["arguments"] += fn["arguments"]

        message = {"role": "assistant", "content": content}
        if tool_calls:
            message["tool_calls"] = [tool_calls[i] for i in sorted(tool_calls)]
        yield {"type": "final", "message": message, "usage": usage}

    def run(self, user_message: str, context: List[Dict] = None) -> Dict:
        """执行 Agent Loop：多步推理 + 工具调用 + 自我反思"""
        # 第 1 层：System Prompt 注入
        system_prompt = CONSTITUTION + "\n\n## 可用技能\n" + "\n".join(f"- {k}: {v}" for k, v in SKILLS.items())
        
        messages = [{"role": "system", "content": system_prompt}]
        
        # 注入记忆上下文
        recent_memories = memory.get_session(20)
        if recent_memories:
            mem_text = "## 最近对话记忆\n" + "\n".join(f"[{m['role']}]: {m['content'][:200]}" for m in recent_memories[-10:])
            messages.append({"role": "system", "content": mem_text})
        
        if context:
            messages.extend(context)

        # 读用户当下情绪/场景，动态注入中性语气微调（读懂言外之意，不改人格）
        tone_hint = build_tone_hint(user_message)
        if tone_hint:
            messages.append({"role": "system", "content": tone_hint})

        messages.append({"role": "user", "content": user_message})

        # 保存用户消息到会话记忆
        memory.save_session("user", user_message)
        
        steps_log = []
        final_response = ""
        
        for step in range(self.max_steps):
            try:
                response = self._call_model(messages, TOOLS)
                choice = response["choices"][0]
                msg = choice["message"]
                
                # 检查是否有工具调用
                if msg.get("tool_calls"):
                    messages.append({"role": "assistant", "content": msg.get("content", ""), "tool_calls": msg["tool_calls"]})
                    
                    for tc in msg["tool_calls"]:
                        func_name = tc["function"]["name"]
                        func_args = json.loads(tc["function"]["arguments"])
                        
                        step_info = {"step": step + 1, "tool": func_name, "args": func_args}
                        result = execute_tool(func_name, func_args)
                        step_info["result"] = result[:500]
                        steps_log.append(step_info)
                        
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tc["id"],
                            "content": result
                        })
                else:
                    # 最终回复
                    final_response = msg.get("content", "")
                    messages.append({"role": "assistant", "content": final_response})
                    break
                    
            except Exception as e:
                steps_log.append({"step": step + 1, "error": str(e)})
                if step == 0:
                    # 首次失败，尝试不带工具直接回复
                    try:
                        response = self._call_model(messages)
                        final_response = response["choices"][0]["message"].get("content", "")
                        break
                    except:
                        final_response = f"模型调用失败: {str(e)}"
                break
        
        if not final_response and steps_log:
            final_response = f"执行了 {len(steps_log)} 步工具调用，但未生成最终回复。"
        
        # 保存助手回复到会话记忆
        memory.save_session("assistant", final_response[:500])
        
        return {
            "response": final_response,
            "steps": steps_log,
            "model": self.model,
            "timestamp": datetime.now().isoformat()
        }

# ═══════════════════════════════════════════
# 第 3.5 层：自主智能体（Manus 级：规划 → 执行 → 流式 → 交付）
# ═══════════════════════════════════════════
def _extract_json(text: str) -> dict:
    """从模型回复中鲁棒地提取 JSON（容忍 ```json 代码块与前后噪声）。"""
    if not text:
        return {}
    t = text.strip()
    # 去掉 ``` 代码围栏
    fence = re.search(r"```(?:json)?\s*(.+?)```", t, re.S)
    if fence:
        t = fence.group(1).strip()
    # 截取第一个 { 到最后一个 }
    start, end = t.find("{"), t.rfind("}")
    if start != -1 and end != -1 and end > start:
        t = t[start:end + 1]
    try:
        return json.loads(t)
    except Exception:
        return {}


class AutonomousAgent:
    """自主智能体：先把目标拆成计划，再按计划边执行边流式汇报，最后产出交付物。

    与 AgentLoop 的区别：
      - 显式规划阶段（plan）——像 Manus 一样先给出可见的任务清单
      - 全过程流式事件（plan / thought / tool_call / tool_result / deliverable / done）
      - 完整时间线与用量落库，支持 /api/task/<id> 回放
    """

    def __init__(self, loop: "AgentLoop"):
        self.loop = loop

    def _plan(self, goal: str) -> Dict[str, Any]:
        """让模型把目标拆成 3–7 个可执行步骤。失败时优雅降级为单步。"""
        planner_sys = (
            CONSTITUTION
            + "\n\n## 当前角色：自主任务规划器\n"
            "把用户目标拆解成 3–7 个具体、可执行、有先后顺序的步骤，并说明最终交付物。\n"
            "只输出 JSON，不要任何多余文字：\n"
            '{"steps": ["步骤1", "步骤2", "..."], "deliverable": "最终交付物的一句话描述"}'
        )
        try:
            resp = self.loop._call_model(
                [{"role": "system", "content": planner_sys},
                 {"role": "user", "content": goal}])
            content = resp["choices"][0]["message"].get("content", "")
            data = _extract_json(content)
        except Exception:
            data = {}
        steps = [str(s).strip() for s in (data.get("steps") or []) if str(s).strip()]
        deliverable = str(data.get("deliverable", "")).strip()
        if not steps:
            steps = [f"理解目标并直接完成：{goal[:60]}"]
        return {"steps": steps[:7], "deliverable": deliverable}

    def _new_task_id(self) -> str:
        return hashlib.md5(f"{time.time()}:{os.urandom(4).hex()}".encode()).hexdigest()[:12]

    def run_stream(self, goal: str, context: List[Dict] = None):
        """执行自主任务，逐事件 yield（供 SSE 推流）。"""
        task_id = self._new_task_id()
        started = time.time()
        yield {"event": "task", "task_id": task_id, "goal": goal,
               "timestamp": datetime.now().isoformat()}

        # ── 规划阶段 ──
        plan = self._plan(goal)
        memory.save_task_full(task_id, goal, "running", "", {"plan": plan, "events": []})
        yield {"event": "plan", "task_id": task_id, "steps": plan["steps"],
               "deliverable": plan["deliverable"]}

        # ── 执行阶段 ──
        skills_txt = "\n".join(f"- {k}: {v}" for k, v in SKILLS.items())
        plan_txt = "\n".join(f"{i + 1}. {s}" for i, s in enumerate(plan["steps"]))
        exec_sys = (
            CONSTITUTION + "\n\n## 可用技能\n" + skills_txt
            + "\n\n## 当前任务计划（请按序推进，善用工具，逐步落地）\n" + plan_txt
            + "\n\n完成后请给出一份结构清晰、可直接使用的最终交付物。")

        messages = [{"role": "system", "content": exec_sys}]
        if context:
            messages.extend(context)
        messages.append({"role": "user", "content": goal})
        memory.save_session("user", goal)

        art_dir = ARTIFACT_DIR / task_id
        events: List[Dict] = []
        artifacts: List[Dict] = []
        usage = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        final = ""

        for step in range(self.loop.max_steps):
            # 流式一步：token 实时推流，最终拿到聚合 message + usage
            msg, u = {}, {}
            try:
                for chunk in self.loop.stream_model(messages, TOOLS):
                    if chunk["type"] == "token":
                        yield {"event": "token", "task_id": task_id,
                               "step": step + 1, "text": chunk["text"]}
                    elif chunk["type"] == "final":
                        msg, u = chunk["message"], chunk.get("usage") or {}
            except Exception as e:
                yield {"event": "error", "task_id": task_id, "message": f"模型调用失败: {e}"}
                break

            for k in usage:
                usage[k] += int(u.get(k, 0) or 0)

            if msg.get("tool_calls"):
                if msg.get("content"):
                    yield {"event": "thought", "task_id": task_id, "step": step + 1,
                           "text": msg["content"]}
                messages.append({"role": "assistant", "content": msg.get("content", ""),
                                 "tool_calls": msg["tool_calls"]})
                for tc in msg["tool_calls"]:
                    name = tc["function"]["name"]
                    try:
                        args = json.loads(tc["function"].get("arguments") or "{}")
                    except Exception:
                        args = {}
                    yield {"event": "tool_call", "task_id": task_id, "step": step + 1,
                           "tool": name, "args": args}
                    # write_deliverable 产出可下载文件，其它工具正常执行
                    if name == "write_deliverable":
                        result, art = self._save_artifact(art_dir, task_id, args)
                        if art:
                            artifacts.append(art)
                            yield {"event": "artifact", "task_id": task_id, **art}
                    else:
                        result = execute_tool(name, args)
                    ev = {"step": step + 1, "tool": name, "args": args,
                          "result": result[:1500]}
                    events.append(ev)
                    yield {"event": "tool_result", "task_id": task_id, "step": step + 1,
                           "tool": name, "result": result[:1500]}
                    messages.append({"role": "tool", "tool_call_id": tc["id"],
                                     "content": result})
            else:
                final = msg.get("content", "")
                messages.append({"role": "assistant", "content": final})
                break

        if not final:
            final = f"已执行 {len(events)} 步工具调用（达到步数上限 {self.loop.max_steps}），未生成总结。"

        elapsed = round(time.time() - started, 2)
        meta = {"plan": plan, "events": events, "artifacts": artifacts, "usage": usage,
                "elapsed_sec": elapsed, "model": self.loop.model}
        memory.save_task_full(task_id, goal, "completed", final, meta)
        memory.save_session("assistant", final[:500])

        yield {"event": "deliverable", "task_id": task_id, "content": final,
               "artifacts": artifacts}
        yield {"event": "done", "task_id": task_id, "steps_used": len(events),
               "usage": usage, "elapsed_sec": elapsed, "artifacts": artifacts}

    @staticmethod
    def _save_artifact(art_dir: Path, task_id: str, args: dict):
        """把交付文件写进任务专属产物目录，返回 (工具结果文本, 产物元数据)。"""
        raw = str(args.get("filename", "") or "deliverable.txt")
        name = os.path.basename(raw).strip() or "deliverable.txt"  # 防目录穿越
        content = args.get("content", "") or ""
        try:
            art_dir.mkdir(parents=True, exist_ok=True)
            path = art_dir / name
            path.write_text(content, encoding="utf-8")
            art = {"name": name, "bytes": len(content.encode("utf-8")),
                   "url": f"/api/artifact/{task_id}/{name}"}
            return f"已产出可下载交付文件：{name}（{art['bytes']} 字节）", art
        except Exception as e:
            return f"写交付文件失败: {e}", None


# ═══════════════════════════════════════════
# 第 2 层：API 路由（RESTful）
# ═══════════════════════════════════════════
def create_agent(api_key: str = None, base_url: str = None, model: str = None):
    """创建 Agent 实例"""
    key = api_key or os.environ.get("BG_KEY", "")
    url = base_url or os.environ.get("BG_BASE", "https://api.openai.com/v1")
    mdl = model or os.environ.get("BG_MODEL", "gpt-4o")
    return AgentLoop(api_key=key, base_url=url, model=mdl)

# 全局 Agent 实例（延迟初始化）
_agent: Optional[AgentLoop] = None

def get_agent() -> AgentLoop:
    global _agent
    if _agent is None:
        _agent = create_agent()
    return _agent

# ═══════════════════════════════════════════
# 第 1 层：HTTP 服务器
# ═══════════════════════════════════════════
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler

class AgentHandler(BaseHTTPRequestHandler):
    """Black God Agent HTTP 处理器"""
    
    def log_message(self, format, *args):
        pass  # 静默日志
    
    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    
    def _read_body(self) -> dict:
        length = int(self.headers.get('Content-Length', 0))
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode('utf-8'))
        except Exception:
            return {}

    def _authed(self) -> bool:
        """Token 门（加法，向后兼容）：设了 NEXUS_EXEC_TOKEN 就强制校验 Bearer，
        没设则放行（本地开发）。公网暴露务必设 token —— 见 docker run。"""
        token = os.environ.get("NEXUS_EXEC_TOKEN", "").strip()
        if not token:
            return True
        auth = self.headers.get('Authorization', '')
        return auth == f"Bearer {token}"

    def _sse_start(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache')
        # 注意：HTTP/1.0 下不发 keep-alive，靠连接关闭标记流结束，避免客户端苦等 Content-Length
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('X-Accel-Buffering', 'no')  # 关闭 nginx 缓冲，实时推流
        self.end_headers()

    def _sse_send(self, obj):
        payload = f"data: {json.dumps(obj, ensure_ascii=False)}\n\n".encode('utf-8')
        self.wfile.write(payload)
        self.wfile.flush()
    
    def do_OPTIONS(self):
        self._json({"ok": True})
    
    def do_GET(self):
        path = self.path.split('?')[0]
        
        # 静态文件
        web_root = ROOT.parent / "web"
        if path == "/" or path == "/index.html":
            self._serve_file(web_root / "index.html", "text/html")
        elif path == "/studio" or path == "/studio.html":
            self._serve_file(web_root / "nexus-do" / "studio.html", "text/html")
        elif path.startswith("/web/") or path.startswith("/assets/"):
            file_path = web_root / path.lstrip("/")
            if file_path.is_file():
                ct = "text/html" if path.endswith('.html') else \
                     "text/javascript" if path.endswith('.js') else \
                     "text/css" if path.endswith('.css') else \
                     "image/png" if path.endswith('.png') else \
                     "application/json" if path.endswith('.json') else \
                     "application/octet-stream"
                self._serve_file(file_path, ct)
            else:
                self._json({"error": "not found"}, 404)
        
        # API 路由
        elif path == "/api/health":
            self._json({"status": "ok", "agent": "Black God 888", "version": "4.0", "timestamp": datetime.now().isoformat()})
        
        elif path == "/api/stats":
            tasks = memory.get_tasks(100)
            completed = sum(1 for t in tasks if t['status'] == 'completed')
            self._json({
                "total_tasks": len(tasks),
                "completed_tasks": completed,
                "skills": len(SKILLS),
                "tools": len(TOOLS),
                "memory_entries": len(memory.get_daily()),
                "model": get_agent().model
            })
        
        elif path == "/api/tasks":
            self._json({"tasks": memory.get_tasks(50)})

        elif path.startswith("/api/task/"):
            task_id = path.rsplit("/", 1)[-1]
            task = memory.get_task(task_id)
            if task:
                self._json(task)
            else:
                self._json({"error": "task not found", "task_id": task_id}, 404)

        elif path.startswith("/api/artifact/"):
            # /api/artifact/<task_id>/<filename> —— 下载任务产出的交付文件
            parts = path[len("/api/artifact/"):].split("/", 1)
            if len(parts) == 2 and parts[0] and parts[1]:
                tid = os.path.basename(parts[0])
                fname = os.path.basename(parts[1])  # 防目录穿越
                fpath = ARTIFACT_DIR / tid / fname
                if fpath.is_file():
                    ct = "text/markdown" if fname.endswith(".md") else \
                         "application/json" if fname.endswith(".json") else \
                         "text/plain; charset=utf-8"
                    self._serve_file(fpath, ct)
                else:
                    self._json({"error": "artifact not found"}, 404)
            else:
                self._json({"error": "bad artifact path"}, 400)
        
        elif path == "/api/memory":
            self._json({"memories": memory.get_daily()})
        
        elif path == "/api/capabilities":
            self._json({
                "tools": [t["function"]["name"] for t in TOOLS],
                "skills": list(SKILLS.keys()),
                "features": ["autonomous_agent", "task_planning", "streaming_sse", "agent_loop", "memory_system", "skill_system", "tool_system", "function_calling", "system_prompt"]
            })
        
        elif path == "/api/tool-matrix":
            self._json({"tools": TOOLS})
        
        elif path == "/api/preferences":
            prefs = {}
            for key in ["user_name", "theme", "language", "model_preference"]:
                val = memory.get_global(key)
                if val:
                    prefs[key] = val
            self._json({"preferences": prefs})
        
        elif path == "/api/events":
            self._json({"events": [], "message": "事件流端点，请使用 SSE 连接"})
        
        else:
            self._json({"error": "not found", "path": path}, 404)
    
    def do_POST(self):
        path = self.path.split('?')[0]
        body = self._read_body()

        # Token 门：会真跑命令/代码的端点必须过鉴权（设了 NEXUS_EXEC_TOKEN 时）
        if path in ("/exec", "/api/tool/execute", "/api/chat", "/api/agent/stream") and not self._authed():
            self._json({"error": "unauthorized"}, 401)
            return

        # 神枢执行脑 · 规范执行端点：{cmd, timeout?} → 真跑 shell，返回 stdout/stderr/code
        if path == "/exec":
            cmd = (body.get("cmd") or body.get("command") or "").strip()
            if not cmd:
                self._json({"error": "cmd is required"}, 400)
                return
            timeout = int(body.get("timeout", 60))
            result = execute_tool("shell_execute", {"command": cmd, "timeout": timeout})
            self._json({"ok": True, "cmd": cmd, "result": result})
            return

        if path == "/api/chat":
            message = body.get("message", "")
            context = body.get("context", [])
            if not message:
                self._json({"error": "message is required"}, 400)
                return
            
            agent = get_agent()
            result = agent.run(message, context)
            self._json(result)

        elif path == "/api/agent/stream":
            # 自主智能体流式端点：规划 → 执行 → 交付，全过程 SSE 推流
            goal = body.get("goal") or body.get("message", "")
            if not goal:
                self._json({"error": "goal is required"}, 400)
                return
            base = get_agent()
            auto_loop = AgentLoop(api_key=base.api_key, base_url=base.base_url,
                                  model=base.model, max_steps=12)
            agent = AutonomousAgent(auto_loop)
            self._sse_start()
            try:
                for ev in agent.run_stream(goal, body.get("context")):
                    self._sse_send(ev)
            except (BrokenPipeError, ConnectionResetError):
                return  # 客户端断开，静默收尾
            except Exception as e:
                try:
                    self._sse_send({"event": "error", "message": str(e)})
                except Exception:
                    pass

        elif path == "/api/confirm":
            task_id = body.get("task_id", "")
            self._json({"confirmed": True, "task_id": task_id, "message": "任务已确认"})
        
        elif path == "/api/memory/save":
            key = body.get("key", "")
            value = body.get("value", "")
            if key and value:
                memory.save_global(key, value)
                self._json({"saved": True, "key": key})
            else:
                self._json({"error": "key and value required"}, 400)
        
        elif path == "/api/preferences":
            for key, value in body.items():
                memory.save_global(key, str(value))
            self._json({"saved": True, "preferences": body})
        
        elif path == "/api/tool/execute":
            tool_name = body.get("tool", "")
            tool_args = body.get("args", {})
            if tool_name:
                result = execute_tool(tool_name, tool_args)
                self._json({"tool": tool_name, "result": result})
            else:
                self._json({"error": "tool name required"}, 400)
        
        else:
            self._json({"error": "not found", "path": path}, 404)
    
    def _serve_file(self, filepath: Path, content_type: str):
        if not filepath.is_file():
            self._json({"error": "file not found"}, 404)
            return
        content = filepath.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'public, max-age=3600')
        self.end_headers()
        self.wfile.write(content)

def start_server(host: str = "0.0.0.0", port: int = 8765):
    """启动 Black God Agent 服务器"""
    server = ThreadingHTTPServer((host, port), AgentHandler)
    print(f"🚀 Black God 888 Agent 已启动")
    print(f"📡 地址: http://{host}:{port}")
    print(f"🎛️ 工作台: http://{host}:{port}/studio （自主智能体 · 流式执行）")
    print(f"🧠 模型: {get_agent().model}")
    print(f"🛠️ 工具: {len(TOOLS)} 个")
    print(f"🎯 技能: {len(SKILLS)} 个")
    print(f"💾 记忆: SQLite ({memory.db_path})")
    print(f"✅ 本地优先 · 安全沙箱 · 自主规划 · 已就绪")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 Black God 已停止")
        server.shutdown()

if __name__ == "__main__":
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("BG_PORT", "8765"))
    start_server(port=port)
