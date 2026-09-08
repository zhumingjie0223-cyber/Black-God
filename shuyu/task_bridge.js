// 枢语执行方言 v1：把语言编译为有界、可检查的工具调用；不执行输入代码。
export const TASK_VERSION = 1;
const mapping = Object.freeze({
  '计算': ['calc', ['expression']], 'calc': ['calc', ['expression']],
  '枢语': ['shuyu', ['operation', 'input']], 'shuyu': ['shuyu', ['operation', 'input']],
  '执行': ['shell_execute', ['command']], 'shell': ['shell_execute', ['command']]
});
export function compileTask(source) {
  if (typeof source !== 'string' || source.length > 8192) throw new Error('枢语程序为空或超过8192字符');
  const lines = source.split('\n').map(x => x.trim()).filter(x => x && !x.startsWith('--'));
  if (!lines.length || lines.length > 4) throw new Error('每个枢语程序需要1至4条执行语句');
  const actions = lines.map((line, index) => {
    const head = /^(?:行[：:]|do:)\s*([^\s(]+)\(/u.exec(line);
    if (!head || !Object.hasOwn(mapping, head[1])) throw new Error(`第${index + 1}行不是已支持的执行语句`);
    let quoted = false, escaped = false, end = -1;
    for (let i = head[0].length; i < line.length; i++) {
      const c = line[i];
      if (escaped) { escaped = false; continue; }
      if (quoted && c === '\\') { escaped = true; continue; }
      if (c === '"') { quoted = !quoted; continue; }
      if (!quoted && c === ')') { end = i; break; }
    }
    if (end < 0 || quoted) throw new Error(`第${index + 1}行括号或字符串未闭合`);
    let args;
    try { args = JSON.parse('[' + line.slice(head[0].length, end) + ']'); }
    catch { throw new Error(`第${index + 1}行参数必须为JSON字符串`); }
    const [tool, keys] = mapping[head[1]];
    if (args.length !== keys.length || args.some(x => typeof x !== 'string' || !x.trim() || x.length > 4096)) throw new Error(`第${index + 1}行参数数量或类型错误`);
    const suffix = line.slice(end + 1).trim();
    let expected = null;
    if (suffix) {
      if (!suffix.startsWith('→')) throw new Error(`第${index + 1}行末尾无效`);
      try { expected = JSON.parse(suffix.slice(1).trim()); } catch { throw new Error('验收结果必须为JSON字符串'); }
      if (typeof expected !== 'string' || expected.length > 4096) throw new Error('验收结果必须为有限长度字符串');
    }
    const parameters = Object.fromEntries(keys.map((key, i) => [key, args[i]]));
    if (tool === 'shell_execute') parameters.timeout = '10';
    return { tool, arguments: parameters, expected };
  });
  return { version: TASK_VERSION, actions };
}

// 标准计算原语：边界明确，不依赖Python环境。
export function primes(input) {
  if (typeof input !== 'string' || !/^[0-9]+$/.test(input) || Number(input) > 10000) throw new Error('质数范围必须为0至10000整数');
  const out = [];
  for (let n = 2; n <= Number(input); n++) {
    let prime = true;
    for (let d = 2; d * d <= n; d++) if (n % d === 0) { prime = false; break; }
    if (prime) out.push(n);
  }
  return out;
}
