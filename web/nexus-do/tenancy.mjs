// ═══════════════════════════════════════════════
// 神枢 · 多租户身份/路由(tenancy.mjs)—— 纯逻辑,无副作用,可单测
// 依据 docs/architecture/多租户地基-每个用户一个神枢.md
//
// 职责:把「一次请求的身份材料」判定成「角色 + 该去哪个 DO 实例」。
//   · 系统主人(权哥):持有效 OWNER_TOKEN → 固定私密实例(不变、零迁移)
//   · 实例主人(每用户):带自己的 uid → 独立实例 u:<uid>
//   · 匿名:无令牌无 uid → 无实例(引导注册)
//
// 安全:角色只由「服务器端可信材料」推导——OWNER_TOKEN 服务器端比对、uid 仅用于选实例。
// 绝不读取客户端自带的角色头(那种头会被顶层 worker 剥掉后重设),故本函数根本不看它。
// © 阿权 / 路飞
// ═══════════════════════════════════════════════

// 系统主人(权哥)的固定实例名——保持历史值,现有数据零迁移。
export const SYSTEM_DO = 'quan-shenshu-nexus';

// uid 白名单:只留安全字符,封顶 64。防止用可控输入拼出别人的实例名或注入。
export function sanitizeUid(raw) {
  return String(raw || '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
}

// 身份判定:{authHeader, uidHeader, ownerToken} → {role, doName, uid}
//   role: 'system' | 'instance' | 'anon'
export function resolveIdentity({ authHeader = '', uidHeader = '', ownerToken = '' } = {}) {
  // 系统主人:服务器端严格比对 OWNER_TOKEN(配了才认;没配则谁也当不了系统主人)
  if (ownerToken && authHeader === 'Bearer ' + ownerToken) {
    return { role: 'system', doName: SYSTEM_DO, uid: null };
  }
  // 实例主人:带自己的 uid → 自己的实例
  const uid = sanitizeUid(uidHeader);
  if (uid) return { role: 'instance', doName: 'u:' + uid, uid };
  // 匿名:无实例
  return { role: 'anon', doName: null, uid: null };
}

// 系统专属路由:实例主人(普通用户)绝不可达——含烧权哥算力(造像/造声/造影)、
// 危险/规模(执行脑/迁移/推送/自主守望/心跳)、跨用户(统计)、以及暂缓的 WS。
export const SYSTEM_ONLY_PATHS = new Set([
  '/exec-test', '/migrate', '/push-test', '/stats',
  '/image', '/voice', '/video',
  '/heartbeat', '/loop', '/wsticket',
]);

// 该路由是否为系统专属(仅系统主人可达)
export function isSystemOnlyPath(path) {
  return SYSTEM_ONLY_PATHS.has(path);
}
