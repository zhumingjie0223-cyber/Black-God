# TODO · Claude Code 权限改最松 + 发布收尾

开工：2026-09-11
诉求：权哥反馈 acceptEdits「还是很紧」→ 改 bypassPermissions（YOLO）

## 步骤

- [ ] 1. 更新 `tools/install-claude-code-config.sh`：defaultMode=bypassPermissions + skipDangerousModePermissionPrompt
- [ ] 2. 同步 `tools/claude-code-settings.template.json`
- [ ] 3. 脚本顺带清理 `~/.claude/settings.local.json` 里的 deny/ask 历史规则
- [ ] 4. 提交推送，给权哥 Mac 一键命令

## 发布（原任务，未变）

- [ ] 8b. Mac 上传 1.2.0 (8)
- [ ] 9. ASC 密钥 + asc.py 提审链
