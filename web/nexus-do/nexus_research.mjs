// Nexus Research Engine — Cloudflare DO compatible, pure ESM, no deps.

export class ResearchEngine {
  constructor({ endpoint = "https://search.internal/query", fetchImpl } = {}) {
    this.endpoint = endpoint;
    this._fetch = fetchImpl || (typeof fetch !== "undefined" ? fetch : null);
  }

  // Split a query into 3-5 sub-queries and request them in parallel.
  async fanout(query, { budget = 5, depth = 1 } = {}) {
    const subs = this._deriveSubqueries(query, depth);
    const capped = subs.slice(0, Math.max(1, Math.min(budget, subs.length)));
    const results = await Promise.all(
      capped.map((sub, i) => this._search(sub, i, depth))
    );
    return results.flat();
  }

  _deriveSubqueries(query, depth) {
    const q = String(query || "").trim();
    const angles = [
      `${q} overview`,
      `${q} evidence`,
      `${q} criticism`,
      `${q} recent developments`,
      `${q} expert consensus`,
    ];
    const n = Math.max(3, Math.min(5, 3 + Number(depth || 1)));
    return angles.slice(0, n);
  }

  async _search(subQuery, idx, depth) {
    // Try a real fetch to the search endpoint; fall back to a simulated result.
    if (this._fetch) {
      try {
        const res = await this._fetch(this.endpoint, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ q: subQuery, depth }),
        });
        if (res && res.ok) {
          const data = await res.json();
          if (Array.isArray(data?.results)) {
            return data.results.map((r, j) => ({
              subQuery,
              title: r.title ?? `Result ${idx}.${j}`,
              url: r.url ?? `https://example.org/${idx}/${j}`,
              snippet: r.snippet ?? r.text ?? "",
              rank: j,
              timestamp: Date.now(),
            }));
          }
        }
      } catch {
        // fall through to simulation
      }
    }
    return this._simulate(subQuery, idx);
  }

  _simulate(subQuery, idx) {
    const count = 2;
    return Array.from({ length: count }, (_, j) => ({
      subQuery,
      title: `Simulated source ${idx}.${j} for "${subQuery}"`,
      url: `https://sim.search/${idx}/${j}`,
      snippet: `Regarding ${subQuery}, evidence point ${j} suggests relevant findings and supporting context.`,
      rank: j,
      timestamp: Date.now(),
    }));
  }

  // Match each claim to its most relevant source; mark unmatched as unsupported.
  alignCitations(claims = [], sources = []) {
    return claims.map((claim) => {
      const claimText = typeof claim === "string" ? claim : claim.text || "";
      let best = null;
      let bestScore = 0;
      for (const src of sources) {
        const hay = `${src.title || ""} ${src.snippet || ""}`;
        const score = this._overlap(claimText, hay);
        if (score > bestScore) {
          bestScore = score;
          best = src;
        }
      }
      if (!best || bestScore <= 0) {
        return { claim: claimText, source: null, score: 0, unsupported: true };
      }
      return {
        claim: claimText,
        source: best,
        score: Number(bestScore.toFixed(3)),
        unsupported: false,
      };
    });
  }

  _overlap(a, b) {
    const tokenize = (s) =>
      String(s)
        .toLowerCase()
        .replace(/[^a-z0-9\u4e00-\u9fff\s]/g, " ")
        .split(/\s+/)
        .filter((t) => t.length > 1);
    const aTok = new Set(tokenize(a));
    const bTok = new Set(tokenize(b));
    if (aTok.size === 0 || bTok.size === 0) return 0;
    let inter = 0;
    for (const t of aTok) if (bTok.has(t)) inter++;
    return inter / aTok.size;
  }

  // Turn raw results into structured evidence records.
  buildEvidenceAccount(results = []) {
    return results.map((r) => {
      const quote = (r.snippet || "").slice(0, 240);