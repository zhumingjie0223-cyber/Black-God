# 认知科学模块接入 nexus_do.core.mjs 改动总说明

## P0 GWT + P1 主动推理

# nexus_do.core.mjs 改动说明

## 1. import（文件顶部）

在现有 import 块末尾追加两行：

```javascript
import { GlobalWorkspace } from './nexus_gw_workspace.mjs';
import { ActiveInferenceEngine } from './nexus_active_inference.mjs';
```

同时在 **ShenshuCore 的 constructor** 末尾实例化（一次性，不要每次调用现建）：

```javascript
this.gw = new GlobalWorkspace({ maxSlots: 5, maxCharsPerSlot: 800 });
this.aiEngine = new ActiveInferenceEngine(
  (s, m, soul, o) => this.callBrain(s, m, soul, o)
);
```

注意 ActiveInferenceEngine 注入的是箭头函数包裹的 `this.callBrain`，保证 this 绑定。

---

## 2. buildDynamicContext 改动

**位置**：方法内部，原来各段上下文（记忆、心相、scratch 等）字符串拼接完成之后、`return`（或最终 `join`）之前。

**改法**：把原来"无条件拼接各种记忆/scratch 片段"的逻辑改成"先收集候选 → arbitrate → 只注入 winner block"：

```javascript
// ① 收集候选（原来直接拼进 context 的那几段，改成 push 进候选池）
const candidates = [];

// 原：相关记忆段落直接拼接 → 改为：
for (const mem of relevantMemories) {
  candidates.push({
    content: mem.text,
    source: '记忆',
    ts: mem.ts,
    isFailed: !!mem.isFailed,
    shu_coord: mem.shu_coord || null,
  });
}

// 原：inference_log / scratch / 世界模型摘要等各段同理，
// 各自 push 一个 {content, source, ts, isFailed?, shu_coord?}

// ② 仲裁 + 格式化
const winners = this.gw.arbitrate(candidates, userText, soul);
const wsBlock = this.gw.buildWorkspaceBlock(winners);

// ③ 注入：原来拼接各段的位置只保留这一个 block
if (wsBlock) parts.push(wsBlock);
```

**关键点**：
- `userText` 必须是本轮用户原始输入（方法签名如果没有，需从调用方透传进来）。
- 不参与竞争的固定段（人格、时间、soul 基本态等）保持原样，**只有"可有可无的检索类内容"进候选池**。
- 失败记录来源的候选务必打 `isFailed: true`，吃 0.3 加成。

---

## 3. runAgentLoop 改动

**位置**：循环体内，原来"每步执行完把结果追加到 scratch 字符串"的那一段。

**原逻辑**（典型形态）：

```javascript
scratch += `\n[步骤${i}] ${action} → ${resultSummary}`;
// 下一轮 prompt 里整段塞 scratch
```

**改为**：scratch 从字符串改成**候选数组**，每步产出一个候选对象，下一轮进入 prompt 前跑一次 arbitrate：

```javascript
// 循环外（初始化处）：
// 原 let scratch = ''  →  改为
const scratchCandidates = [];

// 每步执行完（原 scratch += 的位置）：
scratchCandidates.push({
  content: `[步骤${i}] ${action} → ${resultSummary}`,
  source: 'scratch',
  ts: Date.now(),
  isFailed: !stepOk,          // 失败步骤打标，保证下一轮必被广播
});

// 下一轮构造 prompt 前（原来直接拼 scratch 的位置）：
const winners = this.gw.arbitrate(scratchCandidates, currentGoalText, soul);
const scratchBlock = this.gw.buildWorkspaceBlock(winners);
// 用 scratchBlock 替换原来的 scratch 字符串注入
```

**关键点**：
- `arbitrate` 的第二个参数用**当前任务目标/本步意图文本**，让关键词分量对齐当前要做的事，而不是最初的用户输入。
- 好处：长循环下 scratch 不再线性膨胀，自动只保留最相关的 ≤5 条；失败步骤因 `isFailed` 加成不会被挤掉。
- 若 buildDynamicContext 也在循环内被调用，scratchCandidates 可以直接并入第 2 节的候选池（一个总仲裁），二选一即可，**不要两处都注入造成重复**。

---

## 4. execDevLoop 改动

**位置**：命令执行主循环内，`exec`（实际跑命令）调用的**前后**，以及失败重试分支。

