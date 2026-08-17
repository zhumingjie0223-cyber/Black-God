# UI 收口归档（2026-08-09，权哥拍板）

权哥指令：「UI 合并为一个……做收口，版本确认，下次只有更新」。
自此**主界面 `web/nexus-do/index.html`（Black God）是唯一 UI**，今后 UI 只做更新，不再维护多副本/多入口。

## 归档清单（删除前核实结论）

| 文件 | 原路径 | 核实结论 |
|---|---|---|
| `studio.html` | `web/nexus-do/studio.html` | 工作台前端（神枢·自主智能体工作台）。其权威源 nexus-studio 已于更早归档；`/studio` 路由与 `/api/agent/stream` 端点在内核/worker/exec-brain 中均无实现，属孤儿前端 |
| `voice.html` | `web/voice.html` | 语音合成独立页，无路由服务、主界面无链接 |
| `dashboard.html` | `assets/dashboard/index.html` | 控制台独立页，无路由服务、主界面无链接 |
| `deploy-studio.yml` | `.github/workflows/deploy-studio.yml` | 只在 `web/nexus-studio/**` 变更时触发，该目录已不存在，属死工作流 |

另：过期部署配置 `web/nexus-do/wrangler.toml` 同日归档为 `docs/archive/wrangler.toml.2026-08-09.bak`
（生产权威配置是 `web/nexus-do/wrangler.jsonc`；CI 全部工作流核实无一引用 toml）。

## 回退方式

如需恢复任一页面，把对应文件移回原路径即可（git 历史完整保留）。
