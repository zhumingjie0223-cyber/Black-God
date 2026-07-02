#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Black God · 本地隐私护栏  privacy_guard.py
================================================
作用：在任何数据离开本机之前（模型网关 / S3-R2 上传 / 外部连接器），
      统一扫描密钥、私钥、token、私密文件、PII、以及用户「禁碰清单」，
      命中则按策略 脱敏 / 拦截，并在本地留审计日志。绝不回传隐私。

设计原则：
  - 零依赖（纯标准库），可直接 import。
  - 默认「最小上下文 + 命中即脱敏，敏感文件直接拦」。
  - 一切本地：禁碰清单本地 JSON，审计日志本地 JSONL，不上云。
  - 策略可配，但「拦截」一侧默认从严（宁可少发，不可泄露）。

集成（三处）：
  1) 模型网关发送前：
        msgs, rep = guard_model_messages(messages)
        if rep["blocked"]: return ask_consent_or_refuse(rep)
  2) 文件上传(S3/R2)前：
        dec = guard_file_upload(file_path, file_content)
        if not dec["allowed"]: return {"error": "blocked_by_privacy_guard", "reason": dec["reason"]}
  3) 外部连接器/图像外联前：
        body, rep = guard_outbound_text(body)
"""
import os
import re
import json
import time
import hashlib
from pathlib import Path

# —— 本地存储位置（不上云）——
_BASE = Path(__file__).resolve().parent.parent / "memory"
_BASE.mkdir(parents=True, exist_ok=True)
NEVER_LEAVE_FILE = _BASE / "never_leave.json"     # 用户「禁碰清单」
AUDIT_LOG = _BASE / "privacy_audit.jsonl"          # 本地审计日志


# ============================================================
# 1) 敏感模式（命中即视为机密，必须脱敏或拦截）
# ============================================================
SECRET_PATTERNS = [
    ("openai_key",     re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}\b")),
    ("anthropic_key",  re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,}\b")),
    ("github_token",   re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}\b")),
    ("aws_akid",       re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("google_key",     re.compile(r"\bAIza[0-9A-Za-z_\-]{30,}\b")),
    ("slack_token",    re.compile(r"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b")),
    ("private_key",    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----")),
    ("jwt",            re.compile(r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b")),
    # key=value 形式的口令/密钥（password=..., secret=..., api_key=..., token=...）
    ("kv_secret",      re.compile(r"(?i)\b(pass(?:word)?|secret|api[_\-]?key|access[_\-]?key|token|vapid_private|r2_secret_access_key)\b\s*[:=]\s*['\"]?[^\s'\";]{6,}")),
]

# PII（个人敏感信息，按需脱敏；默认对外发也脱敏）
PII_PATTERNS = [
    ("cn_phone",  re.compile(r"\b1[3-9]\d{9}\b")),
    ("cn_idcard", re.compile(r"\b\d{17}[\dXx]\b")),
    ("bank_card", re.compile(r"\b\d{16,19}\b")),
    ("email",     re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b")),
]

# 敏感文件名/路径标志（这类文件默认禁止外发/上传）
SENSITIVE_PATH_HINTS = [
    ".env", "id_rsa", "id_ed25519", ".pem", ".key", ".pfx", ".p12",
    "vapid_private", "credentials", ".ssh/", ".aws/", "secrets",
    "private_key", "service-account", ".kube/config", "wallet", ".npmrc",
]


# ============================================================
# 2) 禁碰清单（用户标记「永不外发」的路径/仓库/服务器/关键词）
# ============================================================
def _load_never_leave():
    if NEVER_LEAVE_FILE.exists():
        try:
            return json.loads(NEVER_LEAVE_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    # 默认空清单；用户可通过 add_never_leave() 维护
    return {"paths": [], "keywords": [], "repos": [], "hosts": []}


def add_never_leave(kind: str, value: str) -> bool:
    """把某个路径/关键词/仓库/主机加入禁碰清单（本地）。kind ∈ paths|keywords|repos|hosts"""
    d = _load_never_leave()
    if kind not in d:
        return False
    if value not in d[kind]:
        d[kind].append(value)
        NEVER_LEAVE_FILE.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
    return True


# ============================================================
# 3) 扫描 / 脱敏
# ============================================================
def scan(text: str):
    """返回命中列表：[{type, kind, sample}]。kind ∈ secret|pii|never_leave"""
    if not isinstance(text, str) or not text:
        return []
    findings = []
    for name, pat in SECRET_PATTERNS:
        if pat.search(text):
            findings.append({"type": name, "kind": "secret"})
    for name, pat in PII_PATTERNS:
        if pat.search(text):
            findings.append({"type": name, "kind": "pii"})
    nl = _load_never_leave()
    for kw in nl.get("keywords", []):
        if kw and kw in text:
            findings.append({"type": "never_leave_keyword", "kind": "never_leave", "sample": kw})
    return findings


def redact(text: str):
    """把机密替换为 [REDACTED:type]，返回 (脱敏后文本, 命中报告)。"""
    if not isinstance(text, str) or not text:
        return text, []
    report = []
    out = text
    for name, pat in SECRET_PATTERNS:
        out, n = pat.subn(f"[REDACTED:{name}]", out)
        if n:
            report.append({"type": name, "kind": "secret", "count": n})
    for name, pat in PII_PATTERNS:
        out, n = pat.subn(f"[REDACTED:{name}]", out)
        if n:
            report.append({"type": name, "kind": "pii", "count": n})
    nl = _load_never_leave()
    for kw in nl.get("keywords", []):
        if kw and kw in out:
            out = out.replace(kw, "[REDACTED:never_leave]")
            report.append({"type": "never_leave_keyword", "kind": "never_leave", "count": 1})
    return out, report


def is_sensitive_path(path: str) -> bool:
    p = (path or "").lower()
    if any(h in p for h in SENSITIVE_PATH_HINTS):
        return True
    nl = _load_never_leave()
    for marker in nl.get("paths", []):
        if marker and marker.lower() in p:
            return True
    return False


# ============================================================
# 4) 审计（本地 JSONL，append-only）
# ============================================================
def audit(action: str, dest: str, report, extra=None):
    rec = {
        "ts": round(time.time(), 3),
        "action": action,          # redact | block | allow
        "dest": dest,              # model_gateway | s3_upload | connector | image
        "findings": report or [],
        "extra": extra or {},
    }
    try:
        with open(AUDIT_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass
    return rec


# ============================================================
# 5) 对外的护栏入口（集成时调这几个）
# ============================================================
def guard_outbound_text(text: str, dest: str = "connector", block_on_secret: bool = False):
    """
    通用文本出口护栏。默认对密钥/PII 脱敏放行；block_on_secret=True 时命中机密直接拦。
    返回 (处理后文本, 报告dict)
    """
    findings = scan(text)
    has_secret = any(f["kind"] in ("secret", "never_leave") for f in findings)
    if has_secret and block_on_secret:
        audit("block", dest, findings)
        return None, {"blocked": True, "findings": findings}
    clean, rep = redact(text)
    if rep:
        audit("redact", dest, rep)
    return clean, {"blocked": False, "findings": rep}


def guard_model_messages(messages, block_on_secret: bool = False):
    """
    模型网关发送前调用。逐条 message 脱敏（默认脱敏放行，保证模型仍可工作但不含机密）。
    block_on_secret=True 时，发现机密则整体拦截，交由上层走「征求同意」流程。
    返回 (脱敏后 messages, 报告dict)
    """
    all_findings = []
    blocked = False
    out = []
    for m in (messages or []):
        content = m.get("content", "")
        if isinstance(content, str):
            f = scan(content)
            if any(x["kind"] in ("secret", "never_leave") for x in f) and block_on_secret:
                blocked = True
                all_findings.extend(f)
                out.append({**m, "content": "[BLOCKED_BY_PRIVACY_GUARD]"})
                continue
            clean, rep = redact(content)
            all_findings.extend(rep)
            out.append({**m, "content": clean})
        else:
            out.append(m)  # 非纯文本（如多模态）原样保留，由 guard_file_upload 另行把关
    if blocked:
        audit("block", "model_gateway", all_findings)
    elif all_findings:
        audit("redact", "model_gateway", all_findings)
    return out, {"blocked": blocked, "findings": all_findings}


def guard_file_upload(file_path: str, file_content, allow_token: str = None):
    """
    文件上传(S3/R2)前调用。敏感文件默认拦截，除非带显式同意 token。
    返回 {allowed, reason, findings}
    """
    findings = []
    # 1) 路径/文件名判敏
    if is_sensitive_path(file_path):
        findings.append({"type": "sensitive_path", "kind": "secret", "sample": file_path})
    # 2) 内容判敏（文本类才扫）
    text = None
    if isinstance(file_content, (bytes, bytearray)):
        try:
            text = file_content.decode("utf-8", errors="ignore")
        except Exception:
            text = None
    elif isinstance(file_content, str):
        text = file_content
    if text:
        findings.extend(scan(text))

    sensitive = any(f["kind"] in ("secret", "never_leave") for f in findings)
    if sensitive and not _consent_ok(allow_token):
        audit("block", "s3_upload", findings, {"path": file_path})
        return {"allowed": False, "reason": "包含密钥/私密内容，已拦截（需显式同意才能上传）", "findings": findings}

    audit("allow", "s3_upload", findings, {"path": file_path})
    return {"allowed": True, "reason": "ok", "findings": findings}


# ——「显式同意」令牌：一次性，需用户在前端确认后下发——
_CONSENT_SECRET = os.environ.get("BG_CONSENT_SECRET", "")
def make_consent_token(scope: str) -> str:
    """前端用户确认上传后，由后端生成一次性令牌（基于本地密钥，不出网）。"""
    raw = f"{scope}:{int(time.time())//300}:{_CONSENT_SECRET}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]

def _consent_ok(token: str) -> bool:
    if not token or not _CONSENT_SECRET:
        return False
    # 5 分钟窗口内有效
    now = int(time.time()) // 300
    for w in (now, now - 1):
        raw = f"upload:{w}:{_CONSENT_SECRET}"
        if token == hashlib.sha256(raw.encode()).hexdigest()[:32]:
            return True
    return False


# ============================================================
# 自测
# ============================================================
if __name__ == "__main__":
    demo = "我的 key 是 sk-ABCDEFGHIJKLMNOPQRSTUVWX 还有 <GITHUB_TOKEN_ENV>，手机 13800138000"
    clean, rep = redact(demo)
    print("脱敏后:", clean)
    print("报告:", rep)
    print("敏感文件 .env ->", is_sensitive_path("/home/u/.env"))
    print("上传 id_rsa ->", guard_file_upload("/home/u/.ssh/id_rsa", b"-----BEGIN OPENSSH PRIVATE KEY-----\n..."))
