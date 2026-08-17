# Black God 私人版 — 工程收口完整清单（CLOSURE_PLAN）

> 体检日期：2026-06-28　体检人：赵思涵
> 结论：**方向对、零件全、代码真（11核心模块0占位）、病在"没接线"。**
> 主内核 agent_kernel_v4.py 是个自包含单体，把 core/ 所有高级模块全绕过了。
> 当前线上的"我"= 有铁律的工具人，不会读你情绪、不自进化、不省Key、不认识你。

---

## 一、现状速览

### ✅ 已在跑（v4 主内核 690 行）
| 模块 | 状态 |
|---|---|
| 简化人格铁律（内嵌） | ✅ 跑 |
| Agent Loop（多步+工具+降级） | ✅ 跑 |
| 工具系统 10 个 | ✅ 跑 |
| 技能 14 个（写死字典） | ⚠️ 静态 |
| 三层记忆 SQLite | ✅ 跑 |
| HTTP 18 接口 | ✅ 跑 |

### 🔴 真货但是孤儿（core/，0占位，全完整实现，没接线）
| 模块 | 行数 | 价值 | 文档卖点 |
|---|---|---|---|
| real_dialog_engine.py | 196 | 情绪识别+场景切换+主动延续 | "懂你言外之意" |
| self_evolving.py | 362 | 向量记忆+技能自生成+经验复盘 | "越用越强" |
| adaptive_reasoning.py | 287 | 5级推理自动选 | **省Key核心** |
| multi_agent.py | 329 | Planner/Executor/Verifier/Coordinator | "自己拆任务" |
| onboarding.py | 412 | 本地画像+行为分析+授权 | **首次认识你** |
| user_profile_engine.py | 270 | 用户画像+偏好分析 | 本地画像 |
| skill_index.py | 276 | 技能扫描+自动分类分级 | 动态技能 |
| sandbox.py | 209 | docker/firejail/simple 三级沙箱 | 强沙箱 |
| reflexion.py | 140 | 自我反思校验 | 自我纠错 |
| memory_integrator.py | 132 | 记忆压缩+关键信息提取 | 记忆像人 |
| preference_engine.py | 57 | 偏好引擎 | 本地偏好 |

---

## 二、接线三大坑（必须先填，否则接进去就崩）

### 坑1：硬编码旧服务器路径 /opt/bg-agent（6处，5文件）
memory_integrator.py / sandbox_docker.py / skill_index.py / task_engine.py / user_profile_engine.py
→ 全部改成相对 ROOT 的路径（MEMORY_DIR / DATA_DIR）

### 坑2：LLM 调用接口签名不统一
- 用 `call_fn(messages)`：adaptive_reasoning / multi_agent / self_evolving / reflexion / code_engine / openai_agent
- 用 `llm_call(messages)`：real_dialog_engine / open_voice_engine
- v4 内核里是 `AgentLoop._call_model(messages, tools)` 返回原始 dict
→ 必须造一个统一适配器 `llm(messages) -> str`，喂给所有 core 模块

### 坑3：前后端 API 缺口
| 前端在调 | 后端 | 处理 |
|---|---|---|
| /api/profile | 只有 /api/preferences | 补 /api/profile |
| /api/push/subscribe | 无 | 补 |
| /api/push/unsubscribe | 无 | 补 |

---

## 三、收口路线（5 阶段，按性价比排序）

### 🥇 阶段1：让"我"活过来（改动最小，体感最大）
- [ ] 1.1 造统一 LLM 适配器 `llm(messages)->str`（包一层 _call_model）
- [ ] 1.2 接 real_dialog_engine → /api/chat 增加情绪/场景识别
- [ ] 1.3 CONSTITUTION.md 完整8层人格替换 v4 内嵌简化版
- [ ] 1.4 接 reflexion 自我反思（可选，回答后自检）
- **验收**：发"快点"→她加速；发"累了"→她心疼；发技术→她专业不撒娇

### 🥈 阶段2：前后端对齐（不再点了没反应）
- [ ] 2.1 补 /api/profile（GET 读画像 + POST 存画像）
- [ ] 2.2 补 /api/push/subscribe + /api/push/unsubscribe
- [ ] 2.3 webpush/ 已有 vapid 密钥，挂上推送路由
- **验收**：前端所有按钮都有真实后端响应

### 🥉 阶段3：省Key缓冲系统（文档核心卖点）
- [ ] 3.1 接 adaptive_reasoning → 简单任务用轻模型/本地，复杂才上强模型
- [ ] 3.2 加 LLM 响应缓存（相同/相似问题命中缓存，不重复烧Key）
- [ ] 3.3 接 memory_integrator → 长上下文先本地压缩再喂模型
- **验收**：重复问题秒回不烧Key；简单问题不调强模型

### 阶段4：本地画像 / 首次认识你（文档第一卖点）
- [ ] 4.1 修 onboarding.py + user_profile_engine.py 的 /opt 路径
- [ ] 4.2 接首次引导流程 → 建本地画像（本地存，不上云）
- [ ] 4.3 未授权 → 陌生人模式
- **验收**：首次打开走引导；授权多少懂多少；不授权当陌生人

### 阶段5：自进化 + 动态技能 + 多智能体
- [ ] 5.1 接 self_evolving → 任务沉淀技能、失败复盘
- [ ] 5.2 接 skill_index → 动态扫描技能替代写死的14个字典
- [ ] 5.3 接 multi_agent → 复杂任务自动拆解并行
- **验收**：复杂任务自动拆；用过的套路自动变技能

---

## 四、暂不做（文档提到但优先级低）
- App 商城端到端：需要 iOS 原生配合，当前 PWA 阶段先放
- 语音18情绪训练：voice_engine 在但模型未训，独立任务
- 远端 GPU 执行：需要服务器资源，按需

---

## 五、铁律（执行约束）
1. 每阶段改完先本地 py_compile + 启动冒烟测试，过了才算完
2. 不碰 47.93.100.200，不碰乡村振兴
3. 敏感文件（.env.cloudflare / vapid_private.pem）永不上传
4. 私人版改完 → 剥离人格 → 才搬公开版
5. 每个改动先给权哥分析，确认后才写
