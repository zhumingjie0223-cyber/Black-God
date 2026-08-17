# 吾爱破解爱盘 - Debuggers 调试器（208MB）

来源：https://down.52pojie.cn/Tools/Debuggers/

## 工具清单（11款精品）

### 用户态调试器

#### **x64dbg** - 开源现代调试器（推荐）
- **2026-05_27** (30.1 MB, 2026-06)
- 支持 x86/x64 双架构
- 插件生态丰富，脚本API强大
- 红队渗透必备：内存分析、shellcode调试、注入检测

#### **OllyDbg** - 经典逆向神器
- **吾爱破解专用版** (12.3 MB, 2016-01) - 集成常用插件
- **v2.01** (6.6 MB, 2013-10) - 官方版本
- **OllyICE 1.10** (5.2 MB, 2017-01) - 增强版（集成反反调试）
- 适合 x86 逆向，界面友好，插件丰富

#### **WinDbg** - 微软官方内核调试器
- **X64 v10.0.26100.6584** (38.9 MB, 2025-11)
- **X86 v10.0.26100.6584** (32.9 MB, 2025-11)
- **amd64 6.12.2.633** (16.3 MB, 2012-11) - 经典版
- **x86 6.12.2.633** (17.9 MB, 2012-11)
- 内核调试、驱动分析、蓝屏分析、Windows内部机制研究

### 专用工具

#### **Cheat Engine** - 游戏修改器/内存扫描
- **v7.7** (33.1 MB, 2026-06)
- 内存扫描、修改、注入
- 红队用途：进程内存分析、运行时hook

#### **API Monitor** - API调用监控
- **v2r13 x86/x64** (8.1 MB, 2025-03)
- 实时监控进程API调用
- 红队用途：行为分析、恶意软件取证

#### **Nanomite** - x64调试器
- **x64** (6.6 MB, 2013-10)
- 轻量级 x64 调试

---

## 红队应用场景

### 1. **恶意软件分析**
- **x64dbg** - 动态分析恶意样本，跟踪payload解密流程
- **OllyDbg** - 经典32位样本调试，反反调试插件绕过检测

### 2. **漏洞利用开发**
- **WinDbg** - 内核漏洞调试，驱动漏洞分析
- **x64dbg** - 用户态ROP链构造，shellcode调试

### 3. **进程注入与Hook**
- **Cheat Engine** - 定位关键函数地址，注入自定义代码
- **API Monitor** - 监控程序API调用，找注入点

### 4. **免杀Payload调试**
- **x64dbg** - 调试免杀马，确保shellcode正确执行
- **OllyICE** - 反反调试增强，绕过加壳检测

### 5. **内存取证**
- **WinDbg** - dump进程内存，分析加载的恶意模块
- **Cheat Engine** - 扫描进程内存，定位敏感字符串

---

## 工具组合推荐

**基础逆向**
```
OllyDbg吾爱专版 + x64dbg + Cheat Engine
```

**高级漏洞分析**
```
WinDbg + x64dbg + API Monitor
```

**恶意软件深度分析**
```
x64dbg + OllyICE（反反调试） + API Monitor（行为监控） + Cheat Engine（内存扫描）
```

---

## 学习资源