```javascript
// —— 执行前（exec 调用之前）——
const { expected } = await this.aiEngine.before(cmd, soul, { instanceMode });
// instanceMode 下 before 内部自动跳过 callBrain，无需外面判断

// —— 执行（原有逻辑不动）——
const result = await this.execCmd(cmd);   // {ok, stdout, stderr, code}

// —— 执行后（原来判断 result.ok 决定重试的位置之前）——
const { delta, strategy, worldModelUpdate } =
  await this.aiEngine.after(cmd, result, expected, soul, { instanceMode });

// 记日志 + 封装成 GW 候选（供后续 buildDynamicContext 竞争）
const rec = this.aiEngine.logInference(soul, {
  cmd, expected,
  actual: (result.stdout + result.stderr).slice(0, 300),
  delta,
});
if (rec && delta >= 0.5) {
  scratchCandidates.push({          // 或 buildDynamicContext 的候选池
    content: `预测误差${delta.toFixed(2)}：${rec.cmd} → ${rec.actual}`,
    source: 'inference',
    ts: rec.ts,
    isFailed: !result.ok,
  });
}

// —— 策略分派（替换原来单一的"失败→重试"分支）——
switch (strategy) {
  case 'continue':
    // 原成功路径不变
    break;

  case 'update_world':
    if (worldModelUpdate) {
      this.aiEngine.updateWorldModel(soul, worldModelUpdate);
      // 下一轮生成修复命令的 prompt 里注入新假设：
      // `环境假设已修正：${worldModelUpdate.newAssumption}，基于此重新生成命令`
      // 然后走原有的"让大脑重新出命令"路径
    } else {
      // 诊断失败降级：fall through 到 fix_cmd
    }
    // 注意：无 worldModelUpdate 时不 break，落到 fix_cmd
    if (worldModelUpdate) break;
    // falls through

  case 'fix_cmd':
    // 原有的失败重试逻辑原样保留（把 stderr 喂给大脑修命令）
    break;
}
```

**关键点**：
- `before` 失败/instanceMode 都返回 `{expected:''}`，`after` 对空 expected 有兜底逻辑，所以主流程**不需要任何 try/catch 包裹**这两个调用（模块内部已吞异常）。
- `updateWorldModel` 与 `logInference` 直接改 soul 对象，改完后走**原有的 soul 持久化时机**（不新增写盘点）。
- 重试计数逻辑不变：`update_world` 也消耗一次重试额度，防止假设诊断循环打转。

---

## P2 现象自我模型

# nexus_do.core.mjs 改动说明（P2 部分）

## 1. 文件顶部 import（+1行）

```javascript
import { PhenomenalSelfModel } from './nexus_self_model.mjs';
```

## 2. `buildDynamicContext` 开头（+3行）

方法体第一行（拼接context字符串之前）加：

```javascript
const selfModel = new PhenomenalSelfModel();
const selfAwareness = selfModel.buildSelfAwareness(soul);
// selfAwareness 追加到最终输出字符串（放在最前面，作为第一人称自我状态段）
```

在原有 context 拼接处（比如最后 return 之前）加一段：

```javascript
if (selfAwareness) ctx = `【自我】${selfAwareness}\n\n` + ctx;
```

（`ctx` 换成该方法里实际累积上下文的变量名。）

## 3. `handleTalk` 末尾（callBrain/runAgentLoop 返回、拿到 reply 之后，原 saveSoul 之前，+7行左右）

```javascript
// —— P2 现象自我模型更新 ——
const selfModel = new PhenomenalSelfModel();
if (selfModel.detectCorrection(text)) {
  selfModel.update(soul, { type: 'correction', content: text, coord: soul.current_shu_coord });
}
const eventType = brainResult.ok === false ? 'failure' : 'success';
selfModel.update(soul, { type: eventType, content: (reply || '').slice(0, 100), coord: soul.current_shu_coord });
await this.saveSoul(soul);
```

注意点：
- 如果 `handleTalk` 原本已有 `await this.saveSoul(soul)`，把上面这段**插在原 saveSoul 之前**，不要重复save两次；即：先 selfModel 更新，再统一save一次。
- `brainResult` 换成 handleTalk 里实际接收 callBrain/runAgentLoop 返回值的变量名；如果该返回值没有 `ok` 字段（正常成功路径），`brainResult.ok === false` 为 false，走 success 分支，符合预期。
- update 内部对 `soul.self_model`、`soul.shu_trajectory` 全部 `||` 兜底，老soul不需要迁移脚本。

## 4. （可选联动）`execDevLoop` 内失败分支（+2行）

execRemote 最终失败（3轮耗尽）处加：

```javascript
new PhenomenalSelfModel().update(soul, { type: 'failure', content: cmd.slice(0, 100), tool: 'exec', coord: soul.current_shu_coord });
```

这样命令级失败也进能力边界，`buildSelfAwareness` 下轮对话就能体现"部署配置上还不稳"这类局限。此改动不影响 execDevLoop 返回值，纯附加写soul（由外层 handleTalk 的 saveSoul 统一落盘）。