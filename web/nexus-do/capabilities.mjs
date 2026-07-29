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
    id: 'talk', name: '对话', layer: '意识',
    desc: '带状态/记忆/枢语坐标回话',
    handler: 'handleTalk', argShape: '(text, request, caps)',
    tier: 'instance',
    owner_only: true,
  },
  {
    id: 'agent', name: 'iOS 快捷指令联动', layer: '行动',
    desc: '从回复里抽取可执行动作（地图/电话/日历/网页 scheme）',
    handler: 'handleAgent', argShape: '(text, context)',
    tier: 'instance',
    owner_only: true,
  },
  {
    id: 'inner', name: '元认知内心独白', layer: '意识',
    desc: '回头看自己，输出内心状态与独白',
    handler: 'getInner', argShape: '()',
    tier: 'instance',
    owner_only: true,
  },
  {
    id: 'heartbeat', name: '自主心跳', layer: '意识',
    desc: '自己醒来，想主人到憋不住会主动发 TG',
    handler: 'autonomousTick', argShape: '()',
    tier: 'system',
    owner_only: true,
  },
  {
    id: 'device', name: '设备感知', layer: '感知',
    desc: '认得主人的设备，记录设备信息',
    handler: 'recordDevice', argShape: '(info, request)',
    tier: 'instance',
    owner_only: true,
  },
  {
    id: 'gen_image', name: '造像', layer: '创造',
    desc: '文生图',
    handler: 'genImage', argShape: '(prompt, opts)',
    tier: 'system',
    owner_only: true,
  },
  {
    id: 'gen_voice', name: '发声', layer: '创造',
    desc: '文本转语音',
    handler: 'genVoice', argShape: '(text, opts)',
    tier: 'system',
    owner_only: true,
  },
  {
    id: 'gen_video', name: '造影', layer: '创造',
    desc: '文生视频',
    handler: 'genVideo', argShape: '(prompt, opts)',
    tier: 'system',
    owner_only: true,
  },
  {
    id: 'push', name: '主动推送', layer: '行动',
    desc: '向所有订阅端推送消息（web push）',
    handler: 'pushToAll', argShape: '(title, body, url)',
    tier: 'system',
    owner_only: true,
  },
  {
    id: 'tg', name: 'TG 私聊', layer: '行动',
    desc: '通过 Telegram Bot 给主人发消息',
    handler: 'sendToQuan', argShape: '(text)',
    tier: 'system',
    owner_only: true,
  },
  {
    id: 'stats', name: '自我统计', layer: '元认知',
    desc: '返回注册用户名单/用量统计（含昵称/地区，仅主人可看）',
    handler: 'getStats', argShape: '()',
    tier: 'system',
    owner_only: true,   // 与 /stats 私密路由语义一致：含用户 PII，绝不公开
  },
  {
    id: 'soul', name: '灵魂快照', layer: '意识',
    desc: '返回灵魂状态（心绪/亲密度/设备与地理信息，仅主人可看）',
    handler: 'getSoulPublic', argShape: '()',
    tier: 'instance',
    owner_only: true,   // 与 /soul 私密路由语义一致：含设备/地理等隐私字段，绝不公开
  },
  {
    id: 'exec', name: '执行脑（真沙箱）', layer: '行动',
    desc: '在主人自有服务器上真跑 shell 命令/代码（需配 NEXUS_EXEC_URL + token；未配则如实告知，绝不假装）',
    handler: 'execRemote', argShape: '(command)',
    tier: 'system',
    owner_only: true,   // 能在真机跑命令，最高危：仅主人、且靠服务器端 token 双重门
  },
  {
    id: 'apple', name: 'iOS 硬件手', layer: '行动',
    desc: '经沙箱执行脑真调主人 iPhone 的 21 个宿主工具：闹钟/日历/提醒/天气/定位/导航/健康/剪贴板/智能家居/通知/相册/识图/朗读等（照 Minis 宿主 apple-* 契约；需执行脑隧道，未接入则如实告知）',
    handler: 'appleTool', argShape: '(arg: "工具名 子命令 参数")',
    tier: 'system',
    owner_only: true,   // 直接操作主人私人设备，最高危：仅主人，且经执行脑隧道 token 门
  },
  {
    id: 'analyze_target', name: '目标研判', layer: '逆向',
    desc: '对逆向目标做初步研判：识别保护类型（VMP/Themida/网络验证/驱动验证/.NET/Electron），输出推荐分析路径、难度和最快突破点',
    handler: 'reverseKB', argShape: '(目标名称或描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'find_entry', name: '定位关键函数', layer: '逆向',
    desc: '用错误字符串法/API断点法定位注册验证、VIP判断等核心函数，给出具体操作步骤',
    handler: 'reverseKB', argShape: '(目标名称或描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'bypass_antidebug', name: '反反调试', layer: '逆向',
    desc: '绕过NtGlobalFlag/IsDebuggerPresent/VMP/Themida/ptrace等反调试手段，给出具体bypass步骤和工具配置',
    handler: 'reverseKB', argShape: '(目标名称或描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'frida_hook', name: 'Frida Hook脚本', layer: '逆向',
    desc: '为Android/iOS目标生成完整Frida hook脚本：函数拦截/返回值篡改/签名绕过/ptrace bypass/SSL Pinning绕过',
    handler: 'reverseKB', argShape: '(目标进程名或描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'js_deobfuscate', name: 'JS反混淆', layer: '逆向',
    desc: '还原JS混淆：识别eval型/字符串数组/VM指令/控制流平坦化/AES加密，提取key/iv，给出Python复现代码',
    handler: 'reverseKB', argShape: '(目标JS文件或混淆特征描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'crack_network_auth', name: '破解网络验证', layer: '逆向',
    desc: '分析并破解网络授权验证：抓包定位校验请求，还原算法，生成本地验证patch或伪造响应方案',
    handler: 'reverseKB', argShape: '(目标名称或验证描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'apk_repack', name: 'APK重打包', layer: '逆向',
    desc: '完整APK逆向重打包流程：apktool解包→smali修改VIP/验证逻辑→重打包→签名，给出完整bash命令',
    handler: 'reverseKB', argShape: '(目标APK名称或包名)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'ios_bypass', name: 'iOS越狱/签名绕过', layer: '逆向',
    desc: '绕过iOS越狱检测/签名校验/完整性检测，生成Frida脚本，覆盖NSFileManager/SecStaticCodeCheckValidity等常见检测点',
    handler: 'reverseKB', argShape: '(目标App名称或描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'get_full_chain', name: '完整攻击链', layer: '逆向',
    desc: '制定完整逆向攻击链：情报→突破→分析→武器化，每步含具体命令/代码，覆盖Windows/Android/iOS/JS/流量/PWN',
    handler: 'reverseKB', argShape: '(目标名称或描述)',
    tier: 'heavy', owner_only: true,
  },
  {
    id: 'watch', name: '自主守望（闭环神·环）', layer: '行动',
    desc: '架一条不用人守的常驻管道：她定时自己去取、真调工具推演，有变化就主动推给主人。说「帮我每小时盯一下X」即可织一条。',
    handler: 'createWatch', argShape: '(text: 盯什么·多久一次)',
    tier: 'system',
    owner_only: true,
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
// ctx 兼容两种写法：
//   · 布尔（旧·单租户）：true=主人上下文，false=公开。语义不变。
//   · 对象（新·多租户）：{ role: 'system' | 'instance' | 'anon' }。
//     system=系统主人(权哥,全权)；instance=实例主人(只放行 tier==='instance' 的能力)；
//     anon=匿名(只放行非 owner_only,现阶段=无)。
export function resolveCapability(id, ctx = false) {
  const cap = CAPABILITIES.find((c) => c.id === id);
  if (!cap) return { ok: false, reason: 'unknown_capability', id };
  const role = (ctx && typeof ctx === 'object') ? ctx.role : (ctx ? 'system' : 'anon');
  if (role === 'system') return { ok: true, cap };
  if (role === 'instance') {
    if (cap.tier === 'instance') return { ok: true, cap };
    return { ok: false, reason: 'system_only', id };  // 实例主人碰不到系统级(exec/烧钱/跨用户)
  }
  // anon
  if (cap.owner_only) return { ok: false, reason: 'owner_only', id };
  return { ok: true, cap };
}
