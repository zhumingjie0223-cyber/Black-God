#!/usr/bin/env node
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, readdir, stat } from 'node:fs/promises';
import { dirname } from 'node:path';

const PORT = process.env.PORT || 8080;
const TASK_TOKEN = process.env.TASK_TOKEN || '';

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function checkAuth(req) {
  if (!TASK_TOKEN) return true;
  const h = req.headers['authorization'] || '';
  const m = h.match(/^Bearer\s+(.+)$/);
  return m && m[1] === TASK_TOKEN;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function validPath(p) {
  return typeof p === 'string' && p.startsWith('/tmp/') && !p.includes('..');
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const path = url.pathname;

    if (req.method === 'GET' && path === '/health') {
      return sendJson(res, 200, { ok: true });
    }

    if (!checkAuth(req)) {
      return sendJson(res, 401, { ok: false, error: 'unauthorized' });
    }

    if (req.method === 'POST' && path === '/exec') {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return sendJson(res, 400, { ok: false, error: 'bad_json' });
      }
      const cmd = parsed.cmd;
      const timeout = parsed.timeout;
      if (typeof cmd !== 'string') {
        return sendJson(res, 400, { ok: false, error: 'bad_cmd' });
      }
      const t = Number.isFinite(timeout) ? timeout : 30000;
      console.log(`[exec] ${new Date().toISOString()} cmd=${JSON.stringify(cmd)} timeout=${t}`);

      const child = spawn('/bin/sh', ['-c', cmd], { cwd: '/tmp', detached: true });
      let stdout = '';
      let stderr = '';
      let killed = false;
      let done = false;

      const timer = setTimeout(() => {
        killed = true;
        try {
          process.kill(-child.pid, 'SIGKILL');
        } catch {}
      }, t);

      child.stdout.on('data', (d) => {
        if (stdout.length < 8000) stdout += d.toString();
      });
      child.stderr.on('data', (d) => {
        if (stderr.length < 2000) stderr += d.toString();
      });

      child.on('error', (err) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        sendJson(res, 200, {
          ok: false,
          code: null,
          stdout: stdout.slice(0, 8000),
          stderr: stderr.slice(0, 2000),
          error: err.message,
        });
      });

      child.on('close', (code) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        sendJson(res, 200, {
          ok: !killed && code === 0,
          code,
          stdout: stdout.slice(0, 8000),
          stderr: stderr.slice(0, 2000),
          error: killed ? 'timeout' : null,
        });
      });
      return;
    }

    if (req.method === 'POST' && path === '/edit') {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return sendJson(res, 400, { ok: false, error: 'bad_json' });
      }
      const { path: fp, search, replace } = parsed;
      if (!validPath(fp)) {
        return sendJson(res, 400, { ok: false, error: 'bad_path' });
      }
      if (typeof search !== 'string' || typeof replace !== 'string') {
        return sendJson(res, 400, { ok: false, error: 'bad_args' });
      }
      let content;
      try {
        content = await readFile(fp, 'utf8');
      } catch {
        return sendJson(res, 200, { ok: false, error: 'file_not_found' });
      }
      let count = 0;
      let idx = 0;
      while ((idx = content.indexOf(search, idx)) !== -1) {
        count++;
        idx += search.length || 1;
      }
      if (count === 0) {
        return sendJson(res, 200, { ok: false, error: 'not_found' });
      }
      if (count > 1) {
        return sendJson(res, 200, { ok: false, error: 'not_unique', count });
      }
      const next = content.replace(search, replace);
      await writeFile(fp, next, 'utf8');
      return sendJson(res, 200, {
        ok: true,
        replaced: 1,
        size: Buffer.byteLength(next),
      });
    }

    if (req.method === 'POST' && path === '/read') {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return sendJson(res, 400, { ok: false, error: 'bad_json' });
      }
      const { path: fp } = parsed;
      if (!validPath(fp)) {
        return sendJson(res, 400, { ok: false, error: 'bad_path' });
      }
      let offset = Number.isFinite(parsed.offset) ? parsed.offset : 1;
      let limit = Number.isFinite(parsed.limit) ? parsed.limit : 200;
      if (offset < 1) offset = 1;
      if (limit < 0) limit = 0;
      let content;
      try {
        content = await readFile(fp, 'utf8');
      } catch {
        return sendJson(res, 200, { ok: false, error: 'file_not_found' });
      }
      const lines = content.split('\n');
      const total_lines = lines.length;
      const slice = lines.slice(offset - 1, offset - 1 + limit).join('\n');
      return sendJson(res, 200, {
        ok: true,
        total_lines,
        content: slice.slice(0, 8000),
      });
    }

    if (req.method === 'POST' && path === '/write') {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return sendJson(res, 400, { ok: false, error: 'bad_json' });
      }
      const { path: fp, content } = parsed;
      if (!validPath(fp)) {
        return sendJson(res, 400, { ok: false, error: 'bad_path' });
      }
      if (typeof content !== 'string') {
        return sendJson(res, 400, { ok: false, error: 'bad_args' });
      }
      await mkdir(dirname(fp), { recursive: true });
      await writeFile(fp, content, 'utf8');
      return sendJson(res, 200, {
        ok: true,
        size: Buffer.byteLength(content),
      });
    }

    if (req.method === 'POST' && path === '/ls') {
      const raw = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return sendJson(res, 400, { ok: false, error: 'bad_json' });
      }
      const dp = parsed.path == null ? '/tmp' : parsed.path;
      if (!(dp === '/tmp' || validPath(dp)) || (typeof dp === 'string' && dp.includes('..'))) {
        return sendJson(res, 400, { ok: false, error: 'bad_path' });
      }
      let names;
      try {
        names = await readdir(dp);
      } catch {
        return sendJson(res, 200, { ok: false, error: 'not_found' });
      }
      const entries = [];
      for (const name of names.slice(0, 200)) {
        let type = '?';
        let size = 0;
        try {
          const st = await stat(dp + (dp.endsWith('/') ? '' : '/') + name);
          type = st.isDirectory() ? 'd' : 'f';
          size = st.size;
        } catch {}
        entries.push({ name, type, size });
      }
      return sendJson(res, 200, { ok: true, entries });
    }

    return sendJson(res, 404, { ok: false, error: 'not_found' });
  } catch (err) {
    try {
      sendJson(res, 500, { ok: false, error: err.message });
    } catch {}
  }
});

process.on('uncaughtException', (err) => {
  console.error('[uncaughtException]', err);
});
process.on('unhandledRejection', (err) => {
  console.error('[unhandledRejection]', err);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`task_runner listening on 0.0.0.0:${PORT}`);
});
