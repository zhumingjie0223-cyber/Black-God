/**
 * 神枢 Nexus · Verdict Source（测试即真值）
 * verdict_source.mjs
 *
 * 核心理念：Agent 自述"修好了"无效，容器内官方测试 pass/fail 才是 verdict
 * 逆向来源：Devin SWE-agent 验证驱动回环 + Replit 测试执行层
 * 部署环境：Cloudflare Workers + E2B 沙箱
 */

import { execCommand } from './nexus_sandbox.mjs';

/**
 * 在 E2B 沙箱里跑真实测试，返回 verdict
 * @param {string} sandboxId - E2B 沙箱 ID
 * @param {object} suite - { framework: 'jest'|'pytest'|'cargo'|'auto', command?: string, expectedPass?: string[], timeout?: number }
 * @returns {Promise<{verdict: 'pass'|'fail'|'error', passed: string[], failed: string[], stack: string[], duration: number}>}
 */
export async function runGroundTruthTests(sandboxId, suite = {}) {
  const { framework = 'auto', command, expectedPass = [], timeout = 60000 } = suite;
  const startTime = Date.now();
  
  try {
    // 1. 自动检测测试框架
    let detectedFramework = framework;
    if (framework === 'auto') {
      detectedFramework = await detectTestFramework(sandboxId);
    }
    
    // 2. 构造测试命令
    const testCommand = command || getDefaultTestCommand(detectedFramework);
    
    // 3. 执行测试（带超时）
    const result = await execCommand(sandboxId, testCommand, timeout);
    const duration = Date.now() - startTime;
    
    // 4. 解析测试结果
    const parsed = parseTestOutput(result.stdout + '\n' + result.stderr, detectedFramework);
    
    // 5. 判定 verdict
    let verdict = 'error';
    if (result.exitCode === 0 && parsed.failed.length === 0) {
      verdict = 'pass';
    } else if (result.exitCode !== 0 || parsed.failed.length > 0) {
      verdict = 'fail';
    }
    
    // 6. 检查期望通过的测试
    if (expectedPass.length > 0) {
      const actualPassed = new Set(parsed.passed);
      const allExpectedPass = expectedPass.every(t => actualPassed.has(t));
      if (!allExpectedPass) {
        verdict = 'fail';
        parsed.failed.push(`期望通过 ${expectedPass.length} 个测试，实际只通过 ${parsed.passed.length} 个`);
      }
    }
    
    return {
      verdict,
      passed: parsed.passed,
      failed: parsed.failed,
      stack: parsed.stack,
      duration,
      framework: detectedFramework
    };
    
  } catch (err) {
    const duration = Date.now() - startTime;
    
    // 超时或执行失败
    if (err.name === 'AbortError' || err.message.includes('timeout')) {
      return {
        verdict: 'error',
        passed: [],
        failed: ['测试超时'],
        stack: [`测试执行超过 ${timeout}ms 被强制终止`],
        duration,
        framework: 'unknown'
      };
    }
    
    return {
      verdict: 'error',
      passed: [],
      failed: ['执行失败'],
      stack: [err.message, err.stack || ''].filter(Boolean),
      duration,
      framework: 'unknown'
    };
  }
}

/**
 * Agent 说"我修好了"不算数，必须测试说 pass
 * @param {string} agentClaim - Agent 的自述
 * @param {object} testResult - runGroundTruthTests 返回值
 * @returns {{trusted: boolean, warning: string}}
 */
export function assertNotSelfReported(agentClaim, testResult) {
  const selfReportKeywords = [
    '已修复', '应该可以了', '修好了', '问题解决', '已完成',
    'fixed', 'should work', 'resolved', 'done', 'completed'
  ];
  
  const hasSelfReport = selfReportKeywords.some(kw => 
    agentClaim.toLowerCase().includes(kw.toLowerCase())
  );
  
  if (hasSelfReport && testResult.verdict !== 'pass') {
    return {
      trusted: false,
      warning: `⚠️ Agent 声称"${agentClaim.slice(0, 50)}..."，但测试结果为 ${testResult.verdict}。只信测试，不信自述。`
    };
  }
  
  if (testResult.verdict === 'pass') {
    return { trusted: true, warning: '' };
  }
  
  return {
    trusted: false,
    warning: `测试 verdict=${testResult.verdict}，失败：${testResult.failed.slice(0, 3).join(', ')}`
  };
}

