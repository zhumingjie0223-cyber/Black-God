import { ShenshuCore } from './nexus_do.core.mjs';

// 造一个假 core：只测 parseToolCalls + appleTool 的命令拼接逻辑，不真连执行脑。
const core = Object.create(ShenshuCore.prototype);
let capturedCmd = null;
// 桩掉 execRemote：不真发网络，只捕获拼出来的命令
core.execRemote = async (cmd) => { capturedCmd = cmd; return { ok: true, code: 0, stdout: '{"ok":true,"data":"stub"}' }; };
core.storage = { get: async () => ({}) };
core.env = {};

let pass = 0, fail = 0;
const ok = (name, cond, dbg) => { console.log((cond ? '✓ ' : '✗ ') + name + (cond ? '' : `  [实际: ${JSON.stringify(dbg)}]`)); cond ? pass++ : fail++; };

// 1. parseToolCalls 认得 apple 标记
const calls = core.parseToolCalls('好的我来定 ⟨工具:apple｜alarm set --time 07:30 --label 起床⟩ 稍等');
ok('parseToolCalls 解析出 apple 调用', calls.length === 1 && calls[0].tool === 'apple');
ok('参数正确', calls[0].arg === 'alarm set --time 07:30 --label 起床');

// 2. appleTool 拼出正确宿主命令
await core.appleTool('alarm set --time 07:30 --label 起床');
ok('拼出 apple-alarm 命令 + --compact', capturedCmd === 'apple-alarm set --time 07:30 --label 起床 --compact');

// 3. 白名单外的工具被拒
const bad = await core.appleTool('rm -rf /');
ok('非白名单工具被拒（rm 不在 21 工具里）', bad.ok === false && /未知/.test(bad.note));

// 4. 只给工具名无参数也能跑（如 weather）
capturedCmd = null;
await core.appleTool('weather');
ok('无参数工具 weather 正确拼接', capturedCmd === 'apple-weather --compact', capturedCmd);

// 5. 带 apple- 前缀也能识别
capturedCmd = null;
await core.appleTool('apple-location');
ok('容错 apple- 前缀', capturedCmd === 'apple-location --compact');

// 6. 返回结构含 out
capturedCmd = null;
const r = await core.appleTool('device');
ok('返回结构 ok+out 齐全', r.ok === true && r.out.includes('stub'));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
