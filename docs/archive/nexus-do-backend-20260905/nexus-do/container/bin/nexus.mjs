#!/usr/bin/env node
// 神枢伪命令桥·客户端（借鉴 Minis 原生卸载模式）
// 沙箱内统一入口：把能力调用打到本机 task_runner 的 /bridge，由它代持令牌转发回神枢。
// 用法（一般经 nexus-memory / nexus-shuyu / nexus-soul 包装脚本调用）：
//   nexus.mjs memory.search <关键词>
//   nexus.mjs memory.note   <要记住的内容>
//   nexus.mjs shuyu.query   <词或义>
//   nexus.mjs soul.status
// 结果以单行 JSON 打到 stdout；失败退出码 1。

const cap = process.argv[2] || '';
const arg = process.argv.slice(3).join(' ').trim();

if (!cap) {
  console.error('用法: nexus.mjs <能力> [参数]（能力: memory.search / memory.note / shuyu.query / soul.status）');
  process.exit(1);
}

const params =
  cap === 'memory.search' || cap === 'shuyu.query' ? { q: arg } :
  cap === 'memory.note' ? { text: arg } : {};

let result;
try {
  const r = await fetch('http://127.0.0.1:' + (process.env.PORT || 8080) + '/bridge', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ cap, params }),
    signal: AbortSignal.timeout(15000)
  });
  result = await r.json();
} catch (e) {
  result = { ok: false, error: ('桥不可达: ' + (e && e.message || e)).slice(0, 200) };
}

console.log(JSON.stringify(result));
process.exit(result && result.ok ? 0 : 1);
