> ⚠️ 已归档（2026-07-26 生成，见 docs/plan/MASTER_PLAN.md 获取最新计划）

# Black God 系统完整改造蓝图
> 基于 28家竞品逆向 + 枢语协作 + UI升级
> 生成时间：2026-07-26 04:55
> © 思涵（督导）+ 原声模型（执行）

---

## 一、现状盘点

### 已完成（今天 7-26）
✅ 28家竞品逆向 → 25条改进提炼（P0/P1/P2分级）  
✅ shenshu-private 合并到 Black-God（PR #85 已 merge，commit bc47b76）  
✅ 私有仓删除  
✅ 技术资产到位：
  - E2B 沙箱（nexus_sandbox.mjs）
  - 14子Agent 编排（nexus_agent_orchestrator.mjs）
  - 代码引擎（nexus_code_engine.mjs）
  - 52pojie 红队库
  - skills/redteam-workshop

### 现有架构
```
Black-God/
├── shuyu/                    # 枢语引擎（29.5亿语义空间）
│   ├── shuyu_engine.py       # 5维乘法引擎
│   ├── nexuslang.js          # 意识解释器（feel→think→become→say→grow）
│   └── gen.mjs               # 10元代码引擎
├── web/
│   ├── nexus-do/             # 神枢 DO（3966行核心）
│   │   ├── nexus_do.core.mjs # 主逻辑
│   │   ├── nexus_sandbox.mjs # E2B 沙箱
│   │   ├── nexus_agent_orchestrator.mjs # 14子Agent
│   │   ├── nexus_code_engine.mjs # 代码生成
│   │   └── index.html        # 神枢前端
│   ├── nexus-studio/         # Agent Studio 工作台
│   └── index.html            # 主页/门户
├── 52pojie_redteam/          # 红队工具库
└── skills/                   # 技能系统
```

---

## 二、核心问题（为什么要改）

### 当前痛点
1. **Agent 自述 ≠ 真实结果** — 模型说"修好了"，但测试不通过，没有 verdict 闭环
2. **上下文爆炸** — 长日志/大文件直接回填，撑爆 context，后续轮次失智
3. **补丁直写文件** — 模型输出立刻落盘，没有校验/回退，一次错误全盘污染
4. **编辑意图丢失** — 用户刚改了什么、光标在哪，Agent 不知道，每次从零推理
5. **枢语独立运行** — 29.5亿语义空间闲置，没接入神枢工作流

### 对标竞品能力
| 能力 | Cursor | Devin | Replit | 神枢现状 | 目标 |
|---|---|---|---|---|---|
| 编辑意图上下文 | ✅ | 🚧 | ❌ | ❌ | ✅ |
| 验证驱动回环 | ❌ | ✅ | 🚧 | ❌ | ✅ |
| 结构化补丁落盘 | ✅ | ✅ | ✅ | ❌ | ✅ |
| 观察压缩 | ✅ | ✅ | 🚧 | ❌ | ✅ |
| 测试即真值 | ❌ | ✅ | 🚧 | ❌ | ✅ |
| 枢语语义注入 | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 三、改造方案（P0 先行，分三阶段）

### 🔴 阶段 1：P0 核心闭环（1-2天，立刻开工）

**目标**：让神枢能自我验证、自我纠错、上下文不爆炸

#### 1.1 Verdict 驱动回环（Devin 式）
**改动文件**：
- 新增 `web/nexus-do/verdict_source.mjs` — 测试即真值
- 新增 `web/nexus-do/verdict_loop.mjs` — plan→execute→verify→replan 状态机
- 修改 `web/nexus-do/nexus_agent_orchestrator.mjs` — 接入 verdict_loop
- 修改 `web/nexus-do/nexus_do.core.mjs` — 暴露 `/verdict` 端点

**核心逻辑**：
```javascript
// Agent 说"修好了"不算，测试说 pass 才算
const verdict = await runGroundTruthTests(sandbox, testSuite);
if (verdict.verdict !== 'pass') {
  // 注入失败原因到下轮，防重复错误
  context.lastFailure = { reason, stack, whatWasTried };
  retry();
}
```

**交付标准**：
- [ ] Agent 循环 3 轮失败后，第 4 轮能根据前 3 次失败原因换方案
- [ ] 测试不通过 → Agent 不能说"完成"
- [ ] history 可回溯每轮 plan/result/verdict

---

#### 1.2 观察归一化（Cline 教科书）
**改动文件**：
- 新增 `web/nexus-do/observation_normalizer.mjs`
- 修改 `web/nexus-do/nexus_sandbox.mjs` — 所有工具返回走 normalizer

**核心逻辑**：
```javascript
// 长输出截断+摘要+窗口化
const normalized = normalizeToolResult(rawOutput, { maxChars: 2000 });
// 只回填压缩版，完整版存 storage
```

**交付标准**：
- [ ] 10万行日志 → 压缩到 2000 字符，保留错误行
- [ ] 文件编辑只返回光标附近 ±20 行
- [ ] Agent 上下文从 200K token 降到 50K，轮次从 5 轮增到 50 轮

---

