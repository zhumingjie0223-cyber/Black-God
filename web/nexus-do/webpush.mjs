// ═══════════════════════════════════════════════
// Web Push — RFC 8291 (aes128gcm) + RFC 8292 (VAPID)
// 纯 Web Crypto 实现，跑在 Cloudflare Workers 上，无外部依赖。
// VAPID 密钥对由 Worker 自动生成并存 DO storage，权哥无需手动配。
// © 阿权 / 路飞
// ═══════════════════════════════════════════════

const enc = new TextEncoder();

function b64urlToBytes(s) {
  s = String(s).replace(/-/g, '+').replace(/_/g, '/');
  const pad = s.length % 4 ? 4 - (s.length % 4) : 0;
  s += '='.repeat(pad);
  const bin = atob(s);
  const b = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i);
  return b;
}
function bytesToB64url(buf) {
  const a = new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < a.length; i++) s += String.fromCharCode(a[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function concat(...arrs) {
  let len = 0; for (const a of arrs) len += a.length;
  const out = new Uint8Array(len); let o = 0;
  for (const a of arrs) { out.set(a, o); o += a.length; }
  return out;
}

async function hmacSha256(keyBytes, data) {
  const k = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, data));
}
// HKDF（单块输出，len<=32）
async function hkdf(salt, ikm, info, len) {
  const prk = await hmacSha256(salt, ikm);
  const okm = await hmacSha256(prk, concat(info, new Uint8Array([1])));
  return okm.slice(0, len);
}

// —— VAPID 密钥对（ECDSA P-256）——
export async function generateVapidKeys() {
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pubJwk = await crypto.subtle.exportKey('jwk', kp.publicKey);
  const privJwk = await crypto.subtle.exportKey('jwk', kp.privateKey);
  const raw = concat(new Uint8Array([4]), b64urlToBytes(pubJwk.x), b64urlToBytes(pubJwk.y));
  return { publicKey: bytesToB64url(raw), privateJwk: privJwk };
}

async function vapidJWT(audience, subject, privJwk) {
  const header = { typ: 'JWT', alg: 'ES256' };
  const now = Math.floor(Date.now() / 1000);
  const payload = { aud: audience, exp: now + 12 * 3600, sub: subject };
  const h = bytesToB64url(enc.encode(JSON.stringify(header)));
  const p = bytesToB64url(enc.encode(JSON.stringify(payload)));
  const signingInput = enc.encode(h + '.' + p);
  const key = await crypto.subtle.importKey('jwk', privJwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, signingInput)); // r||s (64B)
  return h + '.' + p + '.' + bytesToB64url(sig);
}

// —— RFC 8291 aes128gcm 加密 ——
export async function encryptPayload(subscription, payloadStr) {
  const uaPublic = b64urlToBytes(subscription.keys.p256dh); // 65B raw
  const authSecret = b64urlToBytes(subscription.keys.auth); // 16B
  const asKp = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPubRaw = new Uint8Array(await crypto.subtle.exportKey('raw', asKp.publicKey)); // 65B
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, asKp.privateKey, 256)); // 32B

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyInfo = concat(enc.encode('WebPush: info\0'), uaPublic, asPubRaw);
  const ikm = await hkdf(authSecret, ecdh, keyInfo, 32);
  const cek = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);

  const plain = concat(enc.encode(payloadStr), new Uint8Array([2])); // 0x02 = 末记录分隔符
  const aesKey = await crypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aesKey, plain));

  // header: salt(16) || rs(4=4096) || idlen(1=65) || keyid(as_public 65)
  const rs = new Uint8Array([0, 0, 0x10, 0]);
  const header = concat(salt, rs, new Uint8Array([asPubRaw.length]), asPubRaw);
  return concat(header, ct);
}

// —— 发送一条 Web Push ——
export async function sendWebPush(subscription, payloadStr, vapid) {
  const audience = new URL(subscription.endpoint).origin;
  const jwt = await vapidJWT(audience, vapid.subject || 'mailto:owner@blackgod.app', vapid.privateJwk);
  const body = await encryptPayload(subscription, payloadStr);
  const res = await fetch(subscription.endpoint, {
    method: 'POST',
    headers: {
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      'TTL': '2419200',
      'Urgency': 'normal',
      'Authorization': `vapid t=${jwt}, k=${vapid.publicKey}`,
    },
    body,
  });
  return { ok: res.ok, status: res.status };
}

// —— 测试用：解密（验证加密正确性；线上不用）——
export async function _decryptForTest(subKeyPair, authSecret, cipher) {
  const salt = cipher.slice(0, 16);
  const idlen = cipher[20];
  const asPubRaw = cipher.slice(21, 21 + idlen);
  const ct = cipher.slice(21 + idlen);
  const uaPubRaw = new Uint8Array(await crypto.subtle.exportKey('raw', subKeyPair.publicKey));
  const asKey = await crypto.subtle.importKey('raw', asPubRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: asKey }, subKeyPair.privateKey, 256));
  const keyInfo = concat(enc.encode('WebPush: info\0'), uaPubRaw, asPubRaw);
  const ikm = await hkdf(authSecret, ecdh, keyInfo, 32);
  const cek = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);
  const aesKey = await crypto.subtle.importKey('raw', cek, { name: 'AES-GCM' }, false, ['decrypt']);
  const plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aesKey, ct));
  return new TextDecoder().decode(plain.slice(0, -1)); // 去掉 0x02
}

export { b64urlToBytes, bytesToB64url };
