#!/bin/bash
# Black God Agent 启动脚本（干净版：key 走环境变量/.env，不硬编码）
cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"

# 加载同级或上级 .env（若存在）。.env 已被 .gitignore 挡住，不会进仓库。
for envf in "$ROOT/.env" "$ROOT/../.env"; do
  if [ -f "$envf" ]; then
    set -a; . "$envf"; set +a
    echo "已加载 $envf"
    break
  fi
done

# 默认网关（仅地址，无密钥）
: "${BG_BASE:=https://your-gateway.example/v1}"
: "${BG_MODEL:=gpt-5.5}"
: "${BG_PORT:=8765}"
export BG_BASE BG_MODEL BG_PORT

if [ -z "$BG_KEY" ]; then
  echo "⚠️  未检测到 BG_KEY。请在 .env 写入 BG_KEY=... 或 export BG_KEY 后再启动。"
fi

pkill -f "server.py" 2>/dev/null
sleep 1
setsid python3 server.py > /tmp/bg-agent.log 2>&1 < /dev/null &
echo "启动 PID: $!  端口: $BG_PORT  模型: $BG_MODEL"
sleep 3
echo "--- 日志 ---"
cat /tmp/bg-agent.log
echo "--- 端口 ---"
ss -lntp 2>/dev/null | grep "$BG_PORT" || echo "未监听"
