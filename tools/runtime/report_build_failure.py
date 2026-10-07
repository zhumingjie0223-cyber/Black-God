#!/usr/bin/env python3
"""把生成日志中的已知错误转换成有限公开注解，不回显自由文本。"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
MAX_LOG_BYTES = 65536
SCRIPT_NAMES = {"build.py", "prepare_image.py", "bundle.py"}
TOOL_NAMES = {"xcrun", "xcodegen", "meson", "ninja", "clang", "fakefsify", "ish", "pip"}
LOCKED_FILE_PATTERN = re.compile(
    r"(?:alpine-minirootfs-[0-9]+\.[0-9]+\.[0-9]+-aarch64\.tar\.gz|"
    r"(?:libcrypto3|libssl3)-[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+\.apk)\Z"
)


def locked_file_names():
    try:
        lock = json.loads((ROOT / "tools/runtime/image-lock.json").read_text())
        items = [lock["archive"], *lock["packages"]]
        return {item["file"] for item in items
                if isinstance(item.get("file"), str) and LOCKED_FILE_PATTERN.fullmatch(item["file"])}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return set()


def read_log_tail(path):
    with path.open("rb") as handle:
        handle.seek(0, 2)
        handle.seek(max(0, handle.tell() - MAX_LOG_BYTES))
        return handle.read(MAX_LOG_BYTES).decode("utf-8", errors="replace")


def summarize(log, exit_code, locked_files):
    fields = ["退出码=" + str(exit_code)]
    script = None
    tool = None
    http_status = None
    locked_file = None
    error_position = len(log)
    category = "未知生成错误"

    downloads = list(re.finditer(r"(?m)^锁定下载失败：([^\r\n]+)；HTTP ([0-9]{3})$", log))
    http_errors = list(re.finditer(r"(?:HTTPError: HTTP Error|Tunnel connection failed:) ([0-9]{3})\b", log))
    checksum_errors = list(re.finditer(r"ValueError: (Downloaded|Cached) checksum mismatch\b", log))
    exceptions = list(re.finditer(
        r"(?m)^(?:[A-Za-z_][A-Za-z0-9_]*\.)*"
        r"(FileNotFoundError|TimeoutExpired|OperationalError|CalledProcessError|ValueError|RuntimeError|URLError):[^\r\n]*",
        log,
    ))

    if downloads:
        match = downloads[-1]
        category = "锁定文件下载失败"
        script = "prepare_image.py"
        http_status = match[2]
        if match[1] in locked_files:
            locked_file = match[1]
    elif checksum_errors:
        match = checksum_errors[-1]
        category = "下载校验失败" if match[1] == "Downloaded" else "缓存校验失败"
        script = "prepare_image.py"
    elif http_errors:
        match = http_errors[-1]
        category = "下载或代理返回错误"
        http_status = match[1]
        error_position = match.start()
    elif exceptions:
        match = exceptions[-1]
        category = {
            "FileNotFoundError": "构建文件或工具不存在",
            "TimeoutExpired": "构建子进程超时",
            "OperationalError": "镜像数据库操作失败",
            "CalledProcessError": "构建子进程失败",
            "ValueError": "生成数据校验失败",
            "RuntimeError": "资源生成失败",
            "URLError": "下载连接失败",
        }[match[1]]
        error_position = match.start()
        # 工具名只允许固定枚举；参数、路径及异常原文均不输出。
        for name in sorted(TOOL_NAMES):
            if re.search(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", match[0]):
                tool = name
                break
    elif re.search(r"(?m)^.+:[0-9]+:[0-9]+: (?:fatal )?error:", log):
        category = "原生源码编译失败"
        tool = "clang"

    if script is None:
        frames = re.findall(r'File "[^"\n]*[/\\](build\.py|prepare_image\.py|bundle\.py)", line [0-9]+', log[:error_position])
        if frames and frames[-1] in SCRIPT_NAMES:
            script = frames[-1]
    fields.append("类别=" + category)
    if script:
        fields.append("脚本=" + script)
    if tool:
        fields.append("工具=" + tool)
    if http_status:
        fields.append("HTTP=" + http_status)
    if locked_file:
        fields.append("文件=" + locked_file)
    fields.append("详细日志见生成日志附件")
    return "；".join(fields)


def main():
    parser = argparse.ArgumentParser(description="发布有限的工程生成失败诊断")
    parser.add_argument("log", type=Path)
    parser.add_argument("exit_code", type=int)
    args = parser.parse_args()
    if args.exit_code == 0:
        return
    try:
        message = summarize(read_log_tail(args.log), args.exit_code, locked_file_names())
    except OSError:
        message = "退出码=" + str(args.exit_code) + "；类别=生成日志读取失败"
    # 即使字段来自白名单，也按工作流命令协议转义。
    message = message[:400].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print("::error title=工程生成失败::" + message)


if __name__ == "__main__":
    main()