- **看雪论坛** - OllyDbg/x64dbg插件开发教程
- **吾爱破解** - [Windows破解入门导航](https://www.52pojie.cn/thread-582852-1-1.html)
- **IDA Pro Book** - 高级调试技巧（虽是IDA但通用）

---

# 吾爱破解爱盘 - Anti_Rootkit 反Rootkit工具（485.6MB）

来源：https://down.52pojie.cn/Tools/Anti_Rootkit/

## 工具清单（25款ARK神器）

### 国产顶级ARK（活跃维护）

#### **火绒剑 KswordARK**
- **5.1.2.2-4 R0** (16 MB, 2026-07) - 最新版
- 火绒安全出品，驱动级检测
- 功能：进程/模块/内核/网络/启动项/服务全面监控

#### **OpenArk**
- **v2.0.0** (19.5 MB, 2026-06)
- 开源ARK工具，持续更新
- GitHub: https://github.com/BlackINT3/OpenArk

#### **PCHunter** - 经典ARK神器
- **v1.6** (2.7 MB, 2026-06) - 最新版
- **free版** (6.9 MB, 2019-02)
- 功能最全面的ARK，驱动/内核/SSDT/IDT/回调/进程/注册表

#### **Pyark**
- **20260519** (23.7 MB, 2026-06)
- Python编写的ARK

#### **ATool**
- **20250723.1204** (70.1 MB, 2025-08)
- 多功能ARK

#### **NoOne**
- **v1.0.13.24** (14.3 MB, 2026-02)

#### **YDArk**
- **v1.0.3.3** (13.9 MB, 2024-03)

#### **DarkArk**
- **v1.1** (4.9 MB, 2026-03)

#### **WKE**
- **20251214** (20.1 MB, 2026-02)

#### **WKTools**
- **最新版** (19.7 MB, 2025-11)

#### **QDoctor**
- **最新版** (40.2 MB, 2026-06)

### 微软官方Sysinternals（红队必备）

#### **Sysinternals Suite**
- **完整套装** (184.1 MB, 2026-06)
- 包含70+系统工具：
  - **Process Explorer (Procexp)** - 进程树查看，替代任务管理器
  - **Process Monitor (Procmon)** - 实时监控文件/注册表/网络/进程活动
  - **Autoruns** - 启动项管理（杀持久化必备）
  - **TCPView** - 网络连接实时监控
  - **PsExec** - 远程执行（红队横向移动）
  - **PsTools** - 远程管理工具集
  - **Handle** - 句柄查看
  - **AccessChk** - 权限检查
  - **Sysmon** - 系统监控驱动（EDR核心）

#### **Autoruns** 单独版
- **64位** (1.8 MB, 2026-06)
- **32位** (1.7 MB, 2026-06)

#### **Process Explorer** 单独版
- **procexp.exe** (4.4 MB, 2026-05/04)

#### **Process Monitor** 单独版
- **Procmon.exe** (4 MB, 2026-06)

### 国际经典ARK

#### **System Informer** (原Process Hacker)
- **v3.2.25011** (21.9 MB, 2025-03)
- 开源进程监控，比Process Explorer更强
- GitHub: https://github.com/winsiderss/systeminformer

#### **GMER**
- **最新版** (362.6 KB, 2022-02)
- Rootkit检测经典工具，驱动级扫描

#### **RKUnhooker LE**
- **最新版** (396.5 KB, 2011-11)
- 反Hook工具

#### **XueTr 吾爱破解论坛专版**
- **定制版** (3.3 MB, 2011-11)
- 经典国产ARK

### 其他专用工具

#### **Kernel Detective**
- **v1.4.0** (1.2 MB, 2019-07)
- 内核检测

#### **Malware Defender**
- **中文版** (1.7 MB, 2014-02)
- 恶意软件防御

#### **System Safety Monitor (SSM)**
- **2.4.0.622 beta** (4.3 MB, 2014-02)
- 系统安全监控

---

## 红队应用场景

### 1. **权限提升后隐藏**
- **PCHunter** - 删除进程/模块在任务管理器中的显示，隐藏驱动
- **火绒剑** - 清理内核回调（PsSetCreateProcessNotifyRoutine等）

### 2. **持久化检测与清理**
- **Autoruns** - 查找所有自启动项（注册表Run/服务/计划任务/驱动/Winlogon等）
- **Process Monitor** - 监控恶意软件创建持久化的瞬间

### 3. **横向移动后门清理**
- **Process Explorer** - 找隐藏进程/注入的DLL
- **TCPView（Sysinternals）** - 查看异常网络连接

### 4. **Rootkit对抗**
- **GMER** - 扫描SSDT/IDT/IRP Hook
- **PCHunter** - 手动恢复被Hook的内核函数

### 5. **内存马检测**
- **Process Monitor** - 监控无文件恶意代码的行为特征
- **Process Explorer** - dump可疑进程内存分析

### 6. **EDR绕过研究**
- **Sysmon配置分析** - 研究企业Sysmon规则，构造免检测行为
- **Sysinternals Suite** - 学习EDR底层实现（Sysmon就是迷你EDR）

---

## 工具组合推荐

**快速应急响应**
```
火绒剑 + Autoruns + Process Explorer + TCPView
```

**深度取证分析**
```
PCHunter + Process Monitor + Sysinternals Suite + GMER
```

**内核级对抗**
```
PCHunter（手动恢复Hook） + 火绒剑（驱动级检测） + GMER（Rootkit扫描）
```

**红队隐蔽对抗**
```
研究PCHunter检测原理 → 绕过ARK检测 → 用Process Monitor验证隐藏效果
```

---

## 学习路径

1. **入门** - Process Explorer + Autoruns（理解Windows启动/进程机制）
2. **进阶** - PCHunter + 火绒剑（驱动/内核/SSDT/回调）
3. **高级** - Sysinternals全家桶 + GMER（Rootkit原理与对抗）
4. **实战** - 结合《Windows内核安全与驱动开发》+ 《Rootkit Arsenal》书籍

---

## 注意

⚠ **ARK工具都需要管理员权限运行**，部分需要加载驱动（如PCHunter的PCHunter64.sys）

⚠ **火绒剑/PCHunter** 可以直接终止系统关键进程（csrss/smss等），误操作会蓝屏

⚠ **Sysinternals工具** 被很多EDR/杀软白名单信任，红队可利用（如PsExec横向移动）
