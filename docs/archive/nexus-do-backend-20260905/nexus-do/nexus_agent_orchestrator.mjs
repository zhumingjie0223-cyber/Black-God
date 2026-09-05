/**
 * 神枢 Nexus · Agent Orchestrator
 * nexus_agent_orchestrator.mjs
 *
 * 逆向来源：Replit proto CreateAgentConfig + chateau AgentState 状态机
 * 部署环境：Cloudflare Workers (ES Module)
 */

// ─── 子 Agent 类型枚举（对齐 Replit proto 字段号）───
export const AgentType = {
  CODE:              'code_agent',           // 7: 主力写代码
  GENERAL:           'general_subagent',     // 8: 通用子任务
  TEST:              'test_agent',           // 9: 自动化测试
  MISSION:           'mission_agent',        // 10: 任务型
  FIXTURE_TEST:      'fixture_test_agent',   // 11: 固件测试
  PLANNING:          'planning_agent',       // 12: 规划
  TASK:              'task_agent',           // 13: 定时/后台任务
  DESIGN:            'design_agent',         // 14: 设计
  SECURITY_SCANNER:  'security_scanner',     // 15: 安全扫描
  LOAD_TESTING:      'load_testing_agent',   // 16: 压测
  SEO_SCANNER:       'seo_scanner',          // 17: SEO
  ARCHITECT:         'architect_agent',      // 18: 架构规划
  EXPLORE:           'explore_agent',        // 19: 代码库探索
  CONVERSATION:      'conversation_agent',   // 21: 纯对话
  SIDEKICK:          'sidekick_agent',       // 22: 副驾（最轻量）
};

// ─── 状态机阶段（Replit AgentState.Lifecycle.Phase）───
const Phase = { IDLE: 'IDLE', DISPATCHING: 'DISPATCHING', WAITING: 'WAITING_FOR_INPUT' };

// ─── SubagentPresentation 三态 ───
const Presentation = {
  working: () => ({ status: 'Working' }),
  stopped: (reason) => ({ status: 'Stopped', reason }),
  done: (ok, result_markdown, cancelled = false) => ({ status: 'Done', ok, result_markdown, cancelled }),
};

/**
 * AssignmentChannel：带 revision 版本号的双向通道（对齐 Replit AssignmentChannelEntry）
 */
class AssignmentChannel {
  #entries = [];
  #revision = 0;

