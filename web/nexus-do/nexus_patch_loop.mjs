// PatchAgentLoop.js — Cursor-style 6-primitive patch loop

/**
 * @typedef {Object} PatchTools
 * @property {(args: { task: any, plan: any, diagnostics: any }) => Promise<string[]>} search
 *   Locate relevant files. Should resolve to an array of file paths.
 * @property {(args: { paths: string[] }) => Promise<Record<string, string>>} read
 *   Read file contents. Should resolve to a map of path -> content.
 * @property {(args: { task: any, files: Record<string, string>, previousPlan: any, diagnostics: any }) => Promise<{ finish?: boolean }>} plan
 *   Derive the next edit intent.
 * @property {(args: { plan: any, files: Record<string, string> }) => Promise<{ updatedFiles?: Record<string, string> }>} applyPatch
 *   Apply the patch and optionally return updated file contents.
 * @property {(args: { files: Record<string, string>, patch: any }) => Promise<{ errors?: any[] } | null>} getDiagnostics
 *   Run typecheck / lint / test. Non-empty `errors` triggers a repair.
 * @property {(args: { plan: any, patch: any, diagnostics: any }) => Promise<any>} repair
 *   Refine the plan for the next round.
 * @property {(args: { plan: any, files: Record<string, string> }) => Promise<any>} finish
 *   Finalize and produce the result.
 */

/**
 * @typedef {Object} PatchLoopOptions
 * @property {number} [maxRounds=8]  Maximum number of iterations before aborting.
 * @property {boolean} [throwOnError=false]  If true, tool errors abort the loop by throwing;
 *   otherwise the loop terminates gracefully and reports the failure in the result.
 */

/**
 * @typedef {Object} PatchLoopResult
 * @property {boolean} ok           Whether the loop completed successfully.
 * @property {number} rounds        Number of rounds executed.
 * @property {any} result           The value returned by `tools.finish`, if any.
 * @property {any} diagnostics      The last diagnostics object seen.
 * @property {Array<Object>} trace  Ordered execution trace of every step.
 * @property {string} [error]       Present when the loop aborted due to an error.
 */

// --- CHANGE: required-tool validation so we fail fast with a clear message ---
const REQUIRED_TOOLS = /** @type {const} */ ([
  'search',
  'read',
  'plan',
  'applyPatch',
  'getDiagnostics',
  'repair',
  'finish',
]);

/**
 * Run a Cursor-style 6-primitive patch loop:
 * search → read → plan → applyPatch → getDiagnostics → repair, iterating until
 * diagnostics are clean, the plan signals completion, or `maxRounds` is reached.
 *
 * @param {any} task                     The task description passed to the tools.
 * @param {PatchTools} tools             The tool implementations backing each primitive.
 * @param {PatchLoopOptions} [opts={}]   Loop configuration.
 * @returns {Promise<PatchLoopResult>}   Structured outcome of the loop.
 * @throws {TypeError} If `tools` is missing required functions (always thrown — invalid setup).
 * @throws {Error} If a tool fails and `opts.throwOnError` is true.
 */
