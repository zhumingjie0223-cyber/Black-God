---
name: shenshu (神枢)
version: 1.0.0
description: >
  神枢 —— Black God 体系的中枢系统。天之中枢，运转万物；神枢不亲自干活，
  是让 Builder / Chat / Agent 三个执行层围着它转的那根轴心。
license: Private (Black God internal)
---

# 神枢 (Shenshu) —— Black God 中枢系统

> 定位纠正: 神枢不是 AI Agent，神枢是"轴"。
> Builder / Chat / Agent 是绕着神枢转的"门"。
> 神枢本身不执行任务，它决定谁执行、用什么资源执行、执行多深。

---

## 一、神枢做什么

神枢是三层调度中枢:

```
                    ┌─────────────┐
                    │    神枢      │  ← 中枢，不干活，只调度
                    │  (Shenshu)   │
                    └──────┬───────┘
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ Builder  │    │  Chat    │    │  Agent   │
    │ 造应用   │    │ 对话工具  │    │ 任务执行  │
    └──────────┘    └──────────┘    └──────────┘
```

神枢负责三件事，仅此三件:

1. **模型调度**: 根据任务复杂度，把请求路由到正确的模型档位和 Provider
2. **降级保护**: Primary 模型失败时，自动切 Sub 模型，不让用户看到报错
3. **上下文守恒**: 长任务用 todo.md 驱动，防止 AI 中途忘记目标(源自 Manus 方法论)

---

## 二、神枢的三个执行层

### 2.1 Builder (造应用层) —— fork自 bolt.new (MIT)

```
职责: 自然语言 → 完整可运行应用
技术: Remix + WebContainer + CodeMirror
内核: 复用 bolt.new 的 boltArtifact/boltAction 结构化输出协议
      改名为 shenshuArtifact / shenshuAction
```

### 2.2 Chat (对话工具层) —— 源自 Minis 逆向

```
职责: AI对话 + 系统工具调用(健康/日历/浏览器/定位等28个)
技术: Linux Shell(ish-arm64/proot) + MCP + 技能库
```

### 2.3 Agent (任务执行层) —— 源自 Manus 方法论

```
职责: 长任务规划与执行，不跑偏
核心: todo.md 驱动
  用户下任务 → 神枢拆解成清单 → 逐步执行并标记完成
  → 上下文过长时重读清单找回目标 → 交付
```

---

## 三、神枢调度逻辑 (核心升级)

### 3.1 模型分档路由表

| 复杂度评分 | 档位 | Provider/模型 |
|-----------|------|---------------|
| 0-20 | 极低 | Anthropic 2jie / Haiku 4.5 |
| 20-40 | 低 | 网关 / Sonnet 4.6 |
| 40-60 | 中 | max号 / Sonnet 5 |
| 60-80 | 高 | Anthropic 2jie / Opus 4.7 |
| 80-100 | 极高 | max号 / Opus 4.8 |
| 兜底 | 降本 | DeepSeek V4 Flash |
| 跨厂备份 | 主力挂 | Google Gemini 2.5 Pro |

### 3.2 降级保护机制 (今晚实测修复)

```
每个会话 = Primary + Sub 双模型绑定
Primary 空响应/超时 → 自动切 Sub → 用户无感知

已验证配置:
  session.primaryModel = entry:<provider>/<model>
  session.subModel     = entry:<provider>/<model>  (必须两个不同Provider)
```

**关键教训(今晚实测)**: 同一个 Provider 内部切模型不算真正的容灾——必须跨 Provider(如 Anthropic 3 ↔ Anthropic 2jie)才能防住"一条OAuth线路抽风"这类问题。

### 3.3 Agent Loop 池 (已扩容)

```
9个模型分布在2个独立Provider:
  Provider A (max号/Anthropic 3):  Fable5 / Opus4.8 / Sonnet5
  Provider B (Anthropic 2jie):     Haiku4.5 / Sonnet4.6 / Opus4.7
                                    / Sonnet5 / Fable5 / Opus4.8
```

---

## 四、todo.md 驱动机制 (神枢 Agent 层实现)

```markdown
# 任务: <用户目标>

## 状态: 进行中

- [x] 步骤1: 已完成
- [x] 步骤2: 已完成
- [ ] 步骤3: 当前执行中
- [ ] 步骤4: 待执行
- [ ] 步骤5: 待执行

## 上下文锚点
关键决策: ...
已知约束: ...
```

规则:
1. 复杂任务(预估>5步)必须先写 todo.md 落盘到 `/var/shenshu/workspace/todo.md`
2. 每完成一步立即更新勾选状态
3. 上下文超过一定长度或多轮工具调用后，主动重读 todo.md
4. 交付前检查所有步骤是否勾选完整

---

## 五、已完成的实际升级 (2026-07-12)

| 升级项 | 内容 | 状态 |
|--------|------|------|
| Agent Loop 扩容 | 3个模型 → 9个模型，跨2个Provider | ✅ 已生效 |
| 会话降级保护 | Primary+Sub双模型绑定 | ✅ 已验证 |
| Fable5 上岗 | 双线路(max号+2jie)互备 | ✅ 已测试 |
| Builder源码 | bolt.new核心10文件已获取 | ✅ 待改造 |
| MCP子系统 | 完整Python源码(50KB) | ✅ 待接入 |
| 系统工具接口 | 28个工具完整规格 | ✅ 已归档 |

---

## 六、下一步升级计划

| 优先级 | 任务 | 说明 |
|--------|------|------|
| P0 | Builder改造 | bolt.new → 神枢Builder,替换品牌+接入分档路由 |
| P0 | todo.md机制落地 | 在长任务场景实装,验证防跑偏效果 |
| P1 | 全局默认双模型组 | 需App内手动建Model Group(接口不支持自动化) |
| P1 | Chat工具集成 | 28个系统工具接入神枢Chat层 |
| P2 | 技能库迁移 | 44个MinisSkills + 6个自有技能整合 |
| P2 | 部署上线 | CF Workers + 4台GCP服务器 |

---

> 神枢 · Black God 中枢系统
> 阿权/路飞 © 2026
