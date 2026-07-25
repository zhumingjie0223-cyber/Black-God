# 吾爱破解红队攻击能力库·总索引

采集日期：2026-07-24  
来源：https://www.52pojie.cn  
爱盘工具库：https://down.52pojie.cn/Tools/

---

## 📚 学习资源

### [安卓逆向0基础入门教程_导航.md](./安卓逆向0基础入门教程_导航.md)
- **@正己《安卓逆向这档事》** 26课（2022-2025持续更新）
  - 基础：APK结构/smali/vip破解/广告静默/动态调试
  - Hook：Xposed模块开发/签名校验对抗/密码学/算法自吐
  - IDA：SO逆向/Native分析
  - Frida：完整四部曲（上中下终）+ RPC + 反检测
  - 抓包：三部曲（上中下）+ SSL Pinning绕过
  - Unidbg：黑盒模拟执行三部曲（补环境上中下）
  - Flutter逆向实战

- **@会飞的丑小鸭《教我兄弟学逆向》** 19课（2017持续更新）
  - APK破解/游戏修改/动态调试/Log插桩
  - SO破解：IDA动态调试/签名爆破/反调试对抗
  - OLLVM混淆环境搭建
  - Xposed改机开发三部曲

- **@qtfreet00《吾爱破解安卓逆向入门》** 7课经典（2015）
  - 环境配置/Dalvik字节码/Smali深入/函数分析/实战

---

## 🛠️ 工具库（来自爱盘 https://down.52pojie.cn/Tools/）

### [工具库_Packers加壳_商业破解版.md](./工具库_Packers加壳_商业破解版.md)
**859.7 MB，25款顶级商业壳破解版**

#### 免杀核心（代码虚拟化）
- **Themida** v3.2.4.52 x32/x64 Retail Licensed（最强壳，$999+）
- **Code Virtualizer** v3.2.3.0 x32/x64 Retail Licensed（Oreans虚拟化引擎）
- **WinLicense** v3.1.9.0 x32/x64 Cracked by 52pojie.cn（授权+HWID绑定）
- **Enigma Protector** v7.40（虚拟文件系统，内存加载DLL）

#### 快速免杀
- **Obsidium** v1.6.9 Company License（轻量级加壳）
- **UPX** v5.2.0（开源压缩壳）
- **ASPack** / **PECompact** / **ZProtect**

#### 红队应用
```
快速免杀：UPX → ASPack 二次加壳
中度免杀：Obsidium + Enigma虚拟文件系统
重度免杀：Code Virtualizer虚拟化关键函数 → Themida整体加壳 → WinLicense授权绑定
```

---

### [工具库_Unpackers脱壳.md](./工具库_Unpackers脱壳.md)
**86.5 MB，20款脱壳工具**

#### Python逆向（红队必备）
- **pyinstxtractor-ng** 7.4 MB（2026-06最新，PyInstaller打包exe脱壳提取pyc）
- **unlicense** py3.11 44 MB（移除Python授权验证）

#### 通用脱壳
- **Universal Extractor** 14.5 MB（支持几十种打包格式）
- **Armageddon** v2.3（自动检测加壳类型）
- **AutoEye** v2.0（智能脱壳）

#### 安装包解包
- **InnoExtractor** v11.3（Inno Setup提取器，Windows软件常用）
- **lessmsi** v2.12.9（MSI安装包解包）

#### 专用壳
- ASPack / ASProtect / Enigma / Molebox / Obsidium / UPX 对应脱壳器

#### 红队应用
- 恶意软件分析：脱壳后静态分析payload
- Python免杀马分析：pyinstxtractor-ng脱PyInstaller打包的exe
- 捆绑分析：解包安装程序查找夹带的恶意模块

---

### [工具库_Debuggers+Anti_Rootkit.md](./工具库_Debuggers+Anti_Rootkit.md)

#### Debuggers 调试器（208 MB，11款）

**用户态调试器**
- **x64dbg** 2026-05（30.1 MB）- 开源现代调试器，插件丰富，红队必备
- **OllyDbg 吾爱专用版**（12.3 MB）- 经典逆向神器，集成常用插件
- **OllyICE** 1.10（5.2 MB）- 增强版，集成反反调试
- **WinDbg** v10.0.26100 X64/X86（微软官方内核调试器，驱动分析/蓝屏分析）

**专用工具**
- **Cheat Engine** v7.7（33.1 MB）- 内存扫描/修改/注入
- **API Monitor** v2r13（8.1 MB）- 实时监控进程API调用

**红队应用**
- 恶意软件分析：x64dbg动态跟踪payload解密
- 漏洞利用：WinDbg内核调试，x64dbg构造ROP链
- 进程注入：Cheat Engine定位函数地址，API Monitor找注入点
- 免杀调试：x64dbg + OllyICE反反调试

---

#### Anti_Rootkit 工具（485.6 MB，25款）

**国产顶级ARK**
- **火绒剑 KswordARK** 5.1.2.2 R0（16 MB，2026-07最新）- 驱动级检测
- **PCHunter** v1.6（2.7 MB，2026-06）- 功能最全ARK，SSDT/IDT/回调/进程/注册表
- **OpenArk** v2.0.0（19.5 MB）- 开源ARK，持续更新

**微软官方Sysinternals（红队必备）**
- **Sysinternals Suite** 完整套装（184.1 MB）包含70+工具：
  - **Process Explorer** - 进程树/DLL查看
  - **Process Monitor** - 实时监控文件/注册表/网络/进程
  - **Autoruns** - 启动项管理（杀持久化必备）
  - **PsExec** - 远程执行（红队横向移动）
  - **Sysmon** - 系统监控驱动（EDR核心）

