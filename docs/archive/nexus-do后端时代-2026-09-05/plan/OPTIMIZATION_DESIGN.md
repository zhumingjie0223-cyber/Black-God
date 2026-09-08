# Black God — 功能与优化深化设计（Functional & Optimization Spec）

> 配套《设计纲领 v2》。纲领回答"为什么 / 是什么"，本文回答"**怎么实现、怎么优化**"。
> 内容是工程可直接拆解的：决策函数、评分公式、数据结构、伪代码、配置示例、功能优先级矩阵。
> 边界：所有执行与逆向 / 安全类能力仅服务于**你自己的或已授权的系统**（同纲领 §6 红线）。

---

## 0. 优化总原则

> **每一次"到达昂贵模型"的请求，都是上一层没拦住的失败。**

Black God 的功能性 = 执行力；优化性 = 让执行力**更省、更快、更准、越用越强**。一切优化围绕四个目标：
**省 Key（成本↓）· 低延迟（响应↓）· 高命中（准确↑）· 自进化（越用越强）。**

---

## 1. 成本优化引擎（"不烧 Key"的工程实现）

这是整个项目的优化核心。它是一条**自上而下的拦截级联（cascade）**：请求每下沉一层，成本上升一个量级，所以尽量在上层解决。

### 1.1 请求级联路由（Cascade Router）

```text
请求进来
 │
 ├─[L0] 规则/确定性匹配 —— 计算、文件操作、状态查询、路由 → 本地直接出结果（成本 ~0）
 │
 ├─[L1] 精确缓存 —— 归一化后的 query 命中过 → 直接返回（成本 ~0）
 │
 ├─[L2] 语义缓存 —— embedding 相似度 ≥ θ_sim 命中 → 复用/微调旧答案（成本：1 次 embed）
 │
 ├─[L3] 记忆检索 —— 答案在画像/项目记录/历史任务里 → 本地合成（成本：检索）
 │
 ├─[L4] 技能命中 —— 有沉淀技能可处理 → 走技能流程（成本：技能内部，多为本地/工具）
 │
 ├─[L5] 复杂度分类 —— 轻任务 → 本地/小模型；重任务 → 强模型
 │      （分类器本身用规则+小模型，不烧强模型）
 │
 └─[L6] 强模型 —— 仅当上面全 miss 且任务确实需要推理时才到这
```

**伪代码：**
```python
def handle(request):
    if r := rules_engine.try(request):          return r        # L0
    if r := exact_cache.get(norm(request)):     return r        # L1
    if r := semantic_cache.get(request, θ_sim): return refine(r) # L2
    if r := memory.answer(request):             return r        # L3
    if skill := skill_router.match(request):    return skill.run(request)  # L4
    tier = complexity_classifier(request)       # L5  → "local" | "small" | "strong"
    answer = model_gateway.route(request, tier) # L6
    learn(request, answer)                       # 沉淀：缓存+记忆+可能的技能
    return answer
```

> `θ_sim` 建议起步 0.92（cosine），按误命中率回调。语义缓存命中后**不要直接返回旧答案**——做一次轻量 `refine`（小模型校正时效/差异），避免"答非所问但相似"。

### 1.2 缓存体系（三层）

| 层 | 键 | 失效策略 | 命中收益 |
|---|---|---|---|
| 精确缓存 | `hash(归一化 query + 上下文指纹)` | TTL + 源变更失效 | 省整次调用 |
| 语义缓存 | query embedding（向量库） | TTL + 相似簇老化 | 省整次调用 |
| 前缀 / KV 缓存 | 共享 prompt 前缀（system + 人格 + few-shot） | LRU / radix 树 | 省重复 prefill |

**前缀缓存（关键优化）**：system prompt + 人格层 + 工具定义这些**每次都一样的前缀**，在自托管模型上用 **RadixAttention 思路（SGLang/vLLM 原生支持）复用 KV cache**——典型场景前缀占 60~80% token，能直接跳过这部分计算，TTFT 大幅下降。
> 落地：自托管开源模型走 SGLang serving 开前缀缓存；调闭源 API（Claude/GPT）则利用各家的 **prompt caching** 折扣（把稳定前缀放最前面）。

### 1.3 上下文压缩（省 token 的第二战场）

长上下文**先本地压缩再上模型**。按场景选策略：

