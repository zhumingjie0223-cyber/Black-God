/**
 * 神枢 Nexus · Verdict Loop（验证驱动回环状态机）
 * verdict_loop.mjs
 *
 * 核心理念：plan → execute → verify → (fail? replan : done)
 * 逆向来源：Devin SWE-agent 验证驱动回环
 * 部署环境：Cloudflare Workers + E2B 沙箱
 */

import { runGroundTruthTests, assertNotSelfReported } from './verdict_source.mjs';

/**
 * 主循环：plan → execute → verify → (fail? replan : done)
 * @param {object} orchestrator - NexusOrchestrator 实例
 * @param {string} sandboxId - E2B 沙箱 ID
 * @param {object} task - { goal: string, context: object, maxRetries: number, testSuite: object }
 * @param {object} state - DO storage（可选，用于持久化 history）
 * @returns {Promise<{success: boolean, attempts: number, history: object[], finalVerdict: object}>}
 */
export async function runVerdictLoop(orchestrator, sandboxId, task, state = null) {
  const { goal, context = {}, maxRetries = 3, testSuite } = task;
  
  let attempt = 0;
  const history = [];
  let lastVerdict = null;
  
  console.log(`[VerdictLoop] 开始任务: ${goal}`);
  
  while (attempt < maxRetries) {
    attempt++;
    console.log(`[VerdictLoop] 第 ${attempt}/${maxRetries} 轮`);
    
    try {
      // 1. Plan：调用 orchestrator 生成计划
      const planPrompt = buildPlanPrompt(goal, context, history, attempt);
      const planResult = await orchestrator.dispatch({
        agent_type: 'planning_agent',
        message: planPrompt,
        sandbox_id: sandboxId
      });
      
      const plan = {
        actions: parsePlanActions(planResult.result),
        claim: extractClaim(planResult.result)
      };
      
      console.log(`[VerdictLoop] Plan: ${plan.actions.length} 个操作`);
      
      // 2. Execute：在沙箱执行计划
      const executeResult = await executePlan(sandboxId, plan.actions, orchestrator);
      
      // 3. Verify：跑测试得到 verdict
      if (!testSuite) {
        // 没有测试套件，只能信 agent 自述
        console.warn('[VerdictLoop] 无测试套件，无法验证，视为成功');
        return {
          success: true,
          attempts: attempt,
          history: [...history, { attempt, plan, executeResult, verdict: { verdict: 'pass', reason: '无测试套件' } }],
          finalVerdict: { verdict: 'pass', reason: '无测试套件' }
        };
      }
      
      const verdict = await runGroundTruthTests(sandboxId, testSuite);
      
      // 检查 agent 自述 vs 测试真值
      const trustCheck = assertNotSelfReported(plan.claim, verdict);
      if (!trustCheck.trusted) {
        console.warn(`[VerdictLoop] ${trustCheck.warning}`);
      }
      
      // 记录本轮
      history.push({
        attempt,
        plan,
        executeResult,
        verdict,
        trustCheck
      });
      
      lastVerdict = verdict;
      
      // 4. 判定：pass → 成功退出
      if (verdict.verdict === 'pass') {
        console.log(`[VerdictLoop] ✅ 第 ${attempt} 轮测试通过`);
        
        // 持久化 history（可选）
        if (state) {
          await state.storage.put(`verdict_history_${Date.now()}`, history);
        }
        
        return {
          success: true,
          attempts: attempt,
          history,
          finalVerdict: verdict
        };
      }
      
      // 5. Replan：失败 → 注入失败原因到下轮 context
      context.lastFailure = {
        reason: verdict.failed.slice(0, 3).join('; '),
        stack: verdict.stack.slice(0, 5),
        whatWasTried: plan.actions,
        attemptNumber: attempt
      };
      
      console.log(`[VerdictLoop] ❌ 第 ${attempt} 轮失败: ${context.lastFailure.reason}`);
      
    } catch (err) {
      console.error(`[VerdictLoop] 第 ${attempt} 轮异常:`, err.message);
      history.push({
        attempt,
        error: err.message,
        stack: err.stack
      });
      
      context.lastFailure = {
        reason: `执行异常: ${err.message}`,
        stack: [err.stack],
        whatWasTried: [],
        attemptNumber: attempt
      };
    }
  }
  
  // 所有重试耗尽
  console.log(`[VerdictLoop] ⚠️ ${maxRetries} 轮全部失败`);
  
  // 持久化 history
  if (state) {
    await state.storage.put(`verdict_history_failed_${Date.now()}`, history);
  }
  
  return {
    success: false,
    attempts: attempt,
    history,
    finalVerdict: lastVerdict
  };
}

