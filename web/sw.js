/* ============================================================
   Black God · Service Worker v3.2 (iOS-hardened)
   缓存策略沿用 v3.0；新增真·Web Push，并针对 iOS 做硬化：
   - push: 每次都强制 showNotification（哪怕 payload 空/坏），
           绝不"静默推送"——否则 iOS 会逐步收回推送配额。
   - notificationclick: 聚焦已开页面或打开 App 并跳到对应任务。
   - pushsubscriptionchange: 订阅被系统轮换时自动重订并回报后端。
   ============================================================ */
const CACHE = 'bg-v3.2';
const SHELL = ['/', '/index.html', '/manifest.json', '/icon-192.png', '/icon-512.png'];

/* 公钥是公开的，安全写死。换密钥时此处 + push-client.js + 后端三处同步改。 */
const VAPID_PUBLIC_KEY = 'BHM1sPhLLPoBoxqX8EQ627drm_QWjx4mOhyVfypuJ2tjnsXFZ6rRV6Y_pzeh6vERXlHOIvbbDIY3U2XpWfR6tR8';

function urlBase64ToUint8Array(b64) {
  const pad = '='.repeat((4 - (b64.length % 4)) % 4);
  const base64 = (b64 + pad).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => Promise.allSettled(SHELL.map((u) => c.add(u)))));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  if (url.pathname.startsWith('/api/')) {
    e.respondWith(fetch(req).catch(() =>
      new Response(JSON.stringify({ error: 'offline', message: '当前离线，请联网后重试' }),
        { headers: { 'Content-Type': 'application/json' } })));
    return;
  }
  if (url.origin !== self.location.origin) {
    e.respondWith(fetch(req).catch(() => caches.match(req)));
    return;
  }
  e.respondWith(
    caches.match(req).then((cached) =>
      cached || fetch(req).then((resp) => {
        if (resp && resp.status === 200 && resp.type === 'basic') {
          const copy = resp.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return resp;
      }).catch(() => caches.match('/index.html')))
  );
});

/* ====================== 真·Web Push ====================== */

// 收到推送：无论如何都弹一条通知（iOS 配额保命）
self.addEventListener('push', (event) => {
  event.waitUntil((async () => {
    let data = {};
    try { data = event.data ? event.data.json() : {}; }
    catch (_) {
      try { data = { body: event.data ? event.data.text() : '' }; } catch (e) { data = {}; }
    }

    const title = data.title || 'Black God';
    const options = {
      body: data.body || '你有一条新消息',
      icon: data.icon || '/icon-192.png',
      badge: data.badge || '/icon-192.png',
      tag: data.tag || 'bg-push',
      renotify: true,
      requireInteraction: !!data.requireInteraction,
      data: { url: data.url || '/', taskId: data.taskId || null, raw: data },
      actions: Array.isArray(data.actions) ? data.actions : []
    };
    // 后台系统通知也要有声有震：silent 关掉，震动给默认模式
    // （震动 Android 生效；iOS 由系统设置决定，带上无害；声音用系统通知音）
    options.silent = false;
    options.vibrate = data.vibrate ||
      (data.requireInteraction ? [45, 35, 45, 35, 45] : [30, 20, 30]);

    try {
      await self.registration.showNotification(title, options);
    } catch (e) {
      // 兜底：上面任何异常都再强弹一条最简通知，确保本次 push 非静默
      try { await self.registration.showNotification('Black God', { body: '你有一条新消息', icon: '/icon-192.png', tag: 'bg-fallback' }); } catch (_) {}
    }
  })());
});

// 点通知：聚焦已开窗口 / 否则新开，并跳到对应任务
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  if (event.action === 'dismiss') return;

  const d = event.notification.data || {};
  let target = d.url || '/';
  if (d.taskId) {
    const sep = target.includes('?') ? '&' : '?';
    target = `${target}${sep}task=${encodeURIComponent(d.taskId)}`;
  }
  event.waitUntil((async () => {
    const all = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) {
      if ('focus' in c) {
        await c.focus();
        if ('postMessage' in c) c.postMessage({ type: 'push-open', url: target, taskId: d.taskId });
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});

// 系统轮换订阅：自动重订并回报后端
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil((async () => {
    try {
      const sub = await self.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
      });
      await fetch('/api/push/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subscription: sub })
      });
    } catch (_) { /* 下次打开 push-client 的 autoResync 会补 */ }
  })());
});

self.addEventListener('message', (e) => { if (e.data === 'skipWaiting') self.skipWaiting(); });