  post(role, content) {
    this.#revision++;
    const entry = { revision: this.#revision, role, content, ts: Date.now() };
    this.#entries.push(entry);
    return entry;
  }

  since(revision = 0) {
    return this.#entries.filter(e => e.revision > revision);
  }

  get latestRevision() { return this.#revision; }
  get entries() { return [...this.#entries]; }
}

/**
 * Assignment：一个用户消息 → 一个分派单元
 */
class Assignment {
  constructor(id, agentType, params) {
    this.id = id;
    this.agentType = agentType;
    this.params = params;
    this.state = 'RUNNING';          // RUNNING / COMPLETED / FAILED
    this.channel = new AssignmentChannel();
    this.blocked_at_revision = null;
    this.presentation = Presentation.working();
    this.created_at = Date.now();
  }

  complete(result_markdown) {
    this.state = 'COMPLETED';
    this.presentation = Presentation.done(true, result_markdown);
  }

  fail(reason) {
    this.state = 'FAILED';
    this.presentation = Presentation.stopped(reason);
  }

  block(revision) {
    this.blocked_at_revision = revision;
    this.presentation = Presentation.stopped('blocked_waiting_input');
  }
}

/**
 * NexusOrchestrator：神枢多子 Agent 调度核
 *
 * 用法：
 *   const orch = new NexusOrchestrator({ aiEndpoint, ownerToken });
 *   const result = await orch.dispatch(AgentType.ARCHITECT, {
 *     task: '重构枢语引擎',
 *     responsibility: '拆分 shuyu_v2 模块边界',
 *     model_profile: 'POWER',
 *     include_git_diff: true,
 *   });
 */
export class NexusOrchestrator {
  #queue = [];           // Assignment[]
  #phase = Phase.IDLE;
  #idCounter = 0;
  #config;

  constructor(config = {}) {
    this.#config = {
      aiEndpoint: config.aiEndpoint ?? 'https://aquan.lufei.uk/talk',
      ownerToken:  config.ownerToken  ?? '',
      maxConcurrent: config.maxConcurrent ?? 3,
      timeoutMs:   config.timeoutMs   ?? 120_000,
    };
  }

  // ─── 按 AgentType 校验 + 构造 params ───
  #buildParams(agentType, raw) {
    const base = { execution_home: raw.execution_home ?? { conversation: { id: `nexus-${Date.now()}` } } };

    switch (agentType) {
      case AgentType.ARCHITECT:
        return {
          ...base,
          responsibility:       raw.responsibility ?? '',
          mode:                 raw.mode ?? 'BUILD',           // BUILD / PLAN / DESIGN
          model_profile:        raw.model_profile ?? 'POWER',  // LITE/ECONOMY/POWER/POWER_TURBO
          task:                 raw.task ?? '',
          relevant_files:       raw.relevant_files ?? [],
          include_git_diff:     raw.include_git_diff ?? false,
          relevant_git_commits: raw.relevant_git_commits ?? '',
        };

      case AgentType.DESIGN:
        return { ...base, task: raw.task ?? '', relevant_files: raw.relevant_files ?? [],
                 relevant_skills: raw.relevant_skills ?? [], output_dir: raw.output_dir ?? 'dist/' };

      case AgentType.GENERAL:
        return { ...base, task: raw.task ?? '', relevant_files: raw.relevant_files ?? [],
                 relevant_skills: raw.relevant_skills ?? [] };

      case AgentType.SECURITY_SCANNER:
        return { ...base, task: raw.task ?? '安全扫描', relevant_files: raw.relevant_files ?? [],
                 relevant_skills: raw.relevant_skills ?? [] };

      case AgentType.SEO_SCANNER:
        return { ...base, task: raw.task ?? 'SEO分析', relevant_files: raw.relevant_files ?? [] };

      case AgentType.SIDEKICK:
        return { ...base, task: raw.task ?? '' };

      case AgentType.CODE:
        return { ...base, repl_id: raw.repl_id ?? 'nexus-main',
                 migrate_from_ai_infra: raw.migrate_from_ai_infra ?? false };

      default:
        return { ...base, task: raw.task ?? '', ...raw };
    }
  }

  // ─── 核心：向 AI 发请求（走神枢 /talk 端点）───
  async #callAI(agentType, params, signal) {
    const systemHint = this.#agentSystemHint(agentType, params);
    const body = JSON.stringify({
      message: params.task ?? JSON.stringify(params),
      system_override: systemHint,
      model_profile: params.model_profile ?? 'POWER',
    });

    const resp = await fetch(this.#config.aiEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.#config.ownerToken}`,
      },
      body,
      signal,
    });

