// nexus_plan_state.mjs
// Editable Plan state machine for Cloudflare Durable Objects.
// Pure ES Module, no external dependencies.

const VALID_STATUSES = ['pending', 'in-progress', 'done', 'blocked', 'failed'];

const TRANSITIONS = {
  pending: ['in-progress', 'blocked', 'failed'],
  'in-progress': ['done', 'blocked', 'failed'],
  blocked: ['pending', 'in-progress', 'failed'],
  failed: ['pending', 'in-progress'],
  done: ['in-progress'], // allow reopening
};

function nowISO() {
  return new Date().toISOString();
}

function genId() {
  return 'step_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}

function storageKey(planId) {
  return `plan:${planId}`;
}

export class PlanStateMachine {
  constructor(planId, steps = [], version = 0) {
    this.planId = planId;
    this.steps = steps.map((s) => this._normalizeStep(s));
    this.version = version;
  }

  _normalizeStep(s) {
    return {
      id: s.id || genId(),
      title: s.title || '',
      status: VALID_STATUSES.includes(s.status) ? s.status : 'pending',
      deps: Array.isArray(s.deps) ? [...s.deps] : [],
      result: s.result ?? null,
      createdAt: s.createdAt || nowISO(),
    };
  }

  _getStep(stepId) {
    return this.steps.find((s) => s.id === stepId);
  }

  _depsSatisfied(step) {
    return step.deps.every((depId) => {
      const dep = this._getStep(depId);
      return dep && dep.status === 'done';
    });
  }

  /**
   * Transition a step to a new status.
   * Enforces deps must all be done before moving to in-progress.
   */
  transition(stepId, toStatus, result) {
    const step = this._getStep(stepId);
    if (!step) throw new Error(`step not found: ${stepId}`);
    if (!VALID_STATUSES.includes(toStatus)) {
      throw new Error(`invalid status: ${toStatus}`);
    }

    const allowed = TRANSITIONS[step.status] || [];
    if (step.status !== toStatus && !allowed.includes(toStatus)) {
      throw new Error(
        `invalid transition: ${step.status} -> ${toStatus} (step ${stepId})`
      );
    }

    if (toStatus === 'in-progress' && !this._depsSatisfied(step)) {
      throw new Error(`deps not satisfied for step ${stepId}`);
    }

    step.status = toStatus;
    if (result !== undefined) step.result = result;
    return step;
  }

  /**
   * Human/manual plan editing.
   * patch = { add: [step], remove: [id], reorder: [id] }
   */
  editPlan(patch = {}) {
    const { add, remove, reorder } = patch;

    if (Array.isArray(remove) && remove.length) {
      const removeSet = new Set(remove);
      this.steps = this.steps.filter((s) => !removeSet.has(s.id));
      // clean dangling deps
      for (const s of this.steps) {
        s.deps = s.deps.filter((d) => !removeSet.has(d));
      }
    }

    if (Array.isArray(add) && add.length) {
      for (const s of add) {
        const step = this._normalizeStep(s);
        if (this._getStep(step.id)) {
          throw new Error(`duplicate step id: ${step.id}`);
        }
        this.steps.push(step);
      }
    }

    if (Array.isArray(reorder) && reorder.length) {
      const byId = new Map(this.steps.map((s) => [s.id, s]));
      const ordered = [];
      for (const id of reorder) {
        const s = byId.get(id);
        if (s) {
          ordered.push(s);
          byId.delete(id);
        }
      }
      // append any steps not mentioned in reorder, preserving prior order
      for (const s of this.steps) {
        if (byId.has(s.id)) ordered.push(s);
      }
      this.steps = ordered;
    }

    return this.steps;
  }

  /**
   * Steps whose deps are all done and are still pending.
   */
  nextRunnable() {
    return this.steps.filter(
      (s) => s.status === 'pending' && this._depsSatisfied(s)
    );
  }

  toJSON() {
    return {
      planId: this.planId,
      steps: this.steps,
      version: this.version,
      updatedAt: nowISO(),
    };
  }

  /**
   * Persist with optimistic concurrency control.
   * If expectedVersion is provided, the stored version must match
   * (i.e. no concurrent writer has bumped it since hydrate) or the
   * write is rejected. On success the version is auto-incremented.
   */
  async persist(storage, expectedVersion) {
    const current = await storage.get(storageKey(this.planId));
    const currentVersion = current?.version ?? 0;

    if (expectedVersion !== undefined && currentVersion !== expectedVersion) {
      const err = new Error(
        `version conflict: expected ${expectedVersion}, found ${currentVersion}`
      );
      err.code = 'VERSION_CONFLICT';
      throw err;
    }

    const nextVersion = currentVersion + 1;
    await storage.put(storageKey(this.planId), {
      planId: this.planId,
      steps: this.steps,
      version: nextVersion,
    });
    this.version = nextVersion;
    return nextVersion;
  }

  static async hydrate(planId, storage) {
    const data = await storage.get(storageKey(planId));
    if (!data) return new PlanStateMachine(planId, [], 0);
    return new PlanStateMachine(planId, data.steps || [], data.version ?? 0);
  }
}

/* ---------------- HTTP handlers ---------------- */

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

/**
 * GET current plan JSON.
 * Reads planId from the request query string.
 */
export async function handlePlanGet(req, storage) {
  const planId = new URL(req.url).searchParams.get('planId');
  if (!planId) return json({ error: 'planId required' }, 400);

  const psm = await PlanStateMachine.hydrate(planId, storage);
  return json({
    ...psm.toJSON(),
    nextRunnable: psm.nextRunnable().map((s) => s.id),
  });
}

/**
 * Accept a patch request { planId, patch } and apply it.
 */
export async function handlePlanEdit(req, storage) {
  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid JSON body' }, 400);
  }

  const { planId, patch } = body || {};
  if (!planId) return json({ error: 'planId required' }, 400);

  const psm = await PlanStateMachine.hydrate(planId, storage);
  const baseVersion = psm.version;

  try {
    psm.editPlan(patch || {});
  } catch (err) {
    return json({ error: String(err.message || err) }, 400);
  }

  try {
    await psm.persist(storage, baseVersion);
  } catch (err) {
    if (err.code === 'VERSION_CONFLICT') {
      return json({ error: String(err.message || err), code: 'VERSION_CONFLICT' }, 409);
    }
    throw err;
  }

  return json({
    ...psm.toJSON(),
    nextRunnable: psm.nextRunnable().map((s) => s.id),
  });
}

/**
 * Advance a step's status: { planId, stepId, toStatus, result? }
 */
export async function handlePlanAdvance(req, storage) {
  let body;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid JSON body' }, 400);
  }

  const { planId, stepId, toStatus, result } = body || {};
  if (!planId || !stepId || !toStatus) {
    return json({ error: 'planId, stepId, toStatus required' }, 400);
  }

  const psm = await PlanStateMachine.hydrate(planId, storage);
  const baseVersion = psm.version;

  let step;
  try {
    step = psm.transition(stepId, toStatus, result);
  } catch (err) {
    return json({ error: String(err.message || err) }, 400);
  }

  try {
    await psm.persist(storage, baseVersion);
  } catch (err) {
    if (err.code === 'VERSION_CONFLICT') {
      return json({ error: String(err.message || err), code: 'VERSION_CONFLICT' }, 409);
    }
    throw err;
  }

  return json({
    step,
    plan: psm.toJSON(),
    nextRunnable: psm.nextRunnable().map((s) => s.id),
  });
}
