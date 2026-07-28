import { createServer } from 'node:http';
import { spawn } from 'node:child_process';

const PORT = parseInt(process.env.PORT || '8080', 10);
const TASK_TOKEN = process.env.TASK_TOKEN || '';

function log(...args) {
  console.log(`[${new Date().toISOString()}]`, ...args);
}

process.on('uncaughtException', (err) => {
  log('uncaughtException:', err && err.stack ? err.stack : String(err));
});

process.on('unhandledRejection', (reason) => {
  log('unhandledRejection:', reason && reason.stack ? reason.stack : String(reason));
});

function truncate(str, max) {
  if (str.length <= max) return str;
  return str.slice(0, max);
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 1024 * 1024) {
        reject(new Error('body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function checkAuth(req) {
  if (!TASK_TOKEN) return true;
  const header = req.headers['authorization'] || '';
  return header === `Bearer ${TASK_TOKEN}`;
}

async function handleExec(req, res) {
  if (!checkAuth(req)) {
    sendJson(res, 401, { ok: false, error: 'unauthorized' });
    return;
  }

  let raw;
  try {
    raw = await readBody(req);
  } catch {
    sendJson(res, 400, { ok: false, error: 'bad request' });
    return;
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    sendJson(res, 400, { ok: false, error: 'invalid json' });
    return;
  }

  const cmd = payload && typeof payload.cmd === 'string' ? payload.cmd : null;
  if (!cmd) {
    sendJson(res, 400, { ok: false, error: 'missing cmd' });
    return;
  }

  let timeout = Number(payload.timeout);
  if (!Number.isFinite(timeout) || timeout <= 0) timeout = 30;
  if (timeout > 60) timeout = 60;

  log('exec:', JSON.stringify(cmd), `timeout=${timeout}s`);

  const child = spawn('/bin/sh', ['-c', cmd], {
    cwd: '/tmp',
    detached: true,
  });

  let stdout = '';
  let stderr = '';
  let finished = false;
  let timedOut = false;

  child.stdout.on('data', (d) => { stdout += d.toString('utf8'); });
  child.stderr.on('data', (d) => { stderr += d.toString('utf8'); });

  const timer = setTimeout(() => {
    timedOut = true;
    try {
      process.kill(-child.pid, 'SIGKILL');
    } catch (e) {
      log('kill error:', String(e));
    }
  }, timeout * 1000);

  const finish = (code) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    sendJson(res, 200, {
      ok: !timedOut && code === 0,
      code: code,
      stdout: truncate(stdout, 8000),
      stderr: truncate(stderr, 2000),
      error: timedOut ? 'timeout' : null,
    });
  };

  child.on('close', (code) => finish(code));

  child.on('error', (err) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    log('spawn error:', String(err));
    sendJson(res, 200, {
      ok: false,
      code: null,
      stdout: truncate(stdout, 8000),
      stderr: truncate(stderr, 2000),
      error: String(err && err.message ? err.message : err),
    });
  });
}

const server = createServer((req, res) => {
  const url = req.url || '/';
  const method = req.method || 'GET';

  if (method === 'GET' && url === '/health') {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (method === 'POST' && url === '/exec') {
    handleExec(req, res).catch((err) => {
      log('handleExec error:', String(err));
      if (!res.headersSent) {
        sendJson(res, 500, { ok: false, error: 'internal error' });
      }
    });
    return;
  }

  sendJson(res, 404, { ok: false, error: 'not found' });
});

server.listen(PORT, '0.0.0.0', () => {
  log(`task_runner listening on 0.0.0.0:${PORT}`);
});