/**
 * 注入失败原因到 prompt context（防重复错误）
 * @param {object} ctx - task.context，含 lastFailure
 * @returns {string} 格式化的失败上下文
 */
export function injectFailureReason(ctx) {
  if (!ctx.lastFailure) return '';
  
  const { reason, stack, whatWasTried, attemptNumber } = ctx.lastFailure;
  
  const triedActions = Array.isArray(whatWasTried) 
    ? whatWasTried.map((a, i) => `${i + 1}. ${a.type}: ${a.target || a.command || ''}`).join('\n')
    : JSON.stringify(whatWasTried);
  
  return `
[上一轮失败 #${attemptNumber}]
原因：${reason}

堆栈（前5行）：
${stack.join('\n')}

已尝试方案：
${triedActions}

⚠️ 请换一个完全不同的方案，避免重复上述操作。
`.trim();
}

// ========== 内部辅助函数 ==========

/**
 * 构建 plan 阶段的 prompt
 */
function buildPlanPrompt(goal, context, history, attemptNumber) {
  let prompt = `# 任务目标\n${goal}\n\n`;
  
  // 注入失败历史
  if (context.lastFailure) {
    prompt += injectFailureReason(context) + '\n\n';
  }
  
  // 附加上下文
  if (context.files && Object.keys(context.files).length > 0) {
    prompt += `# 当前文件\n`;
    for (const [path, content] of Object.entries(context.files)) {
      prompt += `${path}: ${content.length} 字符\n`;
    }
    prompt += '\n';
  }
  
  prompt += `# 要求（第 ${attemptNumber} 轮）\n`;
  prompt += `生成一个具体的执行计划，包含：\n`;
  prompt += `- 多个操作步骤（edit/run/install）\n`;
  prompt += `- 每步的具体目标文件/命令\n`;
  prompt += `- 你对本次方案的预期结果\n\n`;
  prompt += `输出格式：\n`;
  prompt += `1. [操作类型] 目标 - 说明\n`;
  prompt += `2. ...\n`;
  prompt += `预期：这个方案应该能...\n`;
  
  return prompt;
}

/**
 * 从 agent 回复中解析出操作步骤
 */
function parsePlanActions(agentReply) {
  const actions = [];
  const lines = agentReply.split('\n');
  
  for (const line of lines) {
    // 匹配：1. [edit] src/app.js - 修复bug
    const match = line.match(/^\d+\.\s*\[(\w+)\]\s*(.+?)\s*-\s*(.+)/);
    if (match) {
      const [, type, target, description] = match;
      actions.push({ type, target, description });
    }
  }
  
  return actions.length > 0 ? actions : [{ type: 'unknown', target: agentReply.slice(0, 100), description: 'parsed from agent reply' }];
}

/**
 * 提取 agent 的声明（"应该能..."）
 */
function extractClaim(agentReply) {
  const lines = agentReply.split('\n');
  for (const line of lines) {
    if (line.includes('预期') || line.includes('应该') || line.includes('能够')) {
      return line;
    }
  }
  return agentReply.slice(0, 100);
}

/**
 * 执行计划（调用沙箱/orchestrator）
 */
async function executePlan(sandboxId, actions, orchestrator) {
  const results = [];
  
  for (const action of actions) {
    try {
      if (action.type === 'edit') {
        // 调用 code engine 修改文件
        const result = await orchestrator.dispatch({
          agent_type: 'code_agent',
          message: `编辑文件 ${action.target}: ${action.description}`,
          sandbox_id: sandboxId
        });
        results.push({ action: 'edit', target: action.target, success: true, result });
      } else if (action.type === 'run') {
        // 直接在沙箱跑命令（需要通过 orchestrator 或直接调 sandbox）
        const result = await orchestrator.dispatch({
          agent_type: 'general_subagent',
          message: `执行命令: ${action.target}`,
          sandbox_id: sandboxId
        });
        results.push({ action: 'run', command: action.target, success: true, result });
      } else if (action.type === 'install') {
        const result = await orchestrator.dispatch({
          agent_type: 'general_subagent',
          message: `安装依赖: ${action.target}`,
          sandbox_id: sandboxId
        });
        results.push({ action: 'install', package: action.target, success: true, result });
      } else {
        results.push({ action: action.type, target: action.target, success: false, error: 'unknown action type' });
      }
    } catch (err) {
      results.push({ action: action.type, target: action.target, success: false, error: err.message });
    }
  }
  
  return results;
}
