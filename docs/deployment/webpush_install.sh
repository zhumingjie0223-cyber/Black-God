#!/usr/bin/env bash
# =============================================================
# Black God · Web Push 安全安装脚本（绝不弄丢文件版）
# 在你「已 clone 的 blackgod 仓库根目录」执行：
#   bash /解压目录/blackgod-webpush/install.sh
# 行为：覆盖任何同名文件前，先把原文件备份到 .bg_backup_时间戳/。
#       不 push（你自己用 token 推）。出问题可一键还原。
# =============================================================
set -e
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d .git ]; then
  echo "✗ 当前目录不是 git 仓库根目录。先 cd 进你的 blackgod 仓库再运行。"; exit 1
fi

STAMP=".bg_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$STAMP"
echo "→ 原文件将备份到: $STAMP/"

# 需要落地的文件清单： 源(相对包)  目标(相对仓库)
FILES="
web/index.html|web/index.html
web/sw.js|web/sw.js
web/push-client.js|web/push-client.js
web/manifest.json|web/manifest.json
web/icon-192.png|web/icon-192.png
web/icon-512.png|web/icon-512.png
server/server_push_example.py|server/server_push_example.py
server/server_sse_example.py|server/server_sse_example.py
server/requirements.txt|server/requirements.txt
server/vapid_private.pem|server/vapid_private.pem
README_WEBPUSH.md|README_WEBPUSH.md
"

OVERWRITTEN=""
echo "$FILES" | while IFS='|' read -r SRC DST; do
  [ -z "$SRC" ] && continue
  mkdir -p "$(dirname "$DST")"
  if [ -f "$DST" ]; then
    mkdir -p "$STAMP/$(dirname "$DST")"
    cp "$DST" "$STAMP/$DST"            # 先备份原文件
    echo "  备份并覆盖: $DST"
  else
    echo "  新增:        $DST"
  fi
  cp "$PKG/$SRC" "$DST"
done

# .gitignore 追加（不覆盖，只补缺失行）
touch .gitignore
for L in "server/vapid_private.pem" "server/vapid_keys.txt" "server/subscriptions.json" "server/subscriptions.json.tmp" "$STAMP/"; do
  grep -qxF "$L" .gitignore || echo "$L" >> .gitignore
done

echo ""
echo "✓ 完成。原文件都在 $STAMP/ 里，想还原就把里面的文件拷回去。"
echo ""
echo "建议先用 git 看清改动，满意再推："
echo "    git status"
echo "    git diff -- web/index.html server/server_sse_example.py"
echo "    git add web/ server/ README_WEBPUSH.md .gitignore"
echo "    git commit -m 'feat: 真·Web Push v3.2（iOS加固+声震弹）'"
echo "    git push origin main      # 用你自己的 token，别写进 URL"
echo ""
echo "不满意？两种还原："
echo "  A) 没 commit 过：cp -r $STAMP/* .   （把备份拷回去）"
echo "  B) commit 前用 git：git checkout -- <文件>"
