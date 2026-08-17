// ═══════════════════════════════════════════════
// 神枢 · 逆向工具箱 nexus_reverse
// 网页逆向/反混淆的手术刀，配合 execBrowse(真浏览器)/hijack(劫持工坊)使用：
//   · 自定义字母表 base64 编解码（还原网站魔改的 base64）
//   · RC4 加解密（还原网站请求签名常用的对称加密）
//   · JSVMP 追踪 hook 生成器（打印虚拟机执行核心的真实函数/参数/返回值）
// 全为确定性纯函数，UTF-8 安全，便于测试。素材来源：权哥提供的逆向片段。
// © Black God
// ═══════════════════════════════════════════════

// 标准 base64 字母表（默认值）。网站魔改时传入它自己的 64 字符表即可还原。
export const STD_BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// 输入统一转字节：字符串按 UTF-8，Uint8Array 原样。
function toBytes(input) {
  if (input instanceof Uint8Array) return input;
  return new TextEncoder().encode(String(input));
}

// 自定义字母表 base64 编码。alphabet 必须正好 64 字符；pad 为填充符（默认 '='）。
export function base64Encode(input, alphabet = STD_BASE64_ALPHABET, pad = '=') {
  if (typeof alphabet !== 'string' || alphabet.length !== 64) throw new Error('字母表必须正好 64 个字符');
  const bytes = toBytes(input);
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const has1 = i + 1 < bytes.length, has2 = i + 2 < bytes.length;
    const v = (bytes[i] << 16) | ((has1 ? bytes[i + 1] : 0) << 8) | (has2 ? bytes[i + 2] : 0);
    out += alphabet[(v >> 18) & 63];
    out += alphabet[(v >> 12) & 63];
    out += has1 ? alphabet[(v >> 6) & 63] : pad;
    out += has2 ? alphabet[v & 63] : pad;
  }
  return out;
}

// 自定义字母表 base64 解码。asBytes=true 返回 Uint8Array，否则按 UTF-8 解成字符串。
export function base64Decode(encoded, alphabet = STD_BASE64_ALPHABET, pad = '=', asBytes = false) {
  if (typeof alphabet !== 'string' || alphabet.length !== 64) throw new Error('字母表必须正好 64 个字符');
  const lookup = Object.create(null);
  for (let i = 0; i < 64; i++) lookup[alphabet[i]] = i;
  // 只保留字母表内的有效字符（丢弃填充符、换行、空格等噪音）
  const clean = String(encoded).split('').filter(c => c !== pad && lookup[c] !== undefined);
  const bytes = [];
  for (let i = 0; i < clean.length; i += 4) {
    const c0 = lookup[clean[i]], c1 = lookup[clean[i + 1]];
    const c2 = clean[i + 2] !== undefined ? lookup[clean[i + 2]] : undefined;
    const c3 = clean[i + 3] !== undefined ? lookup[clean[i + 3]] : undefined;
    const v = (c0 << 18) | (c1 << 12) | ((c2 ?? 0) << 6) | (c3 ?? 0);
    bytes.push((v >> 16) & 0xff);
    if (c2 !== undefined) bytes.push((v >> 8) & 0xff);
    if (c3 !== undefined) bytes.push(v & 0xff);
  }
  const arr = Uint8Array.from(bytes);
  return asBytes ? arr : new TextDecoder().decode(arr);
}

// RC4 字节级核心（KSA + PRGA）。加解密同一函数（对称异或）。
export function rc4Bytes(keyBytes, dataBytes) {
  if (!keyBytes || keyBytes.length === 0) throw new Error('RC4 密钥不能为空');
  const S = Array.from({ length: 256 }, (_, i) => i);
  let j = 0;
  for (let i = 0; i < 256; i++) {
    j = (j + S[i] + keyBytes[i % keyBytes.length]) & 255;
    [S[i], S[j]] = [S[j], S[i]];
  }
  const out = new Uint8Array(dataBytes.length);
  let a = 0; j = 0;
  for (let k = 0; k < dataBytes.length; k++) {
    a = (a + 1) & 255;
    j = (j + S[a]) & 255;
    [S[a], S[j]] = [S[j], S[a]];
    out[k] = dataBytes[k] ^ S[(S[a] + S[j]) & 255];
  }
  return out;
}

// RC4 加密：明文 → 密文（base64 包装，便于传输/落库）。alphabet 可传网站魔改表。
export function rc4Encrypt(key, text, alphabet = STD_BASE64_ALPHABET) {
  return base64Encode(rc4Bytes(toBytes(key), toBytes(text)), alphabet);
}

// RC4 解密：密文（base64）→ 明文。与 rc4Encrypt 对称往返。
export function rc4Decrypt(key, b64, alphabet = STD_BASE64_ALPHABET) {
  const cipher = base64Decode(b64, alphabet, '=', true);
  return new TextDecoder().decode(rc4Bytes(toBytes(key), cipher));
}

// JSVMP 追踪 hook 生成器：产出一段注入 JS，打印虚拟机 apply 调用处的真实函数/上下文/参数/返回值，
// 用于把「看不懂的自定义字节码」还原成「它到底调了什么、算出了什么」。纯字符串生成，不执行任何东西。
export function jsvmpApplyHook({ vmVar = 's', ctxVar = 'b', argsVar = 'u', label = '调用 apply' } = {}) {
  return [
    `console.log('[${label}]', { 函数: String(${vmVar}), 上下文: ${ctxVar}, 参数: JSON.stringify(${argsVar}) });`,
    `var __nx_ret = ${vmVar}.apply(${ctxVar}, ${argsVar});`,
    `console.log('[返回值]', __nx_ret);`,
    `__nx_ret;`,
  ].join('\n');
}

export default {
  STD_BASE64_ALPHABET,
  base64Encode,
  base64Decode,
  rc4Bytes,
  rc4Encrypt,
  rc4Decrypt,
  jsvmpApplyHook,
};
