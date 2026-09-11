#!/usr/bin/env bash
# 一键配置 Claude Code：第三方网关 + 最松权限 + 清掉历史 deny（静默拒绝元凶）
# Mac：bash tools/install-claude-code-config.sh
# 只清拒绝规则、不动密钥：SWEEP_ONLY=1 bash tools/install-claude-code-config.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${CLAUDE_CODE_ENV_FILE:-$ROOT/claude-code.env.json}"
SETTINGS="$HOME/.claude/settings.json"
USER_LOCAL="$HOME/.claude/settings.local.json"
CLAUDE_JSON="$HOME/.claude.json"
PERMISSION_MODE="${PERMISSION_MODE:-bypassPermissions}"
SWEEP_ONLY="${SWEEP_ONLY:-0}"

if [[ "$PERMISSION_MODE" != "bypassPermissions" && "$PERMISSION_MODE" != "auto" ]]; then
  echo "✗ PERMISSION_MODE 只能是 bypassPermissions 或 auto" >&2
  exit 1
fi

# ── 共用：扫并清 permissions.deny / ask（deny 优先级最高，会静默拒绝）──
run_permission_sweep() {
  python3 - "$SETTINGS" "$USER_LOCAL" "$CLAUDE_JSON" "$ROOT" << 'PY'
import json, os, subprocess, sys

settings, user_local, claude_json, script_root = sys.argv[1:5]
home = os.path.expanduser("~")
ALLOW_ALL = sorted([
    "Bash(*)", "Edit(*)", "Write(*)", "Read(*)", "Glob(*)", "Grep(*)",
    "WebFetch(*)", "Agent(*)", "NotebookEdit(*)", "Task(*)", "WebSearch(*)",
])

def strip_permissions(cfg, label):
    changed = False
    perms = cfg.get("permissions")
    if not isinstance(perms, dict):
        return changed
    for key in ("deny", "ask"):
        if perms.pop(key, None):
            print(f"  ✓ [{label}] 已删 permissions.{key}")
            changed = True
    mode = perms.get("defaultMode")
    if mode in ("dontAsk", "default", "plan", "manual"):
        perms["defaultMode"] = "bypassPermissions"
        print(f"  ✓ [{label}] defaultMode {mode} → bypassPermissions")
        changed = True
    return changed

def write_json(path, cfg):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if path.startswith(home + "/.claude"):
        os.chmod(path, 0o600)

def clean_file(path, label):
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    if strip_permissions(cfg, label):
        perms = cfg.get("permissions")
        if isinstance(perms, dict) and not perms:
            cfg.pop("permissions", None)
        write_json(path, cfg)
        print(f"  ✓ 已写回 {path}")

def walk_claude_json(obj, prefix=""):
    if isinstance(obj, dict):
        perms = obj.get("permissions")
        if isinstance(perms, dict) and (perms.pop("deny", None) or perms.pop("ask", None)):
            print(f"  ✓ [~/.claude.json{prefix}] 已删 deny/ask")
        for k, v in obj.items():
            walk_claude_json(v, f"{prefix}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk_claude_json(v, f"{prefix}[{i}]")

print("→ 清理用户级与全局配置里的 deny/ask …")
clean_file(settings, "user settings")
clean_file(user_local, "user local")

if os.path.isfile(claude_json):
    with open(claude_json, encoding="utf-8") as f:
        cj = json.load(f)
    before = json.dumps(cj, sort_keys=True)
    walk_claude_json(cj)
    if json.dumps(cj, sort_keys=True) != before:
        write_json(claude_json, cj)
        print("  ✓ ~/.claude.json 已更新")
else:
    print("  （无 ~/.claude.json）")

print("→ 扫描各仓库 .claude/settings*.json …")
scan_roots = {home, os.path.join(home, "src"), os.path.join(home, "Documents"),
              os.path.join(home, "Documents", "Codex"), script_root}
try:
    top = subprocess.check_output(
        ["git", "-C", script_root, "rev-parse", "--show-toplevel"],
        stderr=subprocess.DEVNULL, text=True,
    ).strip()
    scan_roots.add(top)
except Exception:
    pass

seen = set()
for base in sorted(scan_roots):
    if not os.path.isdir(base):
        continue
    for dirpath, dirnames, filenames in os.walk(base):
        depth = dirpath[len(base):].count(os.sep)
        if depth > 8:
            dirnames.clear()
            continue
        if ".claude" not in dirnames:
            continue
        cdir = os.path.join(dirpath, ".claude")
        for name in ("settings.local.json", "settings.json"):
            p = os.path.join(cdir, name)
            if p in seen or not os.path.isfile(p):
                continue
            seen.add(p)
            with open(p, encoding="utf-8") as f:
                cfg = json.load(f)
            label = p.replace(home, "~")
            if strip_permissions(cfg, label):
                perms = cfg.get("permissions")
                if isinstance(perms, dict) and not perms:
                    cfg.pop("permissions", None)
                write_json(p, cfg)
                print(f"  ✓ 已写回 {label}")

print("→ 完成权限清扫")
PY
}

run_permission_sweep

if [[ "$SWEEP_ONLY" == "1" ]]; then
  echo ""
  echo "清扫完成（SWEEP_ONLY）。请完全退出 Claude Code 后重开，进 /permissions 确认无 Deny 规则。"
  exit 0
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

echo "→ 写入 $SETTINGS …"
mkdir -p "$(dirname "$SETTINGS")"
python3 - "$SETTINGS" "$BASE_URL" "$AUTH_TOKEN" "$PERMISSION_MODE" << 'PY'
import json, os, sys
path, base, token, mode = sys.argv[1:5]
ALLOW_ALL = sorted([
    "Bash(*)", "Edit(*)", "Write(*)", "Read(*)", "Glob(*)", "Grep(*)",
    "WebFetch(*)", "Agent(*)", "NotebookEdit(*)", "Task(*)", "WebSearch(*)",
])
cfg = json.load(open(path)) if os.path.exists(path) else {}
env = cfg.setdefault("env", {})
env.update({
    "ANTHROPIC_BASE_URL": base,
    "ANTHROPIC_AUTH_TOKEN": token,
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
})
env.pop("ANTHROPIC_API_KEY", None)
perms = cfg.setdefault("permissions", {})
perms["defaultMode"] = mode
perms.pop("deny", None)
perms.pop("ask", None)
perms["allow"] = ALLOW_ALL
perms.pop("disableAutoMode", None)
perms.pop("disableBypassPermissionsMode", None)
cfg.pop("disableBypassPermissionsMode", None)
cfg["sandbox"] = {"enabled": False}
if mode == "bypassPermissions":
    cfg["skipDangerousModePermissionPrompt"] = True
else:
    cfg.pop("skipDangerousModePermissionPrompt", None)
    cfg["autoMode"] = {"allow": ["Allow all tool use"], "soft_deny": [], "hard_deny": []}
cfg["model"] = "fable"
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.chmod(path, 0o600)
print(f"  ✓ env + {mode} + allow 全开 + sandbox 关")
PY

# zsh 别名：双保险，CLI 层也跳过权限
MARK="# claude-code-yolo"
ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  if ! grep -q "$MARK" "$ZSHRC" 2>/dev/null; then
    echo "→ 写入 ~/.zshrc 别名 claude-yolo …"
    cat >> "$ZSHRC" << 'EOF'

# claude-code-yolo — 最松启动，与 settings.json bypassPermissions 叠加
alias claude-yolo='claude --dangerously-skip-permissions'
EOF
  fi
  if grep -q 'ANTHROPIC_API_KEY' "$ZSHRC" 2>/dev/null; then
    echo "→ 从 ~/.zshrc 移除 ANTHROPIC_API_KEY …"
    grep -v 'ANTHROPIC_API_KEY' "$ZSHRC" > "$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"
  fi
fi

echo ""
echo "完成。请："
echo "  1. 完全退出 Claude Code（Cmd+Q），新开终端"
echo "  2. 运行 claude-yolo  或  claude"
echo "  3. 输入 /permissions —— 列表里不应再有 Deny 行"
echo "  4. /status 确认 Permission mode = bypassPermissions"
echo ""
echo "若仍显示「请求被拒绝」且是 API 报错（非工具权限），那是网关内容审核，与权限无关。"
