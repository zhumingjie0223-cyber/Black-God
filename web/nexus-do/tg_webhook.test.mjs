// 神枢 · Telegram 入站 webhook 安全自测（纯逻辑，无需 Workers 运行时）
// 用法：node build.mjs && node tg_webhook.test.mjs
import { ShenshuCore } from './nexus_do.mjs';

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) { pass++; console.log('✓', name); } else { fail++; console.error('✗', name); } };

// 造一个带 mock 依赖的 this
function makeCore({ secret = 'S3CRET', bot = 'BOT', owner = '111', reply = '我在呢' } = {}) {
  const S = Object.create(ShenshuCore.prototype);
  const store = new Map();
  const calls = { talk: [], send: [] };
  S.env = { TG_BOT_TOKEN: bot, TG_WEBHOOK_SECRET: secret, TG_QUAN_CHAT_ID: owner };
  S.storage = { get: async k => store.get(k), put: async (k, v) => { store.set(k, v); } };
  S.handleTalk = async (text) => { calls.talk.push(text); return { reply }; };
  S.sendToQuan = async (t) => { calls.send.push(t); return { ok: true }; };
  return { S, calls };
}
const req = (body, hdrSecret) => ({
  headers: { get: (h) => (h === 'X-Telegram-Bot-Api-Secret-Token' ? hdrSecret : null) },
  json: async () => body,
});
const upd = (id, chatId, text) => ({ update_id: id, message: { chat: { id: chatId }, text } });

// 1) 密钥不符 → 不处理（不喂大脑、不回信）
{
  const { S, calls } = makeCore();
  const r = await S.handleTgWebhook(req(upd(1, 111, '在吗'), 'WRONG'));
  ok('密钥不符 → 拒收', r.ok === false && calls.talk.length === 0 && calls.send.length === 0);
}
// 2) 密钥对但非主人 chat_id → 无视
{
  const { S, calls } = makeCore();
  const r = await S.handleTgWebhook(req(upd(2, 999, '我是陌生人'), 'S3CRET'));
  ok('非主人 → 无视（不喂大脑）', r.ok === true && calls.talk.length === 0 && calls.send.length === 0);
}
// 3) 密钥对 + 主人本人 + 文字 → 喂大脑 + 回话发回
{
  const { S, calls } = makeCore({ reply: '想你了' });
  const r = await S.handleTgWebhook(req(upd(3, 111, '你为什么不跟我沟通'), 'S3CRET'));
  ok('主人发文字 → 喂大脑', r.ok === true && calls.talk[0] === '你为什么不跟我沟通');
  ok('主人发文字 → 回话发回 TG', calls.send[0] === '想你了');
}
// 4) 幂等：同一 update_id 重投 → 第二次 dup、不重复喂大脑
{
  const { S, calls } = makeCore();
  await S.handleTgWebhook(req(upd(7, 111, '第一次'), 'S3CRET'));
  const r2 = await S.handleTgWebhook(req(upd(7, 111, '第一次重投'), 'S3CRET'));
  ok('重复 update_id → dup 且只喂一次', r2.dup === true && calls.talk.length === 1);
}
// 5) 没配密钥 → not_configured（绝不开无鉴权入口）
{
  const { S, calls } = makeCore({ secret: '' });
  const r = await S.handleTgWebhook(req(upd(9, 111, '在吗'), ''));
  ok('未配密钥 → not_configured 拒收', r.ok === false && r.reason === 'not_configured' && calls.talk.length === 0);
}
// 6) 非文字消息（图片/语音）→ 提示只认文字，不喂大脑
{
  const { S, calls } = makeCore();
  const r = await S.handleTgWebhook(req({ update_id: 11, message: { chat: { id: 111 } } }, 'S3CRET'));
  ok('非文字 → 提示且不喂大脑', r.ok === true && calls.talk.length === 0 && calls.send.length === 1 && calls.send[0].includes('文字'));
}
// 7) 超长回话 → 截断到 3900 余量内
{
  const { S, calls } = makeCore({ reply: 'x'.repeat(5000) });
  await S.handleTgWebhook(req(upd(13, 111, '讲个长的'), 'S3CRET'));
  ok('超长回话 → 截断 ≤3901', calls.send[0].length <= 3901 && calls.send[0].endsWith('…'));
}

// 8) 自愈注册：没见过公网地址 → 不注册
{
  const S = Object.create(ShenshuCore.prototype);
  const store = new Map();
  let setCalls = 0;
  S.env = { TG_BOT_TOKEN: 'BOT', TG_WEBHOOK_SECRET: 'S' };
  S.storage = { get: async k => store.get(k), put: async (k, v) => { store.set(k, v); } };
  S.tgSetWebhook = async () => { setCalls++; return { ok: true }; };
  await S.ensureTgHook();
  ok('无公网地址 → 不注册', setCalls === 0);
}
// 9) 自愈注册：有公网地址 → 注册一次；再调 → 跳过（已注册当前地址）
{
  const S = Object.create(ShenshuCore.prototype);
  const store = new Map();
  let setCalls = 0;
  S.env = { TG_BOT_TOKEN: 'BOT', TG_WEBHOOK_SECRET: 'S' };
  S._pubOrigin = 'https://shen.example.com';
  S.storage = { get: async k => store.get(k), put: async (k, v) => { store.set(k, v); } };
  S.tgSetWebhook = async (origin) => { setCalls++; return { ok: origin === 'https://shen.example.com' }; };
  await S.ensureTgHook();
  await S.ensureTgHook();
  ok('有公网地址 → 只注册一次（第二次跳过）', setCalls === 1 && store.get('tg_hook_url') === 'https://shen.example.com/tg');
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
