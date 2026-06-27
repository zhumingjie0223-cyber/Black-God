#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God Agent —— 强力工具层（Agent 的真实"手"）
让 Agent 能跑 Shell / Python / 操作文件 / 上网 / 自装工具。
这些是 Agent 真正能干活的能力，不是玩具。
"""
import subprocess, os, re, json, time, urllib.request, urllib.parse, pathlib

WORKSPACE = pathlib.Path(os.environ.get("BG_WORKSPACE", "/tmp/bg_agent_work"))
WORKSPACE.mkdir(parents=True, exist_ok=True)

# ============ 真正能干活的工具 ============

def t_shell(a):
    """跑任意 Shell 命令"""
    cmd = a.get("command", "")
    if not cmd: return "缺少 command"
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                           timeout=a.get("timeout", 60), cwd=str(WORKSPACE))
        out = (r.stdout or "") + (("\n[stderr]\n" + r.stderr) if r.stderr else "")
        return (out.strip() or "(无输出)")[:3000] + (f"\n[退出码:{r.returncode}]" if r.returncode else "")
    except subprocess.TimeoutExpired:
        return "命令超时"
    except Exception as e:
        return f"执行出错:{e}"

def t_python(a):
    """写 Python 代码当场跑"""
    code = a.get("code", "")
    if not code: return "缺少 code"
    f = WORKSPACE / f"_run_{int(time.time()*1000)}.py"
    f.write_text(code, encoding="utf-8")
    try:
        r = subprocess.run(["python3", str(f)], capture_output=True, text=True,
                           timeout=a.get("timeout", 60), cwd=str(WORKSPACE))
        out = (r.stdout or "") + (("\n[stderr]\n" + r.stderr) if r.stderr else "")
        return (out.strip() or "(无输出)")[:3000]
    except subprocess.TimeoutExpired:
        return "代码超时"
    except Exception as e:
        return f"运行出错:{e}"
    finally:
        try: f.unlink()
        except: pass

def t_write_file(a):
    """写文件"""
    path, content = a.get("path", ""), a.get("content", "")
    if not path: return "缺少 path"
    p = WORKSPACE / path if not os.path.isabs(path) else pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return f"已写入 {p}（{len(content)} 字符）"

def t_read_file(a):
    """读文件"""
    path = a.get("path", "")
    p = WORKSPACE / path if not os.path.isabs(path) else pathlib.Path(path)
    if not p.exists(): return f"文件不存在:{p}"
    return p.read_text(encoding="utf-8", errors="ignore")[:3000]

def t_install(a):
    """自己装工具：apk / pip"""
    pkg = a.get("package", "")
    mgr = a.get("manager", "pip")  # pip 或 apk
    if not pkg: return "缺少 package"
    cmd = f"pip install {pkg}" if mgr == "pip" else f"apk add {pkg}"
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=180)
    return f"[{mgr} {pkg}] " + ((r.stdout or "") + (r.stderr or ""))[-500:]

def t_web_search(a):
    q = a.get("query", "")
    try:
        u = "https://api.duckduckgo.com/?q=" + urllib.parse.quote(q) + "&format=json&no_html=1"
        with urllib.request.urlopen(u, timeout=20) as r:
            j = json.load(r)
        out = []
        if j.get("AbstractText"): out.append(j["AbstractText"])
        for t in (j.get("RelatedTopics") or [])[:6]:
            if t.get("Text"): out.append("• " + t["Text"])
        return "\n".join(out) or "无结果，建议用 fetch_url 抓具体网页"
    except Exception as e:
        return f"搜索失败:{e}"

def t_fetch_url(a):
    url = a.get("url", "")
    if not url: return "缺少 url"
    try:
        with urllib.request.urlopen("https://r.jina.ai/" + url, timeout=30) as r:
            return r.read().decode("utf-8", "ignore")[:3000]
    except Exception as e:
        return f"抓取失败:{e}"

def t_calc(a):
    e = a.get("expression", "")
    if not re.match(r"^[\d\s+\-*/().,%]+$", e): return "非法表达式"
    try: return str(eval(e, {"__builtins__": {}}))
    except Exception as ex: return f"计算错误:{ex}"

def t_time(a):
    return time.strftime("%Y-%m-%d %H:%M:%S")

# 工具注册表：name -> (描述, 函数, anthropic_schema)
POWER_TOOLS = {
    "shell": ("跑任意 Shell 命令（Linux）", t_shell,
        {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}),
    "python": ("写 Python 代码并执行", t_python,
        {"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]}),
    "write_file": ("写文件", t_write_file,
        {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}),
    "read_file": ("读文件", t_read_file,
        {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}),
    "install": ("自己装工具包 pip/apk", t_install,
        {"type": "object", "properties": {"package": {"type": "string"}, "manager": {"type": "string"}}, "required": ["package"]}),
    "web_search": ("联网搜索", t_web_search,
        {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}),
    "fetch_url": ("抓取网页正文", t_fetch_url,
        {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}),
    "calculator": ("数学计算", t_calc,
        {"type": "object", "properties": {"expression": {"type": "string"}}, "required": ["expression"]}),
    "get_time": ("当前时间", t_time, {"type": "object", "properties": {}}),
}

def anthropic_schemas():
    return [{"name": n, "description": d, "input_schema": s} for n, (d, f, s) in POWER_TOOLS.items()]

def exec_tool(name, args):
    item = POWER_TOOLS.get(name)
    if not item: return f"未知工具:{name}"
    return item[1](args or {})

if __name__ == "__main__":
    # 自检：每个工具真跑一遍
    print("═" * 50, "\n强力工具层自检\n", "═" * 50)
    print("[shell] ls:", exec_tool("shell", {"command": "echo hello && uname"})[:60])
    print("[python]:", exec_tool("python", {"code": "print(sum(range(101)))"}))
    print("[write]:", exec_tool("write_file", {"path": "t.txt", "content": "test"}))
    print("[read]:", exec_tool("read_file", {"path": "t.txt"}))
    print("[calc]:", exec_tool("calculator", {"expression": "999*999"}))
    print("[time]:", exec_tool("get_time", {}))
    print(f"\n✅ 共 {len(POWER_TOOLS)} 个强力工具就绪")
