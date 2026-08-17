# 吾爱破解爱盘 - Unpackers 脱壳工具（86.5MB）

来源：https://down.52pojie.cn/Tools/Unpackers/

## 工具清单（20款）

| 工具名 | 大小 | 更新时间 | 用途 |
|--------|------|----------|------|
| **ASPack UnPacker** 1.13 | 195.9 KB | 15年前 | ASPack加壳脱壳 |
| **ASProtect Unpacker** | 855 KB | 15年前 | ASProtect脱壳 |
| **Armageddon** v2.3 | 1.2 MB | 3年前 | 通用脱壳 |
| **AutoEye** v2.0.0.1000 | 1.5 MB | 3年前 | 自动化脱壳 |
| **AutoIt Extractor** | 495.5 KB | 5年前 | AutoIt脚本提取 |
| **CoolDumpper** | 284.2 KB | 16年前 | 内存dump |
| **Enigma Virtual Box Unpacker** v0.63 | 292.7 KB | 2年前 | Enigma虚拟化脱壳 |
| **InnoExtractor** v11.3.0.161 | 2.8 MB | 7个月前 | Inno Setup提取器 |
| **InnoUnpacker** v2.2.9 | 2.2 MB | 3个月前 | Inno Setup解包 |
| **MSI解包工具 lessmsi** v2.12.9 | 723.6 KB | 3个月前 | MSI安装包解包 |
| **Molebox Virtualization Studio unpacker** v0.65 | 296.8 KB | 5年前 | Molebox虚拟化脱壳 |
| **Obsidium Unpacker** by winndy | 828.1 KB | 15年前 | Obsidium脱壳 |
| **UPX Unpacker** | 123 KB | 10年前 | UPX压缩脱壳 |
| **UnAutoIt** | 7.6 MB | 5年前 | AutoIt反编译 |
| **Universal Extractor** | 14.5 MB | 10年前 | 通用解包器 |
| **Unpacker_ASPack** | 411.8 KB | 7年前 | ASPack专用脱壳 |
| **Unpacker_PECompact** | 394.6 KB | 13年前 | PECompact脱壳 |
| **innoextract** 1.9 | 508.5 KB | 5年前 | Inno Setup命令行提取 |
| **pyinstxtractor-ng** | 7.4 MB | 1个月前 | **PyInstaller脱壳**（最新） |
| **unlicense** py3.11 | 44 MB | 2年前 | Python授权移除 |

## 核心工具说明

### 通用脱壳
- **Universal Extractor** - 支持几十种打包格式
- **Armageddon** - 自动化检测加壳类型
- **AutoEye** - 智能脱壳

### Python逆向
- **pyinstxtractor-ng** - PyInstaller打包的exe脱壳提取pyc（红队必备）
- **unlicense** - 移除Python授权验证

### 安装包解包
- **InnoExtractor** / **InnoUnpacker** - Inno Setup安装包提取（Windows软件常用）
- **lessmsi** - MSI安装包解包

### 专用壳
- ASPack / ASProtect / Enigma / Molebox / Obsidium / UPX - 各种商业/免费加壳工具对应的脱壳器

## 红队应用场景

1. **恶意软件分析** - 脱壳后静态分析payload
2. **软件逆向** - 绕过代码混淆和保护
3. **Python免杀** - PyInstaller打包免杀马，pyinstxtractor-ng可脱
4. **捆绑分析** - 解包安装程序查找夹带的恶意模块
