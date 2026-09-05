// 神枢 · 工具字段级预检总线
//
// 目的：在 Agent plan 与 invokeCapability 两端使用同一规则，防止文本提示、UI 或重放请求绕过字段约束。
// 该层只归一化和拒绝输入；不执行工具，也不替代一次性确认/租约/幂等账本。

const isObject = (value) => value && typeof value === 'object' && !Array.isArray(value);
const text = (value, max = 8000) => String(value ?? '').trim().slice(0, max);
const safePath = (value) => {
  const path = text(value, 1024);
  return !!path && !path.includes('\0') && !/(^|\/)\.\.(\/|$)/.test(path);
};

const DEVICE_ACTIONS = new Set(['see', 'open_app', 'notify', 'speak', 'clipboard_read', 'clipboard_write', 'health', 'weather', 'location', 'calendar', 'maps', 'shortcut']);
const HEALTH_TYPES = new Set(['steps', 'heart-rate', 'sleep', 'hrv', 'calories', 'distance', 'spo2', 'weight']);

export const TOOL_PREFLIGHT_SCHEMA_VERSION = 1;

function requiredString(params, field, errors, { max = 8000, allowEmpty = false } = {}) {
  const value = params[field];
  if (typeof value !== 'string') { errors.push({ field, code: 'string_required' }); return ''; }
  if (!allowEmpty && !value.trim()) { errors.push({ field, code: 'nonempty_required' }); return ''; }
  if (value.length > max) errors.push({ field, code: 'too_long', max });
  return value.trim().slice(0, max);
}

function validateDevice(params, errors, warnings) {
  const action = requiredString(params, 'action', errors, { max: 64 });
  if (action && !DEVICE_ACTIONS.has(action)) errors.push({ field: 'action', code: 'enum_invalid', allowed: [...DEVICE_ACTIONS] });
  const next = { ...params, action };
  if (action === 'health' && params.types) {
    const types = String(params.types).split(',').map((value) => value.trim()).filter(Boolean);
    const bad = types.filter((value) => !HEALTH_TYPES.has(value));
    if (bad.length) errors.push({ field: 'types', code: 'enum_invalid', invalid: bad, allowed: [...HEALTH_TYPES] });
    next.types = types.join(',');
  }
  if (['clipboard_write', 'notify', 'speak', 'shortcut'].includes(action) && params.confirm !== true) warnings.push({ field: 'confirm', code: 'owner_confirmation_required' });
  if (action === 'open_app' && params.scheme && !/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(String(params.scheme))) errors.push({ field: 'scheme', code: 'url_scheme_invalid' });
  return next;
}

function validateFileEdit(params, errors) {
  const path = requiredString(params, 'path', errors, { max: 1024 });
  if (path && !safePath(path)) errors.push({ field: 'path', code: 'path_traversal_or_invalid' });
  const oldString = requiredString(params, 'old_string', errors, { max: 100_000, allowEmpty: true });
  // 神枢文件编辑契约：new_string 为空字符串表示删除，必须允许；但 null/缺失必须拒绝。
  if (typeof params.new_string !== 'string') errors.push({ field: 'new_string', code: 'string_required_allow_empty_for_delete' });
  else if (params.new_string.length > 100_000) errors.push({ field: 'new_string', code: 'too_long', max: 100_000 });
  return { ...params, path, old_string: oldString, new_string: typeof params.new_string === 'string' ? params.new_string : '' };
}

export function preflightToolCall(capability, params = {}, { phase = 'plan' } = {}) {
  const cap = text(capability, 128);
  const errors = [];
  const warnings = [];
  if (!cap) errors.push({ field: 'capability', code: 'required' });
  if (!isObject(params)) errors.push({ field: 'params', code: 'object_required' });
  const input = isObject(params) ? { ...params } : {};
  let normalized = input;

  switch (cap) {
    case 'talk': normalized = { ...input, text: requiredString(input, 'text', errors, { max: 20_000 }) }; break;
    case 'agent': normalized = { ...input, text: requiredString(input, 'text', errors, { max: 20_000 }), context: isObject(input.context) ? input.context : {} }; break;
    case 'exec': normalized = { ...input, command: requiredString(input, 'command', errors, { max: 16_000 }) }; break;
    case 'apple': normalized = { ...input, arg: requiredString({ arg: input.arg ?? input.command }, 'arg', errors, { max: 8000 }) }; break;
    case 'device_control': normalized = validateDevice(input, errors, warnings); break;
    case 'gen_image':
    case 'gen_video': normalized = { ...input, prompt: requiredString(input, 'prompt', errors, { max: 4000 }) }; break;
    case 'gen_voice':
    case 'tg':
    case 'watch': normalized = { ...input, text: requiredString(input, 'text', errors, { max: 8000 }) }; break;
    case 'push': {
      const title = requiredString(input, 'title', errors, { max: 160 });
      const body = requiredString(input, 'body', errors, { max: 4000, allowEmpty: true });
      const url = text(input.url || '/', 2048);
      if (url && !url.startsWith('/') && !/^https:\/\//.test(url)) errors.push({ field: 'url', code: 'url_invalid' });
      normalized = { ...input, title, body, url: url || '/' };
      break;
    }
    case 'file_edit': normalized = validateFileEdit(input, errors); break;
    case 'file_read':
    case 'file_write': {
      const path = requiredString(input, 'path', errors, { max: 1024 });
      if (path && !safePath(path)) errors.push({ field: 'path', code: 'path_traversal_or_invalid' });
      if (cap === 'file_write') requiredString(input, 'content', errors, { max: 100_000, allowEmpty: true });
      normalized = { ...input, path };
      break;
    }
    case 'inner':
    case 'heartbeat':
    case 'stats':
    case 'soul':
    case 'device': break;
    default: errors.push({ field: 'capability', code: 'unknown_or_unregistered' });
  }

  return {
    version: TOOL_PREFLIGHT_SCHEMA_VERSION,
    ok: errors.length === 0,
    capability: cap,
    phase,
    normalized,
    errors,
    warnings,
  };
}