| 策略 | 适用 | 做法 |
|---|---|---|
| 截断 | 明显无关的尾部 | 滑动窗口保留最近 N 轮 |
| 抽取式摘要 | 事实密集 | 本地小模型/规则抽 `事实三元组`，丢原文 |
| 生成式摘要 | 叙事/讨论 | 小模型压成要点 |
| 检索式重组 | 超长历史 | 只把**与当前任务相关**的片段拼进上下文（RAG over 自己的记忆） |
| 结构化替代 | 表格/日志/代码 | 转成 schema/diff，而非贴原文 |

**上下文预算分配**（每次请求一个固定 token 预算，按槽位分）：
```text
总预算 = ctx_window - 输出预留
├─ 系统人格 + 工具定义   （走前缀缓存，不重复计费）
├─ 任务指令              （满额保留）
├─ 相关记忆 top-k        （检索排序后裁剪）
├─ 相关技能/few-shot     （命中才放）
└─ 近期对话             （压缩后的摘要 + 最近若干轮原文）
```

### 1.4 成本核算与预算护栏

每次任务带一个**预算上限**，实时累计 token / 调用，超阈值降级或确认：
```python
budget = TaskBudget(max_tokens=..., max_calls=..., max_cost=...)
# 接近上限 → 自动切小模型 / 触发压缩 / 停止扩展 / 请用户确认
```
全链路记 `per-task / per-model / per-skill` 成本，进审计日志（对照 Claude Code 的 per-tool 成本追踪）。这同时是 §纲领-10 "单位任务成本随时间下降"指标的数据源。

---

## 2. 模型网关（智能路由）

> 上层永远叫 Black God，底层自动选最合适的脑子。路由不是随机切，是**带评分的决策**。

### 2.1 模型能力画像表

每个后端维护一张画像（可随实测更新）：
```yaml
claude:    {coding: 0.95, reasoning: 0.93, long_ctx: 0.9, cost: high,  latency: mid,  refuse_rate: low-mid}
gpt:       {coding: 0.9,  reasoning: 0.92, long_ctx: 0.85, cost: high, latency: mid}
deepseek:  {coding: 0.9,  reasoning: 0.88, cost: low,  latency: mid-slow}
local_sm:  {coding: 0.6,  reasoning: 0.55, cost: ~0,  latency: fast}   # 本地小模型兜底
```

### 2.2 路由决策函数

```python
def route(task, candidates):
    def score(m):
        if not available(m): return -inf
        return ( w_cap * capability(m, task.type)
               + w_succ * recent_success_rate(m, task.type)
               - w_cost * norm_cost(m)
               - w_lat  * norm_latency(m)
               - w_ref  * refuse_prob(m, task) )       # 易被拒的任务避开高拒绝模型
    return max(candidates, key=score)
```
权重按场景档位切：**成本敏感**抬 `w_cost`，**质量优先**抬 `w_cap/w_succ`，**实时交互**抬 `w_lat`。

### 2.3 容错：fallback 链 + 熔断 + 重试

```text
首选模型
 │  失败/拒绝/超时/限流
 ├─ 重试（指数退避，≤2 次）
 ├─ 同档备选模型
 ├─ 降一档（强→中→小）
 └─ 本地小模型兜底 / 明确告知用户该任务暂不可用
熔断：某模型连续失败 → 暂时下线 N 分钟，不再路由过去（半开探测恢复）
```

---

## 3. Agent Loop 深化（规划 → 执行 → 反思）

把"给结果而不是丢回问题"做成一个**带自我纠错和死循环守卫的状态机**（思路对齐 LangGraph 的显式状态图 + checkpoint + HITL）。

```text
        ┌─────────┐
        │ PLAN    │  拆任务、定步骤、选工具
        └────┬────┘
             ▼
        ┌─────────┐      ┌──────────────┐
   ┌───▶│ ACT     │─────▶│ OBSERVE      │  执行工具/命令，收结果
   │    └─────────┘      └──────┬───────┘
   │                            ▼
   │                     ┌──────────────┐
   │   修正方案           │ REFLECT/CRITIC│  结果对不对？要不要改？
   └─────────────────────┤  ├─ 通过 → 下一步/交付
                         │  ├─ 失败 → 修正后回 ACT
                         │  └─ 越界/高危 → HITL 确认
                         └──────────────┘
```

