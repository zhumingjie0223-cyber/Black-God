# Black God · v3.1 升级说明（Obsidian Chrome）

> 冷铬/银灰重写 + Agent 执行可视化 + 后台任务通知 + 首次本地引导 + 品牌独立 + 金属图标。

## 一、本次全部改动

**配色：黑金 → 冷铬/银灰（对齐「神」字 Logo 金属质感）**
品牌用银灰金属渐变；状态色独立管理（🟢成功/🔵进行中/🔴失败/🟡警告），集中在 CSS 顶部变量。

**Agent 能力**
- 实时执行时间线（工具名 + 转圈→✓/✕ + 详情，SSE 流式）
- 输入区：能力芯片（联网/深度思考/代码/命令/看图）+ 📎上传 + 🎙语音
- 消息操作：复制 / 重新生成 / 分享

**新增 · 后台任务通知（求稳）**
- 完成 / 失败 / 需确认 都会弹**系统通知**（无权限自动退回应用内提示）
- **危险操作确认弹窗**：执行命令等敏感动作前，横幅 + 通知等你「允许/拒绝」
- **断线/刷新可恢复**：任务登记在本地，回到前台自动对账 `/api/tasks` 并补发通知
- 「我的 → 任务通知」开关可关；首次引导结束时征求通知权限

**新增 · 首次使用引导（仅本地，绝不上云）**
- 6 步向导收集：称呼 / 身份 / 关注领域 / 活跃时段 / 沟通风格
- 全部写入本地 `localStorage`，并自动灌入人格 + 记忆，让"懂你"立即生效
- 「我的」页有「关于你 · 🔒 仅本地保存」卡片，可随时编辑/清除
- 每次对话把画像随请求带给后端（字段 `userProfile`），不经任何第三方

**品牌独立**
- 移除全部第三方模型名（Claude/GPT/DeepSeek/Legend/OpenAI），改为自有命名：
  Auto 智能路由 / 主脑 Core / 深思 Deep / 疾风 Swift / 轻羽 Lite

**砍掉的画蛇添足**
- 常驻动画粒子（耗电）→ 静态金属渐晕 + 噪点
- Google 字体 Cinzel（渲染不了中文、国内慢）→ 系统字 + CSS 金属浮雕
- 全局禁选 → 解除，消息可复制

**新增 · 金属质感图标**
- `icon-512.png` / `icon-192.png`：黑曜石底 + 冷铬「神」字浮雕，PWA 装桌面用

## 二、文件清单

| 下载的文件 | 放到仓库 |
|---|---|
| `index.html` | `web/index.html` |
| `manifest.json` | `web/manifest.json` |
| `sw.js` | `web/sw.js` |
| `icon-512.png` | `web/icon-512.png` |
| `icon-192.png` | `web/icon-192.png`（覆盖旧的） |
| `server_sse_example.py` | `server/`（参考接入） |
| `UPGRADE_v3.0.md` | 仓库根目录（记录） |

## 三、本地验证

```bash
cd web && python3 -m http.server 8765
# 打开 http://localhost:8765；第一次会走引导，后端没接也能看全部效果
```

## 四、接口接入

- **同源直读（默认）**：前端直调本机 `/api/chat`、`/api/stats`、`/api/tasks`、`/api/confirm`。
- **外接网关**：App 内「我的 → 接口设置」填 Base URL + Key（标准 Chat 接口）。
- **执行可视化 + 确认**：后端 `/api/chat` 按 `server_sse_example.py` 吐 SSE
  （`step / token / confirm / done`），确认走 `POST /api/confirm {id, approve}`。
- **任务通知**：`/api/tasks` 每条带 `{task_id, status}`，前端对账后补发通知。
- Nginx 反代加 `proxy_buffering off;`。

## 五、推送到 GitHub（你自己来，别再贴 token）

```bash
cd blackgod
cp ~/Downloads/index.html      web/index.html
cp ~/Downloads/manifest.json   web/manifest.json
cp ~/Downloads/sw.js           web/sw.js
cp ~/Downloads/icon-512.png    web/icon-512.png
cp ~/Downloads/icon-192.png    web/icon-192.png
mkdir -p server && cp ~/Downloads/server_sse_example.py server/
cp ~/Downloads/UPGRADE_v3.0.md ./

git add web/ server/ UPGRADE_v3.0.md
git commit -m "feat: Obsidian Chrome v3.1 — 执行可视化/后台通知/本地引导/品牌独立/金属图标"
git push
```

`git push` 弹登录：用户名 `uumingtian-max`，密码栏粘**新 token**（只进钥匙串，不留痕）。
或先 `gh auth login` 一次，以后免 token。
