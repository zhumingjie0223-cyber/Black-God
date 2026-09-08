/* ============================================================
   Black God · Web Push 前端助手  v1.1 (iOS-aware)
   window.BGPush:
     await BGPush.enable()  -> {ok:true, endpoint} | {ok:false, reason}
        reason: unsupported | denied | ios-too-old | ios-needs-install
     await BGPush.disable() -> true
     await BGPush.status()  -> {supported, permission, subscribed, ios, standalone, iosVersion}
   ============================================================ */
(function () {
  // 与 sw.js / 后端的 VAPID_PUBLIC_KEY 必须一致
  const VAPID_PUBLIC_KEY = 'BHM1sPhLLPoBoxqX8EQ627drm_QWjx4mOhyVfypuJ2tjnsXFZ6rRV6Y_pzeh6vERXlHOIvbbDIY3U2XpWfR6tR8';

  function getUserId() {
    try {
      const p = JSON.parse(localStorage.getItem('bg.userProfile') || '{}');
      return p.id || p.name || null;
    } catch (_) { return null; }
  }

  function urlBase64ToUint8Array(b64) {
    const pad = '='.repeat((4 - (b64.length % 4)) % 4);
    const base64 = (b64 + pad).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    const arr = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
    return arr;
  }

  function iosInfo() {
    const ua = navigator.userAgent || '';
    const isiOS = /iP(hone|ad|od)/.test(ua) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1); // iPadOS 伪装桌面
    const standalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
      || window.navigator.standalone === true;
    let ver = null;
    const m = ua.match(/OS (\d+)_(\d+)/);
    if (m) ver = parseFloat(m[1] + '.' + m[2]);
    return { isiOS, standalone, ver };
  }

  const supported = () =>
    'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

  const getReg = () => navigator.serviceWorker.ready;

  async function postJSON(url, body) {
    const r = await fetch(url, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
    });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.json().catch(() => ({}));
  }

  async function enable() {
    if (!supported()) return { ok: false, reason: 'unsupported' };

    const ios = iosInfo();
    if (ios.isiOS) {
      if (ios.ver !== null && ios.ver < 16.4) return { ok: false, reason: 'ios-too-old' };
      if (!ios.standalone) return { ok: false, reason: 'ios-needs-install' }; // 必须先加到主屏幕
    }

    // 通知权限（iOS 必须在用户手势里申请——开关点击就是手势）
    let perm = Notification.permission;
    if (perm === 'default') perm = await Notification.requestPermission();
    if (perm !== 'granted') return { ok: false, reason: 'denied' };

    const reg = await getReg();
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
      });
    }
    await postJSON('/api/push/subscribe', { subscription: sub, userId: getUserId() });
    localStorage.setItem('bg.push.on', '1');
    console.log('[BGPush] 已订阅', sub.endpoint);
    return { ok: true, endpoint: sub.endpoint };
  }

  async function disable() {
    localStorage.setItem('bg.push.on', '0');
    if (!supported()) return true;
    try {
      const reg = await getReg();
      const sub = await reg.pushManager.getSubscription();
      if (sub) {
        await postJSON('/api/push/unsubscribe', { endpoint: sub.endpoint });
        await sub.unsubscribe();
      }
    } catch (e) { console.warn('[BGPush] 退订异常（忽略）', e); }
    return true;
  }

  async function status() {
    const ios = iosInfo();
    if (!supported()) return { supported: false, permission: 'unsupported', subscribed: false, ios: ios.isiOS, standalone: ios.standalone, iosVersion: ios.ver };
    let subscribed = false;
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      const sub = reg && (await reg.pushManager.getSubscription());
      subscribed = !!sub;
    } catch (_) {}
    return { supported: true, permission: Notification.permission, subscribed, ios: ios.isiOS, standalone: ios.standalone, iosVersion: ios.ver };
  }

  // 每次启动：开过推送但订阅丢了 → 静默补订阅（iOS 重订的主要保险）
  async function autoResync() {
    if (localStorage.getItem('bg.push.on') !== '1') return;
    const s = await status();
    if (s.supported && s.permission === 'granted' && !s.subscribed) {
      if (s.ios && !s.standalone) return; // iOS 未装主屏幕，订不了
      enable().catch(() => {});
    }
  }
  if (supported()) navigator.serviceWorker.ready.then(autoResync).catch(() => {});

  window.BGPush = { enable, disable, status, supported };
})();