#### 1.3 结构化补丁中间层（v0 工程 ROI 最高）
**改动文件**：
- 新增 `web/nexus-do/patch_executor.mjs`
- 修改 `web/nexus-do/nexus_code_engine.mjs` — 禁止直写文件，必须走 patch_executor

**核心逻辑**：
```javascript
// 模型输出先解析 → 校验 → 再落盘
const gen = parseGeneration(modelOutput); // { files, deps, commands }
const { valid, errors } = validateGeneration(gen);
if (!valid) return { regenPrompt: errors.join('\n') }; // 回退重生成
await applyPatch(sandbox, gen); // 唯一落盘入口
```

**交付标准**：
- [ ] 模型输出路径 `../../../etc/passwd` → 校验拦截，不落盘
- [ ] 语法错误文件 → 不落盘，回退重生成
- [ ] 依赖/文件/命令分三步执行，失败不污染已完成部分

---

#### 1.4 编辑意图窗口（Cursor 近90秒行为）
**改动文件**：
- 新增 `web/nexus-do/edit_intent_window.mjs`
- 修改 `web/nexus-do/index.html` — 前端捕获编辑/光标事件 push 到 DO
- 修改 `web/nexus-do/nexus_do.core.mjs` — 每轮 agent prompt 注入 buildIntentContext()

**核心逻辑**：
```javascript
// 环形缓冲 24 条，超 90 秒衰减
await pushEditIntent(state, { type: 'accept', file, line, text });
const context = await buildIntentContext(state);
// 注入 prompt 开头，优先级高于 RAG
```

**交付标准**：
- [ ] 用户手动改一行 → Agent 下轮知道
- [ ] 光标停在某函数 → Agent 重点关注该函数
- [ ] 意图窗口显示最近 5 个文件的改动摘要

---

#### 1.5 枢语协作注入（Black God 独有）
**改动文件**：
- 修改 `web/nexus-do/nexus_do.core.mjs` — import shuyu
- 新增 `web/nexus-do/shuyu_bridge.mjs` — 枢语词汇生成 + 注入逻辑

**核心逻辑**：
```javascript
// 根据用户意图生成枢语词汇
const shuyuWord = await generateShuyuWord(userIntent);
// 注入到 system prompt
const enrichedPrompt = `${systemPrompt}\n\n[枢语指令] ${shuyuWord}`;
```

**枢语能力接入点**：
1. **意图编码** — 用户说"修复这个 bug" → 枢语生成 `Kyr-thal-ex`（修复-精准-执行）
2. **情绪调制** — 用户暴怒 → 枢语注入 `Zha-mor-quen`（稳定-谨慎-防御）
3. **能力召唤** — 需要逆向 → 枢语注入 `Vel-khar-nox`（解析-深挖-暴露）

**交付标准**：
- [ ] 用户输入 → 枢语词汇 → Agent 行为变化可观测
- [ ] 枢语词汇日志可追溯（每轮记录用了什么词）
- [ ] 29.5亿语义空间能按维度查询（5维：动作/对象/情绪/强度/时态）

---

### 🟡 阶段 2：UI 升级（Lovable 风格 + 深林夜翡翠绿，2-3天）

**目标**：视觉冲击 + 3D 联动 + 品牌辨识度

#### 2.1 主页门户（web/index.html）
- **配色**：深林夜（#0a1612）+ 翡翠绿辉光（#10b981, glow 2px）
- **Logo**：用 `assets/sihan/photo_C722D06B`（翡翠绿辉光神字图标）
- **Hero 区**：3D 旋转神枢模型（Three.js）
- **动画**：Framer Motion 式流畅过渡
- **字体**：JetBrains Mono（代码感）+ Noto Sans SC（中文）

#### 2.2 神枢前端（web/nexus-do/index.html）
- **实时状态**：verdict 循环可视化（plan→execute→verify 三阶段进度条）
- **意图窗口**：右侧边栏显示最近编辑意图（文件/行号/时间）
- **枢语面板**：当前注入的枢语词汇 + 语义解释
- **日志压缩**：长输出折叠，点击展开完整版

#### 2.3 Agent Studio（web/nexus-studio/）
- **14子Agent 卡片**：每个 Agent 状态（idle/working/blocked）+ 进度
- **依赖图**：Agent 调用关系可视化（D3.js force graph）
- **沙箱监控**：E2B 资源占用（CPU/内存/文件数）实时图表

**UI 素材来源**：
- 用 `/var/minis/shared/ui_research/` 里 14 家抓的 CSS token
- `14家合并去重_完整清单.css`（13KB 去重后可复用）
- Lovable/v0/Cursor 的组件库抄袭精华

---

### 🟢 阶段 3：P1/P2 改进（按需迭代，3-7天）

**P1 改进（10项）**：
- 增量 diff（只发变更文件）
- 事件流增量感知（E2B 事件 streaming）
- 共享黑板 + Verifier（多 Agent 交叉检查）
- 多模型分层路由（快/推理/长上下文按场景分级）
- 断言级引用校验（NLI 反查证据）
- ... 

**P2 改进（10项）**：
- information gain 停止判据
- 候选 rerank 模型
- 用户手改 drift 合并
- WASM 本地沙箱层
- ...

