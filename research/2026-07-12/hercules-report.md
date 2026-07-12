# Hercules.app — 逆向工程报告

> 逆向日期: 2026-07-12
> 平台: hercules.app
> 公司: Zeus AI Labs, Inc.
> 状态: 闭源 SaaS — 源码不可得，以下为公开文档 + 前端分析 + 架构推断

---

## 一、平台概述

Hercules 是一个 **AI 驱动的应用和网站构建平台**（SaaS）。用户通过自然语言对话即可构建完整的 SaaS 应用、电商网站、内部工具、移动应用等。

| 指标 | 数值 |
|------|------|
| 用户量 | 300,000+ |
| 公司 | Zeus AI Labs, Inc. |
| 成立 | 2025-2026 |
| Twitter | @usehercules |
| 域名 | hercules.app |

---

## 二、技术栈（前端分析）

### 2.1 前端框架

```
React 19 + TanStack Start (SolidStart fork)
├── TanStack Router (文件路由)
├── TanStack Query (服务端状态)
├── Zod (schema 验证)
├── Rolldown (打包)
├── Tailwind CSS (样式)
├── Lucide Icons (图标)
└── Module Federation (微前端)
```

### 2.2 JS Bundle 分析

| Bundle | 用途 |
|--------|------|
| `api-client-*.js` | API 客户端 (TanStack Query hooks) |
| `zod-*.js` | 数据验证 |
| `user-*.js` | 用户状态管理 |
| `query-client-*.js` | 查询缓存 |
| `useStore-*.js` | Zustand 状态管理 |
| `spinner-*.js` | UI 组件 |
| `rolldown-runtime-*.js` | 模块运行时 |

### 2.3 分析追踪

```
Google Analytics (G-5KTWFT6QYW)
Google Tag Manager (GTM-NF2286FS)
Google Ads (AW-17495728654)
Reddit Pixel
```

---

## 三、产品功能全览 (60+ 功能)

### 3.1 AI 引擎

| 功能 | 说明 |
|------|------|
| **Agent Modes** | Plan (规划) / Debug (调试) / Build (构建) 三种模式 |
| **Multi-Agent** | 多 AI Agent 并行，每个聊天 tab 一个 Agent |
| **Chat Connectors** | 30+ 第三方工具连接 (Hubspot/Slack/Salesforce/Zendesk) |
| **Hercules MCP** | Model Context Protocol 集成 |
| **AI Gateway** | 内置 AI (OpenAI/Anthropic/Google)，无需自带 API Key |
| **AI Image Gen** | Logo/插画/产品图/横幅 |
| **Web Search** | AI 可搜索互联网 |
| **Browser Interaction** | AI 可交互浏览器测试 |
| **Code Read/Write** | AI 可读写代码库 |
| **Database Access** | AI 可修改数据库 |

### 3.2 4 种 AI 模型

| 模型 | 速度 | 精度 | 成本 |
|------|------|------|------|
| Expert-Fast | 最快 (2.5x) | 高 | 2x |
| Expert (推荐) | 标准 | 最高 | 标准 |
| Balanced | 标准 | 中 | 中 |
| Lite | 标准 | 低 | 最低 |

### 3.3 应用功能

| 类别 | 功能列表 |
|------|---------|
| **发布** | 自定义域名、Hercules 子域名、一键发布、域名购买 |
| **Auth** | Google/Apple/Microsoft/Facebook/LinkedIn/Email/密码/SAML SSO |
| **Database** | 内置数据库，AI 自动建表，可视化管理 |
| **Backend** | Serverless API 路由、定时任务、Cron Jobs、自动扩容 |
| **Files & Media** | 图片/视频/PDF 存储 + CDN + 图像转换 |
| **Email** | 欢迎邮件/发票/订单确认，域名验证 |
| **Analytics** | PV/UV/热门页面/来源，零配置 |
| **Payments** | Stripe 集成，SaaS 订阅/实物/数字商品/活动/会员/捐赠 |
| **Mobile** | PWA + App Store + Google Play 发布 |
| **Push** | 手动/事件触发/定时推送通知 |
| **SEO** | OG 标签/站点地图/元标签 |
| **i18n** | 100+ 语言，RTL 支持 |
| **Version Control** | 版本历史，回滚 |
| **Branches** | 并行开发分支，独立后端 |
| **Environments** | 生产/开发环境分离 |
| **Code Editor** | 内置代码编辑器 |
| **Dev Machines** | 临时构建测试服务器 |
| **Secrets** | API Key 安全存储，按环境隔离 |
| **Security Audit** | 自动安全审计 |
| **Browser Tests** | 自动化回归测试 |
| **Capture Tools** | 截图/标注/录屏/元素选择 |
| **Visual Edit** | 可视化编辑 |
| **Audits** | 产品/设计/工程/安全/营销全面审计 |

