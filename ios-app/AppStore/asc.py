#!/usr/bin/env python3
"""App Store Connect API 工具 —— 把本目录 metadata/ 里的商店文案一条命令推到 App Store Connect。

零第三方依赖（标准库 + cryptography），可在任何有 Python 3 的机器上跑，不需要 macOS。

凭据一律走环境变量（不要写进仓库、不要贴聊天）：
    ASC_ISSUER_ID        App Store Connect → 用户和访问 → 集成 → Issuer ID
    ASC_KEY_ID           同页 API 密钥的 Key ID（10 位）
    ASC_PRIVATE_KEY      .p8 文件全文（含 BEGIN/END 行；换行可写成字面 \\n）
    ASC_PRIVATE_KEY_PATH 或者给 .p8 文件路径（二选一）

子命令：
    validate                 只做本地字数校验，不联网、不需要凭据
    check                    验证凭据；列出团队 App；查 Bundle ID 是否注册、App 记录是否存在
    register-bundle-id       Bundle ID 未注册则通过 API 注册（App 记录本身 API 不能建，要在网页点一次）
    push-metadata            推送 名称/副标题/隐私链接 + 描述/关键词/推广文本/更新说明/支持链接
                             --dry-run 只打印将要发送的请求；没有凭据时自动进入离线计划模式
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
META = HERE / "metadata"
PROJECT_YML = HERE.parent / "project.yml"
BASE = "https://api.appstoreconnect.apple.com/v1"

# Apple 商店文案字数上限（按字符数计，中英一致）
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotionalText": 170,
    "description": 4000,
    "whatsNew": 4000,
}

# 处于这些状态的版本/信息才允许改文案
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "WAITING_FOR_REVIEW",
    "INVALID_BINARY",
}
LOCKED_STATES = {"READY_FOR_SALE", "REPLACED_WITH_NEW_INFO", "REMOVED_FROM_SALE"}

# 本目录文件名 → App Store Connect 字段名
INFO_FIELDS = {"name.txt": "name", "subtitle.txt": "subtitle"}
VERSION_FIELDS = {
    "description.txt": "description",
    "keywords.txt": "keywords",
    "promotional_text.txt": "promotionalText",
    "release_notes.txt": "whatsNew",
}


class ASCError(RuntimeError):
    pass


# ───────────────────────── 本地材料 ─────────────────────────

def read_text(path: Path) -> str | None:
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8").rstrip("\n")


def read_project() -> dict:
    text = PROJECT_YML.read_text(encoding="utf-8")
    bundle = re.search(r"PRODUCT_BUNDLE_IDENTIFIER:\s*([\w.\-]+)", text)
    version = re.search(r'MARKETING_VERSION:\s*"?([\d.]+)"?', text)
    if not bundle or not version:
        raise ASCError(f"在 {PROJECT_YML} 里找不到 PRODUCT_BUNDLE_IDENTIFIER / MARKETING_VERSION")
    return {"bundle_id": bundle.group(1), "version": version.group(1)}


def list_locales() -> list[str]:
    return sorted(p.name for p in META.iterdir() if p.is_dir() and (p / "name.txt").exists())


def load_locale(locale: str) -> tuple[dict, dict]:
    """返回 (appInfoLocalization 字段, appStoreVersionLocalization 字段)。"""
    d = META / locale
    info = {field: read_text(d / fn) for fn, field in INFO_FIELDS.items()}
    version = {field: read_text(d / fn) for fn, field in VERSION_FIELDS.items()}
    privacy = read_text(META / "privacy_url.txt")
    support = read_text(META / "support_url.txt")
    if privacy:
        info["privacyPolicyUrl"] = privacy
    if support:
        version["supportUrl"] = support
    info = {k: v for k, v in info.items() if v}
    version = {k: v for k, v in version.items() if v}
    return info, version


def validate_locale(locale: str, info: dict, version: dict) -> list[str]:
    problems = []
    for field in ("name", "subtitle"):
        if field not in info:
            problems.append(f"[{locale}] 缺 {field}")
    for field in ("description", "keywords"):
        if field not in version:
            problems.append(f"[{locale}] 缺 {field}")
    for field, value in {**info, **version}.items():
        limit = LIMITS.get(field)
        if limit and len(value) > limit:
            problems.append(f"[{locale}] {field} 超长：{len(value)} > {limit}")
    return problems


def cmd_validate(_args) -> int:
    project = read_project()
    print(f"Bundle ID: {project['bundle_id']}    版本: {project['version']}")
    total = 0
    for locale in list_locales():
        info, version = load_locale(locale)
        problems = validate_locale(locale, info, version)
        total += len(problems)
        print(f"\n[{locale}]")
        for field, value in {**info, **version}.items():
            limit = LIMITS.get(field)
            mark = f"{len(value)}/{limit}" if limit else "—"
            preview = value.replace("\n", " ")[:48]
            print(f"  {field:<16} {mark:>9}  {preview}{'…' if len(value) > 48 else ''}")
        for p in problems:
            print("  ✗ " + p)
    print("\n" + ("✓ 本地文案全部在 Apple 字数上限内" if not total else f"✗ 共 {total} 处问题，先修再推"))
    return 0 if not total else 1


# ───────────────────────── API 客户端 ─────────────────────────

def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def load_credentials() -> dict | None:
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    pem = os.environ.get("ASC_PRIVATE_KEY", "")
    path = os.environ.get("ASC_PRIVATE_KEY_PATH", "").strip()
    if not pem and path:
        pem = Path(path).read_text(encoding="utf-8")
    pem = pem.replace("\\n", "\n").strip()
    if not (issuer and key_id and pem):
        return None
    return {"issuer": issuer, "key_id": key_id, "pem": pem}


class ASC:
    def __init__(self, creds: dict, dry_run: bool = False):
        self.creds = creds
        self.dry_run = dry_run
        self._token = None
        self._token_exp = 0

    # Apple 要 ES256，签名必须是 64 字节的 r||s 拼接，不是 DER
    def token(self) -> str:
        now = int(time.time())
        if self._token and now < self._token_exp - 60:
            return self._token
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

        key = serialization.load_pem_private_key(self.creds["pem"].encode(), password=None)
        header = {"alg": "ES256", "kid": self.creds["key_id"], "typ": "JWT"}
        payload = {"iss": self.creds["issuer"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
        signing_input = f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}." \
                        f"{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
        r, s = decode_dss_signature(key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
        sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        self._token = f"{signing_input}.{_b64url(sig)}"
        self._token_exp = now + 1200
        return self._token

    def request(self, method: str, path: str, body: dict | None = None, params: dict | None = None):
        url = path if path.startswith("http") else BASE + path
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        if self.dry_run and method != "GET":
            print(f"  [dry-run] {method} {url}")
            if body:
                print("           " + json.dumps(body, ensure_ascii=False)[:600])
            return None
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raw = e.read().decode(errors="replace")
            try:
                errs = json.loads(raw).get("errors", [])
                detail = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errs) or raw
            except Exception:
                detail = raw
            raise ASCError(f"{method} {path} → HTTP {e.code}: {detail}") from None

    def get(self, path, **params):
        return self.request("GET", path, params=params or None)

    def post(self, path, body):
        return self.request("POST", path, body)

    def patch(self, path, body):
        return self.request("PATCH", path, body)

    # ── 资源查询 ──

    def find_app(self, bundle_id: str) -> dict | None:
        items = self.get("/apps", **{"filter[bundleId]": bundle_id}).get("data", [])
        return items[0] if items else None

    def find_bundle_id(self, identifier: str) -> dict | None:
        items = self.get("/bundleIds", **{"filter[identifier]": identifier}).get("data", [])
        return next((i for i in items if i["attributes"]["identifier"] == identifier), None)

    def editable_app_info(self, app_id: str) -> dict | None:
        infos = self.get(f"/apps/{app_id}/appInfos").get("data", [])
        for i in infos:
            if i["attributes"].get("appStoreState") in EDITABLE_STATES:
                return i
        for i in infos:
            if i["attributes"].get("appStoreState") not in LOCKED_STATES:
                return i
        return infos[0] if infos else None

    def editable_version(self, app_id: str) -> dict | None:
        versions = self.get(f"/apps/{app_id}/appStoreVersions",
                            **{"filter[platform]": "IOS", "limit": 200}).get("data", [])
        for v in versions:
            a = v["attributes"]
            state = a.get("appVersionState") or a.get("appStoreState")
            if state in EDITABLE_STATES:
                return v
        return None

    def localizations(self, path: str) -> dict[str, dict]:
        items = self.get(path, limit=200).get("data", [])
        return {i["attributes"]["locale"]: i for i in items}


# ───────────────────────── 子命令 ─────────────────────────

def need_client(args) -> ASC:
    creds = load_credentials()
    if not creds:
        raise ASCError("没有找到凭据。请设置环境变量 ASC_ISSUER_ID / ASC_KEY_ID / ASC_PRIVATE_KEY（或 ASC_PRIVATE_KEY_PATH）。"
                       "云端请放到 Cursor 面板 → Cloud Agents → Secrets，不要贴进聊天。")
    return ASC(creds, dry_run=getattr(args, "dry_run", False))


def cmd_token(args) -> int:
    print(need_client(args).token())
    return 0


def cmd_check(args) -> int:
    client = need_client(args)
    project = read_project()
    bundle_id = project["bundle_id"]

    apps = client.get("/apps", limit=200).get("data", [])
    print(f"✓ 凭据有效，团队下共 {len(apps)} 个 App")
    for a in apps:
        at = a["attributes"]
        print(f"    - {at.get('name')}  ({at.get('bundleId')})  sku={at.get('sku')}")

    bid = client.find_bundle_id(bundle_id)
    print(f"{'✓' if bid else '✗'} Bundle ID {bundle_id} {'已注册' if bid else '未注册 → 跑 register-bundle-id'}")

    app = client.find_app(bundle_id)
    if app:
        print(f"✓ App 记录已存在：{app['attributes']['name']}（id={app['id']}）")
        v = client.editable_version(app["id"])
        print(f"{'✓' if v else '⚠'} 可编辑版本：{v['attributes']['versionString'] if v else '无（push-metadata 会按 project.yml 新建 ' + project['version'] + '）'}")
    else:
        print(f"✗ 还没有 App 记录。App Store Connect API 不支持新建 App，需在网页点一次：\n"
              f"    appstoreconnect.apple.com → 我的 App → ＋ → 新建 App（平台 iOS，套装 ID 选 {bundle_id}，"
              f"SKU 例如 blackgod-nexus-ios，主要语言 简体中文）。建好后再跑 push-metadata。")
    return 0


def cmd_register_bundle_id(args) -> int:
    client = need_client(args)
    bundle_id = read_project()["bundle_id"]
    if client.find_bundle_id(bundle_id):
        print(f"✓ Bundle ID {bundle_id} 已注册，无需操作")
        return 0
    body = {"data": {"type": "bundleIds", "attributes": {
        "identifier": bundle_id, "name": args.name, "platform": "IOS"}}}
    resp = client.post("/bundleIds", body)
    if resp is None:
        return 0
    print(f"✓ 已注册 Bundle ID {bundle_id}（id={resp['data']['id']}）")
    return 0


def _upsert_localization(client: ASC, existing: dict[str, dict], collection: str,
                         parent_type: str, parent_id: str, locale: str, attrs: dict) -> None:
    if locale in existing:
        loc_id = existing[locale]["id"]
        client.patch(f"/{collection}/{loc_id}", {"data": {"type": collection, "id": loc_id, "attributes": attrs}})
        print(f"  ✓ [{locale}] 已更新 {collection}：{', '.join(attrs)}")
    else:
        body = {"data": {"type": collection, "attributes": {"locale": locale, **attrs},
                         "relationships": {parent_type: {"data": {"type": parent_type + "s", "id": parent_id}}}}}
        client.post(f"/{collection}", body)
        print(f"  ✓ [{locale}] 已新建 {collection}：{', '.join(attrs)}")


def cmd_push_metadata(args) -> int:
    project = read_project()
    locales = args.locales.split(",") if args.locales else list_locales()

    # 先本地校验，任何一处超长都不发
    payloads = {}
    problems = []
    for locale in locales:
        info, version = load_locale(locale)
        problems += validate_locale(locale, info, version)
        payloads[locale] = (info, version)
    if problems:
        print("\n".join("✗ " + p for p in problems))
        return 1
    print(f"✓ 本地文案校验通过：{', '.join(locales)}")

    creds = load_credentials()
    if not creds:
        print("\n⚠ 未配置凭据，进入离线计划模式：以下是将要推送的内容（不联网）\n")
        for locale, (info, version) in payloads.items():
            print(f"[{locale}] appInfoLocalization ← {json.dumps(info, ensure_ascii=False)[:300]}")
            print(f"[{locale}] appStoreVersionLocalization ← 字段 {list(version)}")
        return 0

    client = ASC(creds, dry_run=args.dry_run)
    app = client.find_app(project["bundle_id"])
    if not app:
        raise ASCError(f"App Store Connect 里还没有 {project['bundle_id']} 的 App 记录，先在网页新建 App（见 check 的提示）")
    app_id = app["id"]
    print(f"✓ 目标 App：{app['attributes']['name']}（id={app_id}）")

    # ① App 信息层：名称 / 副标题 / 隐私政策链接
    info_obj = client.editable_app_info(app_id)
    if not info_obj:
        raise ASCError("拿不到 appInfo，App 记录可能刚建还没初始化，稍后重试")
    existing_info = client.localizations(f"/appInfos/{info_obj['id']}/appInfoLocalizations")
    print("\n① App 信息（名称/副标题/隐私链接）")
    for locale, (info, _) in payloads.items():
        _upsert_localization(client, existing_info, "appInfoLocalizations", "appInfo", info_obj["id"], locale, info)

    # ② 版本层：描述 / 关键词 / 推广文本 / 更新说明 / 支持链接
    version_obj = client.editable_version(app_id)
    if not version_obj:
        body = {"data": {"type": "appStoreVersions",
                         "attributes": {"platform": "IOS", "versionString": project["version"]},
                         "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
        resp = client.post("/appStoreVersions", body)
        if resp is None:
            print(f"\n② 版本层：将新建版本 {project['version']} 后再写文案（dry-run 到此为止）")
            return 0
        version_obj = resp["data"]
        print(f"\n✓ 已新建版本 {project['version']}")
    ver_id = version_obj["id"]
    print(f"\n② 版本 {version_obj['attributes']['versionString']}（描述/关键词/推广文本/更新说明/支持链接）")
    existing_ver = client.localizations(f"/appStoreVersions/{ver_id}/appStoreVersionLocalizations")
    for locale, (_, version) in payloads.items():
        try:
            _upsert_localization(client, existing_ver, "appStoreVersionLocalizations", "appStoreVersion", ver_id, locale, version)
        except ASCError as e:
            # 首个版本 Apple 不允许填“此版本的新增内容”，去掉后重试
            if "whatsNew" in str(e) and "whatsNew" in version:
                retry = {k: v for k, v in version.items() if k != "whatsNew"}
                _upsert_localization(client, existing_ver, "appStoreVersionLocalizations", "appStoreVersion", ver_id, locale, retry)
                print(f"    ⚠ [{locale}] 首个版本不能填更新说明（whatsNew），已跳过该字段")
            else:
                raise

    print("\n✓ 文案推送完成。仍需在网页手工完成：截图上传、类别、年龄分级问卷、App 隐私问卷、定价/销售范围、选择构建版本、审核备注。"
          "\n  （这些 API 要么不开放，要么需要人来做判断，见 SUBMIT_GUIDE.md 第 4/6/7 步。）")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="App Store Connect 上架自动化（神枢 Black God）")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate", help="仅本地字数校验").set_defaults(fn=cmd_validate)
    sub.add_parser("token", help="打印一枚 JWT（调试用）").set_defaults(fn=cmd_token)
    sub.add_parser("check", help="验证凭据、查 Bundle ID / App 记录").set_defaults(fn=cmd_check)
    r = sub.add_parser("register-bundle-id", help="注册 Bundle ID")
    r.add_argument("--name", default="Black God Nexus", help="Bundle ID 在开发者后台显示的名称")
    r.set_defaults(fn=cmd_register_bundle_id)
    m = sub.add_parser("push-metadata", help="推送商店文案")
    m.add_argument("--dry-run", action="store_true", help="只打印将发送的写请求")
    m.add_argument("--locales", help="逗号分隔，默认 metadata/ 下全部语言目录")
    m.set_defaults(fn=cmd_push_metadata)
    args = p.parse_args(argv)
    try:
        return args.fn(args)
    except ASCError as e:
        print(f"✗ {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
