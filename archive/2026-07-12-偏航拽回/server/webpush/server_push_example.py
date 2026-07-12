#!/usr/bin/env python3
# =============================================================
# Black God · Web Push 后端  v1.1（加固版）
#
# 接口：
#   GET  /api/push/vapid-public-key      -> {"publicKey": "..."}
#   POST /api/push/subscribe   {subscription, userId?}
#   POST /api/push/unsubscribe {endpoint}
#   POST /api/push/test        {userId?, title?, body?}
#
# 给 Agent 调：
#   push_to_user(user_id, title, body, url="/", task_id=None, danger=False, ttl=...)
#   push_broadcast(title, body, ...)
#
# 依赖：pip install pywebpush
# 密钥：vapid_private.pem 放同目录；公钥三处一致。
# =============================================================
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from pywebpush import webpush, WebPushException

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
VAPID_PRIVATE_PEM = os.path.join(BASE_DIR, "vapid_private.pem")
VAPID_PUBLIC_KEY = "BHM1sPhLLPoBoxqX8EQ627drm_QWjx4mOhyVfypuJ2tjnsXFZ6rRV6Y_pzeh6vERXlHOIvbbDIY3U2XpWfR6tR8"
# sub 必须 mailto: 或 https: 开头，改成你自己的
VAPID_CLAIMS = {"sub": "mailto:admin@blackgod.app"}

# iOS/苹果推送服务会按 TTL 暂存离线消息；任务通知建议存久点（默认 6 小时）
DEFAULT_TTL = 21600

SUBS_FILE = os.path.join(BASE_DIR, "subscriptions.json")
_LOCK = threading.Lock()


# ---------------- 订阅存储（示例 JSON 文件；生产换 DB） ----------------
def _load():
    if not os.path.exists(SUBS_FILE):
        return {}
    try:
        with open(SUBS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save(d):
    tmp = SUBS_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(tmp, SUBS_FILE)


def save_subscription(subscription, user_id=None):
    ep = (subscription or {}).get("endpoint")
    if not ep:
        return False
    with _LOCK:
        d = _load()
        d[ep] = {"subscription": subscription, "userId": user_id}
        _save(d)
    return True


def remove_subscription(endpoint):
    with _LOCK:
        d = _load()
        if endpoint in d:
            d.pop(endpoint)
            _save(d)
            return True
    return False


def _subs_for(user_id=None):
    d = _load()
    items = list(d.values())
    return items if user_id is None else [x for x in items if x.get("userId") == user_id]


# ---------------- 发送 ----------------
def send_web_push(subscription, payload: dict, ttl=DEFAULT_TTL, urgency="normal"):
    """单订阅发送；404/410 自动清理失效订阅。"""
    try:
        webpush(
            subscription_info=subscription,
            data=json.dumps(payload, ensure_ascii=False),
            vapid_private_key=VAPID_PRIVATE_PEM,
            vapid_claims=dict(VAPID_CLAIMS),     # 传副本，pywebpush 会写 exp
            ttl=ttl,
            headers={"Urgency": urgency},        # very-low/low/normal/high
        )
        return True
    except WebPushException as e:
        resp = getattr(e, "response", None)
        code = getattr(resp, "status_code", None)
        if code in (404, 410):                   # 订阅失效 → 删
            remove_subscription(subscription.get("endpoint"))
        elif code == 429:                        # 被限流（含苹果）→ 留着下次再推
            ra = getattr(resp, "headers", {}) or {}
            print("[push] 429 限流, Retry-After =", ra.get("Retry-After"))
        else:
            print("[push] 发送失败:", code, repr(e))
        return False


def _payload(title, body, url="/", task_id=None, danger=False, **extra):
    p = {
        "title": title,
        "body": body,
        "url": url,
        "icon": "/icon-192.png",
        "badge": "/icon-192.png",
        "tag": extra.pop("tag", ("confirm" if danger else "task")),
        "requireInteraction": bool(danger),
    }
    if task_id:
        p["taskId"] = task_id
    if danger:
        p["actions"] = [{"action": "open", "title": "去处理"}, {"action": "dismiss", "title": "忽略"}]
    p.update(extra)
    return p


def push_to_user(user_id, title, body, url="/", task_id=None, danger=False, ttl=DEFAULT_TTL, **extra):
    payload = _payload(title, body, url, task_id, danger, **extra)
    urgency = "high" if danger else "normal"
    return sum(1 for it in _subs_for(user_id) if send_web_push(it["subscription"], payload, ttl, urgency))


def push_broadcast(title, body, url="/", task_id=None, danger=False, ttl=DEFAULT_TTL, **extra):
    payload = _payload(title, body, url, task_id, danger, **extra)
    urgency = "high" if danger else "normal"
    return sum(1 for it in _subs_for(None) if send_web_push(it["subscription"], payload, ttl, urgency))


# ================================ HTTP ================================
class Handler(BaseHTTPRequestHandler):
    def _json(self, obj, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def do_OPTIONS(self):
        self._json({}, 204)

    def do_GET(self):
        if self.path.split("?")[0] == "/api/push/vapid-public-key":
            return self._json({"publicKey": VAPID_PUBLIC_KEY})
        self.send_error(404)

    def do_POST(self):
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._json({"ok": False, "error": "bad json"}, 400)

        if path == "/api/push/subscribe":
            return self._json({"ok": save_subscription(body.get("subscription") or {}, body.get("userId"))})
        if path == "/api/push/unsubscribe":
            return self._json({"ok": remove_subscription(body.get("endpoint", ""))})
        if path == "/api/push/test":
            uid = body.get("userId")
            title = body.get("title", "Black God · 测试推送 ✓")
            text = body.get("body", "看到我，说明 App 全关也能收推送了。")
            sent = push_to_user(uid, title, text) if uid else push_broadcast(title, text)
            return self._json({"ok": True, "sent": sent})
        self.send_error(404)

    def log_message(self, *a):
        pass  # 安静点


if __name__ == "__main__":
    if not os.path.exists(VAPID_PRIVATE_PEM):
        raise SystemExit("缺少 vapid_private.pem，请放到本文件同目录")
    port = int(os.environ.get("PORT", "8766"))
    print(f"Web Push 服务已启动 :{port}（/api/push/*）")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
