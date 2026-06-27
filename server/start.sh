#!/bin/bash
# Black God Agent 启动脚本
cd /opt/bg-agent
pkill -f "bg-agent/server.py" 2>/dev/null
sleep 1
export BG_KEY="sk-a21f3fd89a53a23eaa253781fa2b34c992c35cc285400d64bfb10d53f0ca6fdc"
export BG_BASE="https://apiclaude.cc/v1"
export BG_MODEL="claude-haiku-4-5-20251001"
export BG_PORT=8765
setsid python3 server.py > /tmp/bg-agent.log 2>&1 < /dev/null &
echo "启动 PID: $!"
sleep 3
echo "--- 日志 ---"
cat /tmp/bg-agent.log
echo "--- 端口 ---"
ss -lntp 2>/dev/null | grep 8765 || echo "未监听"
