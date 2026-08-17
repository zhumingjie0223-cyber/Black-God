// nexus_sse_block.mjs — Block协议 SSE 输出（v0逆向）
// 把流式 chunk 包装成结构化 block 帧，前端 BlockRenderer 消费

/**
 * @param {ReadableStream|EventEmitter} readable - 上游 LLM 流
 * @param {ReadableStreamDefaultController} controller - SSE 控制器
 * @param {TextEncoder} enc
 * @returns {string} blockId
 */
export function streamBlockSSE(readable, controller, enc) {
  const blockId = 'block-' + crypto.randomUUID();
  let opened = false;

  const send = (frame) => {
    controller.enqueue(enc.encode('data: ' + JSON.stringify(frame) + '\n\n'));
  };

  readable.on('data', (chunk) => {
    const delta = typeof chunk === 'string' ? chunk : String(chunk ?? '');
    if (!delta) return;
    opened = true;
    send({ type: 'text', id: blockId, delta, state: 'streaming' });
  });

  readable.on('end', () => {
    if (opened) send({ type: 'text', id: blockId, state: 'done' });
    controller.enqueue(enc.encode('\n\n'));
    controller.close();
  });

  readable.on('error', (err) => {
    send({ type: 'error', id: blockId, message: err?.message || 'stream error', state: 'done' });
    controller.close();
  });

  return blockId;
}

/**
 * 发送 thinking 块（CoT折叠）
 */
export function sendThinkingBlock(controller, enc, content, state = 'done') {
  const frame = {
    type: 'thinking',
    id: 'think-' + crypto.randomUUID(),
    content,
    state,
  };
  controller.enqueue(enc.encode('data: ' + JSON.stringify(frame) + '\n\n'));
}

/**
 * 发送 diff 块
 */
export function sendDiffBlock(controller, enc, diff, filename) {
  const frame = {
    type: 'diff',
    id: 'diff-' + crypto.randomUUID(),
    diff,
    filename,
    state: 'done',
  };
  controller.enqueue(enc.encode('data: ' + JSON.stringify(frame) + '\n\n'));
}
