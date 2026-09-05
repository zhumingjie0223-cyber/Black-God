// BlockRenderer.js — 统一消息块渲染器（v1 升级版）

/**
 * @typedef {Object} Block
 * @property {string} id            - 块唯一标识
 * @property {string} type          - 块类型（text/thinking/diff/artifact/error/plan…）
 * @property {string} [state]       - 状态，例如 'streaming' | 'done'
 * @property {Object} [payload]     - 块负载数据
 */

/**
 * @typedef {Object} RenderCtx
 * @property {HTMLElement|null} [el]         - 复用的 DOM 元素
 * @property {StreamTypewriter} [typewriter] - 文本块打字机实例
 */

/**
 * 渲染函数签名
 * @callback RendererFn
 * @param {Block} block
 * @param {RenderCtx} ctx
 * @returns {HTMLElement}
 */

/** @type {Map<string, RendererFn>} */
const RENDERERS = new Map();

/**
 * 注册一个块渲染器。
 * @param {string} type       - 块类型
 * @param {RendererFn} renderer - 渲染函数
 * @throws {TypeError} 当 type 非字符串或 renderer 非函数时
 */
export function registerRenderer(type, renderer) {
  // ── FIX: 增加入参校验，防止注册非法渲染器 ──
  if (typeof type !== 'string' || !type) {
    throw new TypeError('registerRenderer: type 必须为非空字符串');
  }
  if (typeof renderer !== 'function') {
    throw new TypeError('registerRenderer: renderer 必须为函数');
  }
  RENDERERS.set(type, renderer);
}

/**
 * 简易流式打字机：按固定速率逐字显示排队文本。
 */
export class StreamTypewriter {
  /**
   * @param {HTMLElement} el                  - 目标元素
   * @param {Object} [options]
   * @param {number} [options.speed=16]       - 每字间隔毫秒
   */
  constructor(el, { speed = 16 } = {}) {
    // ── FIX: 校验 el，避免后续 textContent 访问报错 ──
    if (!(el && typeof el === 'object' && 'textContent' in el)) {
      throw new TypeError('StreamTypewriter: el 必须为 DOM 元素');
    }
    this.el = el;
    // ── FIX: speed 兜底，避免非法值导致 setInterval 异常 ──
    this.speed = Number.isFinite(speed) && speed >= 0 ? speed : 16;
    this.queue = '';
    this.shown = '';
    this.timer = null;
  }

  /**
   * 追加待显示文本并启动打字机。
   * @param {string} chunk
   */
  push(chunk) {
    // ── FIX: 容错非字符串 chunk ──
    if (chunk == null) return;
    this.queue += String(chunk);
    this._tick();
  }

  /** @private 启动/维持定时刷新。 */
  _tick() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      // ── FIX: 元素可能已从 DOM 移除，检测后自动停止 ──
      if (!this.el || !this.el.isConnected) {
        this.destroy();
        return;
      }
      if (this.shown.length >= this.queue.length) {
        clearInterval(this.timer);
        this.timer = null;
        return;
      }
      this.shown = this.queue.slice(0, this.shown.length + 1);
      this.el.textContent = this.shown;
    }, this.speed);
  }

  /** 立即完成显示全部排队文本。 */
  finish() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.shown = this.queue;
    // ── FIX: finish 时 el 可能已失效，加保护 ──
    if (this.el) this.el.textContent = this.shown;
  }

  /** ── NEW: 显式销毁，清理定时器，供 remove 时调用防内存泄漏 ── */
  destroy() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.el = null;
  }
}

/* ───────────────────────── 内置渲染器 ───────────────────────── */

registerRenderer('text', (block, ctx) => {
  const el = ctx.el || document.createElement('div');
  el.className = 'block block-text';
  if (!ctx.typewriter || ctx.typewriter.el !== el) {
    // ── FIX: 元素被替换时重建打字机，避免写入旧节点 ──
    if (ctx.typewriter) ctx.typewriter.destroy();
    ctx.typewriter = new StreamTypewriter(el);
  }
  const payload = block.payload || {}; // ── FIX: payload 可能缺失 ──
  if (block.state === 'streaming') {
    ctx.typewriter.push(payload.delta || '');
  } else {
    // ── FIX: 非流式且有完整 text 时，直接设置队列后 finish ──
    if (typeof payload.text === 'string') {
      ctx.typewriter.queue = payload.text;
    }
    ctx.typewriter.finish();
  }
  return el;
});

registerRenderer('thinking', (block, ctx) => {
  const el = ctx.el instanceof HTMLDetailsElement ? ctx.el : document.createElement('details');
  el.className = 'block block-thinking';
  el.open = block.state === 'streaming';
  const payload = block.payload || {};
  // ── FIX: summary 与内容分节构建，避免整体 innerHTML 覆盖导致状态丢失 ──
  el.innerHTML =
    `<summary>${block.state === 'streaming' ? '思考中…' : '思考'}</summary>` +
    `<pre>${esc(payload.text || '')}</pre>`;
  return el;
});