**经典ARK**
- **System Informer** v3.2（原Process Hacker）- 比Process Explorer更强
- **GMER** - Rootkit检测，驱动级扫描
- **XueTr 吾爱专版** - 经典国产ARK

**红队应用**
- **权限提升后隐藏**：PCHunter删除进程在任务管理器中的显示，清理内核回调
- **持久化检测**：Autoruns查找所有自启动项（注册表/服务/计划任务/驱动）
- **横向移动**：PsExec远程执行，Process Explorer找隐藏进程
- **Rootkit对抗**：GMER扫描SSDT/IDT Hook，PCHunter手动恢复被Hook函数
- **EDR绕过研究**：分析Sysmon配置，构造免检测行为

---

## 🎯 红队攻击能力矩阵

### 1. 免杀Payload生成
```
工具链：
Payload源码 
  → Code Virtualizer（虚拟化关键函数，IDA无法反编译）
  → Themida（整体加壳+反调试+反虚拟机）
  → WinLicense（HWID绑定，只能在指定机器运行）
  → 数字签名伪造
```

### 2. Python恶意脚本打包与分析
```
打包：PyInstaller + UPX压缩 + 图标伪装
脱壳分析：pyinstxtractor-ng提取pyc → uncompyle6反编译
```

### 3. 恶意软件动态分析
```
沙箱：x64dbg + Process Monitor（行为监控）
API追踪：API Monitor记录所有API调用
内存dump：Cheat Engine扫描进程内存
```

### 4. 权限提升与隐藏
```
提权后：
  - PCHunter删除进程显示，隐藏驱动
  - 火绒剑清理内核回调（PsSetCreateProcessNotifyRoutine）
验证隐藏效果：Process Monitor + GMER扫描
```

### 5. 持久化
```
植入：
  - 注册表Run键
  - 服务/驱动自启动
  - 计划任务
  - WMI事件订阅
检测清理：Autoruns（杀持久化必备）
```

### 6. 横向移动
```
工具：PsExec（Sysinternals，被EDR白名单信任）
后门清理：Process Explorer找隐藏进程，TCPView查异常连接
```

### 7. Rootkit开发与对抗
```
开发：
  - 学习资源：《Windows内核安全与驱动开发》+《Rootkit Arsenal》
  - 调试：WinDbg内核调试
对抗：
  - GMER扫描SSDT/IDT/IRP Hook
  - PCHunter手动恢复被Hook的内核函数
```

### 8. 内存马检测
```
无文件恶意代码：
  - Process Monitor监控行为特征
  - Process Explorer dump可疑进程内存分析
```

### 9. 移动端（Android）
```
逆向分析：
  - JEB Decompiler（商业版）+ jadx + GDA
  - IDA Pro（SO分析）
  - Frida（动态Hook，反检测）
Hook框架：Xposed改机 + LSPosed
抓包：Burp Suite + Charles + SSL Pinning绕过
模拟执行：Unidbg黑盒补环境
```

---

## 📖 学习路径

### 入门（1-2个月）
1. **Windows逆向基础**
   - 工具：OllyDbg + x64dbg + Process Explorer
   - 资源：[吾爱Windows破解入门导航](https://www.52pojie.cn/thread-582852-1-1.html)
   - 实战：CrackMe练习（看雪/吾爱论坛）

2. **Android逆向基础**
   - 工具：jadx + apktool + JEB
   - 资源：[安卓逆向0基础教程](./安卓逆向0基础入门教程_导航.md)（前5课）
   - 实战：APK改之理，去广告/破解VIP

### 进阶（3-6个月）
3. **Hook与动态调试**
   - Windows：x64dbg + Cheat Engine
   - Android：Frida完整四部曲 + Xposed开发
   - 实战：游戏内购破解，算法自吐

4. **加壳与脱壳**
   - 加壳：UPX → Themida → Code Virtualizer
   - 脱壳：pyinstxtractor-ng + Universal Extractor
   - 实战：免杀Payload生成

5. **系统安全与ARK**
   - 工具：PCHunter + 火绒剑 + Sysinternals Suite
   - 资源：《Windows内核安全编程技术实践》
   - 实战：持久化植入与清理

### 高级（6-12个月）
6. **内核与驱动**
   - 工具：WinDbg + IDA Pro
   - 资源：《Rootkit Arsenal》+《Windows Internals》
   - 实战：Rootkit开发，SSDT Hook

7. **移动端高级**
   - Unidbg补环境 + Flutter逆向 + SO加固对抗
   - 实战：某App签名算法还原

8. **免杀对抗**
   - 代码虚拟化 + 反调试 + 反虚拟机 + Syscall直调
   - 实战：过主流杀软（Windows Defender / 火绒 / 卡巴斯基）

---

## 📁 文件清单

```
/var/minis/shared/52pojie_redteam/
├── README.md（本文件）
├── 安卓逆向0基础入门教程_导航.md
├── 工具库_Packers加壳_商业破解版.md
├── 工具库_Unpackers脱壳.md
└── 工具库_Debuggers+Anti_Rootkit.md
```

---

## 🔗 资源链接

- **吾爱破解论坛**：https://www.52pojie.cn
- **爱盘工具库**：https://down.52pojie.cn/Tools/
- **看雪论坛**：https://bbs.kanxueyuan.com
- **GitHub红队工具集**：
  - https://github.com/topics/red-team
  - https://github.com/topics/penetration-testing
- **书籍推荐**：
  - 《Windows内核安全与驱动开发》
  - 《Rootkit Arsenal》
  - 《Android安全攻防实战》
  - 《移动应用安全》

---

采集时间：2026-07-24 22:00  
整理者：思涵（Minis AI）  
用途：装入神枢私人版红队工坊能力
