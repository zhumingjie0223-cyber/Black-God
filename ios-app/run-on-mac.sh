#!/usr/bin/env bash
# 在 Mac 上把「神枢 Black God」装到你自己的 iPhone —— 不上架、不花钱
# 只需一个免费 Apple ID(签名 7 天有效,过期再跑一次本脚本即可)。
#
# 前置条件:
#   1) 一台 Mac,已从 App Store 安装 Xcode(首次打开跑一次让它装好命令行组件)。
#   2) iPhone 用数据线连上 Mac,手机上点「信任此电脑」。
#   3) 在 Xcode → Settings → Accounts 里用你的 Apple ID 登录一次(免费账号即可)。
#
# 用法:
#   cd 到仓库,执行:  bash ios-app/run-on-mac.sh
#   若已知开发者 Team ID,可命令行直装:  DEV_TEAM=XXXXXXXXXX bash ios-app/run-on-mac.sh
#   (不填 DEV_TEAM 时会自动打开 Xcode,按屏幕提示点 3 下即可安装。)

set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"   # 进入 ios-app/

echo "==> 0/3 环境检查"
[ "$(uname)" = "Darwin" ] || { echo "✗ 本脚本必须在 macOS 上运行(iOS 只能在 Mac 上构建)。"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "✗ 未检测到 Xcode。请先从 App Store 安装 Xcode 并打开一次。"; exit 1; }
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then echo "  正在安装 xcodegen…"; brew install xcodegen;
  else echo "✗ 需要 xcodegen。请先装 Homebrew(https://brew.sh)后执行:brew install xcodegen"; exit 1; fi
fi

echo "==> 1/3 由 project.yml 生成 Xcode 工程"
xcodegen generate

if [ -n "${DEV_TEAM:-}" ]; then
  echo "==> 2/3 命令行自动签名并构建(Team=$DEV_TEAM)"
  # 找到第一台已连接的真机 iPhone 的 UDID(Xcode 15+ 的 devicectl)
  UDID="$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ {print $NF; exit}')" || true
  xcodebuild -project BlackGod888.xcodeproj -scheme BlackGod888 -configuration Debug \
    -destination "generic/platform=iOS" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEV_TEAM" CODE_SIGN_STYLE=Automatic \
    -derivedDataPath build clean build
  APP="$(/usr/bin/find build/Build/Products -maxdepth 2 -name '*.app' -type d | head -1)"
  echo "==> 3/3 安装到设备"
  if [ -n "${UDID:-}" ] && [ -n "${APP:-}" ]; then
    xcrun devicectl device install app --device "$UDID" "$APP"
    echo "✓ 已装到 iPhone($UDID)。首次运行需在 iPhone「设置 → 通用 → VPN与设备管理」里信任你的开发者证书。"
  else
    echo "⚠ 没自动找到已连接的 iPhone 或构建产物;改用 Xcode 手动安装:见下方提示。"
    open BlackGod888.xcodeproj
  fi
else
  echo "==> 2/3 打开 Xcode(未提供 DEV_TEAM,走图形界面安装,最稳)"
  open BlackGod888.xcodeproj
  cat <<'TIP'

==> 3/3 在 Xcode 里点 3 下即可装机:
   1) 左侧选中 BlackGod888 target → 顶部 Signing & Capabilities →
      勾选「Automatically manage signing」,Team 选你的 Apple ID(免费账号即可)。
      若报 bundle id 被占用,把 PRODUCT_BUNDLE_IDENTIFIER 改成独一无二的即可(自用随便改)。
   2) 顶部设备下拉,选中你那台已连线的 iPhone。
   3) 按 Cmd+R(或点 ▶︎)。装好后到 iPhone「设置 → 通用 → VPN与设备管理」信任开发者。
   ※ 免费 Apple ID 签名 7 天有效,过期把手机连上 Mac 再跑一次本脚本 / 再 Cmd+R 即可。
TIP
fi
