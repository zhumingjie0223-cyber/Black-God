#!/usr/bin/env bash
# 一键配置 Claude Code 走第三方网关（默认 apiclaude.cc）+ 最松权限（bypassPermissions）
# Mac 终端：bash tools/install-claude-code-config.sh
# 密钥放在同目录 claude-code.env.json（已 gitignore，勿提交）
#
# 权限模式（环境变量 PERMISSION_MODE，默认 bypassPermissions）：
#   bypassPermissions — 几乎不弹窗（仅 rm -rf / 等熔断 + 显式 ask 规则）
#   auto              — 分类器后台放行，比 acceptEdits 松，比 bypass 稍严
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${CLAUDE_CODE_ENV_FILE:-$ROOT/claude-code.env.json}"
SETTINGS="$HOME/.claude/settings.json"
LOCAL_SETTINGS="$HOME/.claude/settings.local.json"
PERMISSION_MODE="${PERMISSION_MODE:-bypassPermissions}"

if [[ "$PERMISSION_MODE" != "bypassPermissions" && "$PERMISSION_MODE" != "auto" ]]; then
  echo "✗ PERMISSION_MODE 只能是 bypassPermissions 或 auto，当前: $PERMISSION_MODE" >&2
  exit 1
fi

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

echo "→ 写入 $SETTINGS （权限模式: $PERMISSION_MODE）…"
mkdir -p "$(dirname "$SETTINGS")"
python3 - "$SETTINGS" "$BASE_URL" "$AUTH_TOKEN" "$PERMISSION_MODE" << 'PY'
import json, os, sys
path, base, token, mode = sys.argv[1:5]
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
perms = cfg.setdefault("permissions", {})
perms["defaultMode"] = mode
# bypass 模式下 allow 白名单无意义；auto 模式保留常见工具加速放行
if mode == "auto":
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
else:
    perms.pop("allow", None)
# 清掉可能锁死模式的开关
perms.pop("disableAutoMode", None)
perms.pop("disableBypassPermissionsMode", None)
cfg.pop("disableBypassPermissionsMode", None)
# 最松：跳过启动时「危险模式」二次确认（仅用户级 settings 生效）
if mode == "bypassPermissions":
    cfg["skipDangerousModePermissionPrompt"] = True
else:
    cfg.pop("skipDangerousModePermissionPrompt", None)
cfg["model"] = "fable"
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.chmod(path, 0o600)
print(f"  ✓ 已合并 env + 权限模式 {mode}")
PY

echo "→ 清理 $LOCAL_SETTINGS 里可能拖后腿的 deny/ask …"
python3 - "$LOCAL_SETTINGS" << 'PY'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    print("  （无 local 文件，跳过）")
    raise SystemExit(0)
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
changed = False
perms = cfg.get("permissions")
if isinstance(perms, dict):
    for key in ("deny", "ask"):
        if perms.pop(key, None):
            changed = True
            print(f"  ✓ 已移除 permissions.{key}")
    if not perms:
        cfg.pop("permissions", None)
        changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("  ✓ settings.local.json 已更新")
else:
    print("  （无需改动）")
PY

if [[ -f "$HOME/.zshrc" ]] && grep -q 'ANTHROPIC_API_KEY' "$HOME/.zshrc" 2>/dev/null; then
  echo "→ 从 ~/.zshrc 移除 ANTHROPIC_API_KEY …"
  grep -v 'ANTHROPIC_API_KEY' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
fi

echo ""
echo "完成。新开终端运行: claude"
echo "进去后 /status 应显示 Base URL = $BASE_URL"
if [[ "$PERMISSION_MODE" == "bypassPermissions" ]]; then
  echo "权限：bypassPermissions（最松，日常命令基本不弹窗）"
else
  echo "权限：auto（较松；若要更松: PERMISSION_MODE=bypassPermissions bash $0）"
fi