### 3.4 电商 (Hercules Commerce)

| 功能 | 说明 |
|------|------|
| 支付方式 | Stripe 集成，全球收款 |
| 商品类型 | SaaS 订阅/实物/数字商品/服务/活动/会员/捐赠 |
| 优惠券 | 百分比/固定折扣，用量限制+过期 |
| 税务 | 自动计税 |
| 合规 | KYC/银行账户/Stripe 验证 |
| 退款 | 内置退款管理 |

---

## 四、定价

| 方案 | 月费 | AI 额度 | 核心差异 |
|------|------|---------|---------|
| Free | $0 | 15 credits | Hercules 子域名 |
| Pro | $25 | 75 credits | 自定义域名、SEO、去水印 |
| Business | $50 | 75 credits | RBAC、SSO/SAML、优先支持 |
| Enterprise | 联系 | 定制 | SCIM、单租户、专属支持 |

---

## 五、架构推断

```
┌─────────────────────────────────────────┐
│           用户浏览器 (PWA)               │
│  React 19 + TanStack Start              │
├─────────────────────────────────────────┤
│         Hercules API Gateway             │
│  ┌─────────────────────────────────┐    │
│  │  Auth Service (OAuth/SAML/SSO)   │    │
│  │  AI Agent Orchestrator           │    │
│  │  Code Generation Engine          │    │
│  │  Database Service                │    │
│  │  File Storage (CDN)              │    │
│  │  Payment Service (Stripe)        │    │
│  │  Email Service                   │    │
│  │  Analytics Engine                │    │
│  │  Deployment Engine               │    │
│  └─────────────────────────────────┘    │
├─────────────────────────────────────────┤
│           基础设施                       │
│  Serverless 函数 + 自动扩容             │
│  PostgreSQL/MySQL 数据库                 │
│  CDN 文件分发                           │
│  Docker/K8s 容器化                      │
└─────────────────────────────────────────┘
```

---

## 六、API 端点推断

从 JS bundle 分析，推测的 API 结构：

```
POST   /api/auth/login          OAuth/Email 登录
POST   /api/auth/register       注册
GET    /api/user/me             当前用户
GET    /api/apps                应用列表
POST   /api/apps                创建应用
GET    /api/apps/:id            应用详情
POST   /api/ai/chat             AI 对话
POST   /api/ai/agent            创建 Agent
GET    /api/db/tables           数据库表
POST   /api/db/query            数据库查询
POST   /api/deploy              部署
GET    /api/analytics           分析数据
POST   /api/commerce/checkout   支付结账
```

---

## 七、与 Minis 对比

| 维度 | Hercules | Minis (OpenMinis) |
|------|----------|-------------------|
| 定位 | AI 应用构建器 | AI Agent 运行环境 |
| 开源性 | ❌ 闭源 SaaS | ⚠️ 部分开源 |
| 用户量 | 300k+ | 未公开 |
| AI 模型 | 4 档内置 | 用户自配 Provider |
| 后端 | Serverless 内置 | 无 (纯客户端) |
| 部署 | 一键发布 | 不涉及 |
| 数据库 | 内置 | 无 |
| 支付 | Stripe 内置 | 无 |
| MCP | 支持 | 支持 |
| Linux Shell | ❌ | ✅ (iSH/proot) |
| 系统集成 | 无 | 28 个原生工具 |

---

## 八、诚实结论

| 项目 | 状态 |
|------|------|
| 前端技术栈 | ✅ 100% 分析完成 |
| 功能清单 | ✅ 100% (60+ 功能) |
| 定价模型 | ✅ 100% |
| API 结构 | ⚠️ 推断 (无公开 API 文档) |
| 后端源码 | 🔴 不可得 (闭源 SaaS) |
| AI Agent 实现 | 🔴 不可得 (核心商业机密) |

**Hercules 是闭源商业 SaaS，无公开仓库，无可用源码。**

---

> 逆向日期: 2026-07-12
> 来源: hercules.app + docs + llms.txt + JS bundle 分析
