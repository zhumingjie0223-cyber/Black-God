#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God Agent —— 重型工具层（更狠的手）
浏览器自动化 / SSH 远程 / 图像识别 / 定时任务
依赖：minis-browser-use, ssh+sshpass, apple-vision, crontab
"""
import subprocess, json, os, shlex

def _run(cmd, timeout=90):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return ((r.stdout or "") + (("\n[err]" + r.stderr) if r.stderr else "")).strip()
    except subprocess.TimeoutExpired:
        return "超时"
    except Exception as e:
        return f"出错:{e}"

# ============ 浏览器自动化 ============
def _extract_text(raw):
    """从 minis-browser-use 的 JSON 输出里挖出纯文本"""
    try:
        j = json.loads(raw)
        d = j.get("data", j)
        if isinstance(d, dict):
            return d.get("text") or d.get("content") or d.get("title") or json.dumps(d, ensure_ascii=False)[:800]
        return str(d)
    except:
        return raw

def t_browser(a):
    """浏览器操作：navigate/screenshot/get_text/click/type。
    navigate 后自动抓标题+正文纯文本返回。"""
    action = a.get("action", "navigate")
    parts = [f"minis-browser-use {shlex.quote(action)}"]
    for k in ("url", "selector", "text"):
        if a.get(k):
            parts.append(f"--{k} {shlex.quote(str(a[k]))}")
    parts.append("--tool_title Agent浏览器操作")
    out = _run(" ".join(parts), timeout=120)
    if action == "navigate":
        title = ""
        try: title = json.loads(out).get("data", {}).get("title", "")
        except: pass
        txt_raw = _run("minis-browser-use get_text --tool_title 抓正文", timeout=60)
        txt = _extract_text(txt_raw)
        return f"页面标题: {title}\n页面正文:\n{txt[:1500]}"
    return _extract_text(out)[:3000]

# ============ SSH 远程执行 ============
def t_ssh(a):
    """SSH 到远程机器执行命令。args: host, user, password, command"""
    host = a.get("host", ""); user = a.get("user", "root")
    pw = a.get("password", ""); cmd = a.get("command", "")
    if not host or not cmd: return "缺少 host 或 command"
    base = f"ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 {user}@{host} {shlex.quote(cmd)}"
    full = f"sshpass -p {shlex.quote(pw)} {base}" if pw else base
    return _run(full, timeout=90)[:3000]

# ============ 图像识别（Apple Vision）============
def t_vision(a):
    """识别图片：ocr/classify/barcode/analyze。args: path, mode"""
    path = a.get("path", ""); mode = a.get("mode", "ocr")
    if not path: return "缺少 path"
    if not os.path.exists(path): return f"图片不存在:{path}"
    out = _run(f"apple-vision {shlex.quote(mode)} {shlex.quote(path)} --compact", timeout=60)
    return out[:2000]

# ============ 定时任务 ============
def t_schedule(a):
    """加定时任务（crontab）。args: schedule(cron表达式), command
    ⚠️ iOS 限制：app 挂起即停，仅前台运行时有效。"""
    sched = a.get("schedule", ""); cmd = a.get("command", "")
    if not sched or not cmd: return "缺少 schedule 或 command"
    # 读现有 + 追加
    cur = _run("crontab -l 2>/dev/null")
    cur = "" if "no crontab" in cur.lower() or "出错" in cur else cur
    new = (cur + f"\n{sched} {cmd}\n").strip()
    tmp = "/tmp/_bg_cron"
    open(tmp, "w").write(new + "\n")
    res = _run(f"crontab {tmp}")
    return f"已加定时任务: {sched} {cmd}\n⚠️ iOS 限制：仅 app 前台运行时执行。长期任务建议用 Apple Shortcuts。\n{res}"

# 重型工具注册：name -> (描述, 函数, schema)
HEAVY_TOOLS = {
    "browser": ("浏览器自动化(navigate/screenshot/get_text/click/type)", t_browser,
        {"type": "object", "properties": {
            "action": {"type": "string", "description": "navigate/screenshot/get_text/click/type"},
            "url": {"type": "string"}, "selector": {"type": "string"}, "text": {"type": "string"}},
         "required": ["action"]}),
    "ssh": ("SSH远程执行命令", t_ssh,
        {"type": "object", "properties": {
            "host": {"type": "string"}, "user": {"type": "string"},
            "password": {"type": "string"}, "command": {"type": "string"}},
         "required": ["host", "command"]}),
    "vision": ("图像识别(ocr/classify/barcode/analyze)", t_vision,
        {"type": "object", "properties": {
            "path": {"type": "string"}, "mode": {"type": "string"}},
         "required": ["path"]}),
    "schedule": ("加定时任务(cron，iOS有限制)", t_schedule,
        {"type": "object", "properties": {
            "schedule": {"type": "string"}, "command": {"type": "string"}},
         "required": ["schedule", "command"]}),
}

def exec_heavy(name, args):
    item = HEAVY_TOOLS.get(name)
    return item[1](args or {}) if item else f"未知:{name}"

if __name__ == "__main__":
    print("═"*50, "\n重型工具层自检\n", "═"*50)
    # 浏览器：抓个简单页面
    print("[browser navigate example.com]:")
    print("  ", t_browser({"action": "navigate", "url": "https://example.com"})[:120])
    # 图像识别：找张图测
    print(f"\n✅ 共 {len(HEAVY_TOOLS)} 个重型工具就绪: {list(HEAVY_TOOLS)}")
