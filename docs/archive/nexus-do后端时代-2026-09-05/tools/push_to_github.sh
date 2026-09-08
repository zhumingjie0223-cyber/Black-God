#!/bin/sh
# Black God 推送到 GitHub 脚本

cd /var/minis/shared/blackgod/

echo "=== Black God GitHub 推送 ==="
echo ""

# 检查是否有未提交的更改
if [ -n "$(git status --porcelain)" ]; then
  echo "✓ 检测到未提交的更改，正在提交..."
  git add .
  git commit -m "Update: $(date +'%Y-%m-%d %H:%M:%S')"
fi

echo "✓ 本地改动已提交"
echo ""
echo "开始推送到 GitHub..."
echo ""

# 推送
git push -u origin main

if [ $? -eq 0 ]; then
  echo ""
  echo "🎉 推送成功！"
  echo ""
  echo "查看仓库: https://github.com/uumingtian-max/blackgod"
  echo ""
  
  # 显示最新提交
  echo "最新提交:"
  git log --oneline -3
else
  echo ""
  echo "❌ 推送失败"
  echo ""
  echo "可能原因:"
  echo "1. Token 权限不足（需要 repo 权限）"
  echo "2. Token 已过期"
  echo "3. 网络问题"
fi
