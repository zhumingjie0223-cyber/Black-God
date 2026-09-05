// 神枢 · /tg 入站路由自测（对着 main 现役那套 handleTelegramWebhook）
// 回归保护：曾经 /tg 路由引用未声明的 ctx，每条消息必抛 ReferenceError → 500，
// Telegram 反复重投也进不来；且处理器把「调大脑 + 回消息」全塞在 ctx?.waitUntil?.() 里，
// 光传 undefined 会被静默跳过。本测试锁死这两点不许回退。
// 用法：node build.mjs && node tg_route.test.mjs
import { ShenshuCore } from './nexus_do.mjs';

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) { pass++; console.log('✓', name); } else { fail++; console.error('✗', name); } };

function makeCore({ secret = 'S3CRET', chat = '111', reply = '我在呢' } = {}) {
  const S = Object.create(ShenshuCore.prototype);
  const store = new Map();
  const calls = { talk: [], send: [] };
  S.env = { TG_BOT_TOKEN: 'BOT', TG_WEBHOOK_SECRET: secret, TG_QUAN_CHAT_ID: chat, OWNER_TOKEN: 'OWN' };
  S.storage = { get: async k => store.get(k), put: async (k, v) => { store.set(k, v); }, list: async () => new Map() };
  S.handleTalk = async (text) => { calls.talk.push(text); return { reply }; };
  S.sendToQuan = async (t) => { calls.send.push(t); return { ok: true }; };
  S.checkRateLimit = async () => ({ blocked: false });
  return { S, calls };
}

// 造一个真 Request（走完整 _fetch 路由，不是直接点处理器——才能验到 ctx 那处）
const tgRequest = (body, secret = 'S3CRET') => new Request('https://nexus-do.example.workers.dev/tg', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': secret },
  body: JSON.stringify(body),
});
const upd = (id, chatId, text) => ({ update_id: id, message: { chat: { id: chatId }, from: { id: chatId }, text } });

// 1) 主人发消息 → 不再 500，且大脑真被调用、回话真被发出（核心回归）
{
  const { S, calls } = makeCore({ reply: '想你了' });
  const r = await S._fetch(tgRequest(upd(101, 111, '在吗')));
  ok('主人发消息 → 不再 500', r.status === 200);
  ok('大脑真被调用（没被 waitUntil 吞掉）', calls.talk.length === 1 && calls.talk[0] === '在吗');
  ok('回话真被发回 TG', calls.send.length === 1 && calls.send[0].includes('想你了'));
}
// 2) 密钥不符 → 403，且绝不碰大脑
{
  const { S, calls } = makeCore();
  const r = await S._fetch(tgRequest(upd(102, 111, '我是坏人'), 'WRONG'));
  ok('密钥不符 → 403 且不喂大脑', r.status === 403 && calls.talk.length === 0 && calls.send.length === 0);
}
// 3) 非主人 chat → 200 但不喂大脑（不给陌生人用主人的脑子）
{
  const { S, calls } = makeCore({ chat: '111' });
  const r = await S._fetch(tgRequest(upd(103, 999, '你好')));
  ok('非主人 → 不喂大脑', r.status === 200 && calls.talk.length === 0);
}
// 4) 同一 update_id 重投 → 只处理一次（Telegram 超时重投不会重复回话）
{
  const { S, calls } = makeCore();
  await S._fetch(tgRequest(upd(104, 111, '重复消息')));
  await S._fetch(tgRequest(upd(104, 111, '重复消息')));
  ok('重投去重 → 只喂一次大脑', calls.talk.length === 1);
}
// 5) 大脑抛错 → 仍回 200 且给兜底话（不让 Telegram 因 500 反复重投）
{
  const { S, calls } = makeCore();
  S.handleTalk = async () => { throw new Error('大脑炸了'); };
  const r = await S._fetch(tgRequest(upd(105, 111, '在吗')));
  ok('大脑抛错 → 仍 200 且有兜底回话', r.status === 200 && calls.send.length === 1);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
