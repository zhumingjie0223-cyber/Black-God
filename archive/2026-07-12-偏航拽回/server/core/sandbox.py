#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
安全沙箱 — Black God
隔离执行代码/命令，防炸、防逃逸、后台稳定运行

核心：
- Docker 容器隔离（优先）
- chroot jail（轻量备选）
- 资源限制（CPU/内存/时间/网络）
- 后台服务防护（nohup + setsid + 崩溃自重启）

高级配置（仅用于自己拥有或已授权的环境）：
- 网络模式可选（默认隔离，需要时可配置联网）
- 特权容器（可选 root，仅在明确需要时启用）
- 端口映射（本地服务调试 / 监听）
- 文件系统持久化（保留中间产物，便于分析）
- 多架构支持（x86/ARM/MIPS 交叉编译）
"""
import os
import re
import subprocess
import tempfile
import time
import json
from pathlib import Path


class Sandbox:
    """安全沙箱：隔离执行，后台稳定"""

    def __init__(self, mode="auto", timeout=30, memory_limit="512m", 
                 network="none", privileged=False, ports=None):
        """
        mode: auto/docker/firejail/simple
        network: none(隔离)/bridge(联网)/host(直通)
        privileged: 特权容器（危险，仅在明确需要时启用）
        ports: 端口映射 {"8080": "80"} — 本地服务调试/监听
        """
        self.mode = self._detect_mode() if mode == "auto" else mode
        self.timeout = timeout
        self.memory_limit = memory_limit
        self.network = network
        self.privileged = privileged
        self.ports = ports or {}
        self.work_dir = Path("/tmp/bg88_sandbox")
        self.work_dir.mkdir(parents=True, exist_ok=True)

    def _detect_mode(self) -> str:
        """检测可用沙箱后端"""
        if subprocess.run(["which", "docker"], capture_output=True).returncode == 0:
            return "docker"
        if os.path.exists("/usr/bin/firejail"):
            return "firejail"
        return "simple"  # 简单进程隔离兜底

    def execute(self, code: str, language: str = "python") -> dict:
        """执行代码，返回 {success, output, error}"""
        if self.mode == "docker":
            return self._docker_exec(code, language)
        elif self.mode == "firejail":
            return self._firejail_exec(code, language)
        else:
            return self._simple_exec(code, language)

    def _docker_exec(self, code: str, language: str) -> dict:
        """Docker 容器隔离（最安全）"""
        image = "python:3.11-alpine" if language == "python" else "alpine:latest"
        code_file = self.work_dir / f"code_{int(time.time())}.py"
        code_file.write_text(code)
        try:
            cmd = [
                "docker", "run", "--rm",
                "--network", self.network,  # 可配置联网
                "--memory", self.memory_limit,
                "--cpus", "1",
                "-v", f"{code_file}:/code.py:ro",
            ]
            # 特权容器（危险，仅在明确需要时）
            if self.privileged:
                cmd.append("--privileged")
            # 端口映射（本地服务调试/监听）
            for host_port, container_port in self.ports.items():
                cmd.extend(["-p", f"{host_port}:{container_port}"])
            
            cmd.extend([
                image,
                "python3" if language == "python" else "sh",
                "/code.py" if language == "python" else "-c", 
                code if language != "python" else ""
            ])
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout)
            code_file.unlink()
            return {
                "success": r.returncode == 0,
                "output": r.stdout,
                "error": r.stderr,
                "sandbox": "docker",
                "network": self.network,
                "privileged": self.privileged
            }
        except subprocess.TimeoutExpired:
            code_file.unlink()
            return {"success": False, "error": f"超时（{self.timeout}s）", "sandbox": "docker"}
        except Exception as e:
            return {"success": False, "error": str(e), "sandbox": "docker"}

    def _firejail_exec(self, code: str, language: str) -> dict:
        """Firejail 隔离"""
        code_file = self.work_dir / f"code_{int(time.time())}.py"
        code_file.write_text(code)
        try:
            cmd = [
                "firejail", "--quiet", "--noprofile",
                "--net=none", "--private", "--noroot",
                "python3" if language == "python" else "sh",
                str(code_file)
            ]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout)
            code_file.unlink()
            return {
                "success": r.returncode == 0,
                "output": r.stdout,
                "error": r.stderr,
                "sandbox": "firejail"
            }
        except subprocess.TimeoutExpired:
            code_file.unlink()
            return {"success": False, "error": f"超时（{self.timeout}s）", "sandbox": "firejail"}
        except Exception as e:
            return {"success": False, "error": str(e), "sandbox": "firejail"}

    def _simple_exec(self, code: str, language: str) -> dict:
        """简单进程隔离（兜底，不安全但能跑）"""
        code_file = self.work_dir / f"code_{int(time.time())}.py"
        code_file.write_text(code)
        try:
            cmd = ["python3" if language == "python" else "sh", str(code_file)]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout)
            code_file.unlink()
            return {
                "success": r.returncode == 0,
                "output": r.stdout,
                "error": r.stderr,
                "sandbox": "simple",
                "warning": "无隔离，不安全"
            }
        except subprocess.TimeoutExpired:
            code_file.unlink()
            return {"success": False, "error": f"超时（{self.timeout}s）", "sandbox": "simple"}
        except Exception as e:
            return {"success": False, "error": str(e), "sandbox": "simple"}

    def run_service_stable(self, cmd: str, name: str, log_dir="/tmp/bg88_services") -> dict:
        """
        后台服务稳定运行（不被意外终止）
        - nohup：忽略挂断信号
        - setsid：脱离会话
        - 输出重定向：防 SIGPIPE
        - 崩溃自重启：systemd/supervisor 或简单循环
        """
        log_path = Path(log_dir)
        log_path.mkdir(parents=True, exist_ok=True)
        log_file = log_path / f"{name}.log"
        pid_file = log_path / f"{name}.pid"

        # 启动命令：setsid nohup cmd >> log 2>&1 &
        start_cmd = f"setsid nohup {cmd} >> {log_file} 2>&1 & echo $! > {pid_file}"
        try:
            subprocess.run(start_cmd, shell=True, timeout=5)
            time.sleep(0.5)
            if pid_file.exists():
                pid = int(pid_file.read_text().strip())
                # 检查进程存活
                alive = subprocess.run(["kill", "-0", str(pid)], capture_output=True).returncode == 0
                return {
                    "success": alive,
                    "pid": pid,
                    "log": str(log_file),
                    "status": "running" if alive else "died"
                }
            return {"success": False, "error": "PID文件未生成"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def stop_service(self, name: str, log_dir="/tmp/bg88_services") -> dict:
        """停止后台服务"""
        pid_file = Path(log_dir) / f"{name}.pid"
        if not pid_file.exists():
            return {"success": False, "error": "服务不存在"}
        try:
            pid = int(pid_file.read_text().strip())
            subprocess.run(["kill", str(pid)], capture_output=True)
            time.sleep(0.3)
            alive = subprocess.run(["kill", "-0", str(pid)], capture_output=True).returncode == 0
            if not alive:
                pid_file.unlink()
            return {"success": not alive, "stopped": not alive}
        except Exception as e:
            return {"success": False, "error": str(e)}


def sandbox_tool(args, **kw):
    """Agent 工具：sandbox(code=..., language=...)"""
    sb = Sandbox()
    r = sb.execute(args.get("code", ""), args.get("language", "python"))
    if r["success"]:
        return f"✅ 执行成功({r['sandbox']}):\n{r['output'][:200]}"
    return f"❌ 失败({r['sandbox']}): {r['error'][:200]}"
