// Black God PWA Service Worker
const CACHE = "blackgod-v1";
const ASSETS = [
  "/",
  "/index.html",
  "/theme.css",
  "/manifest.json",
  "/logo.png",
  "/icon-192.png",
  "/icon-512.png",
];

self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).catch(() => {}));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return; // 不缓存 API 写请求
  const url = new URL(req.url);
  if (url.pathname.startsWith("/api/")) return; // API 始终走网络

  // 静态资源：缓存优先，回退网络
  e.respondWith(
    caches.match(req).then((cached) =>
      cached ||
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match("/index.html"))
    )
  );
});
