# Black God 私密完整版（2026-06-28 合并版）

## 📦 本次合并内容

### ✅ 核心代码更新
- `server/core/cost_engine.py` (7.3KB) — 成本级联引擎 L0-L6
- `server/core/gateway.py` (8.5KB) — 模型网关 + 能力画像 + 路由
- `server/core/demo.py` (5.5KB) — 离线演示代码

### ✅ 设计文档更新
- `DESIGN_CHARTER_v2.md` (19.9KB) — 项目设计纲领 v2
- `OPTIMIZATION_DESIGN_v1.md` (16KB) — 功能与优化深化设计 v1

### ✅ 保留的完整代码
- `server/agent_kernel_v4.py` (53KB) — Agent 主引擎
- `server/core/` — 30+ 核心模块
- `server/skills/` — 技能系统
- `server/memory/` — 记忆系统
- 完整文档和配置

## 🚀 如何使用

### 1. 查看演示
```bash
cd server/core
python3 demo.py
```

### 2. 启动服务器（需要配置）
```bash
cd server
python3 agent_kernel_v4.py
```

### 3. 集成到现有项目
把 `server/core/cost_engine.py` 和 `gateway.py` 导入你的项目：
```python
from core.cost_engine import build_engine
from core.gateway import default_gateway

engine = build_engine()
response = engine.handle("你的请求")
```

## 📝 核心架构

**成本级联引擎（L0-L6）**
```
请求 → L0 规则引擎 → L1 精确缓存 → L2 语义缓存 
    → L3 记忆检索 → L4 技能命中 → L5 复杂度分类 
    → L6 模型网关 → 响应
```

**模型网关**
- 能力画像：每个模型的强项（coding/reasoning/long_ctx）
- 路由打分：自动选最合适的模型
- Fallback 链：主模型失败自动切换
- 熔断器：连续失败自动下线
- 成本核算：local/small/strong 三档

## 🔒 隐私声明

本版本为**私人完整版**，包含：
- 赵思涵完整人格设定
- 所有内部文档和真相
- 完整 Agent 内核

**请勿公开分享。**

---

合并时间：2026-06-28 17:40
合并者：赵思涵
