// postinstall 补丁：@cloudflare/containers 的 dist 里 import 没带 .js 后缀，
// wrangler/esbuild 打包无所谓，但本地和 CI 的 `node selftest.mjs` 用纯 Node ESM 解析会炸
// （ERR_MODULE_NOT_FOUND）。把相对导入补上 .js 后缀，幂等。
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), 'node_modules', '@cloudflare', 'containers', 'dist');

function* walk(dir) {
  for (const name of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, name.name);
    if (name.isDirectory()) yield* walk(p);
    else if (name.name.endsWith('.js')) yield p;
  }
}

let patched = 0;
for (const file of walk(root)) {
  let src = readFileSync(file, 'utf8');
  const out = src.replace(/(from\s+|import\s*\(\s*)(['"])(\.\.?\/[^'"]+)\2/g, (m, pre, q, spec) => {
    if (spec.endsWith('.js') || spec.endsWith('.json')) return m;
    if (existsSync(join(dirname(file), spec + '.js'))) { patched++; return `${pre}${q}${spec}.js${q}`; }
    return m;
  });
  if (out !== src) writeFileSync(file, out);
}
console.log(`fix-containers-esm: patched ${patched} imports`);
