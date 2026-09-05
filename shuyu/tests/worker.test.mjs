// worker.mjs 路由集成测试 — node --test（Mock KV，无需 Workers 运行时）
import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.mjs';

function mockEnv() {
  const store = new Map();
  return {
    SOUL: {
      async get(k) { return store.has(k) ? store.get(k) : null; },
      async put(k, v) { store.set(k, v); },
    },
    _store: store,
  };
}

const call = (env, path, init) =>
  worker.fetch(new Request(`https://shuyu.example${path}`, init), env);

test('GET / 返回引擎元信息', async () => {
  const res = await call(mockEnv(), '/');
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.capacity, 7_667_712_000);
  assert.ok(Array.isArray(body.endpoints));
});

test('GET /decode 正常与校验', async () => {
  const env = mockEnv();
  const ok = await (await call(env, '/decode?id=888888888')).json();
  assert.equal(ok.词, 'Nix-teks-ia1-h·qi');
  assert.equal((await call(env, '/decode?id=abc')).status, 400);
  assert.equal((await call(env, '/decode?id=-1')).status, 400);
  assert.equal((await call(env, '/decode?id=7667712000')).status, 400);
  assert.equal((await call(env, '/decode')).status, 400);
});

test('GET /encode 往返与非法词', async () => {
  const env = mockEnv();
  const ok = await (await call(env, '/encode?word=Nix-teks-ia1-h%C2%B7qi')).json();
  assert.equal(ok.id, 888888888);
  assert.equal((await call(env, '/encode?word=notaword')).status, 400);
  assert.equal((await call(env, '/encode')).status, 400);
});

test('GET /coin 种子可复现', async () => {
  const env = mockEnv();
  const a = await (await call(env, '/coin?seed=abc')).json();
  const b = await (await call(env, '/coin?seed=abc')).json();
  assert.deepEqual(a, b);
  const layered = await (await call(env, '/coin?layer=%E6%83%85%E6%84%9F')).json();
  assert.equal(layered.层, '情感');
  const bare = await call(env, '/coin');
  assert.equal(bare.status, 200);
});

test('POST /talk 解释意识流并持久化灵魂', async () => {
  const env = mockEnv();
  const res = await call(env, '/talk', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: 'feel "他说想我" → 暖\nbecome: mood+0.2' }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.result.perception.emotion, '暖');
  assert.ok(env._store.has('SOUL'), '灵魂状态应写入 KV');
  // 非 JSON / 缺字段
  assert.equal((await call(env, '/talk', { method: 'POST', body: 'x' })).status, 400);
  assert.equal((await call(env, '/talk', {
    method: 'POST', body: JSON.stringify({}),
  })).status, 400);
});

test('POST /broadcast 万网散播全流程', async () => {
  const env = mockEnv();
  const body = await (await call(env, '/broadcast', { method: 'POST' })).json();
  assert.equal(body.broadcast, 'STAS-LOCK-REAL');
  assert.ok(body.state.persona, '散播后人格显现');
  assert.ok(env._store.has('SOUL'));
});

test('GET /status 无 KV 绑定也不崩', async () => {
  const res = await call({}, '/status');
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.deepEqual(body.soul, {});
});

test('未知路由 404，OPTIONS 204', async () => {
  assert.equal((await call(mockEnv(), '/nope')).status, 404);
  assert.equal((await call(mockEnv(), '/talk', { method: 'OPTIONS' })).status, 204);
});

// ══════ v4.1 新路由（2026-09-05）：汉译反查 / 语义检索 / 按义造词 ══════

test('GET /encode 同时接受拉丁与汉译，两种写法同源', async () => {
  const env = mockEnv();
  const lat = await (await call(env, '/encode?word=Nix-teks-ia1-h%C2%B7qi')).json();
  const han = await (await call(env, `/encode?word=${encodeURIComponent('尼异朱极一外起')}`)).json();
  assert.equal(lat.form, '拉丁');
  assert.equal(han.form, '汉译');
  assert.equal(han.id, lat.id);
  // ?han= 别名也认
  const alias = await (await call(env, `/encode?han=${encodeURIComponent('奥形凝起')}`)).json();
  assert.equal(alias.id, 0);
  // 畸形汉译照样 400
  assert.equal((await call(env, `/encode?word=${encodeURIComponent('奥形凝起起')}`)).status, 400);
});

test('GET /search 语义检索与参数校验', async () => {
  const env = mockEnv();
  const r = await (await call(env, `/search?q=${encodeURIComponent('毁灭')}`)).json();
  assert.equal(r.count, 1);
  assert.equal(r.hits[0].拉丁, 'Nix');
  const scoped = await (await call(env, `/search?q=gal&axis=${encodeURIComponent('标')}`)).json();
  assert.deepEqual(scoped.hits.map(h => h.汉), ['时光']);
  assert.equal((await call(env, '/search')).status, 400);
  assert.equal((await call(env, '/search?q=x&axis=z')).status, 400);
  const none = await (await call(env, `/search?q=${encodeURIComponent('绝不存在')}`)).json();
  assert.equal(none.count, 0);
});

test('GET /compose 按义造词：成功 / 解析失败 400 / 空参 400', async () => {
  const env = mockEnv();
  const q = new URLSearchParams({ 核: '毁灭', 映: '光', 态: '爆', 标: '溯', 相: '起' }).toString();
  const w = await (await call(env, `/compose?${q}`)).json();
  assert.equal(w.汉, '尼光爆溯起');
  assert.equal(w.id, 885744896);
  assert.deepEqual(w.spec, { 核: '毁灭', 映: '光', 态: '爆', 标: '溯', 相: '起' });
  const short = await (await call(env, '/compose?c=120&m=24&s=50&k=32&p=0')).json();
  assert.equal(short.id, 885744896);
  const bad = await call(env, `/compose?${new URLSearchParams({ 核: '绝不存在' })}`);
  assert.equal(bad.status, 400);
  assert.match((await bad.json()).error, /核轴找不到/);
  assert.equal((await call(env, '/compose')).status, 400);
  assert.equal((await call(env, '/compose?foo=bar')).status, 400);
});

test('GET / 与 /status 带轴尺寸与新路由清单', async () => {
  const root = await (await call(mockEnv(), '/')).json();
  assert.deepEqual(root.axes, { 核: 1040, 映: 180, 态: 80, 标: 64, 相: 8 });
  assert.ok(root.endpoints.some(e => e.startsWith('/search')));
  assert.ok(root.endpoints.some(e => e.startsWith('/compose')));
  const st = await (await call(mockEnv(), '/status')).json();
  assert.deepEqual(st.axes, root.axes);
});
