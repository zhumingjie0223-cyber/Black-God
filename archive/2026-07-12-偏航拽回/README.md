# 归档:2026-07-12 偏航拽回

> 按铁律「先备份/归档再删除」执行:本目录内容**一件没删**,只是从主线挪开。
> 要找回任何东西:直接从本目录拷回,或 `git log --follow <文件>` 查完整历史。

## 为什么归档

CLAUDE.md 铁律:**神枢架构是纯 Cloudflare Workers,不用 VPS**。
但主线上逐渐堆入了一条 VPS 服务器技术线和大量阶段性规划文档,把
`web/nexus-do/`(真正的神枢大脑)淹没了。权哥 2026-07-12 指令「跑偏的仓库拽回来」,
故将偏航内容整体归档,主线回归 Workers。

## 归档清单

### VPS 服务器线(与纯 Workers 铁律冲突)
| 内容 | 说明 |
|---|---|
| `server/` | Python 服务端全家桶:gateway、shenshu 路由、agent_kernel_v4、exec_brain、MCP 子系统、bolt.new Builder 融合模块 |
| `mock_gateway.py` | 本地模拟网关 |
| `test_suite.py` | 针对 `127.0.0.1:8765` 本地服务器的 API 测试套件 |
| `Dockerfile` / `docker-compose.yml` | 服务器容器化部署 |
| `push_to_github.sh` | 旧推送脚本 |

注:main 顶上那对「纠正→Revert」拉扯提交(9a44b72/26aac9c)改的就是这里的
`server/core/gateway.py`——归档后这条线整体冻结,不再有拉扯。

### 逆向工程与交接归档
| 内容 | 说明 |
|---|---|
| `research/` | 2026-07-12 全平台逆向工程归档(无密钥) |
| `handover/` | 完整交接文档 |

### 偏航期规划/报告文档(根目录清淤)
AGENT_KERNEL_WHITEPAPER、ARCHITECTURE(英文 VPS 愿景版)、
BLACK_GOD_FUSION_KERNEL_COMPLETE、BLACK_GOD_INTERNAL_KERNEL_REPORT、
CLAUDE_AGENT_FULL_CAPABILITIES、CLAUDE_REVIEW_PROMPT、CLOSURE_PLAN(私人版收口)、
FABLE5_INTEGRATION_TASK、FOUR_AGENTS_CORE_FUSION、MERGE_PLAN / README_MERGE
(与起航/Minis 合并方案)、OPTIMIZATION_DESIGN、PRIVATE_RETROSPECTIVE_AND_UPGRADE_PLAN、
PROJECT_ANALYSIS_REPORT。

## 没被归档的(主线,在原处)

- `web/nexus-do/` 神枢大脑(Workers Durable Object)与全部前端
- `docs/`(含移入 docs/product/ 的核心哲学、设计纲领 v2、上线清单)
- 品牌资产 `brand/`、`assets/`、iOS/安卓壳、根 README/CLAUDE/项目介绍

## 已按权哥指令请回主线的部分

- `server/shenshu/`(分档路由器)——2026-07-12 权哥明确点名开发 router_v2,
  该子目录已移回仓库根 `server/shenshu/`,不再属于本归档。其余内容维持冻结。

## 如果哪天要重启服务器线

先跟权哥确认解除「纯 Workers」铁律,再把 `server/` 拷回根目录即可,
代码原样未动。UI 里「执行脑」设置项的说明文档在
`archive/2026-07-12-偏航拽回/server/执行脑上线.md`。
