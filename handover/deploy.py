#!/usr/bin/env python3
"""部署 nexus 到 CF Workers，multipart 上传三文件 + metadata（含所有secret/binding）"""
import requests, os, sys, json

TOKEN = open('/var/minis/shared/CF_TOKEN_LUFEI_UK.txt').read().strip()
ACCT = "<CF_ACCOUNT_ID_ENV>"
SCRIPT = "nexus"

BASE = f"https://api.cloudflare.com/client/v4/accounts/{ACCT}/workers/scripts/{SCRIPT}"

files_dir = "/var/minis/workspace/nexus_patch"

# 新 TG bot（权哥的 <TG_BOT_USERNAME>，路飞技术服务）
TG_BOT_TOKEN = "<TG_BOT_TOKEN_ENV>"
TG_QUAN_CHAT_ID = "<QUAN_TG_CHAT_ID_ENV>"

# metadata 必须列全所有 bindings + secrets，漏一个运行时读不到
metadata = {
    "main_module": "nexus.mjs",
    "compatibility_date": "2024-11-01",
    "bindings": [
        {"type": "ai", "name": "AI"},
        {"type": "kv_namespace", "name": "SOUL", "namespace_id": "<CF_KV_NAMESPACE_ID_ENV>"},
        # 保留原有 secrets
        {"type": "inherit", "name": "APICLAUDE_KEY"},
        {"type": "inherit", "name": "HANDS_SECRET"},
        {"type": "inherit", "name": "HANDS_TUNNEL_URL"},
        # 新增：TG 主动推送用
        {"type": "secret_text", "name": "TG_BOT_TOKEN", "text": TG_BOT_TOKEN},
        {"type": "secret_text", "name": "TG_QUAN_CHAT_ID", "text": TG_QUAN_CHAT_ID},
    ],
}

files = {
    "metadata": (None, json.dumps(metadata), "application/json"),
    "nexus.mjs": ("nexus.mjs", open(f"{files_dir}/nexus.mjs","rb").read(), "application/javascript+module"),
    "lexicon.js": ("lexicon.js", open(f"{files_dir}/lexicon.js","rb").read(), "application/javascript+module"),
    "lexicon_data.js": ("lexicon_data.js", open(f"{files_dir}/lexicon_data.js","rb").read(), "application/javascript+module"),
}

headers = {"Authorization": f"Bearer {TOKEN}"}
print("上传中...")
r = requests.put(BASE, headers=headers, files=files, timeout=60)
print(f"HTTP {r.status_code}")
try:
    j = r.json()
    if j.get("success"):
        print(f"✅ 部署成功 deployment_id={j['result'].get('deployment_id','')}")
    else:
        print(json.dumps(j, indent=2, ensure_ascii=False)[:2000])
except:
    print(r.text[:1000])

# 配置 Cron trigger（每5分钟触发心跳）
print("\n配置 Cron trigger...")
cron_r = requests.put(
    f"{BASE}/schedules",
    headers={**headers, "Content-Type": "application/json"},
    data=json.dumps([{"cron": "*/5 * * * *"}]),
    timeout=15,
)
print(f"Cron HTTP {cron_r.status_code}: {cron_r.text[:300]}")