export async function runPatchAgentLoop(task, tools, opts = {}) {
  // --- CHANGE: validate tools up front instead of crashing mid-loop ---
  if (!tools || typeof tools !== 'object') {
    throw new TypeError('runPatchAgentLoop: `tools` must be an object.');
  }
  for (const name of REQUIRED_TOOLS) {
    if (typeof tools[name] !== 'function') {
      throw new TypeError(`runPatchAgentLoop: missing required tool "${name}" (must be a function).`);
    }
  }

  // --- CHANGE: guard maxRounds against NaN / <1 / non-integer inputs ---
  const rawMax = opts.maxRounds ?? 8;
  const maxRounds =
    Number.isFinite(rawMax) && rawMax >= 1 ? Math.floor(rawMax) : 8;
  const throwOnError = opts.throwOnError === true;

  const trace = [];
  const ctx = {
    task,
    searchHits: null,
    readFiles: {},
    plan: null,
    lastPatch: null,
    lastDiagnostics: null,
    repairs: 0,
    done: false,
    result: null,
  };

  // --- CHANGE: declare `round` BEFORE `step` (fixes TDZ/scope bug — the
  // original referenced `round` inside `step` before it was declared) ---
  let round = 0;

  /**
   * Execute a named step, timing it and recording the outcome in the trace.
   * @template T
   * @param {string} name       Step label.
   * @param {() => Promise<T>} fn  The async work to run.
   * @returns {Promise<T>}
   */
  const step = async (name, fn) => {
    const t0 = Date.now();
    try {
      const output = await fn();
      trace.push({ round, step: name, ok: true, ms: Date.now() - t0, output });
      return output;
    } catch (err) {
      trace.push({
        round,
        step: name,
        ok: false,
        ms: Date.now() - t0,
        error: String(err?.message ?? err),
      });
      throw err;
    }
  };

  // --- CHANGE: normalize search results to a clean string[] so `read`,
  // `filter`, and `readFiles` indexing never choke on null/non-array/non-string ---
  const normalizeHits = (hits) =>
    Array.isArray(hits) ? hits.filter((p) => typeof p === 'string' && p.length > 0) : [];

  try {
    while (round < maxRounds && !ctx.done) {
      round++;

      // 1. search — locate relevant files
      if (!ctx.searchHits || ctx.repairs > 0) {
        const hits = await step('search', () =>
          tools.search({ task: ctx.task, plan: ctx.plan, diagnostics: ctx.lastDiagnostics })
        );
        ctx.searchHits = normalizeHits(hits); // --- CHANGE: sanitize ---
      }

      // 2. read — pull file contents feeding search hits
      const toRead = (ctx.searchHits ?? []).filter((p) => !(p in ctx.readFiles));
      if (toRead.length) {
        const contents = await step('read', () => tools.read({ paths: toRead }));
        // --- CHANGE: only merge object results; ignore malformed tool output ---
        if (contents && typeof contents === 'object') {
          Object.assign(ctx.readFiles, contents);
        }
      }

      // 3. plan — derive next edit intent from files + diagnostics
      ctx.plan = await step('plan', () =>
        tools.plan({
          task: ctx.task,
          files: ctx.readFiles,
          previousPlan: ctx.plan,
          diagnostics: ctx.lastDiagnostics,
        })
      );

      if (ctx.plan?.finish) {
        ctx.result = await step('finish', () =>
          tools.finish({ plan: ctx.plan, files: ctx.readFiles })
        );
        ctx.done = true;
        break;
      }

      // 4. applyPatch — mutate files
      ctx.lastPatch = await step('applyPatch', () =>
        tools.applyPatch({ plan: ctx.plan, files: ctx.readFiles })
      );
      // --- CHANGE: guard updatedFiles shape before merging ---
      if (ctx.lastPatch?.updatedFiles && typeof ctx.lastPatch.updatedFiles === 'object') {
        Object.assign(ctx.readFiles, ctx.lastPatch.updatedFiles);
      }

      // 5. getDiagnostics — typecheck / lint / test
      ctx.lastDiagnostics = await step('getDiagnostics', () =>
        tools.getDiagnostics({ files: ctx.readFiles, patch: ctx.lastPatch })
      );

      const clean =
        !ctx.lastDiagnostics ||
        (Array.isArray(ctx.lastDiagnostics.errors) && ctx.lastDiagnostics.errors.length === 0);

      if (clean) {
        ctx.result = await step('finish', () =>
          tools.finish({ plan: ctx.plan, files: ctx.readFiles })
        );
        ctx.done = true;
        break;
      }

      // 6. repair — refine plan for next round
      await step('repair', () =>
        tools.repair({
          plan: ctx.plan,
          patch: ctx.lastPatch,
          diagnostics: ctx.lastDiagnostics,
        })
      );
      ctx.repairs++;
    }
  } catch (err) {
    // --- CHANGE: wrap the loop so a tool failure produces a structured result
    // instead of an unhandled rejection (unless caller opts into throwing) ---
    const message = String(err?.message ?? err);
    trace.push({ round, step: 'error', ok: false, error: message });
    if (throwOnError) throw err;
    return {
      ok: false,
      rounds: round,
      result: ctx.result,
      diagnostics: ctx.lastDiagnostics,
      trace,
      error: message,
    };
  }

  if (!ctx.done) {
    trace.push({ round, step: 'abort', ok: false, error: `maxRounds ${maxRounds} exhausted` });
  }

  return {
    ok: ctx.done,
    rounds: round,
    result: ctx.result,
    diagnostics: ctx.lastDiagnostics,
    trace,
  };
}
