// nexus_gw_workspace.test.mjs
// 运行：node --test nexus_gw_workspace.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GlobalWorkspace, tokenize, shuDistance } from './nexus_gw_workspace.mjs';

// 公共测试 soul：中性情绪、有当前枢语坐标
const baseSoul = {
  心绪: 0.5,
  current_shu_coord: { c: 500, m: 90, s: 40, k: 32, p: 4 },
};

test('arbitrate: 关键词相关的候选胜出，且不超过 maxSlots', () => {
  const gw = new GlobalWorkspace({ maxSlots: 2 });
  const now = Date.now();
  const candidates = [
    { content: '部署 docker 容器失败的排查记录', source: 'memory', ts: now },
    { content: '今天天气不错，聊了聊晚饭吃什么', source: 'memory', ts: now },
    { content: 'docker compose 启动配置说明', source: 'skill', ts: now },
    { content: '用户喜欢简短回复', source: 'user_model', ts: now },
  ];
  const winners = gw.arbitrate(candidates, '帮我看看 docker 部署为什么失败', baseSoul);

  // 不超过 maxSlots
  assert.equal(winners.length, 2);
  // 按 salience 降序
  assert.ok(winners[0].salience >= winners[1].salience);
  // 两个 docker 相关候选应胜出
  const contents = winners.map((w) => w.content).join('|');
  assert.ok(contents.includes('docker'));
  assert.ok(!contents.includes('天气'));
});

test('arbitrate: isFailed 加成让旧的失败记录挤进总线', () => {
  const gw = new GlobalWorkspace({ maxSlots: 1 });
  const now = Date.now();
  const candidates = [
    // 全新但无关的普通条目
    { content: '随便聊了两句音乐', source: 'memory', ts: now },
    // 5小时前的失败记录（时效衰减几乎归零），靠 isFailed 加成翻盘
    { content: '之前 rm 相关命令被判定危险被拦截', source: 'failures', ts: now - 5 * 3600000, isFailed: true },
  ];
  const winners = gw.arbitrate(candidates, '继续', baseSoul);
  assert.equal(winners.length, 1);
  assert.equal(winners[0].isFailed, true);
});

test('buildWorkspaceBlock: 内容截断且总长受预算约束；工具函数健壮', () => {
  const gw = new GlobalWorkspace({ maxSlots: 2, maxCharsPerSlot: 50 });
  const now = Date.now();
  const longText = '长'.repeat(500);
  const winners = gw.arbitrate(
    [
      { content: longText, source: 'memory', ts: now },
      { content: longText, source: 'skill', ts: now },
      { content: longText, source: 'obs', ts: now },
    ],
    '长',
    baseSoul
  );
  const block = gw.buildWorkspaceBlock(winners);

  // 包含标题
  assert.ok(block.startsWith('【工作空间广播】'));
  // 总长不超预算（maxSlots * maxCharsPerSlot = 100，加上标题与前缀的宽松上限）
  assert.ok(block.length <= 2 * 50 + 60);
  // 每行内容被截断（带省略号）
  assert.ok(block.includes('…'));

  // 空 winner 返回空串
  assert.equal(gw.buildWorkspaceBlock([]), '');

  // tokenize：中英混合
  const toks = tokenize('debug 部署失败');
  assert.ok(toks.includes('debug'));
  assert.ok(toks.includes('部署'));

  // shuDistance：相同坐标距离为0，坐标缺失返回 null
  assert.equal(shuDistance(baseSoul.current_shu_coord, baseSoul.current_shu_coord), 0);
  assert.equal(shuDistance(null, baseSoul.current_shu_coord), null);
});
