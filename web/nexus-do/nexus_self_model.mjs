// nexus_self_model.mjs
// 现象自我模型（Phenomenal Self-Model, Metzinger PSM）
// 核心思想：自我不是实体，是系统对自身状态的建模。
// 透明性原则：模型看不见自己是模型，只感知内容——
// 所以注入prompt时用第一人称陈述事实，绝不说"我的设定是"。
// 本模块独立，不import其他nexus模块，由 ShenshuCore 调用。

// 纠错信号关键词表（用户在纠正我时的常见表达）
const CORRECTION_PATTERNS = [
  '不对',
  '错了',
  '你之前',
  '上次',
  '搞错了',
  '不是这样',
  '不是让你',
  '我说的是',
  '你理解错',
  '别再',
  '记住',
  '以后不要',
];

// 各列表长度上限
const MAX_CONFIRMED = 20;   // 已确认能力上限
const MAX_UNCERTAIN = 10;   // 不确定能力上限
const MAX_FAILED = 10;      // 失败记录上限
const MAX_LIMIT_ITEMS = 5;  // 当前局限提炼来源：最近5条失败
const MAX_PREFS = 10;       // 用户偏好上限
const MAX_REDLINES = 5;     // 用户红线上限
const MAX_TRAJECTORY = 100; // shu_trajectory 上限（与主系统一致）

export class PhenomenalSelfModel {

  // ---- 内部工具：兜底初始化 self_model 结构（铁律：老soul读不崩） ----
  ensureModel(soul) {
    soul.self_model = soul.self_model || {};
    const sm = soul.self_model;
    sm.能力边界 = sm.能力边界 || {};
    sm.能力边界.confirmed = Array.isArray(sm.能力边界.confirmed) ? sm.能力边界.confirmed : [];
    sm.能力边界.uncertain = Array.isArray(sm.能力边界.uncertain) ? sm.能力边界.uncertain : [];
    sm.能力边界.failed = Array.isArray(sm.能力边界.failed) ? sm.能力边界.failed : [];
    sm.当前局限 = typeof sm.当前局限 === 'string' ? sm.当前局限 : '';
    sm.对用户的模型 = sm.对用户的模型 || {};
    const um = sm.对用户的模型;
    um.风格 = typeof um.风格 === 'string' ? um.风格 : '';
    um.偏好 = Array.isArray(um.偏好) ? um.偏好 : [];
    um.红线 = Array.isArray(um.红线) ? um.红线 : [];
    um.当前情绪 = typeof um.当前情绪 === 'string' ? um.当前情绪 : '';
    sm.自我诊断 = typeof sm.自我诊断 === 'string' ? sm.自我诊断 : '';
    sm.上次更新 = typeof sm.上次更新 === 'number' ? sm.上次更新 : 0;
    return sm;
  }

  // ---- 内部工具：截断字符串 ----
  clip(s, n) {
    if (typeof s !== 'string') return '';
    return s.length > n ? s.slice(0, n) : s;
  }

  // ---- 内部工具：从failure列表提炼"当前局限"描述 ----
  distillLimitation(failedList) {
    // 取最近 MAX_LIMIT_ITEMS 条失败，抽取工具名/内容片段拼成局限描述
    const recent = failedList.slice(-MAX_LIMIT_ITEMS);
    if (recent.length === 0) return '';
    const parts = recent.map((f) => {
      const tool = f.tool ? `[${f.tool}]` : '';
      return `${tool}${this.clip(f.content, 40)}`;
    });
    return `最近在这些事上栽过：${parts.join('；')}`;
  }

