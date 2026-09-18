// 枢语执行方言 v2：把语言编译为有界、可检查的工具调用；不执行输入代码。
export const TASK_VERSION = 2;
export const TASK_MAX_ACTIONS = 8;
const mapping = Object.freeze({
  '计算': { tool: 'calc', keys: ['expression'] }, 'calc': { tool: 'calc', keys: ['expression'] },
  '枢语': { tool: 'shuyu', keys: ['operation', 'input'] }, 'shuyu': { tool: 'shuyu', keys: ['operation', 'input'] },
  '执行': { tool: 'shell_execute', keys: ['command'] }, 'shell': { tool: 'shell_execute', keys: ['command'] },
  '规划': { tool: 'plan', keys: ['title'] }, 'plan': { tool: 'plan', keys: ['title'] },
  '核对': { tool: 'verify', keys: ['criterion'] }, 'verify': { tool: 'verify', keys: ['criterion'] },
  '检索': { tool: 'shuyu', keys: ['input'], preset: { operation: '检索' } },
  'search': { tool: 'shuyu', keys: ['input'], preset: { operation: '检索' } },
  '邻近': { tool: 'shuyu', keys: ['input'], preset: { operation: '邻近' } },
  'near': { tool: 'shuyu', keys: ['input'], preset: { operation: '邻近' } },
  '时间': { tool: 'clock', keys: ['timezone'] }, 'clock': { tool: 'clock', keys: ['timezone'] },
  '一息': { tool: 'shuyu', keys: ['input'], preset: { operation: '一息' } },
  'pulse': { tool: 'shuyu', keys: ['input'], preset: { operation: '一息' } },
  '余息': { tool: 'shuyu', keys: ['input'], preset: { operation: '余息' } },
  'trail': { tool: 'shuyu', keys: ['input'], preset: { operation: '余息' } },
  '回息': { tool: 'shuyu', keys: ['input'], preset: { operation: '回息' } },
  'echo': { tool: 'shuyu', keys: ['input'], preset: { operation: '回息' } },
  '摇息': { tool: 'shuyu', keys: ['input'], preset: { operation: '摇息' } },
  'sway': { tool: 'shuyu', keys: ['input'], preset: { operation: '摇息' } },
  '落息': { tool: 'shuyu', keys: ['input'], preset: { operation: '落息' } },
  'land': { tool: 'shuyu', keys: ['input'], preset: { operation: '落息' } }
});
export function compileTask(source) {
  if (typeof source !== 'string' || source.length > 8192) throw new Error('枢语程序为空或超过8192字符');
  const lines = source.split('\n').map(x => x.trim()).filter(x => x && !x.startsWith('--'));
  if (!lines.length || lines.length > TASK_MAX_ACTIONS) throw new Error('每个枢语程序需要1至8条执行语句');
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
    const spec = mapping[head[1]];
    if (args.length !== spec.keys.length || args.some(x => typeof x !== 'string' || !x.trim() || x.length > 4096)) throw new Error(`第${index + 1}行参数数量或类型错误`);
    const suffix = line.slice(end + 1).trim();
    let expected = null;
    if (suffix) {
      if (!suffix.startsWith('→')) throw new Error(`第${index + 1}行末尾无效`);
      try { expected = JSON.parse(suffix.slice(1).trim()); } catch { throw new Error('验收结果必须为JSON字符串'); }
      if (typeof expected !== 'string' || expected.length > 4096) throw new Error('验收结果必须为有限长度字符串');
    }
    const parameters = Object.assign({}, spec.preset || {}, Object.fromEntries(spec.keys.map((key, i) => [key, args[i]])));
    if (spec.tool === 'shell_execute') parameters.timeout = '10';
    return { id: 's' + (index + 1), tool: spec.tool, arguments: parameters, expected };
  });
  return { version: TASK_VERSION, actions };
}

export function describePlan(program) {
  if (!program || !Array.isArray(program.actions)) throw new Error('不是已编译的枢语程序');
  return program.actions.map(action => ({
    id: action.id,
    tool: action.tool,
    title: action.arguments.title || action.arguments.criterion || action.arguments.expression || action.arguments.command || action.arguments.input || action.arguments.timezone || action.tool
  }));
}

// 标准计算原语：线性筛，边界明确，不依赖 Python 环境。
export function primes(input) {
  if (typeof input !== 'string' || !/^[0-9]+$/.test(input) || Number(input) > 10000) throw new Error('质数范围必须为0至10000整数');
  const n = Number(input);
  if (n < 2) return [];
  const marked = new Uint8Array(n + 1);
  const out = [];
  for (let i = 2; i <= n; i++) {
    if (marked[i]) continue;
    out.push(i);
    const start = i * i;
    if (start > n) continue;
    for (let j = start; j <= n; j += i) marked[j] = 1;
  }
  return out;
}
