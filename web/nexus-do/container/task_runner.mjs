import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, writeFile, readdir, mkdir } from 'node:fs/promises';
import { dirname, resolve, relative, join } from 'node:path';
import { chromium } from 'playwright-core';

const PORT = process.env.PORT || 8080;
const TASK_TOKEN = process.env.TASK_TOKEN || '';
const REQUIRE_AUTH = TASK_TOKEN.length > 0;

let _browser = null;
async function getBrowser() {
  if (!_browser || !_browser.isConnected()) {
    _browser = await chromium.launch({
      executablePath: process.env.CHROME_PATH || '/usr/bin/chromium-browser',
      headless: true,
      args: ['--no-sandbox', '--disable-dev-shm-usage']
    });
  }
  return _browser;
}

process.on('SIGTERM', async () => {
  if (_browser) await _browser.close().catch(() => {});
  process.exit(0);
});
process.on('SIGINT', async () => {
  if (_browser) await _browser.close().catch(() => {});
  process.exit(0);
});

function authorize(req) {
  if (!REQUIRE_AUTH) return true;
  const auth = req.headers['authorization'] || '';
  return auth === `Bearer ${TASK_TOKEN}`;
}

function validatePath(p) {
  if (!p.startsWith('/tmp/')) return false;
  if (p.includes('..')) return false;
  return true;
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

function killProcessGroup(pid) {
  try {
    process.kill(-pid, 'SIGKILL');
  } catch (e) {}
}

async function handleExec(body) {
  const { command, timeout = 30 } = body;
  if (!command) return { ok: false, error: 'command required' };

  return new Promise((resolve) => {
    const child = spawn('/bin/sh', ['-c', command], {
      detached: true,
      timeout: timeout * 1000
    });

    let stdout = '', stderr = '';
    let killed = false;

    const timer = setTimeout(() => {
      killed = true;
      killProcessGroup(child.pid);
    }, timeout * 1000);

    child.stdout.on('data', (d) => {
      stdout += d.toString();
      if (stdout.length > 8000) stdout = stdout.slice(0, 8000);
    });

    child.stderr.on('data', (d) => {
      stderr += d.toString();
      if (stderr.length > 2000) stderr = stderr.slice(0, 2000);
    });

    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        ok: true,
        exitCode: killed ? null : code,
        stdout: stdout.slice(0, 8000),
        stderr: stderr.slice(0, 2000),
        killed
      });
    });

    child.on('error', (err) => {
      clearTimeout(timer);
      resolve({ ok: false, error: err.message });
    });
  });
}

