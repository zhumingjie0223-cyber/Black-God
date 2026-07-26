// QueryPlanner.js — 升级版 (ES Module)

const CHITCHAT = /^(hi|hello|hey|thanks?|thank you|你好|谢谢|哈喽|嗨|在吗|再见|bye|ok|okay|好的|嗯+)[\s!.,?！。，？]*$/i;
const YEAR_RE = /\b(19|20)\d{2}\b/;
const CJK_RE = /[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/;
const SPLIT_RE = /\s*\b(?:and|or|以及|还有|或者|与)\b\s*/i;
const STOPWORDS = new Set(['the','a','an','is','are','of','to','in','on','for','and','or','的','了','是','在','和','与']);

function toStr(v) {
  if (v == null) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  try { return String(v); } catch { return ''; }
}

function _withTimeout(promise, ms, signal) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    const onAbort = () => { clearTimeout(t); reject(new Error('aborted')); };
    if (signal) signal.addEventListener('abort', onAbort, { once: true });
    promise.then(
      (v) => { clearTimeout(t); resolve(v); },
      (e) => { clearTimeout(t); reject(e); }
    );
  });
}

// 并发池执行
async function _pool(items, worker, concurrency) {
  const results = new Array(items.length);
  let idx = 0;
  const runners = new Array(Math.min(concurrency, items.length)).fill(0).map(async () => {
    while (idx < items.length) {
      const i = idx++;
      try { results[i] = await worker(items[i], i); }
      catch (e) { results[i] = { error: e, query: items[i], hits: [] }; }
    }
  });
  await Promise.all(runners);
  return results;
}

// 中日韩 + 拉丁分词
function tokenize(text) {
  const tokens = [];
  const parts = text.match(/[a-zA-Z0-9]+|[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/g) || [];
  for (const p of parts) {
    if (CJK_RE.test(p)) tokens.push(p);
    else if (p.length > 1 && !STOPWORDS.has(p.toLowerCase())) tokens.push(p.toLowerCase());
  }
  return tokens;
}

export class QueryPlanner {
  constructor({ searchFn, maxSubQueries = 5, maxHitsPerQuery = 20, concurrency = 4, timeoutMs = 8000 } = {}) {
    if (typeof searchFn !== 'function') {
      throw new TypeError('QueryPlanner: searchFn must be a function');
    }
    this.searchFn = searchFn;
    this.maxSubQueries = maxSubQueries;
    this.maxHitsPerQuery = maxHitsPerQuery;
    this.concurrency = concurrency;
    this.timeoutMs = timeoutMs;
  }

  // 拆分为子查询：词边界切分 + 过滤空 + 去重
  planSubQueries(input) {
    const q = toStr(input).trim();
    if (!q) return [];
    const rawParts = q.split(SPLIT_RE);
    const seen = new Set();
    const out = [];
    for (const part of rawParts) {
      const sub = part.trim();
      if (!sub) continue;
      const key = sub.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(sub);
      if (out.length >= this.maxSubQueries) break;
    }
    return out.length ? out : [q];
  }

  isChitchat(input) {
    const q = toStr(input).trim();
    return !q || CHITCHAT.test(q);
  }

  _freshness(hit) {
    const text = toStr(hit && (hit.date || hit.publishedAt || hit.text || hit.title));
    const m = text.match(YEAR_RE);
    if (!m) return 0.5;
    const year = parseInt(m[0], 10);
    const cur = new Date().getFullYear();
    const age = Math.max(0, cur - year);
    return Math.max(0.2, 1 - age * 0.1);
  }

  _entailment(query, hit) {
    const qTokens = new Set(tokenize(query));
    if (qTokens.size === 0) return 0;
    const hTokens = new Set(tokenize(toStr(hit && (hit.text || hit.title || hit.snippet))));
    let overlap = 0;
    for (const t of qTokens) if (hTokens.has(t)) overlap++;
    return overlap / qTokens.size;
  }

  _sourceQuality(hit) {
    const s = hit && typeof hit.sourceQuality === 'number' ? hit.sourceQuality : null;
    if (s != null) return Math.max(0, Math.min(1, s));
    const url = toStr(hit && hit.url).toLowerCase();
    if (/\.(gov|edu)\b/.test(url)) return 0.95;
    if (/wikipedia|\.org\b/.test(url)) return 0.8;
    if (url) return 0.6;
    return 0.5;
  }

  _score(query, hit) {
    const e = this._entailment(query, hit);
    const s = this._sourceQuality(hit);
    const f = this._freshness(hit);
    return { confidence: e * s * f, entailment: e, sourceQuality: s, freshness: f };
  }

  async run(input, { signal } = {}) {
    const query = toStr(input).trim();
    if (this.isChitchat(query)) {
      return { chitchat: true, query, results: [] };
    }

    const subQueries = this.planSubQueries(query);
    const controller = new AbortController();
    if (signal) signal.addEventListener('abort', () => controller.abort(), { once: true });

    const worker = async (sub) => {
      const raw = await _withTimeout(
        Promise.resolve(this.searchFn(sub, { signal: controller.signal, limit: this.maxHitsPerQuery })),
        this.timeoutMs,
        controller.signal
      );
      const hits = (Array.isArray(raw) ? raw : raw && Array.isArray(raw.hits) ? raw.hits : [])
        .slice(0, this.maxHitsPerQuery);
      return { query: sub, hits };
    };

    const perQuery = await _pool(subQueries, worker, this.concurrency);

    const merged = [];
    const seenHits = new Set();
    for (const r of perQuery) {
      if (!r || r.error) continue;
      for (const hit of r.hits) {
        const id = toStr(hit && (hit.id || hit.url || hit.text || hit.title));
        if (!id || seenHits.has(id)) continue;
        seenHits.add(id);
        merged.push({ ...hit, ...this._score(r.query, hit), matchedQuery: r.query });
      }
    }

    merged.sort((a, b) => b.confidence - a.confidence);
    return { chitchat: false, query, subQueries, results: merged };
  }
}

export default QueryPlanner;