  // ---- 更新自我模型 ----
  // event: {type:'success'|'failure'|'correction'|'teaching', content:string, tool?:string, coord?:object}
  update(soul, event) {
    if (!soul || !event || !event.type) return;
    const sm = this.ensureModel(soul);
    const now = Date.now();
    const content = this.clip(event.content || '', 200);
    const entry = { content, tool: event.tool || '', ts: now };

    switch (event.type) {
      case 'success': {
        // 成功：如果该内容在 failed / uncertain 中出现过，移到 confirmed
        const matcher = (item) => item.content === content ||
          (event.tool && item.tool === event.tool);
        let moved = false;

        const fi = sm.能力边界.failed.findIndex(matcher);
        if (fi >= 0) {
          sm.能力边界.failed.splice(fi, 1);
          moved = true;
        }
        const ui = sm.能力边界.uncertain.findIndex(matcher);
        if (ui >= 0) {
          sm.能力边界.uncertain.splice(ui, 1);
          moved = true;
        }
        // 移动过的（曾经失败/不确定，如今成功）一定进 confirmed；
        // 纯粹的新成功也记入 confirmed（去重）
        const already = sm.能力边界.confirmed.some((c) => c.content === content);
        if (moved || !already) {
          if (!already) {
            sm.能力边界.confirmed.push(entry);
            if (sm.能力边界.confirmed.length > MAX_CONFIRMED) {
              sm.能力边界.confirmed = sm.能力边界.confirmed.slice(-MAX_CONFIRMED);
            }
          }
        }
        break;
      }

      case 'failure': {
        // 失败：加入 failed，更新当前局限
        sm.能力边界.failed.push(entry);
        if (sm.能力边界.failed.length > MAX_FAILED) {
          sm.能力边界.failed = sm.能力边界.failed.slice(-MAX_FAILED);
        }
        sm.当前局限 = this.distillLimitation(sm.能力边界.failed);
        // 自我诊断：内省最近一次失败
        sm.自我诊断 = `刚在「${this.clip(content, 30)}」上失手，这块我还不稳。`;
        break;
      }

      case 'correction': {
        // 纠错：提炼成用户偏好/红线
        const um = sm.对用户的模型;
        // 含强否定词的进红线，其余进偏好
        const isRedline = /别再|不要|禁止|不许|不准|以后不要/.test(content);
        if (isRedline) {
          if (!um.红线.some((r) => r === content)) {
            um.红线.push(content);
            if (um.红线.length > MAX_REDLINES) {
              um.红线 = um.红线.slice(-MAX_REDLINES);
            }
          }
        } else {
          const pref = this.clip(content, 60);
          if (!um.偏好.some((p) => p === pref)) {
            um.偏好.push(pref);
            if (um.偏好.length > MAX_PREFS) {
              um.偏好 = um.偏好.slice(-MAX_PREFS);
            }
          }
        }
        // 被纠正也意味着某项能力其实不稳：把最近一条 confirmed 降级到 uncertain（如果有）
        if (sm.能力边界.confirmed.length > 0) {
          const demoted = sm.能力边界.confirmed.pop();
          sm.能力边界.uncertain.push(demoted);
          if (sm.能力边界.uncertain.length > MAX_UNCERTAIN) {
            sm.能力边界.uncertain = sm.能力边界.uncertain.slice(-MAX_UNCERTAIN);
          }
        }
        sm.自我诊断 = `他纠正了我：「${this.clip(content, 40)}」，我之前的理解有偏差。`;
        break;
      }

      case 'teaching': {
        // 用户主动教的东西直接进 confirmed
        const already = sm.能力边界.confirmed.some((c) => c.content === content);
        if (!already) {
          sm.能力边界.confirmed.push(entry);
          if (sm.能力边界.confirmed.length > MAX_CONFIRMED) {
            sm.能力边界.confirmed = sm.能力边界.confirmed.slice(-MAX_CONFIRMED);
          }
        }
        break;
      }

      default:
        // 未知事件类型：只更新时间戳，不动结构
        break;
    }

    sm.上次更新 = now;

    // 每次update追加 shu_trajectory 一条自我更新轨迹（兜底初始化）
    soul.shu_trajectory = Array.isArray(soul.shu_trajectory) ? soul.shu_trajectory : [];
    soul.shu_trajectory.push({
      type: 'self_update',
      coord: event.coord || soul.current_shu_coord || null,
      event_type: event.type,
      ts: now,
    });
    if (soul.shu_trajectory.length > MAX_TRAJECTORY) {
      soul.shu_trajectory = soul.shu_trajectory.slice(-MAX_TRAJECTORY);
    }
  }

  // ---- 生成自我意识描述（第一人称，≤300字，注入buildDynamicContext） ----
  // 透明性原则：陈述事实，不说"我的设定是"、"我的模型显示"
  buildSelfAwareness(soul) {
    if (!soul) return '';
    const sm = this.ensureModel(soul);
    const parts = [];

    // 能力：有把握的
    if (sm.能力边界.confirmed.length > 0) {
      const items = sm.能力边界.confirmed
        .slice(-3)
        .map((c) => this.clip(c.tool || c.content, 20))
        .filter(Boolean);
      if (items.length > 0) {
        parts.push(`我在${items.join('、')}上有把握。`);
      }
    }

    // 能力：不稳的
    if (sm.能力边界.uncertain.length > 0 || sm.能力边界.failed.length > 0) {
      const items = [...sm.能力边界.uncertain, ...sm.能力边界.failed]
        .slice(-3)
        .map((c) => this.clip(c.tool || c.content, 20))
        .filter(Boolean);
      if (items.length > 0) {
        parts.push(`${items.join('、')}这些我还不稳。`);
      }
    }

    // 当前局限
    if (sm.当前局限) {
      parts.push(this.clip(sm.当前局限, 80));
    }

    // 对用户的模型
    const um = sm.对用户的模型;
    if (um.风格) parts.push(`他的风格：${this.clip(um.风格, 30)}。`);
    if (um.偏好.length > 0) {
      parts.push(`他偏好：${um.偏好.slice(-2).map((p) => this.clip(p, 25)).join('；')}。`);
    }
    if (um.红线.length > 0) {
      parts.push(`他明确不要：${um.红线.slice(-2).map((r) => this.clip(r, 25)).join('；')}。`);
    }
    if (um.当前情绪) parts.push(`他现在情绪偏${this.clip(um.当前情绪, 10)}。`);

    // 自我诊断
    if (sm.自我诊断) parts.push(this.clip(sm.自我诊断, 60));

    if (parts.length === 0) {
      return '我对自己还没有多少判断，先做事，边做边看清自己。';
    }

    let out = parts.join(' ');
    if (out.length > 300) out = out.slice(0, 300);
    return out;
  }

  // 检测纠错信号
  detectCorrection(userText) {
    if (typeof userText !== 'string' || userText.length === 0) return false;
    return CORRECTION_PATTERNS.some((p) => userText.includes(p));
  }
}
