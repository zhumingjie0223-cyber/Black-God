import assert from 'node:assert/strict';

const base = process.env.NEXUS_E2E_BASE || 'http://127.0.0.1:18787';
const ownerToken = process.env.NEXUS_E2E_OWNER_TOKEN || 'nexus-e2e-test-owner-token-20260817';
const authHeaders = {
  Authorization: `Bearer ${ownerToken}`,
  'Content-Type': 'application/json',
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitFor(predicate, label, timeoutMs = 8000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = predicate();
    if (value) return value;
    await sleep(20);
  }
  throw new Error(`等待超时：${label}`);
}

const ticketResponse = await fetch(`${base}/wsticket`, {
  method: 'POST',
  headers: authHeaders,
});
assert.equal(ticketResponse.status, 200, '票据接口必须受鉴权并返回 200');
const ticketBody = await ticketResponse.json();
assert.match(ticketBody.ticket, /^[ef][a-f0-9]{30,}$/i, '票据必须为带实例路由位的一次性随机值');
assert.equal(ticketBody.ttl, 30, '票据有效期必须为 30 秒');

const wsUrl = `${base.replace(/^http/, 'ws')}?t=${encodeURIComponent(ticketBody.ticket)}`;
const ws = new WebSocket(wsUrl);
const frames = [];
let wsError = null;

ws.addEventListener('message', (event) => {
  const frame = JSON.parse(String(event.data));
  frames.push(frame);
  if (frame.type === 'shell_exec') {
    ws.send(JSON.stringify({ type: 'shell_line', line: `relay received: ${frame.code}`, kind: 'stdout' }));
    ws.send(JSON.stringify({
      type: 'shell_result',
      id: frame.id,
      ok: true,
      stdout: `bridge-e2e:${frame.code}`,
      stderr: '',
      exit_code: 0,
    }));
  }
});
ws.addEventListener('error', (event) => { wsError = event; });
await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('WebSocket 打开超时')), 8000);
  ws.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, { once: true });
  ws.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('WebSocket 打开失败')); }, { once: true });
});

ws.send(JSON.stringify({ type: 'device_shell_register', platform: 'e2e-local', protocol: 1 }));
await waitFor(() => frames.find((frame) => frame.type === 'device_shell_ready'), '设备中继注册确认');

const unconfirmedResponse = await fetch(`${base}/device/control`, {
  method: 'POST',
  headers: authHeaders,
  body: JSON.stringify({ action: 'raw', cmd: 'echo bridge-e2e-ok' }),
});
assert.equal(unconfirmedResponse.status, 200, '未确认动作应返回明确的确认门禁结果');
const unconfirmedBody = await unconfirmedResponse.json();
assert.equal(unconfirmedBody.need_confirm, true, '原始 Shell 动作必须先通过确认门禁');
assert.equal(unconfirmedBody.action, 'raw', '确认门禁必须保留请求的设备动作');

const controlResponse = await fetch(`${base}/device/control`, {
  method: 'POST',
  headers: authHeaders,
  body: JSON.stringify({ action: 'raw', cmd: 'echo bridge-e2e-ok', confirm: true }),
});
assert.equal(controlResponse.status, 200, '设备控制 API 必须完成受鉴权请求');
const controlBody = await controlResponse.json();
assert.equal(controlBody.ok, true, `桥接 Shell 回执必须形成成功控制结果：${JSON.stringify(controlBody)}`);
assert.equal(controlBody.action, 'raw', '设备动作必须保留 raw 类型');
assert.equal(controlBody.stdout, 'bridge-e2e:echo bridge-e2e-ok', 'Shell stdout 必须来自中继协议回执');
assert.equal(controlBody.exit_code, 0, 'Shell exit code 必须从中继回执透传');
await waitFor(() => frames.find((frame) => frame.type === 'shell_exec'), 'Worker 下发 shell_exec 帧');

ws.send(JSON.stringify({ type: 'ping' }));
await waitFor(() => frames.find((frame) => frame.type === 'pong'), '心跳 pong 帧');

const secondWs = new WebSocket(wsUrl);
let secondOpened = false;
let secondRejected = false;
secondWs.addEventListener('open', () => { secondOpened = true; secondWs.close(); });
secondWs.addEventListener('error', () => { secondRejected = true; });
await sleep(800);
assert.equal(secondOpened, false, '已消费票据不得重复建立 WebSocket');
assert.equal(secondRejected, true, '重复使用票据必须被拒绝');

ws.close(1000, 'e2e complete');
console.log(JSON.stringify({
  ok: true,
  ticketTtl: ticketBody.ttl,
  frames: frames.map((frame) => frame.type),
  bridgeStdout: controlBody.stdout,
  secondTicketUseRejected: secondRejected,
  unconfirmedActionBlocked: unconfirmedBody.need_confirm === true,
}, null, 2));
