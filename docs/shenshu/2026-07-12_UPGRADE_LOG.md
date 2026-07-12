# 神枢升级改造 —— 今晚全量工作总结

> 日期: 2026-07-12
> 范围: 围绕神枢中枢系统，从定位纠偏到实际落地代码

---

## 一、定位纠偏（最重要的一步）

**神枢不是 AI Agent，神枢是"枢"——门轴。**

```
错误理解: 神枢 = 一个会干活的AI
正确理解: 神枢 = 调度中枢，本身不干活，让 Builder/Chat/Agent 转起来
```

三个执行层围着神枢转:
- **Builder** (造应用) ← fork自 bolt.new(MIT开源)
- **Chat** (对话工具) ← 源自 Minis 逆向(28个系统工具)
- **Agent** (任务执行) ← 源自 Manus 方法论(todo.md驱动)

---

## 二、今晚实测修复的真实问题

### 问题: Claude 原生模型持续报错

**真相排查过程**:
1. 一开始误以为是"模型池太小"(3个→9个) —— 这个修了，但不是主因
2. 用户截图暴露真正病根: `session.subModel` 是空的，没有跨Provider容灾
3. 关键发现: **同一个Provider内切模型不算真正容灾**，OAuth线路挂了两个模型会一起挂
4. 修复: 给会话配置 Primary(max号) + Sub(Anthropic 2jie) 跨厂商双绑定
5. 验证: Fable5 双线路实测通过 ✅

**教训写入文档**: `/var/shenshu/docs/SHENSHU_CORE.md` 第3.2节

---

## 三、代码落地产出

### 3.1 神枢核心文档

`docs/SHENSHU_CORE.md` —— 重新定义神枢定位、三层架构、调度逻辑

### 3.2 神枢 Agent 技能 (todo.md 驱动)

`skills/shenshu-agent/SKILL.md` —— 复杂任务自动生成清单，防止AI长任务跑偏

触发条件: 预估步骤>5 / 明确要求分步 / 涉及多模块

### 3.3 神枢网关路由器 (真实可运行代码)

`gateway/router.py` —— 基于关键词+步骤数+文件数的复杂度评分器

**已实测通过4个用例**:

| 任务 | 复杂度 | 路由到 |
|------|--------|--------|
| 修一下这个错字 | trivial | Haiku4.5 (备: DeepSeek Flash) |
| 帮我加个登录功能 | low | Sonnet4.6网关 (备: 2jie Sonnet4.6) |
| 重构订单模块并发逻辑 | high | 2jie Opus4.7 (备: max号 Opus4.8) |
| 从零设计分布式调度架构 | max | max号 Opus4.8 (备: 2jie Opus4.8) |

**核心设计**: 每一档路由都是"Primary Provider + Sub Provider"跨厂商组合，不会重蹈"同Provider双模型一起挂"的坑。

---

## 四、目录结构

```
/var/minis/shared/shenshu-god/
├── docs/
│   └── SHENSHU_CORE.md          # 神枢核心定位与架构文档
├── gateway/
│   └── router.py                # 分档路由器(可运行,已自测)
├── skills/
│   └── shenshu-agent/
│       └── SKILL.md             # todo.md驱动任务执行技能
├── builder/                     # (待填充: bolt.new改造)
├── core/                        # (待填充: 中枢调度核心)
└── runtime/                     # (待填充: 28工具+MCP集成)
```

---

## 五、还没做的(诚实清单)

| 项目 | 状态 | 原因 |
|------|------|------|
| Builder真正改造 | ❌ 未开始 | 只有bolt.new原始源码,还没fork改名 |
| router.py接入真实Minis会话 | ❌ 未接入 | 目前是独立脚本,需要打通minis-config写入 |
| 全局默认双模型组 | ❌ 无法自动化 | minis-config的groups接口是只读的,必须App内手动建 |
| 28个工具集成到神枢Chat | ❌ 未开始 | 只有接口规格,没写集成代码 |
| todo.md机制实战验证 | ❌ 未实战 | 技能文档写好了,还没在真实复杂任务中跑过 |

---

> 神枢 · Black God
> 阿权/路飞 © 2026