**关键护栏：**
- **死循环守卫**：`max_iterations` + 状态指纹去重——同一状态重复出现就强制终止并上报（防 agent 空转，这是 LangGraph 实战里最常见的坑）。
- **HITL 确认点**：删除 / 覆盖 / 对外发布 / 动生产服务器 / 调起手机 App 授权 → 暂停等确认（接你现有 `/api/confirm`）。
- **checkpoint**：每步存状态快照，失败可从任意点重放 / 回滚，不用从头跑。
- **验证步**：交付前自检（代码跑测试、文件校验、输出 schema 校验），不达标回 ACT。

**反思器（Critic）评估维度**：`目标达成度 · 结果可信度 · 是否有副作用 · 是否越界 · 成本是否超预算`。

---

## 4. 记忆系统深化

### 4.1 检索：向量 + 关键词混合

```python
def recall(query, k):
    v = vector_search(query, top=k*3)        # 语义相关
    kw = keyword_search(query, top=k*3)       # 精确命中（账号名、路径、项目名）
    merged = rerank(v + kw, query)            # 融合重排
    return filter_by_confidence(merged)[:k]
```
> 像账号、服务器名、仓库名、禁碰清单这种**精确实体**必须走关键词/规则命中，纯向量会漏。

### 4.2 压缩管线

```text
原始对话/任务
 → 事实抽取（小模型/规则 → 三元组 {主体, 关系, 值}）
 → 去重 & 合并（与已有记忆比对，矛盾走 §4.4）
 → 摘要（生成式压成要点）
 → 重要度打分
 → 写入对应记忆层
```

### 4.3 遗忘 / 保留评分

每条长期记忆周期性重算保留分，低于阈值且未 pin 则归档/遗忘：
```python
retention = importance              \
          * confidence              \
          * exp(-Δt_since_hit / τ)  \   # 时间衰减
          * log(1 + hit_count)          # 命中越多越该留
#禁碰清单、账号结构、项目规则 → pinned=True，永不遗忘
```

### 4.4 冲突消解（新旧记忆矛盾）

```text
新事实 vs 旧事实冲突时：
 ├─ 同源更新（用户明确改口） → 新覆盖旧，旧转历史版本
 ├─ 置信度差距大            → 取高置信，标注存疑
 └─ 拿不准                  → 保留双值 + 下次主动确认一句
```

### 4.5 记忆条目 Schema

```json
{
  "id": "...", "type": "preference|project|account|rule|fact|skill_ref",
  "key": "禁碰服务器", "value": "prod-01 不可执行写操作",
  "scope": "long", "importance": 0.9, "confidence": 0.95,
  "pinned": true, "source": "用户首次安装授权",
  "created_at": "...", "last_hit": "...", "hit_count": 12
}
```

---

## 5. 技能系统深化

### 5.1 技能 Manifest（结构化，不是提示词）

```yaml
name: git-workflow
version: 1.3.0
trigger:
  intents: ["提交代码", "建分支", "解决冲突"]
  keywords: ["git", "commit", "merge", "仓库"]
  embedding_centroid: [...]        # 语义触发
inputs:  {repo_path, branch?}
steps:   [...]                     # 可复用流程（工具调用序列）
guards:  ["禁碰清单校验", "force-push 需确认"]
metrics: {success_rate: 0.94, runs: 57, avg_cost: low}
state:   active                    # candidate|active|reinforced|deprecated
```

### 5.2 生命周期状态机

```text
候选(candidate) ──验证通过/高频──▶ 启用(active) ──持续高命中──▶ 强化(reinforced)
      │                              │                          │
   低频/不稳定                     命中下降/出错率升           被更优技能取代
      ▼                              ▼                          ▼
   丢弃(discard)                淘汰(deprecated) ◀──────────────┘
重复能力 → 合并(merge)
```

### 5.3 触发匹配（双通道）

```python
def match(request):
    cand = rule_trigger(request)              # 关键词/意图规则
    cand += embedding_trigger(request, θ_skill) # 语义靠近质心
    return best_by(cand, key=lambda s: s.success_rate * s.relevance)
```

### 5.4 质量评分（决定强化/淘汰）

```python
skill_value = success_rate                    \
            * frequency_weight                \
            * (1 - conflict_penalty)          \   # 与其他技能冲突则扣
            * freshness                           # 长期没命中且环境变了 → 衰减
# value 高 → 强化（提权重/缓存其前缀）；持续低 → 淘汰
```