registerRenderer('diff', (block) => {
  const el = document.createElement('pre');
  el.className = 'block block-diff';
  const lines = Array.isArray(block.payload?.lines) ? block.payload.lines : []; // ── FIX ──
  el.innerHTML = lines
    .map((l) => {
      const s = String(l); // ── FIX: 容错非字符串行 ──
      const c = s[0] === '+' ? 'add' : s[0] === '-' ? 'del' : 'ctx';
      return `<span class="diff-${c}">${esc(s)}</span>`;
    })
    .join('\n');
  return el;
});

registerRenderer('artifact', (block) => {
  const el = document.createElement('div');
  el.className = 'block block-artifact';
  const payload = block.payload || {};
  // ── FIX: 标题走文本节点或 esc，正文用 textContent 防注入 ──
  const title = document.createElement('div');
  title.className = 'artifact-title';
  title.textContent = payload.title || 'Artifact';
  el.appendChild(title);
  const body = document.createElement('pre');
  body.textContent = payload.content || '';
  el.appendChild(body);
  return el;
});

registerRenderer('error', (block) => {
  const el = document.createElement('div');
  el.className = 'block block-error';
  el.textContent = '⚠ ' + (block.payload?.message || 'Unknown error'); // ── FIX ──
  return el;
});

registerRenderer('plan', (block) => {
  const el = document.createElement('ol');
  el.className = 'block block-plan';
  const steps = Array.isArray(block.payload?.steps) ? block.payload.steps : []; // ── FIX ──
  el.innerHTML = steps
    .map((s) => `<li class="${s && s.done ? 'done' : ''}">${esc(s?.text ?? '')}</li>`) // ── FIX ──
    .join('');
  return el;
});

/**
 * HTML 转义。
 * @param {*} s
 * @returns {string}
 */
function esc(s) {
  // ── FIX: 补全 " 与 ' 转义，防属性上下文注入 ──
  return String(s ?? '').replace(
    /[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
  );
}

/* ───────────────────────── 渲染控制器 ───────────────────────── */

/**
 * 管理一组块的挂载、复用与增量更新。
 */
export class BlockRenderer {
  /**
   * @param {HTMLElement} root - 挂载根节点
   */
  constructor(root) {
    // ── FIX: 校验 root ──
    if (!(root && typeof root.appendChild === 'function')) {
      throw new TypeError('BlockRenderer: root 必须为 DOM 元素');
    }
    this.root = root;
    /** @type {Map<string, {block: Block, el: HTMLElement, ctx: RenderCtx}>} */
    this.blocks = new Map();
  }

  /**
   * 渲染（或更新）一个块。
   * @param {Block} block
   * @returns {HTMLElement|undefined} 渲染出的元素
   */
  render(block) {
    // ── FIX: 校验 block 结构 ──
    if (!block || typeof block !== 'object' || block.id == null) {
      console.warn('BlockRenderer.render: 无效的 block', block);
      return;
    }
    const renderer = RENDERERS.get(block.type);
    if (!renderer) {
      // ── FIX: 未知类型不静默丢弃，给出可见提示 ──
      console.warn(`BlockRenderer.render: 未注册的块类型 "${block.type}"`);
      return;
    }

    const entry = this.blocks.get(block.id);
    const ctx = entry ? entry.ctx : {};
    ctx.el = entry ? entry.el : null;

    let el;
    try {
      // ── FIX: 渲染器异常隔离，避免单块崩溃拖垮整个渲染流程 ──
      el = renderer(block, ctx);
    } catch (err) {
      console.error(`BlockRenderer: 渲染块 "${block.id}" (${block.type}) 失败`, err);
      el = document.createElement('div');
      el.className = 'block block-error';
      el.textContent = '⚠ 渲染失败';
    }

    if (!(el instanceof Node)) {
      console.error('BlockRenderer: 渲染器未返回有效 DOM 节点', block);
      return;
    }

    if (!entry) {
      this.root.appendChild(el);
      this.blocks.set(block.id, { block, el, ctx });
    } else {
      if (el !== entry.el) entry.el.replaceWith(el);
      entry.el = el;
      entry.block = block;
    }
    return el;
  }

  /**
   * 对已有块做增量 patch 并重渲染。
   * @param {string} id
   * @param {Partial<Block>} patch
   */
  updateBlock(id, patch) {
    const entry = this.blocks.get(id);
    if (!entry) {
      console.warn(`BlockRenderer.updateBlock: 未找到块 "${id}"`);
      return;
    }
    const patchObj = patch || {}; // ── FIX ──
    const merged = {
      ...entry.block,
      ...patchObj,
      payload: { ...(entry.block.payload || {}), ...(patchObj.payload || {}) }, // ── FIX ──
    };
    this.render(merged);
  }

  /**
   * ── NEW: 移除指定块并清理其资源（打字机定时器等）。 ──
   * @param {string} id
   * @returns {boolean} 是否成功移除
   */
  remove