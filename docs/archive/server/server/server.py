#!/usr/bin/env python3
"""Black God 888 — 启动入口（调用 agent_kernel_v4）"""
import os
from pathlib import Path

# 添加当前目录到路径
ROOT = Path(__file__).resolve().parent
import sys
sys.path.insert(0, str(ROOT))

if __name__ == "__main__":
    # 加载 .env
    env_file = ROOT.parent / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding='utf-8', errors='replace').split('\n'):
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                os.environ.setdefault(k.strip(), v.strip())
    
    # 启动内核
    from agent_kernel_v4 import start_server
    port = int(os.environ.get("BG_PORT", "8765"))
    start_server(port=port)