### 5.5 沙箱化执行
技能内的命令/脚本一律在沙箱跑，带 §纲领-6 的权限与审计；技能不能擅自扩权，新权限走显式授权。

---

## 6. 上下文工程（Context Assembly）

每次请求前，**装配器**按预算拼最优上下文（而不是把什么都塞进去）：
```python
def assemble(task, budget):
    ctx  = persona_and_tools()                  # 走前缀缓存
    ctx += task.instruction                      # 满额
    ctx += recall(task, k) |> compress           # 相关记忆，压缩后
    ctx += matched_skills_fewshot(task)          # 命中才放
    ctx += recent_dialog |> summarize_old        # 近期原文 + 旧的摘要
    return trim_to(ctx, budget, priority_order)  # 超预算按优先级裁
```
> 原则：**相关性 > 完整性**。宁可少放但都相关，不要多放稀释注意力（也更省 token）。

---

## 7. 多智能体编排

何时拆子 agent：单 agent 上下文要爆、或任务天然可并行/可分工时。

| 模式 | 适用 | 例 |
|---|---|---|
| 主从 | 一个主控派活、收口 | 主 agent 调研究/写作子 agent |
| 流水线 | 明确步骤依赖 | 采集 → 清洗 → 分析 → 出报告 |
| 辩论/评审 | 要交叉验证 | 写码 agent + 审查 agent |

子 agent 各自带沙箱与预算，结果由主控**归并 + 一致性校验**后交付。注意多 agent 会放大 token，**只在收益明确时用**（对照前面聊的：CrewAI 角色化 prompt 会让 token +30~50%）。

---

## 8. 性能与可观测

- **延迟预算**：交互类任务设 TTFT 目标（如 <1.5s 给首响应/进度），重任务转后台 + 进度时间线（你 v3.1 已有）。
- **缓存命中率看板**：L0~L6 各层命中率、语义缓存误命中率、前缀缓存复用率。
- **审计指标**：每任务的 调用次数 / token / 成本 / 工具清单 / 高危确认记录 / 是否越界（全 0 越界是硬指标）。
- **A/B 与回放**：checkpoint 支持改输入重放，用来调路由权重和 θ 阈值。

---

## 9. 功能 × 优先级矩阵（可直接当 backlog）

| 模块 | 功能 | 优化点 | 优先级 |
|---|---|---|---|
| 成本引擎 | L0~L4 拦截级联 | 先把缓存+记忆+规则拦截做扎实 | **P0** |
| 成本引擎 | 语义缓存 + refine | θ 调参、误命中监控 | P1 |
| 成本引擎 | 前缀/KV 缓存 | 自托管走 SGLang，闭源走 prompt caching | P1 |
| 成本引擎 | 上下文压缩 + 预算护栏 | 检索式重组、按槽位分配 | P1 |
| 模型网关 | 路由打分 + fallback + 熔断 | 能力画像随实测更新 | **P0** |
| Agent Loop | plan/act/observe/reflect | 死循环守卫 + checkpoint | **P0** |
| Agent Loop | HITL 确认 + 验证步 | 接 `/api/confirm` | **P0** |
| 记忆 | 混合检索 + 压缩 + 遗忘 | 实体走关键词、衰减公式 | **P0** |
| 记忆 | 冲突消解 | 矛盾标存疑 + 主动确认 | P2 |
| 技能 | manifest + 生命周期 + 质量闸门 | 自动淘汰、合并重复 | P1 |
| 技能 | 双通道触发 + 沙箱执行 | 语义质心 + 权限隔离 | P1 |
| 上下文 | 装配器 + 优先级裁剪 | 相关性优先 | P1 |
| 多智能体 | 主从/流水线/评审 | 仅收益明确时启用 | P2 |
| 可观测 | 命中率/成本/审计看板 | 驱动调参 | P1 |

> 排序逻辑：**先把"省 + 稳 + 安全"的 P0 做实（这决定它是不是真省 Key、是不是敢自用），再上 P1 优化命中率，最后 P2 扩展。**

---

## 10. 一句话

> 功能性 = 它能动手把事做完；优化性 = 它在**每一层都先想"能不能不烧 Key、能不能更快、能不能复用上次的经验"**，做完再把这次的经验沉淀回缓存、记忆和技能里——**所以越用越省、越用越懂、越用越强。**