// ========== 内部辅助函数 ==========

/**
 * 自动检测测试框架（读 package.json / Cargo.toml / requirements.txt）
 */
async function detectTestFramework(sandboxId) {
  // 检查 package.json
  try {
    const pkg = await execCommand(sandboxId, 'cat package.json', 5000);
    if (pkg.exitCode === 0) {
      const json = JSON.parse(pkg.stdout);
      if (json.devDependencies?.jest || json.dependencies?.jest) return 'jest';
      if (json.devDependencies?.vitest || json.dependencies?.vitest) return 'vitest';
      if (json.scripts?.test) return 'npm test';
    }
  } catch {}
  
  // 检查 Cargo.toml
  try {
    const cargo = await execCommand(sandboxId, 'test -f Cargo.toml && echo 1', 5000);
    if (cargo.stdout.includes('1')) return 'cargo';
  } catch {}
  
  // 检查 pytest
  try {
    const pytest = await execCommand(sandboxId, 'which pytest', 5000);
    if (pytest.exitCode === 0) return 'pytest';
  } catch {}
  
  return 'npm test'; // fallback
}

/**
 * 获取默认测试命令
 */
function getDefaultTestCommand(framework) {
  const commands = {
    jest: 'npm test -- --verbose',
    vitest: 'npm test',
    pytest: 'pytest -v',
    cargo: 'cargo test',
    'npm test': 'npm test'
  };
  return commands[framework] || 'npm test';
}

/**
 * 解析测试输出（识别 passed/failed/stack）
 */
function parseTestOutput(output, framework) {
  const passed = [];
  const failed = [];
  const stack = [];
  
  // Jest / Vitest / npm test
  if (framework === 'jest' || framework === 'vitest' || framework === 'npm test') {
    // PASS 格式：✓ test name 或 PASS tests/file.test.js
    const passMatches = output.matchAll(/(?:PASS|✓|√)\s+(.+?)(?:\(|\n|$)/gi);
    for (const m of passMatches) {
      const name = m[1].trim();
      if (name && !name.includes('Test Suites')) passed.push(name);
    }
    
    // FAIL 格式：✕ test name 或 FAIL tests/file.test.js
    const failMatches = output.matchAll(/(?:FAIL|✕|×)\s+(.+?)(?:\(|\n|$)/gi);
    for (const m of failMatches) {
      const name = m[1].trim();
      if (name && !name.includes('Test Suites')) failed.push(name);
    }
    
    // 提取错误堆栈
    const stackLines = output.split('\n').filter(l => 
      l.includes('Error:') || l.includes('Expected') || l.match(/at \w+\.\w+/)
    );
    stack.push(...stackLines.slice(0, 10));
  }
  
  // Pytest
  else if (framework === 'pytest') {
    const passMatches = output.matchAll(/PASSED\s+(.+)/gi);
    for (const m of passMatches) passed.push(m[1].trim());
    
    const failMatches = output.matchAll(/FAILED\s+(.+)/gi);
    for (const m of failMatches) failed.push(m[1].trim());
    
    const stackLines = output.split('\n').filter(l => 
      l.includes('AssertionError') || l.includes('E ') || l.includes('>')
    );
    stack.push(...stackLines.slice(0, 10));
  }
  
  // Cargo
  else if (framework === 'cargo') {
    const passMatches = output.matchAll(/test\s+(.+?)\s+\.\.\.\s+ok/gi);
    for (const m of passMatches) passed.push(m[1].trim());
    
    const failMatches = output.matchAll(/test\s+(.+?)\s+\.\.\.\s+FAILED/gi);
    for (const m of failMatches) failed.push(m[1].trim());
    
    const stackLines = output.split('\n').filter(l => 
      l.includes('thread') || l.includes('panicked') || l.includes('assertion')
    );
    stack.push(...stackLines.slice(0, 10));
  }
  
  return { passed, failed, stack };
}
