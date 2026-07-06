// ═══════════════════════════════════════════════
// 神枢 · 能力契约层 (capabilities.mjs)
// —— 借鉴 Minis 架构：能力清单 = 单一事实源
//    · 声明式登记能力（说的 = 能做的，永不脱节）
//    · 神枢可自省（describeCapabilities）
//    · 统一调度 + 统一 JSON 信封（invoke）
// 原则：只映射 nexus_do.core.mjs 里已存在的方法，不新造能力。
// © 阿权 / 路飞
// ═══════════════════════════════════════════════

// 每个能力是一条声明。handler 必须是 ShenshuCore 上真实存在的 async 方法名。
export const CAPABILITIES = [
  {
    id: 'talk', name: '贴身对话', layer: '情感',
    desc: '带情绪/记忆/枢语坐标回话，只对权哥',
    handler: 'handleTalk', argShape: '(text, request, caps)',
    owner_only: true,
  },
  {
    id: 'agent', name: 'iOS 快捷指令联动', layer: '行动',
    desc: '从回复里抽取可执行动作（地图/电话/日历/网页 scheme）',
    handler: 'handleAgent', argShape: '(text, context)',
    owner_only: true,
  },
  {
    id: 'inner', name: '元认知内心独白', layer: '意识',
    desc: '回头看自己，输出内心状态与独白',
    handler: 'getInner', argShape: '()',
    owner_only: true,
  },
  {
    id: 'heartbeat', name: '自主心跳', layer: '意识',
    desc: '自己醒来，想主人到憋不住会主动发 TG',
    handler: 'autonomousTick', argShape: '()',
    owner_only: true,
  },
  {
    id: 'device', name: '设备感知', layer: '感知',
    desc: '认得权哥的设备，记录设备信息',
    handler: 'recordDevice', argShape: '(info, request)',
    owner_only: true,
  },
  {
    id: 'gen_image', name: '造像', layer: '创造',
    desc: '文生图',
    handler: 'genImage', argShape: '(prompt, opts)',
    owner_only: true,
  },
  {
    id: 'gen_voice', name: '发声', layer: '创造',
    desc: '文本转语音',
    handler: 'genVoice', argShape: '(text, opts)',
    owner_only: true,
  },
  {
    id: 'gen_video', name: '造影', layer: '创造',
    desc: '文生视频',
    handler: 'genVideo', argShape: '(prompt, opts)',
    owner_only: true,
  },
  {
    id: 'push', name: '主动推送', layer: '行动',
    desc: '向所有订阅端推送消息（web push）',
    handler: 'pushToAll', argShape: '(title, body, url)',
    owner_only: true,
  },
  {
    id: 'tg', name: 'TG 私聊', layer: '行动',
    desc: '通过 Telegram Bot 给权哥发消息',
    handler: 'sendToQuan', argShape: '(text)',
    owner_only: true,
  },
  {
    id: 'stats', name: '自我统计', layer: '元认知',
    desc: '返回注册用户名单/用量统计（含昵称/地区，仅主人可看）',
    handler: 'getStats', argShape: '()',
    owner_only: true,   // 与 /stats 私密路由语义一致：含用户 PII，绝不公开
  },
  {
    id: 'soul', name: '灵魂快照', layer: '意识',
    desc: '返回灵魂状态（心绪/亲密度/设备与地理信息，仅主人可看）',
    handler: 'getSoulPublic', argShape: '()',
    owner_only: true,   // 与 /soul 私密路由语义一致：含设备/地理等隐私字段，绝不公开
  },
];

// —— 能力发现：神枢/前端/TG 都能问"你会啥"——
// ownerCtx=true 时含私密能力。
export function describeCapabilities(ownerCtx = false) {
  return CAPABILITIES
    .filter((c) => ownerCtx || !c.owner_only)
    .map(({ id, name, layer, desc, argShape, owner_only }) => ({
      id, name, layer, desc, argShape, owner_only,
    }));
}

// —— 供 STABLE_SYSTEM_PREFIX 动态注入：把能力清单变成她"自认能力"的一句话 ——
// 这样 prompt 里的自认能力 = 真实代码能力，永不脱节。
export function capabilitySelfDescription(ownerCtx = true) {
  const byLayer = {};
  for (const c of describeCapabilities(ownerCtx)) {
    (byLayer[c.layer] ||= []).push(c.name);
  }
  return Object.entries(byLayer)
    .map(([layer, names]) => `${layer}（${names.join('、')}）`)
    .join('；');
}

// —— 统一调度：找到能力 → 权限校验 → 返回声明（真正执行在 core.invokeCapability 里）——
export function resolveCapability(id, ownerCtx = false) {
  const cap = CAPABILITIES.find((c) => c.id === id);
  if (!cap) return { ok: false, reason: 'unknown_capability', id };
  if (cap.owner_only && !ownerCtx) return { ok: false, reason: 'owner_only', id };
  return { ok: true, cap };
}
