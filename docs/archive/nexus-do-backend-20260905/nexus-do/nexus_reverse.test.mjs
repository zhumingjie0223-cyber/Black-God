// nexus_reverse.mjs 逆向工具箱单元测试 — node --test
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  base64Encode, base64Decode, rc4Bytes, rc4Encrypt, rc4Decrypt, jsvmpApplyHook,
} from './nexus_reverse.mjs';

// 权哥素材里那张魔改字母表（自定义 base64）
const 魔改表 = 'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe';

const toHex = u8 => Array.from(u8).map(b => b.toString(16).padStart(2, '0')).join('');

test('base64 标准向量正确（Man/Ma/M）', () => {
  assert.equal(base64Encode('Man'), 'TWFu');
  assert.equal(base64Encode('Ma'), 'TWE=');
  assert.equal(base64Encode('M'), 'TQ==');
});

test('base64 标准往返（含中文，UTF-8 安全）', () => {
  const s = '神枢阿权·aquan.lufei.uk';
  assert.equal(base64Decode(base64Encode(s)), s);
});

test('base64 魔改字母表往返成立', () => {
  assert.equal(魔改表.length, 64);
  const s = '请求签名 payload={"ts":1730000000}';
  const enc = base64Encode(s, 魔改表);
  assert.notEqual(enc, base64Encode(s));          // 魔改表产出与标准表不同
  assert.equal(base64Decode(enc, 魔改表), s);      // 但用同表能还原
});

test('base64 解码容忍换行/空格噪音', () => {
  assert.equal(base64Decode('TW\nFu '), 'Man');
});

test('RC4 已知向量（key=Key, data=Plaintext）', () => {
  const enc = new TextEncoder();
  const ct = rc4Bytes(enc.encode('Key'), enc.encode('Plaintext'));
  assert.equal(toHex(ct), 'bbf316e8d940af0ad3');   // 教科书标准向量
});

test('RC4 对称：加密再解密回原文（含中文）', () => {
  const key = '权哥的密钥';
  const text = '这是要保护的请求参数 sign=abc123';
  const enc = rc4Encrypt(key, text);
  assert.equal(rc4Decrypt(key, enc), text);
});

test('RC4 + 魔改字母表 端到端往返', () => {
  const key = 'k3y';
  const text = 'token=xyz';
  const enc = rc4Encrypt(key, text, 魔改表);
  assert.equal(rc4Decrypt(key, enc, 魔改表), text);
});

test('RC4 空密钥报错', () => {
  assert.throws(() => rc4Bytes(new Uint8Array(0), new Uint8Array([1])), /密钥不能为空/);
});

test('非法字母表（非 64 字符）报错', () => {
  assert.throws(() => base64Encode('x', 'abc'), /64 个字符/);
});

test('jsvmpApplyHook 生成可用追踪片段', () => {
  const hook = jsvmpApplyHook({ vmVar: 'fn', ctxVar: 'ctx', argsVar: 'args' });
  assert.ok(hook.includes('fn.apply(ctx, args)'));
  assert.ok(hook.includes('返回值'));
});