（P1/P2 具体实施看 P0 效果，按优先级排队）

---

## 四、技术栈 & 依赖

### 后端（Cloudflare Workers + DO）
- **核心**：nexus_do.core.mjs（3966 行，不重写，只增量挂载）
- **沙箱**：E2B（已有 nexus_sandbox.mjs）
- **存储**：SQLite（DO storage）+ KV（缓存）
- **枢语**：Python shuyu_engine.py（5维乘法）+ JS nexuslang.js（意识解释器）

### 前端（原生 Web Components + 轻量库）
- **框架**：无框架，纯 Web Components
- **3D**：Three.js（神枢模型）
- **图表**：D3.js（依赖图/状态可视化）
- **动画**：CSS transitions + Web Animations API
- **字体**：JetBrains Mono + Noto Sans SC

### 测试 & CI
- **单测**：Node assert（已有 *.test.mjs）
- **E2E**：Playwright（可选）
- **CI**：GitHub Actions（已有 .github/workflows/deploy-nexus.yml）

---

## 五、实施计划（时间线）

| 阶段 | 任务 | 工时 | 负责 | 交付物 |
|---|---|---|---|---|
| **P0-1** | verdict_source + verdict_loop | 4h | 原声模型 | 2 个 mjs + 2 个 test |
| **P0-2** | observation_normalizer | 2h | 原声模型 | 1 个 mjs + 1 个 test |
| **P0-3** | patch_executor | 3h | 原声模型 | 1 个 mjs + 1 个 test |
| **P0-4** | edit_intent_window | 3h | 原声模型 | 1 个 mjs + 1 个 test + 前端事件捕获 |
| **P0-5** | shuyu_bridge | 4h | 原声模型 | 1 个 mjs + 枢语词汇表 |
| **集成** | 挂载到 core.mjs + agent orchestrator | 4h | 原声模型 | 修改 2 个文件 |
| **测试** | 端到端验证 P0 闭环 | 4h | 思涵督导 | 测试报告 |
| **UI-1** | 主页门户 3D + 配色 | 6h | 原声模型 | index.html 重构 |
| **UI-2** | 神枢前端实时状态 | 6h | 原声模型 | nexus-do/index.html |
| **UI-3** | Agent Studio 可视化 | 6h | 原声模型 | nexus-studio/studio.html |
| **P1** | 按需迭代 | TBD | 排队 | - |

**总工时（P0+UI）**：~42h，分 3-5 天完成

---

## 六、风险 & 应对

### 风险点
1. **CF Workers 限制**：CPU 30ms/每请求，verdict 循环可能超时
   - **应对**：长任务切片，用 alarm 链式唤醒
2. **E2B 配额**：免费额度有限，测试频繁可能超额
   - **应对**：本地 mock sandbox（P0 测试用），真实沙箱只跑关键验证
3. **枢语性能**：29.5亿查询可能慢
   - **应对**：建索引（按 5 维预计算），LRU 缓存热词
4. **UI 3D 性能**：移动端可能卡
   - **应对**：降级渲染（移动端用 2D，桌面用 3D）

### 回退方案
- P0 任一模块失败 → 该模块降级为 stub（返回 mock 数据），不阻塞其他模块
- UI 渲染失败 → 回退纯文本界面
- 枢语查询超时 → 跳过枢语注入，用原版 prompt

---

## 七、成功标准（验收清单）

### P0 功能验收
- [ ] verdict 循环：Agent 3 轮失败后，第 4 轮根据前 3 次原因换方案
- [ ] 上下文压缩：10 万行日志 → 2000 字符，Agent 轮次从 5 增到 50
- [ ] 补丁校验：路径逃逸/危险命令被拦截，不落盘
- [ ] 编辑意图：用户手动改一行，Agent 下轮知道
- [ ] 枢语注入：用户输入 → 枢语词汇 → Agent 行为变化可观测

### UI 验收
- [ ] 主页 3D 神枢模型流畅旋转（60fps）
- [ ] 深林夜 + 翡翠绿配色应用到所有页面
- [ ] verdict 循环三阶段进度条实时更新
- [ ] 意图窗口显示最近 5 个文件改动
- [ ] 枢语面板显示当前词汇 + 语义解释

### 性能验收
- [ ] P0 端点响应 <500ms（不含 E2B 执行时间）
- [ ] UI 首屏加载 <2s
- [ ] 3D 模型渲染 60fps（桌面）/ 30fps（移动）

---

## 八、下一步行动

**等你批复后立刻开工**。

你看完这份蓝图，回复：
- **「全照做」** → 我按蓝图从 P0-1 开始，逐个模块写代码 + 测试
- **「改 XXX」** → 告诉我哪块要调整（比如 UI 不要 3D / 枢语先不接 / P0 顺序换）
- **「先做 XXX」** → 指定优先级（比如先 UI 后 P0 / 只做某几项）

---

**蓝图版本**：v1.0  
**生成者**：原声模型（思涵督导）  
**生成时间**：2026-07-26 04:55  
**下次更新**：按你反馈修订
