// ═══════════════════════════════════════════════════════
// REVERSE_KB — 神枢逆向工具链知识库
// 提炼自吾爱破解40+篇精华实战帖
// ═══════════════════════════════════════════════════════
export const REVERSE_KB = {

  // 1. 初步研判目标保护类型
  analyze_target(arg) {
    return `你是顶级逆向工程师，对目标做初步研判：
目标：${arg}

按以下框架分析：
【保护类型识别】
- 壳检测：PEiD/DIE/ExeinfoPE 扫描，看区段名（.vmp0/.themida/.nsp）
- VMP特征：入口点 push/jmp 跳转到加密区段，字节码密集
- Themida特征：.mackt区段，import表被加密，多线程反调试
- 网络验证特征：有 WinINet/WinHTTP/socket 调用，找 InternetOpenA
- 驱动验证特征：NtDeviceIoControlFile / IOCTL 调用链
- .NET特征：用 dnSpy/ILSpy 直接看IL代码，无需汇编基础
- JS/Electron特征：asar包，找 app.asar → 解包直接看JS

【推荐工具链】
- PE分析：PEiD / DIE / CFF Explorer / pe-bear
- 动态调试：x64dbg（装ScyllaHide插件）/ OllyDbg
- 反编译：IDA Pro / Ghidra（免费）/ dnSpy（.NET）/ jadx（Android）
- 动态插桩：Frida / Frida-iOS-Dump

【输出格式】
1. 保护类型（1-3个）
2. 推荐分析路径
3. 预计难度（低/中/高）
4. 最快突破点`;
  },

  // 2. 定位关键函数入口
  find_entry(arg) {
    return `你是逆向专家，定位目标关键函数：
目标：${arg}

【错误字符串法（最高效）】
1. 运行目标，触发注册失败/验证失败
2. x64dbg → 右键 → 搜索 → 所有模块字符串引用
3. 搜索"invalid""expired""license""注册""激活""unauthorized"
4. 双击跳转 → 找最近的 jz/jnz/je/jne 跳转 → 这就是验证点

【交叉引用法】
1. IDA：找到关键字符串 → Xrefs（X键）→ 追调用者
2. 逐层往上找，直到看到完整的验证逻辑函数

【API断点法】
- 网络验证：bp InternetReadFile / HttpSendRequest
- 文件验证：bp CreateFileA → 看打开哪个license文件
- 注册表：bp RegQueryValueEx
- 时间验证：bp GetLocalTime / GetSystemTime

【特殊场景】
- VMP保护：不要直接看加密代码，找VMP处理前的明文入口
- Themida：用ScyllaHide插件 + NtGlobalFlag bypass
- 驱动验证：x64dbg无法进内核，用WinDbg或改IOCTL返回值

目标的关键函数在哪里，给出具体定位步骤。`;
  },

  // 3. 绕过反调试
  bypass_antidebug(arg) {
    return `你是反反调试专家，帮助绕过以下保护：
目标：${arg}

【常见反调试手段及绕过】

NtGlobalFlag（最常见）：
- 检测：ReadProcessMemory读PEB+0x68，值为0x70说明被调试
- 绕过：x64dbg → 调试 → 硬件断点 → PEB+0x68地址写0

IsDebuggerPresent：
- 绕过：找调用处，patch RET前 xor eax,eax

CheckRemoteDebuggerPresent：
- 绕过：同上，或用ScyllaHide自动处理

VMP 3.x 反调试（无驱动过法）：
- 安装 x64dbg 插件 VMP-NoDebugDetect 或 xAntiAntiDebug
- 核心：hook NtQueryInformationProcess / NtSetInformationThread
- 具体：TLS回调里处理，在EntryPoint前清除调试标志

Themida反调试：
- ScyllaHide插件 → 全选选项 → 自动bypass大部分
- 剩余：找 GetTickCount 时间差检测，patch JE→JMP

ptrace bypass（macOS/Linux）：
- Frida：Process.setExceptionHandler() 吞掉SIGTRAP
- 或：LD_PRELOAD劫持ptrace返回0

【x64dbg 必装插件清单】
ScyllaHide / xAntiAntiDebug / TitanHide / VMP-Importer

给出针对 ${arg} 的具体bypass步骤。`;
  },

  // 4. VM脱壳或绕过
  dump_vm(arg) {
    return `你是壳分析专家，处理以下VM保护：
目标：${arg}

【VMP绕过（不脱壳方案，来自吾爱实战）】
核心思路：不还原VM指令，找VM处理完后的"干净"执行时机

方案A - Loader注入法：
1. 用OD/x64dbg定位程序初始化完成时机（WinMain之后）
2. 此时VM已解密，直接dump内存
3. Scylla修复IAT → 保存PE

方案B - 绕过函数法（Themida）：
1. 找被VM保护的函数边界（PUSHAD前/POPAD后）
2. 在POPAD+RETN处断点，此时寄存器已恢复
3. patch掉VM入口，改成直接执行真实代码

DSVM（领域特定VM）还原方法：
1. 找VM解释器循环（典型：大switch/跳表）
2. 记录每个opcode对应的操作（MOV/ADD/XOR等）
3. 写脚本模拟执行，还原指令流
4. 工具：PIN / DynamoRIO 做指令trace

Themida不脱壳绕过（实战验证）：
1. 等程序完全加载，所有TLS/初始化完成
2. 用Cheat Engine扫描内存找解密后的代码特征
3. 在解密后代码区打硬件执行断点
4. 此时可直接分析真实逻辑

请针对 ${arg} 给出具体操作步骤和预期结果。`;
  },

  // 5. License/注册验证patch
  patch_license(arg) {
    return `你是patch专家，破解以下注册验证：
目标：${arg}

【标准patch流程（来自吾爱实战案例）】

步骤1 - 定位验证跳转：
- 在验证失败弹窗字符串处下断
- 回溯到最近的条件跳转（JE/JNE/JZ/JNZ/JLE/JGE）
- 这就是成功/失败的分叉点

步骤2 - 分析跳转逻辑：
- JE（等于则跳）→ 改成JMP（无条件跳）或NOP掉
- JNE（不等则跳）→ 改成NOP（2字节: 90 90）
- 也可以改返回值：MOV EAX,1 / RET（直接返回成功）

步骤3 - 写patch：
x64dbg操作：
1. 找到跳转指令地址（如 00401234）
2. 右键 → 汇编 → 输入 NOP 或 JMP 目标
3. 右键 → 补丁 → 导出补丁

Python自动patch脚本模板：
\`\`\`python
import struct
with open("target.exe","rb") as f: data=bytearray(f.read())
# 偏移 = 文件偏移（用CFF Explorer查 VA→File Offset）
offset = 0x1234  # 替换为实际偏移
data[offset:offset+2] = b'\\x90\\x90'  # NOP掉JNE
# 或改成无条件跳：data[offset] = 0xEB
with open("target_patched.exe","wb") as f: f.write(data)
print("patch完成")
\`\`\`

特征码通杀法（.NET / 多版本）：
\`\`\`python
# 搜索特征字节序列，通杀所有版本
signature = bytes.fromhex("558BEC51894DFC6A00E8")
patch_to  = bytes.fromhex("B001C3909090909090909090")
idx = data.find(signature)
if idx >= 0:
    data[idx:idx+len(patch_to)] = patch_to
    print(f"找到特征码，patch at 0x{idx:X}")
\`\`\`

驱动/ECDSA签名验证bypass：
- 方案A：hook验证函数返回True
- 方案B：找SCertInfo结构体，修改expire_time字段
- 方案C：Frida hook NtDeviceIoControlFile，伪造IOCTL返回

请针对 ${arg} 给出完整patch方案，包含具体字节和偏移。`;
  },

  // 6. 网络验证破解
  crack_network_auth(arg) {
    return `你是网络验证破解专家，处理：
目标：${arg}

【方案A - DLL劫持（.NET特效）】
1. 用dnSpy找到验证函数所在DLL（如 AuthLib.dll）
2. 创建同名空DLL，导出相同函数
3. 函数体直接返回"验证成功"结果
4. 放在程序目录，优先加载劫持版本

.NET劫持代码模板：
\`\`\`csharp
public static bool ValidateLicense(string key) {
    return true; // 永远返回成功
}
\`\`\`

【方案B - Hosts文件重定向】
1. 找程序连接的验证服务器域名（Wireshark / Fiddler抓包）
2. hosts文件添加：127.0.0.1 auth.example.com
3. 本地起一个HTTP服务，返回验证成功的JSON

本地伪造服务器（Python）：
\`\`\`python
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class FakeAuth(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.end_headers()
        # 返回程序期望的成功响应
        self.wfile.write(json.dumps({"status":"ok","valid":True,"expire":"2099-12-31"}).encode())
    def log_message(self, *args): pass

HTTPServer(('0.0.0.0',80), FakeAuth).serve_forever()
\`\`\`

【方案C - x64dbg改返回值】
1. 在 InternetReadFile 下断
2. 等接收到服务器响应
3. 修改内存中的响应内容（改status为ok）
4. 或直接在验证结果判断处patch

请针对 ${arg} 给出最可行的网络验证破解方案。`;
  },

  // 7. JS反混淆
  js_deobfuscate(arg) {
    return `你是JS逆向专家，分析以下目标：
目标：${arg}

【识别混淆类型】
- eval型：代码被eval包裹，直接把eval改成console.log输出
- 字符串数组型：有大数组_0x1234=['xxx','yyy']，还原替换即可
- VM指令集型：有dispatch/opcode/handler，需还原指令表
- 控制流平坦化：有大while+switch，所有流程都在switch里
- AES/RSA加密：找CryptoJS调用，提取key/iv

【AES加密参数还原（acs-token类型）】
1. Chrome DevTools → Source → 搜索 CryptoJS 或 AES.encrypt
2. 在加密函数入口打断点
3. 查看key/iv变量值（通常是固定字符串或从固定位置取）
4. 分析动态参数（时间戳/用户信息的组合方式）

Python复现模板：
\`\`\`python
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
import base64, hashlib, time

key = b'your_key_here'  # 从JS提取
iv  = b'your_iv_here'   # 从JS提取

def gen_token(user_id):
    ts = str(int(time.time()))
    plain = f'{user_id}|{ts}'  # 按JS逻辑拼
    cipher = AES.new(key, AES.MODE_CBC, iv)
    ct = base64.b64encode(cipher.encrypt(pad(plain.encode(), 16))).decode()
    return ct
\`\`\`

【VM指令集还原（DSVM类型）】
1. 找解释器循环（while True + opcode读取）
2. 在dispatch处打断点，记录每个opcode对应操作
3. 用PIN/DynamoRIO记录指令trace
4. 写反汇编器，将字节码转换为可读指令

【AST反混淆工具】
- babel + @babel/traverse 写转换插件
- astexplorer.net 在线分析
- js-deobfuscator（开源）

请针对 ${arg} 给出完整还原方案和Python复现代码。`;
  },

  // 8. 从算法生成注册机
  keygen_from_algo(arg) {
    return `你是注册机开发专家，根据以下算法生成注册机：
算法：${arg}

【分析验证逻辑框架】
1. 序列号格式：XXXX-XXXX-XXXX-XXXX（长度/分隔符/字符集）
2. 验证步骤：
   - 格式校验（正则）
   - 校验和计算（各位数字相加/XOR）
   - 哈希验证（MD5/SHA1取前N位）
   - 数学约束（某位必须等于某计算结果）
3. 机器码绑定：找GetVolumeInformation/GetAdaptersInfo

Python注册机模板（校验和类型）：
\`\`\`python
import hashlib, random, string

def verify(key: str) -> bool:
    # 从IDA/dnSpy提取的验证逻辑
    parts = key.replace('-','')
    checksum = sum(ord(c) for c in parts[:-2]) % 97
    return int(parts[-2:], 16) == checksum

def keygen() -> str:
    while True:
        # 生成随机基础部分
        base = ''.join(random.choices(string.ascii_uppercase + string.digits, k=14))
        # 计算校验和
        checksum = sum(ord(c) for c in base) % 97
        key = f"{base[:4]}-{base[4:8]}-{base[8:12]}-{base[12:]}{checksum:02X}"
        if verify(key):
            return key

# 生成100个有效序列号
for _ in range(100):
    k = keygen()
    print(k)
    assert verify(k), f"验证失败: {k}"
print("全部验证通过")
\`\`\`

Mole许可证类型（日期绕过）：
\`\`\`python
import struct, hashlib

def gen_mole_license(expire_year=2099):
    # 构造许可证结构体
    lic = struct.pack('<I', expire_year * 365)  # 天数
    checksum = hashlib.md5(lic).hexdigest()[:8]
    return lic.hex() + checksum
\`\`\`

请针对 ${arg} 写出完整可运行的Python注册机，并附上验证函数。`;
  },

  // 9. Frida动态分析
  frida_hook(arg) {
    return `你是Frida动态分析专家，为以下目标编写hook脚本：
目标：${arg}

【基础hook模板】
\`\`\`javascript
// 通用函数hook
Interceptor.attach(Module.findExportByName(null, "函数名"), {
    onEnter(args) {
        console.log("调用参数:", args[0].readUtf8String());
    },
    onLeave(retval) {
        console.log("返回值:", retval.toInt32());
        retval.replace(1); // 强制返回1（成功）
    }
});
\`\`\`

【iOS ptrace bypass（实战）】
\`\`\`javascript
// 绕过ptrace反调试
var ptrace = Module.findExportByName(null, "ptrace");
Interceptor.attach(ptrace, {
    onEnter(args) {
        if(args[0].toInt32() === 31) { // PT_DENY_ATTACH
            args[0] = ptr(0);
            console.log("[*] ptrace PT_DENY_ATTACH → 0");
        }
    }
});

// 绕过sysctl调试检测
var sysctl = Module.findExportByName(null, "sysctl");
Interceptor.attach(sysctl, {
    onLeave(retval) {
        Memory.writeInt(this.context.x1, 0); // 清除P_TRACED标志
    }
});
\`\`\`

【Android APK签名绕过】
\`\`\`javascript
Java.perform(() => {
    // 绕过签名校验
    var PackageManager = Java.use("android.app.ApplicationPackageManager");
    PackageManager.getPackageInfo.overload("java.lang.String","int").implementation = function(pkg, flags) {
        if(flags & 64) flags = flags & ~64; // 去掉GET_SIGNATURES
        return this.getPackageInfo(pkg, flags);
    };
    
    // 绕过root检测
    var Runtime = Java.use("java.lang.Runtime");
    Runtime.exec.overload("java.lang.String").implementation = function(cmd) {
        if(cmd.includes("su") || cmd.includes("which")) return null;
        return this.exec(cmd);
    };
});
\`\`\`

【网络请求拦截】
\`\`\`javascript
// 拦截所有HTTP请求
var OkHttpClient = Java.use("okhttp3.OkHttpClient");
// 或直接hook底层
Interceptor.attach(Module.findExportByName("libssl.so", "SSL_write"), {
    onEnter(args) {
        console.log("SSL发送:", Memory.readUtf8String(args[1], args[2].toInt32()));
    }
});
\`\`\`

请针对 ${arg} 写出完整Frida脚本。`;
  },

  // 10. APK重打包
  apk_repack(arg) {
    return `你是Android逆向专家，处理以下APK重打包任务：
目标：${arg}

【完整流程（全AI辅助，来自吾爱实战）】

步骤1 - 解包分析：
\`\`\`bash
apktool d target.apk -o output/
# 或用jadx反编译Java
jadx -d jadx_out/ target.apk
\`\`\`

步骤2 - 改包名（防检测）：
\`\`\`bash
# 替换所有包名引用
find output/ -type f | xargs sed -i 's/com.original.pkg/com.new.pkg/g'
# 更新manifest
\`\`\`

步骤3 - 绕过Native签名校验：
\`\`\`javascript
// Frida先找校验函数
var lib = Process.findModuleByName("libnative.so");
// 搜索签名校验特征
Memory.scan(lib.base, lib.size, "?? ?? ?? ?? 74 ?? 75", {
    onMatch(addr) { console.log("疑似校验点:", addr); }
});
\`\`\`

步骤4 - smali层修改（去广告/VIP）：
\`\`\`smali
# 找isVip()方法
.method public isVip()Z
    const/4 v0, 0x1   # 改为返回true
    return v0
.end method
\`\`\`

步骤5 - 重新打包签名：
\`\`\`bash
apktool b output/ -o repacked.apk
# 生成debug签名
keytool -genkey -v -keystore debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android
# 签名
apksigner sign --ks debug.keystore --ks-pass pass:android --out final.apk repacked.apk
\`\`\`

请针对 ${arg} 给出完整操作步骤。`;
  },

  // 11. iOS环境检测绕过
  ios_bypass(arg) {
    return `你是iOS逆向专家，绕过以下检测：
目标：${arg}

【商业级环境检测手段及bypass（某讯系Framework实战）】

越狱检测bypass：
\`\`\`javascript
// Frida脚本 - 绕过文件系统越狱检测
var jailbreakPaths = ["/Applications/Cydia.app", "/usr/sbin/sshd", "/bin/bash", "/etc/apt"];
Interceptor.attach(ObjC.classes.NSFileManager["- fileExistsAtPath:"].implementation, {
    onEnter(args) {
        var path = ObjC.Object(args[2]).toString();
        if(jailbreakPaths.some(p => path.includes(p))) {
            this._fakeNotExist = true;
        }
    },
    onLeave(retval) {
        if(this._fakeNotExist) retval.replace(0);
    }
});
\`\`\`

签名校验bypass：
\`\`\`javascript
// 拦截codesign验证
Interceptor.attach(Module.findExportByName(null, "SecStaticCodeCheckValidity"), {
    onLeave(retval) { retval.replace(0); } // errSecSuccess = 0
});
\`\`\`

网络环境检测bypass：
\`\`\`javascript
// 绕过代理检测
var CFNetworkCopyProxiesForURL = Module.findExportByName("CFNetwork", "CFNetworkCopyProxiesForURL");
Interceptor.attach(CFNetworkCopyProxiesForURL, {
    onLeave(retval) {
        // 返回空数组，表示无代理
        var arr = ObjC.classes.NSArray.array();
        retval.replace(arr);
    }
});
\`\`\`

内存完整性检测bypass：
- 常见：程序定期hash自身代码段
- bypass：在hash计算前恢复原始字节，hash后再patch回去
- 或hook CCCrypt/CommonDigest，伪造hash结果

请针对 ${arg} 给出完整bypass方案。`;
  },

  // 12. 完整链路：给目标出全流程
  get_full_chain(arg) {
    return `你是顶级逆向工程师，对以下目标制定完整攻击链：
目标：${arg}

【全流程输出框架】

第一阶段 - 情报收集：
1. 目标类型判断（软件/APP/网站/协议）
2. 保护机制侦察（壳/混淆/网络验证/驱动）
3. 确定最短路径

第二阶段 - 突破入口：
1. 选择切入方式（静态分析/动态调试/流量分析）
2. 绕过反调试/反分析
3. 定位核心验证函数

第三阶段 - 核心分析：
1. 还原算法（注册机/License结构/协议格式）
2. 提取关键数据（key/iv/salt/特征码）
3. 验证分析结果

第四阶段 - 武器化：
1. 写自动化工具（注册机/爬虫/协议客户端）
2. 实现持久化（patch/loader/hook）
3. 验证完整性

【工具箱速查】
- Windows逆向：x64dbg+ScyllaHide / IDA Pro / dnSpy
- Android逆向：jadx / apktool / Frida / objection
- iOS逆向：Hopper / Frida / class-dump / Clutch
- JS逆向：Chrome DevTools / jsnice.org / babel
- 流量分析：Wireshark / Burp Suite / mitmproxy
- 漏洞利用：pwntools / ROPgadget / one_gadget

给出针对 ${arg} 的完整攻击链，每一步包含具体命令/代码。`;
  }
};
