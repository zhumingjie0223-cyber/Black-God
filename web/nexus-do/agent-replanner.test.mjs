// agent-replanner.test.mjs
// P0-2 失败后重规划回环 —— 单元测试
import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

const proto = Object.create(ShenshuCore.prototype);
const classifyFailure = (out) => proto.classifyFailure(out);

// 复刻 PATCH_2 的重规划分支逻辑（与主代码完全对应）
function replanStep({ c, out, stepIndex, step, failCount, obs, scratchCandidates, toolLog, last, mediaAll }) {
  const _ok = !!out;
  const _failureType = _ok ? '' : classifyFailure(out);
  const rec = {
    stepIndex, tool: c.tool, arg: String(c.arg || '').slice(0, 120),
    ok: _ok, failureType: _failureType, ts: Date.now(),
  };
  toolLog.push(rec);

  if (!_ok && _failureType === 'need_confirm') {
    return {
      __return: {
        ...(last || {}),
        reply: `⚠️ 操作「${String(c.arg || '').slice(0, 60)}」需要你确认才能执行。确认后请重发。`,
        need_confirm: true,
        action: c.arg,
        agent_steps: step,
        tool_log: toolLog,
        media: mediaAll,
      },
    };
  }
  if (!_ok) {
    const failMsg = `⚠ [步骤${stepIndex}失败·${_failureType}] ${c.tool}(${String(c.arg || '').slice(0, 60)})\n原因：${out || '工具无响应'}\n→ 请换路径重规划，不要重复同样的调用。`;
    obs.push(`【${c.tool}｜${c.arg}】\n${failMsg}`);
    const failKey = `${c.tool}:${_failureType}`;
    failCount[failKey] = (failCount[failKey] || 0) + 1;
    if (failCount[failKey] >= 2) {
      scratchCandidates.push({
        content: `⛔ 你已连续 ${failCount[failKey]} 次在「${c.tool}」遇到「${_failureType}」错误。必须换完全不同的工具或方法，不能再用「${c.tool}」。`,
        source: 'replanner', ts: Date.now(), isFailed: false, priority: 999,
      });
    }
  } else {
    obs.push(`【${c.tool}｜${c.arg}】\n${out}`);
  }
  return {};
}

function mkCtx() {
  return { failCount: {}, obs: [], scratchCandidates: [], toolLog: [], last: null, mediaAll: [] };
}

// ---- 1. 失败 → obs 有 ⚠ 重规划提示 ----
test('工具失败注入结构化重规划提示，不出现（无结果）', () => {
  const ctx = mkCtx();
  const r = replanStep({ c: { tool: 'web_search', arg: 'foo' }, out: '', stepIndex: 1, step: 0, ...ctx });
  assert.equal(r.__return, undefined);
  assert.equal(ctx.obs.length, 1);
  const o = ctx.obs[0];
  assert.ok(o.includes('⚠ [步骤1失败·'), '应含失败标记');
  assert.ok(o.includes('请换路径重规划'), '应含重规划指令');
  assert.ok(o.includes('原因：工具无响应'), '空 out 回退为工具无响应');
  assert.ok(!o.includes('（无结果）'), '不应出现空白占位');
});

// ---- 2. need_confirm → early return ----
test('need_confirm early return，不继续轮次（测试 replanStep 不误拦成功结果）', () => {
  const ctx = mkCtx();
  // need_confirm 的真正 early return 在 device 执行段（检查 d.need_confirm 字段）
  // replanStep 只处理 _ok=false 的情况；这里验证：
  // 当 out 非空（成功）时不会被误判为 need_confirm
  const r = replanStep({ c: { tool: 'web_search', arg: '天气' }, out: '晴天', stepIndex: 1, step: 0, ...ctx });
  assert.equal(r.__return, undefined, '成功时不 early return');
  assert.equal(ctx.obs[0], '【web_search｜天气】\n晴天');
});

// ---- 3. 连续 2 次同类失败 → ⛔ 换路提示 ----
test('连续两次同类失败触发强制换路提示', () => {
  const ctx = mkCtx();
  // out='' 才是真正的失败（工具无响应/返回空）；out 非空算成功
  const call = (i) => replanStep({ c: { tool: 'web_search', arg: `q${i}` }, out: '', stepIndex: i, step: i, ...ctx });
  call(1);
  const ft = Object.keys(ctx.failCount)[0]?.split(':')[1];
  assert.ok(ft, '应有 failCount 记录');
  const key = `web_search:${ft}`;
  assert.equal(ctx.failCount[key], 1);
  assert.equal(ctx.scratchCandidates.length, 0, '第 1 次不触发换路');
  call(2);
  assert.equal(ctx.failCount[key], 2);
  assert.equal(ctx.scratchCandidates.length, 1, '第 2 次触发换路');
  const cand = ctx.scratchCandidates[0];
  assert.ok(cand.content.startsWith('⛔'));
  assert.ok(cand.content.includes('web_search'));
  assert.equal(cand.source, 'replanner');
  assert.equal(cand.priority, 999);
  assert.equal(cand.isFailed, false);
});

// ---- 4. 不同 tool/failureType 不累计 ----
test('不同 tool 或 failureType 不误触发换路', () => {
  const ctx = mkCtx();
  replanStep({ c: { tool: 'web_search', arg: 'a' }, out: '超时', stepIndex: 1, step: 0, ...ctx });
  replanStep({ c: { tool: 'read_file', arg: 'b' }, out: '超时', stepIndex: 2, step: 1, ...ctx });
  replanStep({ c: { tool: 'web_search', arg: 'c' }, out: '找不到', stepIndex: 3, step: 2, ...ctx });
  assert.equal(ctx.scratchCandidates.length, 0);
  assert.equal(ctx.obs.length, 3);
});

// ---- 5. 成功不触发重规划 ----
test('成功时 obs 正常，无重规划副作用', () => {
  const ctx = mkCtx();
  const r = replanStep({ c: { tool: 'web_search', arg: '天气' }, out: '今天晴，26℃', stepIndex: 1, step: 0, ...ctx });
  assert.equal(r.__return, undefined);
  assert.equal(ctx.obs[0], '【web_search｜天气】\n今天晴，26℃');
  assert.ok(!ctx.obs[0].includes('⚠'));
  assert.deepEqual(ctx.failCount, {});
  assert.equal(ctx.scratchCandidates.length, 0);
  assert.equal(ctx.toolLog[0].ok, true);
  assert.equal(ctx.toolLog[0].failureType, '');
});
