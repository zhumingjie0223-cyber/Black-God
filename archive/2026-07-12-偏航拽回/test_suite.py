#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Black God 完整测试套件 — 验证所有 API + 性能"""
import urllib.request, json, time

BASE = "http://127.0.0.1:8765"
results = []

def call(name, path, method="GET", data=None, timeout=20):
    url = BASE + path
    t0 = time.time()
    try:
        if method == "GET":
            req = urllib.request.Request(url)
        else:
            req = urllib.request.Request(url, data=json.dumps(data).encode(), method=method)
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode()
            code = r.status
        dt = (time.time() - t0) * 1000
        ok = code == 200
        results.append((name, ok, code, round(dt), body[:120]))
        return json.loads(body) if body.strip().startswith(("{", "[")) else body
    except Exception as e:
        dt = (time.time() - t0) * 1000
        results.append((name, False, "ERR", round(dt), str(e)[:120]))
        return None

print("=" * 60)
print("  🧪 Black God 完整测试套件")
print("=" * 60)

# GET 端点
stats = call("健康检查 /api/stats", "/api/stats")
call("分类 /api/categories", "/api/categories")
call("技能 /api/skills", "/api/skills")
call("任务 /api/tasks", "/api/tasks")
call("记忆 /api/memory", "/api/memory")
call("工具矩阵 /api/tool-matrix", "/api/tool-matrix")
call("能力 /api/capabilities", "/api/capabilities")
call("偏好 /api/preferences", "/api/preferences")
call("应用 /api/apps", "/api/apps")
call("健康 /api/health", "/api/health")

# 前端静态资源
call("首页 /", "/")
call("manifest /manifest.json", "/manifest.json")
call("theme /theme.css", "/theme.css")
call("图标 /icon-192.png", "/icon-192.png")

# POST 对话（核心链路）
chat = call("对话 /api/chat", "/api/chat", "POST", {"message": "你好，测试一下", "max_steps": 1}, timeout=30)

# 输出结果表
print("\n%-32s %-6s %-5s %-8s" % ("接口", "结果", "状态", "耗时(ms)"))
print("-" * 60)
passed = 0
for name, ok, code, dt, preview in results:
    flag = "✅PASS" if ok else "❌FAIL"
    if ok: passed += 1
    print("%-32s %-6s %-5s %-8s" % (name, flag, code, dt))

print("-" * 60)
print(f"\n总计: {passed}/{len(results)} 通过 ({round(passed/len(results)*100)}%)")

# 关键数据
if stats:
    print(f"\n📊 系统数据:")
    print(f"   版本: {stats.get('version')}")
    print(f"   任务: {stats.get('tasks', {}).get('total')} (完成 {stats.get('tasks', {}).get('completed')})")
    print(f"   记忆: {stats.get('memories', {}).get('total')}")

if chat:
    print(f"\n💬 对话测试:")
    print(f"   回复: {str(chat.get('answer', ''))[:80]}")
    print(f"   成功: {chat.get('success')}")
    print(f"   状态: {chat.get('status')}")

# 失败详情
fails = [(n, p) for n, ok, c, d, p in results if not ok]
if fails:
    print(f"\n⚠️ 失败详情:")
    for n, p in fails:
        print(f"   {n}: {p}")