async function handleEdit(body) {
  const { path, search, replace } = body;
  if (!path || !search || replace === undefined) {
    return { ok: false, error: 'path, search, replace required' };
  }
  if (!validatePath(path)) {
    return { ok: false, error: 'path must start with /tmp/ and not contain ..' };
  }

  try {
    const content = await readFile(path, 'utf8');
    const matches = content.split(search).length - 1;
    
    if (matches === 0) {
      return { ok: false, error: 'search string not found' };
    }
    if (matches > 1) {
      return { ok: false, error: 'search string not unique', matches };
    }

    const newContent = content.replace(search, replace);
    await writeFile(path, newContent, 'utf8');
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function handleRead(body) {
  const { path, start = 1, end } = body;
  if (!path) return { ok: false, error: 'path required' };
  if (!validatePath(path)) {
    return { ok: false, error: 'path must start with /tmp/ and not contain ..' };
  }

  try {
    const content = await readFile(path, 'utf8');
    const lines = content.split('\n');
    const s = Math.max(1, start);
    const e = end ? Math.min(lines.length, end) : lines.length;
    const slice = lines.slice(s - 1, e);
    
    return {
      ok: true,
      content: slice.join('\n'),
      lines: slice.length,
      total: lines.length
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function handleWrite(body) {
  const { path, content } = body;
  if (!path || content === undefined) {
    return { ok: false, error: 'path and content required' };
  }
  if (!validatePath(path)) {
    return { ok: false, error: 'path must start with /tmp/ and not contain ..' };
  }

  try {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, content, 'utf8');
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function handleLs(body) {
  const { path } = body;
  if (!path) return { ok: false, error: 'path required' };
  if (!validatePath(path)) {
    return { ok: false, error: 'path must start with /tmp/ and not contain ..' };
  }

  try {
    const entries = await readdir(path, { withFileTypes: true });
    const items = entries.map(e => ({
      name: e.name,
      isDirectory: e.isDirectory()
    }));
    return { ok: true, items };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function handleDef(body) {
  const { symbol, path = '/tmp/ws' } = body;
  if (!symbol) return { ok: false, error: 'symbol required' };
  if (!validatePath(path)) {
    return { ok: false, error: 'path must start with /tmp/ and not contain ..' };
  }

  return new Promise((resolve) => {
    const child = spawn('ctags', ['-R', '--output-format=json', '--fields={name}{input}{line}{kind}{pattern}', '-f', '-'], {
      cwd: path,
      timeout: 30000
    });

    let stdout = '';
    const results = [];

    child.stdout.on('data', (d) => {
      stdout += d.toString();
    });

    child.on('close', () => {
      const lines = stdout.trim().split('\n');
      for (const line of lines) {
        if (!line) continue;
        try {
          const entry = JSON.parse(line);
          if (entry.name === symbol) {
            results.push({
              path: entry.path,
              line: entry.line || null,
              kind: entry.kind || null,
              pattern: entry.pattern || null
            });
            if (results.length >= 50) break;
          }
        } catch (e) {}
      }
      resolve({ ok: true, results, count: results.length });
    });

    child.on('error', (err) => {
      resolve({ ok: false, error: err.message });
    });
  });
}

async function handleRefs(body) {
  const { symbol, path = '/tmp/ws' } = body;
  if (!symbol) return { ok: false, error: 'symbol required' };
  if (!validatePath(path)) {
    return { ok: false, error: 'path must start with /tmp/ and not contain ..' };
  }

  return new Promise((resolve) => {
    // BusyBox grep（alpine 镜像）没有 --include/--exclude-dir，只跑 -rn，过滤全在 JS 里做
    const child = spawn('grep', ['-rn', '-w', '-s', symbol, path], { timeout: 30000 });

    let stdout = '';
    child.stdout.on('data', (d) => {
      stdout += d.toString();
    });

    child.on('close', () => {
      const allowExt = ['.js', '.mjs', '.ts', '.py', '.html'];
      const lines = stdout.trim().split('\n').filter(l => l);
      const results = [];

      for (const line of lines) {
        const match = line.match(/^(.+?):(\d+):(.*)$/);
        if (!match) continue;
        const [, filePath, lineNum, text] = match;
        const rel = relative(path, filePath);
        if (/(^|\/)(\.git|node_modules)\//.test(rel)) continue;
        if (!allowExt.some(ext => rel.endsWith(ext))) continue;
        results.push({ path: rel, line: parseInt(lineNum, 10), text: text.slice(0, 160) });
        if (results.length >= 100) break;
      }

      resolve({ ok: true, results, count: results.length });
    });

    child.on('error', (err) => {
      resolve({ ok: false, error: err.message });
    });
  });
}

async function handleBrowse(body) {
  const { url, actions = [], screenshot = false, timeout = 25 } = body;
  if (!url) return { ok: false, error: 'url required' };

  let page = null;
  try {
    const browser = await getBrowser();
    page = await browser.newPage({
      viewport: { width: 1280, height: 800 },
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Safari/605.1.15'
    });

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeout * 1000 });
    await page.waitForTimeout(1500);

    const actionErrors = [];
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      try {
        if (action.type === 'click') {
          await page.click(action.selector, { timeout: 5000 });
        } else if (action.type === 'type') {
          await page.fill(action.selector, action.text);
        } else if (action.type === 'scroll') {
          await page.evaluate(() => window.scrollBy(0, 800));
        } else if (action.type === 'wait') {
          await page.waitForTimeout(action.ms || 1000);
        }
      } catch (err) {
        actionErrors.push({ index: i, error: err.message.slice(0, 200) });
      }
    }

    const title = await page.title();
    const finalUrl = page.url();
    const text = (await page.evaluate(() => document.body.innerText)).slice(0, 4000);

    const result = { ok: true, title, url: finalUrl, text };
    if (actionErrors.length > 0) result.actionErrors = actionErrors;

    if (screenshot) {
      const buffer = await page.screenshot({ type: 'jpeg', quality: 60, fullPage: false });
      result.screenshot = buffer.toString('base64');
    }

    await page.close();
    return result;
  } catch (err) {
    if (page) await page.close().catch(() => {});
    return { ok: false, error: err.message.slice(0, 200) };
  }
}

const server = createServer(async (req, res) => {
  const log = `${new Date().toISOString()} ${req.method} ${req.url}`;
  console.log(log);

  res.setHeader('Content-Type', 'application/json');

  if (!authorize(req)) {
    res.writeHead(401);
    res.end(JSON.stringify({ ok: false, error: 'unauthorized' }));
    return;
  }

  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200);
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  if (req.method === 'POST') {
    let body;
    try {
      const raw = await readBody(req);
      body = JSON.parse(raw);
    } catch (e) {
      res.writeHead(400);
      res.end(JSON.stringify({ ok: false, error: 'invalid JSON' }));
      return;
    }

    let result;
    if (req.url === '/exec') {
      result = await handleExec(body);
    } else if (req.url === '/edit') {
      result = await handleEdit(body);
    } else if (req.url === '/read') {
      result = await handleRead(body);
    } else if (req.url === '/write') {
      result = await handleWrite(body);
    } else if (req.url === '/ls') {
      result = await handleLs(body);
    } else if (req.url === '/def') {
      result = await handleDef(body);
    } else if (req.url === '/refs') {
      result = await handleRefs(body);
    } else if (req.url === '/browse') {
      result = await handleBrowse(body);
    } else {
      res.writeHead(404);
      res.end(JSON.stringify({ ok: false, error: 'not found' }));
      return;
    }

    res.writeHead(200);
    res.end(JSON.stringify(result));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ ok: false, error: 'not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`task_runner listening on ${PORT}`);
});

process.on('uncaughtException', (err) => {
  console.error('uncaughtException:', err);
});

process.on('unhandledRejection', (err) => {
  console.error('unhandledRejection:', err);
});