    if (!resp.ok) throw new Error(`AI 调用失败: ${resp.status} ${await resp.text()}`);
    const data = await resp.json();
    return data.reply ?? data.text ?? data.content ?? JSON.stringify(data);
  }

  // ─── 每种 Agent 的系统提示方向 ───
  #agentSystemHint(agentType, params) {
    const hints = {
      [AgentType.ARCHITECT]:        `你是架构 Agent。职责：${params.responsibility}。输出架构决策文档。`,
      [AgentType.DESIGN]:           `你是设计 Agent。输出目录：${params.output_dir}。给出完整 CSS/HTML 设计实现。`,
      [AgentType.SECURITY_SCANNER]: `你是安全扫描 Agent。分析以下文件的安全漏洞，输出 OWASP 分类报告。`,
      [AgentType.SEO_SCANNER]:      `你是 SEO 扫描 Agent。分析页面 SEO 问题，输出结构化改进建议。`,
      [AgentType.PLANNING]:         `你是规划 Agent。将任务拆解为可执行子任务列表，按优先级排序。`,
      [AgentType.EXPLORE]:          `你是代码探索 Agent。深入分析代码库结构，输出调用关系图和关键路径。`,
      [AgentType.SIDEKICK]:         `你是副驾 Agent。精简高效，直接给结果，不废话。`,
      [AgentType.CODE]:             `你是代码 Agent。直接输出可运行代码，用 markdown 代码块包裹，文件名在块前一行。`,
    };
    return hints[agentType] ?? `你是 ${agentType} Agent。完成任务：${params.task}`;
  }

  /**
   * dispatch：派遣一个子 Agent
   * @param {string} agentType - AgentType 枚举值
   * @param {object} rawParams  - 原始参数，按 agentType schema 填
   * @returns {Promise<Assignment>}
   */
  async dispatch(agentType, rawParams = {}) {
    const id = `assignment-${++this.#idCounter}-${Date.now()}`;
    const params = this.#buildParams(agentType, rawParams);
    const assignment = new Assignment(id, agentType, params);
    this.#queue.push(assignment);
    this.#phase = Phase.DISPATCHING;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.#config.timeoutMs);

    try {
      // 子 Agent 向通道发第一条消息（记录任务启动）
      assignment.channel.post('system', `[${agentType}] 任务启动: ${params.task ?? id}`);

      const result = await this.#callAI(agentType, params, controller.signal);

      assignment.channel.post('agent', result);
      assignment.complete(result);
    } catch (err) {
      if (err.name === 'AbortError') {
        assignment.fail('timeout');
      } else {
        assignment.fail(err.message);
      }
    } finally {
      clearTimeout(timeout);
      this.#phase = this.#queue.some(a => a.state === 'RUNNING') ? Phase.DISPATCHING : Phase.IDLE;
    }

    return assignment;
  }

  /**
   * dispatchParallel：同时派遣多个子 Agent（Replit AssignmentChannel 并行模式）
   * @param {Array<{type, params}>} tasks
   * @returns {Promise<Assignment[]>}
   */
  async dispatchParallel(tasks) {
    const chunks = [];
    for (let i = 0; i < tasks.length; i += this.#config.maxConcurrent) {
      chunks.push(tasks.slice(i, i + this.#config.maxConcurrent));
    }
    const results = [];
    for (const chunk of chunks) {
      const batch = await Promise.all(chunk.map(t => this.dispatch(t.type, t.params)));
      results.push(...batch);
    }
    return results;
  }

  // ─── 状态查询 ───
  get phase()  { return this.#phase; }
  get queue()  { return this.#queue.map(a => ({ id: a.id, type: a.agentType, state: a.state, presentation: a.presentation })); }

  getAssignment(id) { return this.#queue.find(a => a.id === id) ?? null; }

  /** 获取 Assignment 的版本化通道消息（供前端轮询）*/
  getChannelSince(assignmentId, sinceRevision = 0) {
    const a = this.getAssignment(assignmentId);
    if (!a) return null;
    return { entries: a.channel.since(sinceRevision), latestRevision: a.channel.latestRevision };
  }
}

// ─── Cloudflare Workers HTTP 路由处理 ───
// 挂到 nexus_do.core.mjs 的路由表里：
//
//   import { NexusOrchestrator, AgentType } from './nexus_agent_orchestrator.mjs';
//   const orch = new NexusOrchestrator({ aiEndpoint: env.NEXUS_GATEWAY_URL, ownerToken: env.OWNER_TOKEN });
//
//   case '/agent/dispatch':   handleAgentDispatch(request, env, orch)
//   case '/agent/status':     handleAgentStatus(request, env, orch)
//   case '/agent/channel':    handleAgentChannel(request, env, orch)

export async function handleAgentDispatch(request, env, orch) {
  const { agentType, params } = await request.json();
  if (!agentType) return new Response('agentType required', { status: 400 });

  const assignment = await orch.dispatch(agentType, params ?? {});
  return Response.json({
    id:           assignment.id,
    agentType:    assignment.agentType,
    state:        assignment.state,
    presentation: assignment.presentation,
    channelRevision: assignment.channel.latestRevision,
  });
}

export async function handleAgentStatus(request, env, orch) {
  const url = new URL(request.url);
  const id  = url.searchParams.get('id');
  const a   = id ? orch.getAssignment(id) : null;
  if (!a) return new Response('not found', { status: 404 });
  return Response.json({ id: a.id, state: a.state, presentation: a.presentation });
}

export async function handleAgentChannel(request, env, orch) {
  const url      = new URL(request.url);
  const id       = url.searchParams.get('id');
  const since    = parseInt(url.searchParams.get('since') ?? '0', 10);
  const channel  = orch.getChannelSince(id, since);
  if (!channel) return new Response('not found', { status: 404 });
  return Response.json(channel);
}
