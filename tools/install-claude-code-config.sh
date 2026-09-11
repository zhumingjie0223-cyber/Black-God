#!/usr/bin/env bash
# 一键配置 Claude Code 走第三方网关（默认 apiclaude.cc）
# Mac 终端：bash tools/install-claude-code-config.sh
# 密钥放在同目录 claude-code.env.json（已 gitignore，勿提交）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${CLAUDE_CODE_ENV_FILE:-$ROOT/claude-code.env.json}"
SETTINGS="$HOME/.claude/settings.json"

if [[ -f "$ENV_FILE" ]]; then
  read -r BASE_URL AUTH_TOKEN <<< "$(python3 - "$ENV_FILE" << 'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("ANTHROPIC_BASE_URL", "https://apiclaude.cc"), d.get("ANTHROPIC_AUTH_TOKEN", ""))
PY
)"
else
  BASE_URL="${ANTHROPIC_BASE_URL:-https://apiclaude.cc}"
  AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"
fi

if [[ -z "$AUTH_TOKEN" ]]; then
  echo "✗ 缺少密钥。请创建 $ENV_FILE 或 export ANTHROPIC_AUTH_TOKEN=..." >&2
  exit 1
fi

echo "→ 安装 Claude Code（如未安装）…"
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
claude --version

echo "→ 写入 $SETTINGS …"
mkdir -p "$(dirname "$SETTINGS")"
python3 - "$SETTINGS" "$BASE_URL" "$AUTH_TOKEN" << 'PY'
import json, os, sys
path, base, token = sys.argv[1:4]
cfg = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
env = cfg.setdefault("env", {})
env["ANTHROPIC_BASE_URL"] = base
env["ANTHROPIC_AUTH_TOKEN"] = token
env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
env["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"
env.pop("ANTHROPIC_API_KEY", None)
# 审核宽松：少拒绝、少弹窗——自动接受改文件，常见读写/命令直接放行
perms = cfg.setdefault("permissions", {})
perms["defaultMode"] = "acceptEdits"
allow = set(perms.get("allow") or [])
allow.update([
    "Bash(*)",
    "Edit(*)",
    "Write(*)",
    "Read(*)",
    "Glob(*)",
    "Grep(*)",
    "WebFetch(*)",
])
perms["allow"] = sorted(allow)
perms.pop("disableAutoMode", None)
cfg.pop("disableBypassPermissionsMode", None)
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.chmod(path, 0o600)
print("  ✓ 已合并 env + 宽松审核（acceptEdits + allow 常见工具）")
PY

if [[ -f "$HOME/.zshrc" ]] && grep -q 'ANTHROPIC_API_KEY' "$HOME/.zshrc" 2>/dev/null; then
  echo "→ 从 ~/.zshrc 移除 ANTHROPIC_API_KEY …"
  grep -v 'ANTHROPIC_API_KEY' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
fi

echo ""
echo "完成。新开终端运行: claude"
echo "进去后 /status 应显示 Base URL = $BASE_URL"
