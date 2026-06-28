#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
动态监测 — Black God 888
实时监控：服务状态、资源占用、异常检测、自动告警

监控对象：
- 后台服务（Agent/网关/数据库）
- 系统资源（CPU/内存/磁盘/网络）
- 安全事件（异常登录/攻击尝试）
- 业务指标（对话量/任务成功率）
"""
import json
import subprocess
import time
from pathlib import Path
from datetime import datetime


class Monitor:
    """动态监测：全方位监控 + 自动告警"""

    def __init__(self, alert_callback=None):
        self.alert_callback = alert_callback
        self.metrics_history = []
        self.alert_log = Path("/tmp/bg88_alerts.log")

    def check_services(self) -> dict:
        """检查后台服务状态"""
        services = {
            "bg-agent": self._check_systemd("bg-agent"),
            "bg-gateway": self._check_systemd("bg-gateway"),
            "nginx": self._check_systemd("nginx"),
        }
        # 检查端口监听
        ports = {
            8765: self._check_port(8765),  # Agent
            9000: self._check_port(9000),  # Gateway
            80: self._check_port(80),      # Nginx
        }
        return {"services": services, "ports": ports}

    def _check_systemd(self, name: str) -> dict:
        """检查 systemd 服务"""
        try:
            r = subprocess.run(["systemctl", "is-active", name],
                             capture_output=True, text=True, timeout=5)
            active = r.stdout.strip() == "active"
            return {"status": "running" if active else "stopped", "active": active}
        except Exception:
            return {"status": "unknown", "active": False}

    def _check_port(self, port: int) -> bool:
        """检查端口是否监听"""
        try:
            r = subprocess.run(["lsof", "-i", f":{port}"],
                             capture_output=True, timeout=5)
            return r.returncode == 0
        except Exception:
            return False

    def check_resources(self) -> dict:
        """检查系统资源（不依赖psutil，用shell命令）"""
        # CPU使用率
        try:
            r = subprocess.run(["sh", "-c", "top -bn1 | grep 'CPU:' | awk '{print $2}' | sed 's/%//'"],
                             capture_output=True, text=True, timeout=5)
            cpu = float(r.stdout.strip() or 0)
        except Exception:
            cpu = 0.0
        
        # 内存
        try:
            r = subprocess.run(["free", "-m"], capture_output=True, text=True, timeout=5)
            lines = r.stdout.strip().split('\n')
            mem_line = [l for l in lines if 'Mem:' in l][0].split()
            mem_total = float(mem_line[1])
            mem_used = float(mem_line[2])
            mem_percent = (mem_used / mem_total) * 100 if mem_total > 0 else 0
        except Exception:
            mem_total = mem_used = mem_percent = 0
        
        # 磁盘
        try:
            r = subprocess.run(["df", "/"], capture_output=True, text=True, timeout=5)
            lines = r.stdout.strip().split('\n')
            disk_line = lines[1].split()
            disk_total = float(disk_line[1]) / 1024  # KB to MB
            disk_used = float(disk_line[2]) / 1024
            disk_percent = float(disk_line[4].replace('%', ''))
        except Exception:
            disk_total = disk_used = disk_percent = 0
        
        return {
            "cpu": {"percent": cpu, "alert": cpu > 80},
            "memory": {
                "percent": mem_percent,
                "used_mb": mem_used,
                "total_mb": mem_total,
                "alert": mem_percent > 85
            },
            "disk": {
                "percent": disk_percent,
                "used_gb": disk_used / 1024,
                "total_gb": disk_total / 1024,
                "alert": disk_percent > 90
            },
            "timestamp": time.time()
        }

    def check_security(self) -> dict:
        """安全监测：异常登录/攻击尝试"""
        alerts = []
        
        # 检查失败登录（暴力破解）
        try:
            r = subprocess.run(["grep", "Failed password", "/var/log/auth.log"],
                             capture_output=True, text=True, timeout=5)
            failed_logins = len(r.stdout.strip().split('\n')) if r.stdout else 0
            if failed_logins > 10:
                alerts.append(f"暴力破解尝试: {failed_logins}次失败登录")
        except Exception:
            pass

        # 检查异常端口扫描
        try:
            r = subprocess.run(["netstat", "-an"], capture_output=True, text=True, timeout=5)
            syn_count = r.stdout.count("SYN_RECV")
            if syn_count > 50:
                alerts.append(f"可能的端口扫描: {syn_count}个SYN_RECV连接")
        except Exception:
            pass

        return {"alerts": alerts, "safe": len(alerts) == 0}

    def check_business(self) -> dict:
        """业务指标监测（从数据库/日志读取）"""
        # 预留：从 Agent 数据库读取业务指标
        return {
            "total_conversations": 0,  # TODO: 从DB读
            "success_rate": 0.0,
            "avg_response_time": 0.0,
            "error_count_24h": 0
        }

    def full_check(self) -> dict:
        """全面检查"""
        result = {
            "timestamp": datetime.now().isoformat(),
            "services": self.check_services(),
            "resources": self.check_resources(),
            "security": self.check_security(),
            "business": self.check_business(),
        }
        
        # 收集所有告警
        alerts = []
        if result["resources"]["cpu"]["alert"]:
            alerts.append(f"CPU高负载: {result['resources']['cpu']['percent']:.1f}%")
        if result["resources"]["memory"]["alert"]:
            alerts.append(f"内存告警: {result['resources']['memory']['percent']:.1f}%")
        if result["resources"]["disk"]["alert"]:
            alerts.append(f"磁盘告警: {result['resources']['disk']['percent']:.1f}%")
        alerts.extend(result["security"]["alerts"])
        
        result["alerts"] = alerts
        result["healthy"] = len(alerts) == 0
        
        # 记录历史
        self.metrics_history.append(result)
        if len(self.metrics_history) > 100:
            self.metrics_history.pop(0)
        
        # 触发告警
        if alerts and self.alert_callback:
            self.alert_callback(alerts)
        
        # 记录日志
        if alerts:
            self._log_alert(alerts)
        
        return result

    def _log_alert(self, alerts):
        """记录告警日志"""
        try:
            with self.alert_log.open("a") as f:
                ts = datetime.now().isoformat()
                for a in alerts:
                    f.write(f"[{ts}] {a}\n")
        except Exception:
            pass

    def watch(self, interval=60, duration=None):
        """持续监控（守护模式）"""
        start = time.time()
        while True:
            result = self.full_check()
            print(f"[{result['timestamp']}] 健康: {result['healthy']}")
            if result['alerts']:
                print(f"  ⚠️ {len(result['alerts'])} 个告警")
                for a in result['alerts']:
                    print(f"    - {a}")
            
            if duration and (time.time() - start) > duration:
                break
            
            time.sleep(interval)


def monitor_tool(args, **kw):
    """Agent工具：monitor() 返回当前状态"""
    mon = Monitor()
    r = mon.full_check()
    if r["healthy"]:
        return f"✅ 系统健康 | CPU {r['resources']['cpu']['percent']:.1f}% | 内存 {r['resources']['memory']['percent']:.1f}%"
    return f"⚠️ {len(r['alerts'])}个告警: " + "; ".join(r['alerts'][:3])
