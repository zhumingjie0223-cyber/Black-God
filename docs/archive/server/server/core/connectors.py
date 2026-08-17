#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
connectors.py — Black God 多平台连接器

支持：
  - Telegram Bot API
  - 飞书（Lark）Webhook
  - Slack Webhook
  - 服务器 SSH
  - 自定义 Webhook

Black God 通过这些连接器：
  1. 接收来自各平台的消息
  2. 把 AI 回复推送回对应平台
  3. 主动推送通知（任务完成、提醒等）
"""
import json
import urllib.request
import urllib.parse
import os
import time


# ─────────────────────────────────────────
# Telegram Bot 连接器
# ─────────────────────────────────────────
class TelegramConnector:
    """
    Telegram Bot API 连接器
    用途：Black God 可以通过 TG Bot 接收指令、发送回复
    """

    def __init__(self, token: str = None):
        self.token = token or os.environ.get("TG_BOT_TOKEN", "")
        self.base = f"https://api.telegram.org/bot{self.token}"

    def send(self, chat_id: str, text: str, parse_mode: str = "Markdown") -> dict:
        """发送消息到 Telegram"""
        if not self.token:
            return {"ok": False, "error": "未配置 TG_BOT_TOKEN"}
        try:
            data = json.dumps({
                "chat_id": chat_id,
                "text": text[:4096],
                "parse_mode": parse_mode
            }).encode()
            req = urllib.request.Request(
                f"{self.base}/sendMessage",
                data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def get_updates(self, offset: int = None) -> list:
        """拉取最新消息"""
        if not self.token:
            return []
        try:
            url = f"{self.base}/getUpdates?timeout=5"
            if offset:
                url += f"&offset={offset}"
            with urllib.request.urlopen(url, timeout=15) as r:
                data = json.loads(r.read().decode())
                return data.get("result", [])
        except Exception:
            return []

    def set_webhook(self, webhook_url: str) -> dict:
        """设置 Webhook（推荐，比轮询更高效）"""
        try:
            data = json.dumps({"url": webhook_url}).encode()
            req = urllib.request.Request(
                f"{self.base}/setWebhook",
                data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            return {"ok": False, "error": str(e)}


# ─────────────────────────────────────────
# 飞书 Webhook 连接器
# ─────────────────────────────────────────
class FeishuConnector:
    """
    飞书（Lark）Webhook 连接器
    用途：Black God 可以发消息到飞书群/机器人
    """

    def __init__(self, webhook_url: str = None):
        self.webhook = webhook_url or os.environ.get("FEISHU_WEBHOOK", "")

    def send_text(self, text: str) -> dict:
        """发送文本消息"""
        if not self.webhook:
            return {"ok": False, "error": "未配置 FEISHU_WEBHOOK"}
        return self._post({"msg_type": "text", "content": {"text": text}})

    def send_card(self, title: str, content: str, color: str = "blue") -> dict:
        """发送卡片消息（更好看）"""
        if not self.webhook:
            return {"ok": False, "error": "未配置 FEISHU_WEBHOOK"}
        card = {
            "msg_type": "interactive",
            "card": {
                "config": {"wide_screen_mode": True},
                "header": {
                    "title": {"tag": "plain_text", "content": title},
                    "template": color
                },
                "elements": [{
                    "tag": "div",
                    "text": {"tag": "lark_md", "content": content}
                }]
            }
        }
        return self._post(card)

    def _post(self, payload: dict) -> dict:
        try:
            data = json.dumps(payload, ensure_ascii=False).encode()
            req = urllib.request.Request(
                self.webhook, data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                return {"ok": True, "response": r.read().decode()}
        except Exception as e:
            return {"ok": False, "error": str(e)}


# ─────────────────────────────────────────
# Slack Webhook 连接器
# ─────────────────────────────────────────
class SlackConnector:
    """
    Slack Incoming Webhook 连接器
    用途：Black God 发消息到 Slack 频道
    """

    def __init__(self, webhook_url: str = None):
        self.webhook = webhook_url or os.environ.get("SLACK_WEBHOOK", "")

    def send(self, text: str, blocks: list = None) -> dict:
        """发送消息"""
        if not self.webhook:
            return {"ok": False, "error": "未配置 SLACK_WEBHOOK"}
        payload = {"text": text}
        if blocks:
            payload["blocks"] = blocks
        try:
            data = json.dumps(payload).encode()
            req = urllib.request.Request(
                self.webhook, data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                return {"ok": True, "response": r.read().decode()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def send_rich(self, title: str, content: str, color: str = "#D4AF37") -> dict:
        """发送富文本消息"""
        blocks = [
            {"type": "header", "text": {"type": "plain_text", "text": title}},
            {"type": "section", "text": {"type": "mrkdwn", "text": content}},
            {"type": "divider"}
        ]
        return self.send(title, blocks)


# ─────────────────────────────────────────
# 通用 Webhook 连接器
# ─────────────────────────────────────────
class WebhookConnector:
    """
    通用 Webhook 连接器
    用途：任何支持 HTTP POST 的服务
    """

    def __init__(self, url: str, headers: dict = None):
        self.url = url
        self.headers = headers or {"Content-Type": "application/json"}

    def send(self, payload: dict) -> dict:
        try:
            data = json.dumps(payload, ensure_ascii=False).encode()
            req = urllib.request.Request(
                self.url, data=data, headers=self.headers
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                return {"ok": True, "status": r.status, "body": r.read().decode()[:500]}
        except Exception as e:
            return {"ok": False, "error": str(e)}


# ─────────────────────────────────────────
# 连接器管理器（统一调度）
# ─────────────────────────────────────────
class ConnectorManager:
    """
    统一管理所有平台连接器
    Black God 通过这个类统一调用各平台
    """

    def __init__(self):
        self.tg = TelegramConnector()
        self.feishu = FeishuConnector()
        self.slack = SlackConnector()
        self._webhooks = {}

    def add_webhook(self, name: str, url: str, headers: dict = None):
        """添加自定义 Webhook"""
        self._webhooks[name] = WebhookConnector(url, headers)

    def notify_all(self, title: str, content: str,
                   platforms: list = None) -> dict:
        """
        向所有已配置的平台推送通知
        platforms: ['tg', 'feishu', 'slack'] 或 None（全部）
        """
        results = {}
        targets = platforms or ["tg", "feishu", "slack"]
        msg = f"**{title}**\n\n{content}"

        if "tg" in targets and self.tg.token:
            # TG 需要 chat_id，从环境变量读
            chat_id = os.environ.get("TG_CHAT_ID", "")
            if chat_id:
                results["tg"] = self.tg.send(chat_id, msg)

        if "feishu" in targets and self.feishu.webhook:
            results["feishu"] = self.feishu.send_card(title, content)

        if "slack" in targets and self.slack.webhook:
            results["slack"] = self.slack.send_rich(title, content)

        for name, wh in self._webhooks.items():
            results[name] = wh.send({"title": title, "content": content, "ts": time.time()})

        return results

    def get_status(self) -> dict:
        """返回各平台连接状态"""
        return {
            "telegram": {
                "configured": bool(self.tg.token),
                "env_var": "TG_BOT_TOKEN + TG_CHAT_ID"
            },
            "feishu": {
                "configured": bool(self.feishu.webhook),
                "env_var": "FEISHU_WEBHOOK"
            },
            "slack": {
                "configured": bool(self.slack.webhook),
                "env_var": "SLACK_WEBHOOK"
            },
            "wechat": {
                "configured": False,
                "note": "微信官方接口封闭，需用企业微信或第三方方案"
            },
            "custom_webhooks": list(self._webhooks.keys())
        }


# 全局单例
_manager = None

def get_manager() -> ConnectorManager:
    global _manager
    if not _manager:
        _manager = ConnectorManager()
    return _manager
