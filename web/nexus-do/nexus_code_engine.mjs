/**
 * 神枢 Nexus · 代码生成引擎
 * nexus_code_engine.mjs
 *
 * 逆向来源：Lovable gpt-engineer 真实源码（cli_agent.py / steps.py / chat_to_files.py / diff.py）
 * 部署环境：Cloudflare Workers (ES Module)
 */

// ─── FilesDict：文件路径 → 内容的映射 ───
export class FilesDict extends Map {
  /** 把所有文件序列化成 AI 可读的 chat 格式 */
  toChat() {
    return [...this.entries()]
      .map(([path, content]) => `${path}\n\`\`\`\n${content}\n\`\`\``)
      .join('\n\n');
  }

  toJSON() {
    return Object.fromEntries(this.entries());
  }
}

// ─── chat_to_files_dict：解析 AI 返回的 markdown 文件块（逐字移植自 gpt-engineer）───
// 原正则：r"(\S+)\n\s*```[^\n]*\n(.+?)```"
export function chatToFilesDict(chat) {
  const regex = /(\S+)\n\s*```[^\n]*\n([\s\S]+?)```/g;
  const files = new FilesDict();
  let match;
  while ((match = regex.exec(chat)) !== null) {
    let path = match[1];
    const content = match[2];
    // 清理路径中的非法字符（对齐 Python 版本）
    path = path.replace(/[:<>"|?*]/g, '');
    path = path.replace(/^\[(.*)\]$/, '$1');
    path = path.replace(/^`(.*)`$/, '$1');
    path = path.replace(/[\]:]+$/, '');
    path = path.trim();
    if (path) files.set(path, content.trim());
  }
  return files;
}

// ─── Diff 解析与应用（逆向自 diff.py / parse_diffs / apply_diffs）───
const RETAIN = ' ';
const ADD    = '+';
const REMOVE = '-';
const REMOVE_FLAG = '__NEXUS_REMOVE_LINE__';

function parseDiffs(diffString) {
  const diffs = new Map();
  // 匹配 unified diff 头：--- a/file / +++ b/file
  const fileRegex = /^---\s+(.+?)$\n^\+\+\+\s+(.+?)$/gm;
  // 匹配 hunk 头：@@ -start,len +start,len @@
  const hunkRegex = /@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/g;

  let fileMatch;
  while ((fileMatch = fileRegex.exec(diffString)) !== null) {
    const filenamePre  = fileMatch[1].replace(/^a\//, '').trim();
    const filenamePost = fileMatch[2].replace(/^b\//, '').trim();
    const isNewFile    = filenamePre === '/dev/null';

    // 找这个文件之后的所有 hunk
    const hunks = [];
    const afterHeader = diffString.slice(fileMatch.index + fileMatch[0].length);
    let hunkMatch;
    hunkRegex.lastIndex = 0;

    while ((hunkMatch = hunkRegex.exec(afterHeader)) !== null) {
      const startLinePre  = parseInt(hunkMatch[1], 10);
      const startLinePost = parseInt(hunkMatch[2], 10);

      // 提取 hunk 内容（直到下一个 @@ 或文件头）
      const hunkStart = hunkMatch.index + hunkMatch[0].length;
      const nextHunk  = hunkRegex.exec(afterHeader);
      hunkRegex.lastIndex = nextHunk ? nextHunk.index : hunkRegex.lastIndex;
      const hunkEnd   = nextHunk ? nextHunk.index : afterHeader.length;
      const hunkBody  = afterHeader.slice(hunkStart, hunkEnd);

      const lines = hunkBody.split('\n')
        .filter(l => l.length > 0)
        .map(l => [l[0] === '+' ? ADD : l[0] === '-' ? REMOVE : RETAIN, l.slice(1)]);

      hunks.push({ startLinePre, startLinePost, lines });

      if (!nextHunk) break;
      hunkRegex.lastIndex = nextHunk.index;
    }

    diffs.set(filenamePost, { filenamePre, filenamePost, isNewFile, hunks });
  }
  return diffs;
}

function fileToLinesDict(content) {
  const dict = new Map();
  content.split('\n').forEach((line, idx) => dict.set(idx + 1, line));
  return dict;
}

function applyDiffs(diffs, filesDict) {
  const result = new FilesDict(filesDict);

  for (const [, diff] of diffs) {
    if (diff.isNewFile) {
      // 新文件：提取所有 ADD 行
      const content = diff.hunks
        .flatMap(h => h.lines)
        .filter(([op]) => op === ADD)
        .map(([, line]) => line)
        .join('\n');
      result.set(diff.filenamePost, content);
      continue;
    }

    if (!result.has(diff.filenamePre)) continue;
    const lineDict = fileToLinesDict(result.get(diff.filenamePre));

    for (const hunk of diff.hunks) {
      let cur = hunk.startLinePre;
      for (const [op, line] of hunk.lines) {
        if (op === RETAIN) {
          cur++;
        } else if (op === ADD) {
          cur--;
          const existing = lineDict.get(cur) ?? '';
          if (existing !== REMOVE_FLAG) {
            lineDict.set(cur, existing ? `${existing}\n${line}` : line);
          } else {
            lineDict.set(cur, line);
          }
          cur++;
        } else if (op === REMOVE) {
          lineDict.set(cur, REMOVE_FLAG);
          cur++;
        }
      }
    }

    const finalContent = [...lineDict.entries()]
      .sort(([a], [b]) => a - b)
      .filter(([, v]) => v !== REMOVE_FLAG)
      .map(([, v]) => v)
      .join('\n');

    result.set(diff.filenamePost, finalContent);
    if (diff.filenamePre !== diff.filenamePost) result.delete(diff.filenamePre);
  }

  return result;
}

// ─── AI 调用抽象层（接神枢 /talk 端点）───
class NexusAI {
  constructor(endpoint, ownerToken, modelProfile = 'POWER') {
    this.endpoint    = endpoint;
    this.ownerToken  = ownerToken;
    this.modelProfile = modelProfile;
  }

  async start(systemPrompt, userMessage) {
    return this.#call([
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: userMessage },
    ]);
  }

  async next(messages, assistantFollowup) {
    return this.#call([...messages, { role: 'user', content: assistantFollowup }]);
  }

  async #call(messages) {
    const resp = await fetch(this.endpoint, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${this.ownerToken}`,
      },
      body: JSON.stringify({ messages, model_profile: this.modelProfile }),
    });
    if (!resp.ok) throw new Error(`AI 调用失败: ${resp.status}`);
    const data = await resp.json();
    const reply = data.reply ?? data.text ?? data.content ?? '';
    return [...messages, { role: 'assistant', content: reply }];
  }
}

// ─── preprompts：对齐 gpt-engineer 的提示词结构 ───
const PREPROMPTS = {
  roadmap: `你是神枢代码生成引擎。你会生成高质量、可直接运行的代码。`,

  generate: `
根据需求生成完整代码。每个文件用以下格式输出：

FILE_FORMAT

确保代码完整，不要省略任何部分。`,

  improve: `
分析现有代码并按需求改进。输出 unified diff 格式的修改：

FILE_FORMAT

每个 diff 包含完整的文件路径和标准 @@ 行号标注。`,

  file_format: `
文件名（相对路径）
\`\`\`语言
文件内容
\`\`\`
`,

  file_format_diff: `
--- a/原文件路径
+++ b/新文件路径
@@ -起始行,行数 +起始行,行数 @@
 保留行（空格开头）
+新增行（+开头）
-删除行（-开头）
`,

  philosophy: `
- 代码要完整可运行，不要写 TODO / placeholder
- 用中文注释关键逻辑
- 错误处理要完善
- 遵循现有代码风格
`,
};

/**
 * NexusCodeEngine：神枢代码生成引擎
 *
 * 两种工作模式（对齐 gpt-engineer CliAgent）：
 *   - gen_code：从零生成（init 模式）
 *   - improve：对已有代码打 diff patch（improve 模式）
 */
export class NexusCodeEngine {
  constructor(config = {}) {
    this.ai = new NexusAI(
      config.aiEndpoint ?? 'https://aquan.lufei.uk/talk',
      config.ownerToken ?? '',
      config.modelProfile ?? 'POWER',
    );
  }

  /**
   * genCode：从零生成代码（对齐 gpt-engineer gen_code）
   * @param {string} prompt - 需求描述
   * @returns {FilesDict}
   */
  async genCode(prompt) {
    const sysPrompt =
      PREPROMPTS.roadmap +
      PREPROMPTS.generate.replace('FILE_FORMAT', PREPROMPTS.file_format) +
      '\n\n有用的规范：\n' +
      PREPROMPTS.philosophy;

    const messages = await this.ai.start(sysPrompt, prompt);
    const chat = messages[messages.length - 1].content.trim();
    return chatToFilesDict(chat);
  }

  /**
   * improve：改进已有代码（对齐 gpt-engineer improve，两轮对话）
   * @param {FilesDict} filesDict - 当前文件状态
   * @param {string} prompt       - 改进需求
   * @returns {FilesDict}
   */
  async improve(filesDict, prompt) {
    const sysPrompt =
      PREPROMPTS.roadmap +
      PREPROMPTS.improve.replace('FILE_FORMAT', PREPROMPTS.file_format_diff) +
      '\n\n有用的规范：\n' +
      PREPROMPTS.philosophy;

    // 第一轮：给需求
    let messages = await this.ai.start(sysPrompt, prompt);

    // 第二轮：传当前文件内容（核心双轮对话机制）
    messages = await this.ai.next(
      messages,
      `以下是当前代码实现：\n\n${filesDict.toChat()}`,
    );

    const chat = messages[messages.length - 1].content.trim();
    const diffs = parseDiffs(chat);

    if (diffs.size === 0) {
      // 没解析到 diff，尝试当成新文件输出解析
      return chatToFilesDict(chat);
    }

    return applyDiffs(diffs, filesDict);
  }

  /**
   * genEntrypoint：生成入口脚本（对齐 gpt-engineer gen_entrypoint）
   * @param {string} prompt
   * @param {FilesDict} filesDict
   * @returns {FilesDict} - 只含 run.sh 或 package.json 等入口文件
   */
  async genEntrypoint(prompt, filesDict) {
    const messages = await this.ai.start(
      PREPROMPTS.roadmap + '\n根据以下代码结构，生成启动脚本（run.sh 或 start 命令）：',
      `需求：${prompt}\n\n代码结构：\n${[...filesDict.keys()].join('\n')}`,
    );
    const chat = messages[messages.length - 1].content.trim();
    return chatToFilesDict(chat);
  }
}

// ─── Cloudflare Workers HTTP 路由处理 ───
// 挂到 nexus_do.core.mjs 路由表：
//   import { NexusCodeEngine } from './nexus_code_engine.mjs';
//   const engine = new NexusCodeEngine({ aiEndpoint: env.NEXUS_GATEWAY_URL, ownerToken: env.OWNER_TOKEN });
//
//   case '/code/gen':     handleCodeGen(request, env, engine)
//   case '/code/improve': handleCodeImprove(request, env, engine)

export async function handleCodeGen(request, env, engine) {
  const { prompt } = await request.json();
  if (!prompt) return new Response('prompt required', { status: 400 });

  const filesDict = await engine.genCode(prompt);
  return Response.json({ files: filesDict.toJSON(), count: filesDict.size });
}

export async function handleCodeImprove(request, env, engine) {
  const { prompt, files } = await request.json();
  if (!prompt || !files) return new Response('prompt + files required', { status: 400 });

  const input = new FilesDict(Object.entries(files));
  const result = await engine.improve(input, prompt);
  return Response.json({ files: result.toJSON(), count: result.size });
}
