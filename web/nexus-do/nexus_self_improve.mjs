export class SelfImprove {
  constructor({ eventBus, memory } = {}) {
    this.eventBus = eventBus;
    this.memory = memory;
    this.history = [];
  }

  reflect(failure) {
    return {
      ts: Date.now(),
      kind: failure?.kind || 'unknown',
      error: failure?.error ? String(failure.error).slice(0, 300) : null,
      context: failure?.context ? String(failure.context).slice(0, 200) : null,
    };
  }

  propose(reflection) {
    const lessonMap = {
      brain_error: '调用大脑失败时应降级为本地简答，而非沉默。',
      empty_reply: '回复为空说明提示或上下文有缺陷，需检查注入的自我模型。',
      unknown: '未知失败：记录上下文，同类情形下次先复述问题再回答。',
    };
    const lesson = lessonMap[reflection.kind] || lessonMap.unknown;
    return {
      reflection,
      lesson,
      declarationLine: `[教训 ${new Date(reflection.ts).toISOString().slice(0, 10)}] ${lesson}`,
    };
  }

  improve(soul, proposal) {
    try {
      if (!soul || !proposal?.declarationLine) throw new Error('invalid improve input');
      const decl = soul.self_declaration || '';
      if (!decl.includes(proposal.declarationLine)) {
        soul.self_declaration = (decl ? decl + '\n' : '') + proposal.declarationLine;
      }
      const applied = { ...proposal, applied_at: Date.now() };
      this.history.push(applied);
      this.eventBus?.emit?.('improvement.applied', applied);
      this.memory?.remember?.({ type: 'improvement', content: proposal.lesson, meta: proposal.reflection });
      return applied;
    } catch (e) {
      this.eventBus?.emit?.('improvement.failed', { error: e.message, proposal });
      return null;
    }
  }

  digest() {
    return this.history.slice(-10);
  }
}

export default SelfImprove;
