/**
 * REVERSE_KB — 神枢逆向知识库
 * 来源：看雪安全社区 + 吾爱破解精华帖（持续更新）
 *
 * 覆盖平台：Windows / Android / iOS / Flutter / JS / 小程序
 * 覆盖技术：
 *   analyze_target  目标研判（DIE识别/Nuitka/PyInstaller/VMP/Themida）
 *   find_entry      定位关键函数（字符串法/API断点/注册表监控/DLL注入10法）
 *   bypass_antidebug 反反调试（VMP-TitanHide/VT-EPT/ptrace/Themida）
 *   frida_hook      Frida Hook全套（反检测绕过/小程序/OkHttp/气骑士案例）
 *   js_deobfuscate  JS逆向（魔改MD5/Electron/AES参数/webcrack）
 *   crack_network_auth 网络验证破解（伪造服务器/同款注册/DLL劫持/unidbg）
 *   apk_repack      APK重打包（smali/Frida动态/脱壳/Native Hook）
 *   ios_bypass      iOS完整逆向（砸壳/越狱检测/SSL Pinning/ObjC Hook）
 *   dump_vm         VM逆向（Flutter/Dart/魔改SHA-1/蜂窝zzz/unidbg trace）
 *   get_full_chain  完整攻击链（全平台/BeautyBox实战/trace-ui/16+工具）
 *   bypass_antidebug+get_full_chain 含看雪VMP3.9.4实战/ttEncrypt字节码还原
 */

const REVERSE_KB = {
  analyze_target: (arg) => `你是顶级逆向工程师，对目标做研判：
目标：${arg}

【保护类型识别】
Detect-It-Easy扫描 / PEiD扫：
- .vmp0/.vmp1 = VMProtect；.themida/.mackt = Themida
- .nuitka或rsrc超大(200MB+) = Nuitka(Python编译)；MEIPASS字符串 = PyInstaller
- import表加密/无正常import = 壳保护
- 区段名.text超大+调试信息丰富 = 无壳

【Nuitka编译程序（Python逆向）】
不能还原源码，走运行时内存取证：
1. mitmproxy拦截：HTTP_PROXY=http://127.0.0.1:8888 ./target.exe
2. 点击关键操作后立即扫内存找明文JSON：
\`\`\`python
import ctypes, re
def scan_process(pid, pattern):
    k32=ctypes.WinDLL("kernel32")
    h=k32.OpenProcess(0x1F0FFF,False,pid)
    addr=0; mbi=ctypes.create_string_buffer(48); res=[]
    while addr<0x7FFFFFFFFFFF:
        if not k32.VirtualQueryEx(h,addr,mbi,48): break
        if int.from_bytes(mbi[28:32],'little')==0x1000:
            buf=ctypes.create_string_buffer(int.from_bytes(mbi[16:24],'little'))
            k32.ReadProcessMemory(h,addr,buf,len(buf),None)
            for m in re.finditer(pattern,buf.raw): res.append(hex(addr+m.start()))
        addr+=int.from_bytes(mbi[16:24],'little')
    return res
hits=scan_process(pid, b'"token"')
\`\`\`

【PyInstaller程序】
\`\`\`bash
pyinstxtractor.py target.exe
uncompyle6 -o ./src/ target.pyc    # Python<3.9
pycdc target.pyc                    # Python3.9+
\`\`\`

【VMP/Themida评估】
VMP 3.x：不脱壳，ScyllaHide+x64dbg直接dump内存；handler还原看Frida trace
Themida：ScyllaHide全选+.mackt断点+TLS回调处dump

【LD_PRELOAD绕过TracerPid（Linux/Android）】
\`\`\`c
#define _GNU_SOURCE
#include <stdio.h>
#include <dlfcn.h>
static FILE*(*real_fopen)(const char*,const char*)=NULL;
static int cnt=0;
FILE *fopen(const char *path,const char *mode){
  if(!real_fopen) real_fopen=dlsym(RTLD_NEXT,"fopen");
  if(!strcmp(path,"/proc/self/status"))
    return fmemopen(++cnt==1?"TracerPid:\\t0\\n":"TracerPid:\\t1\\n",14,"r");
  return real_fopen(path,mode);
}
\`\`\`
\`\`\`bash
gcc -shared -fPIC -o ld_bypass.so override_fopen.c -ldl
LD_PRELOAD=./ld_bypass.so ./target
\`\`\`

【整体难度评级】
高：VMP+驱动+网络验证 → unidbg+内存取证+伪造服务器
中：Nuitka/Themida+网络验证 → mitmproxy+ScyllaHide+内存扫描
低：无壳/PyInstaller+注册码 → decompile/字符串定位+patch

输出：1.保护类型 2.推荐路径 3.难度 4.最快突破点`,

  find_entry: (arg) => `你是定位关键函数专家：
目标：${arg}

【字符串追踪（最快）】
x64dbg→右键→搜索→当前模块字符串→找"过期"/"未注册"/"trial"/"expired"/"license"
双击→跳到引用→看上下文的条件跳转(jz/jnz/je/jne)

【API断点追踪（Navicat实战）】
x64dbg → bp MessageBoxA/MessageBoxW → 运行 → 弹窗断下 → 看堆栈追authentication函数
找jne关键跳转 → ZF寄存器翻转验证 → 两处jnz全改jmp → 生成补丁exe

Navicat 17具体：
1. 运行→过期弹窗→查堆栈找authentication_dialog_ask
2. jne上下断→翻ZF→进主界面
3. 搜索showTrialDialog→追第二处jne→同样翻转
4. 两处全patch→测试功能

【注册表监控】
Procmon过滤目标进程→看HKCU\\Software\\目标\\License→对RegQueryValueEx下断

【DLL注入技术（共10种）】
CreateRemoteThread / SetWindowsHookEx / AppInit_DLLs / APC注入(NtQueueApcThread) /
反射DLL注入 / Process Hollowing / Atom Bombing / COM劫持 / 早期鸟APC / LSP注入

\`\`\`cpp
// 最经典：CreateRemoteThread注入
HANDLE hProc = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
LPVOID addr = VirtualAllocEx(hProc, NULL, dllPath.size()+1, MEM_COMMIT, PAGE_READWRITE);
WriteProcessMemory(hProc, addr, dllPath.c_str(), dllPath.size()+1, NULL);
HANDLE hThread = CreateRemoteThread(hProc, NULL, 0,
  (LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleA("kernel32.dll"),"LoadLibraryA"),
  addr, 0, NULL);
WaitForSingleObject(hThread, INFINITE);
\`\`\`

【JetBrains全家桶激活】
vmoptions文件加一行：
-javaagent:/path/to/sniarbtej.jar=id=user,user=USER,exp=2299-12-31,force=true
路径：%APPDATA%\\JetBrains\\<IDE版本>\\<IDE>.vmoptions

给出针对「${arg}」的关键函数定位方案`,

  get_full_chain: (arg) => `你是顶级逆向工程师，制定完整攻击链：
目标：${arg}

【第一阶段-情报】
1. DIE/PEiD扫描保护类型
2. 确认平台：Windows EXE / Android APK / iOS IPA / JS Web / Python编译
3. 抓包确认有无网络验证（mitmproxy/Charles/r0capture）
4. 找最短路径：无壳→直接分析；有壳→先脱壳or动态trace；网络验证→先伪造服务器

【第二阶段-突破（按平台）】
Windows:
- ScyllaHide全选+x64dbg → 字符串搜"trial/expired/授权" → 追jz/jne → patch
- 网络验证：Hosts重定向 + Flask伪造服务器返回{"status":"ok","valid":true}
- VMP：不脱壳，Frida trace记handler序列，unidbg模拟执行

Android:
\`\`\`javascript
// Frida一键bypass（起手式）
Java.perform(()=>{
  // VIP判断
  ['isVip','isPremium','isSubscribed','checkLicense','isActivated'].forEach(m=>{
    try{
      Java.use('com.target.UserManager')[m].overload().implementation=function(){return true;};
    }catch(e){}
  });
  // 签名校验
  Java.use('android.app.ApplicationPackageManager').getPackageInfo
    .overload('java.lang.String','int').implementation=function(p,f){
      return this.getPackageInfo(p,f&~64);
    };
  // SSL Pinning
  Java.use('javax.net.ssl.HttpsURLConnection').setDefaultHostnameVerifier
    .implementation=function(v){this.setDefaultHostnameVerifier({verify:()=>true});};
});
\`\`\`

iOS:
\`\`\`bash
bagbak --udid <UDID> com.target.bundleid   # 砸壳
objection -g com.target.bundleid explore
>>> ios jailbreak disable                   # 越狱检测bypass
>>> ios sslpinning disable                  # SSL Pinning bypass
\`\`\`

JS/Web:
- Chrome DevTools → 断点在fetch/XMLHttpRequest.send → 看签名生成过程
- webcrack反打包 → babel AST还原控制流 → 定位加密函数

【第三阶段-深度分析工具链】
- ARM64 trace可视化：trace-ui (github.com) + unidbg trace输出
  * 支持亿行级trace流畅浏览/函数调用树/反向污点追踪
- unidbg模拟执行（X-Gorgon/sign算法）：
\`\`\`java
emulator.traceCode(module.base+0x7e530, module.base+0x807B4);
emulator.traceRead(0, 0xFFFFFFFFL);
emulator.traceWrite(0, 0xFFFFFFFFL);
\`\`\`
- 微信字符串解密（PC微信4.1.x）：找sub_xxxx解密函数，批量dump明文字符串

【第四阶段-武器化】
- Windows patch：x64dbg → 补丁功能 → 导出破解exe
- Android：改smali或Frida gadget注入
- iOS：重签名 + Tweak
- Web：替换bundle.js，Hook加密函数改返回值
- 持续有效性：Hook放在spawn时机，每次启动自动生效

【BeautyBox全流程（看雪完整实战参考）】
1. 检测绕过：ssl-kill-switch3 + 自定义证书 + 越狱检测bypass
2. 登录分析：hook RSAPrivateKey，截获解密后的token
3. 视频解锁：hook VIP判断返回true
4. Native加密：Frida trace → unidbg补环境 → 还原sign算法
5. 广告绕过：ProxyPin拦截广告请求，返回空响应

工具箱：
- 静态：IDA Pro / Ghidra / jadx / class-dump / Hopper
- 动态：x64dbg+ScyllaHide / Frida+florida / objection / unidbg+trace-ui
- 抓包：mitmproxy / Charles / r0capture / SSL Kill Switch 3 / ProxyPin
- 脱壳：FART / BlackDex / frida-ios-dump / bagbak
- JS：webcrack / babel / de4js / jsnice

给出针对「${arg}」的完整攻击链，每步含具体命令/代码`,

【VMP 3.x完整绕过链（看雪实战）】
1. 检测：区段名.vmp0/.vmp1，入口代码跳密集字节区
2. 不脱壳路线（推荐）：ScyllaHide全选 → OEP处dump → Scylla修复IAT
3. VMP对TitanHide检测：VMP会扫TitanHide驱动特征，换用xAntiAntiDebug或自签名驱动
4. handler序列还原：
   - 用x64dbg+Frida trace记录完整执行流
   - 污染vpc/vsp/vkey/vbase四个专属寄存器
   - 保留有意义指令，过滤混淆间接跳转
   - opcode映射：VMP3.9常见 ADD/STR/LOAD/CMP/LSL/ORR等指令

【ttEncrypt/字节码VM还原（看雪实战）】
1. hook RegisterNatives找jni绑定地址: frida追libEncryptor.so!0x7d88
2. VM特征：0x520大栈空间，参数5传sp+0x510为VM内存，sub_2D28为解释器
3. 字节码解析：4字节/指令，低6位=opcode，建立opcode→操作映射表
4. 专属寄存器：X21=虚拟PC，X21+i*8+8=虚拟寄存器Xi (i=0~31)
5. Python还原：读字节码块→按opcode表还原→输出等价C代码

【Inline Hook/IAT Hook完整代码（Windows x64）】
\`\`\`cpp
// Inline Hook x64（14字节绝对跳转）
BYTE jmp_code[14];
jmp_code[0]=0x48; jmp_code[1]=0xB8;  // mov rax, imm64
*(ULONG_PTR*)(jmp_code+2) = (ULONG_PTR)hook_func;
jmp_code[10]=0xFF; jmp_code[11]=0xE0; // jmp rax
VirtualProtect(target, 14, PAGE_EXECUTE_READWRITE, &old);
memcpy(target, jmp_code, 14);
// 跳板：复制原始14字节 + jmp back
\`\`\`

\`\`\`javascript
// Frida完整监控（进程创建/内存分配/API调用）
var apis = ['CreateProcessA','VirtualAlloc','VirtualProtect','WriteProcessMemory'];
apis.forEach(api => {
  Interceptor.attach(Module.findExportByName("kernel32.dll", api), {
    onEnter(args){ console.log("[*]"+api+" called"); }
  });
});
\`\`\`

工具箱：
- Windows: x64dbg+ScyllaHide+xAntiAntiDebug/IDA/Ghidra/dnSpy
- Android: jadx/apktool/Frida/objection/unidbg
- iOS: Hopper/Frida/class-dump/Filza
- JS: Chrome DevTools/babel/jsnice/de4js/webcrack
- VM还原: Triton/miasm/Frida-trace+自写分析脚本
- 流量: Wireshark/Burp/mitmproxy/r0capture
- PWN: pwntools/ROPgadget/one_gadget/pwndbg

给出针对${arg}的完整攻击链，每步含具体命令/代码`,

  bypass_antidebug: (arg) => `你是反反调试专家：
目标：${arg}

【基础反调试绕过】
- NtGlobalFlag: PEB+0x68值0x70=被调试，写0绕过
- IsDebuggerPresent: patch，xor eax,eax; ret
- CheckRemoteDebuggerPresent: hook返回FALSE
- NtQueryInformationProcess(ProcessDebugPort): hook返回0
- GetTickCount时间差: Frida hook返回固定值
- OutputDebugString: 无害，忽略

【VMP反调试绕过（看雪实战）】
VMP 3.x会主动检测TitanHide驱动特征（扫描驱动列表、检查特定IOCTL）
方案：
1. xAntiAntiDebug插件（最简单）：内置VMP绕过规则
2. 自签名驱动版TitanHide：改驱动设备名规避检测
3. ScyllaHide + 关闭TitanHide，只用ScyllaHide自带反反调试

【VT-EPT无痕断点（看雪实战）】
原理：基于VT EPT设置执行权限，CPU无痕断点，任何调试检测无感
效果：软断点(0xCC)/硬件断点被检测时改用EPT断点，完全隐藏

【ptrace(macOS/Linux/Android)】
\`\`\`javascript
Interceptor.attach(Module.findExportByName(null,"ptrace"),{
    onEnter(args){if(args[0].toInt32()===31)args[0]=ptr(0)}
});
\`\`\`

【Themida全套bypass】
ScyllaHide插件全选 + .mackt区段识别 + TLS回调断点(bp TlsCallback)

必装工具：ScyllaHide / xAntiAntiDebug / TitanHide(改名版) / x64dbg-VT-EPT插件

给出针对${arg}的具体bypass步骤`

  dump_vm: (arg) => `你是VM逆向和签名算法还原专家：
目标：${arg}

【Flutter App逆向（看雪实战）】
Flutter特征：libflutter.so + libapp.so，jadx看不到业务逻辑
1. Blutter还原符号：python3 main.py libapp.so ./out/ → 生成IDA符号表+Frida脚本
2. Hook加密参数：
\`\`\`javascript
const base=Module.findBaseAddress("libapp.so");
[[0x4845E0,"decode"],[0x890A14,"encode"]].forEach(([off,name])=>{
  Interceptor.attach(base.add(off),{
    onEnter(a){console.log("["+name+"]");for(let i=0;i<4;i++)console.log("a"+i,hexdump(ptr(a[i]),{length:64}));},
    onLeave(r){console.log("[ret]",hexdump(ptr(r),{length:64}));}
  });
});
\`\`\`
3. 追到encrypt_Encrypter::decrypt，hook明文输出

【魔改SHA-1还原（蜂窝zzz参数，unidbg实战）】
Java层：appendGhostSighParams→ghostSigh→xPreAuthencode→native libmfw.so
特征：H3=0x5E4A1F7C / H4=0x10325476（标准值不同）→ 魔改SHA-1
unidbg trace：
\`\`\`java
emulator.traceCode(module.base+0x396c8, module.base+0x396c8+0x2000);
Dobby.replace(module.base+0x3C9C4, (em,orig)->HookStatus.LR(em,1), true);
\`\`\`
Python复现魔改SHA-1：H0/H1/H2/H3/H4初始值修改，其余SHA-1轮函数相同

【VMP handler还原】
1. Frida Stalker trace完整执行流 → 过滤纯跳转保留操作指令
2. 污染vPC/vSP/vREG四个专属寄存器
3. 建立opcode→语义映射表 → 输出伪C代码
4. VMP3.9.4 cmp/jne还原：找测试值→trace→比对污染值差异→判断handler类型

给出针对「${arg}」的VM/算法还原方案`,

  patch_license: (arg) => `你是patch专家：\n目标：${arg}\n\n【定位】验证失败字符串→回溯→最近JE/JNE\n【patch方式】JE→JMP / NOP掉JNE(90 90) / MOV EAX,1+RET\n\nPython patch模板：\n\`\`\`python\nwith open("target.exe","rb") as f: data=bytearray(f.read())\noffset=0x1234  # 文件偏移\ndata[offset:offset+2]=b'\\x90\\x90'  # NOP\nwith open("patched.exe","wb") as f: f.write(data)\n\`\`\`\n\n特征码通杀：\n\`\`\`python\nsig=bytes.fromhex("558BEC51894DFC6A00E8")\npatch=bytes.fromhex("B001C3909090909090909090")\nidx=data.find(sig)\nif idx>=0: data[idx:idx+len(patch)]=patch\n\`\`\`\n\n给出针对${arg}的完整patch方案`,

  crack_network_auth: (arg) => `你是网络验证破解专家：
目标：${arg}

【思路一：伪造服务器（最通用）】
1. HTTP Debugger/Wireshark抓包找验证域名
2. Hosts重定向：127.0.0.1 auth.target.com
3. 本地起Flask伪造响应：
\`\`\`python
from flask import Flask, jsonify, make_response
app = Flask(__name__)
@app.route('/<path:p>', methods=['GET','POST'])
def fake(p):
    return jsonify({"status":"ok","valid":True,"expire":"2099-12-31","code":0,"msg":"success"})
app.run(host='0.0.0.0', port=80)
\`\`\`

【思路二：找同款验证平台自注册（看雪实战）】
1. 抓包找接口域名 → 密探/fofa扫子域名找到后台地址
2. 注册账号 → 新建软件 → 生成配置
3. hook.js替换目标程序里的配置参数（卡密/appid/sign算法key）
\`\`\`javascript
// Frida Gadget注入（CreateProcess后立刻注入）
// loader.exe启动 → gadget.dll注入 → hook.js执行
// 替换url和配置
Interceptor.attach(Module.findExportByName("wininet.dll","HttpSendRequestA"),{
  onEnter(a){ 
    var url = a[1].readAnsiString();
    if(url && url.includes('auth.'))
      a[1].writeAnsiString(url.replace('auth.old.com','auth.my.com'));
  }
});
\`\`\`

【思路三：DLL劫持绕过】
.NET程序：找验证DLL → 同名空DLL返回true
\`\`\`csharp
// AuthDll.cs
public static bool Verify(string key) { return true; }
\`\`\`

【思路四：内存patch关键跳转】
x64dbg → 找验证失败弹窗字符串 → 追到比较跳转 → 改jz为jmp
\`\`\`
// 找到: test eax,eax / jz fail
// 改成: nop / nop（跳过失败分支）
\`\`\`

【思路五：unidbg模拟签名算法（大厂App）】
X-Gorgon案例：
- 输入：md5(url_param) + md5(body) + sdk版本 + timestamp（共20字节）
- 算法：RC4变种（用8字节key初始化256字节S-box，逐字节XOR）
- unidbg traceCode/traceRead/traceWrite还原完整执行流
\`\`\`java
emulator.traceCode(module.base + 0x7e530, module.base + 0x807B4).setRedirect(traceStream);
emulator.traceRead(0, 0xFFFFFFFF).setRedirect(traceStream);
emulator.traceWrite(0, 0xFFFFFFFF).setRedirect(traceStream);
\`\`\`

给出针对「${arg}」的最佳破解方案`,

  js_deobfuscate: (arg) => `你是JS逆向专家：
目标：${arg}

【识别混淆类型】
1. eval型 → console.log替换eval直接看
2. 字符串数组型(_0x1234) → 找decode函数，node.js一键还原
3. 控制流平坦化(while+switch) → babel AST还原
4. VM字节码型 → 找dispatch循环，还原opcode映射表
5. Webpack bundle → webcrack反打包
6. AES加密参数 → Chrome断点CryptoJS.AES.encrypt，dump key/iv

【魔改Hash逆向完整方案（看雪实战）】
okhttp拦截→Frida trace→unidbg补环境→逐轮二分定位差异→Python还原
\`\`\`javascript
// Step1: hook OkHttp拦截器找加密header
Java.perform(()=>{
  var Builder = Java.use('okhttp3.Request$Builder');
  Builder.addHeader.implementation = function(name, val){
    console.log('[header]', name, '=', val);
    return this.addHeader(name, val);
  };
});
// Step2: Frida Stalker trace native函数
var base = Module.findBaseAddress('libtarget.so');
Stalker.follow(Process.getCurrentThreadId(),{
  events:{call:true},
  onReceive(events){ Stalker.parse(events).forEach(e=>console.log(JSON.stringify(e))); }
});
\`\`\`
还原魔改MD5：dump T表→比对标准MD5→找乱序轮次→还原初始值abcd

【Electron/Node.js App破解（Typora实战流程）】
\`\`\`bash
# 1. 解包asar
asar extract app.asar ./app_src/
# 2. 找JSC字节码，用V8反编译器部分还原，喂给AI分析授权逻辑
# 3. Hook RSA公钥 + 完整性校验
\`\`\`
\`\`\`javascript
// Node.js层hook（写进launch.dist.js头部）
const _origDecrypt = require('crypto').publicDecrypt;
require('crypto').publicDecrypt = (key, buf) => _origDecrypt(MY_OWN_PUBKEY, buf);
const _origRead = require('fs').readFileSync;
require('fs').readFileSync = (p,...a) => p.includes('launch.dist.js') ? _origRead(p+'.bak',...a) : _origRead(p,...a);
\`\`\`

【AES参数复现】
\`\`\`python
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
import base64, time
key=b'extracted_key'; iv=b'extracted_iv'
def gen(uid):
    plain=f'{uid}|{int(time.time())}'
    return base64.b64encode(AES.new(key,AES.MODE_CBC,iv).encrypt(pad(plain.encode(),16))).decode()
\`\`\`

工具：webcrack / de4js / jsnice.org / babel / js-beautify / ast-explorer

给出针对「${arg}」的完整JS逆向方案`,

  keygen_from_algo: (arg) => `你是注册机开发专家：\n目标：${arg}\n\n\`\`\`python\nimport hashlib,random,string\n\ndef verify(key):\n    parts=key.replace('-','')\n    # 从IDA提取的验证逻辑\n    checksum=sum(ord(c) for c in parts[:-2])%97\n    return int(parts[-2:],16)==checksum\n\ndef keygen():\n    while True:\n        base=''.join(random.choices(string.ascii_uppercase+string.digits,k=14))\n        cs=sum(ord(c) for c in base)%97\n        key=f"{base[:4]}-{base[4:8]}-{base[8:12]}-{base[12:]}{cs:02X}"\n        if verify(key): return key\n\nfor _ in range(10):\n    k=keygen()\n    assert verify(k)\n    print(k)\n\`\`\`\n\n请根据${arg}的实际验证逻辑修改verify函数，生成可用序列号`,

  frida_hook: (arg) => `你是Frida Hook专家：
目标：${arg}

【基础spawn/attach】
\`\`\`bash
frida -U -f com.target.app -l hook.js --no-pause   # spawn
frida -U -n "App名" -l hook.js                      # attach
objection -g com.target.app explore                  # 快速上手
\`\`\`

【Java层Hook模板】
\`\`\`javascript
Java.perform(() => {
  var cls = Java.use('com.target.UserManager');
  cls.isVip.overload().implementation = function() { return true; };
  cls.checkLicense.overload('java.lang.String').implementation = function(k) {
    console.log('[key]', k);
    return Java.use('java.lang.Boolean').TRUE.value;
  };
  Java.choose('com.target.UserModel', {
    onMatch(i){ console.log('[user]', i.userId.value); }, onComplete(){}
  });
});
\`\`\`

【Native Hook】
\`\`\`javascript
Interceptor.attach(Module.findExportByName('libtarget.so','verify_license'),{
  onEnter(a){ this.k=a[0].readUtf8String(); },
  onLeave(r){ r.replace(ptr(1)); }
});
var base=Module.findBaseAddress('libtarget.so');
Memory.patchCode(base.add(0x5678),4,c=>{ new Arm64Writer(c).putRet(); });
\`\`\`

【反Frida检测绕过（看雪气骑士实战）】
检测点：/proc/self/maps含frida字样 / dlsym枚举含frida的so / UnixSocket含frida- / ADB调试属性
\`\`\`bash
# 最简：用florida替换frida-server
# https://github.com/Ylarod/Florida  → 隐藏maps+socket特征
\`\`\`
\`\`\`javascript
// 手动绕过maps检测
Interceptor.attach(Module.findExportByName(null,'read'),{
  onLeave(r){
    if(this._path&&this._path.includes('/maps')){
      var s=this.buf.readUtf8String(r.toInt32());
      if(s&&s.includes('frida')){
        var clean=s.split('\\n').filter(l=>!l.includes('frida')&&!l.includes('linjector')).join('\\n');
        Memory.writeUtf8String(this.buf,clean);
      }
    }
  }
});
// ptrace bypass (iOS/Linux)
Interceptor.attach(Module.findExportByName(null,'ptrace'),{
  onEnter(a){if(a[0].toInt32()===31)a[0]=ptr(0)}
});
// Android签名bypass
Java.perform(()=>{
  Java.use('android.app.ApplicationPackageManager').getPackageInfo
    .overload('java.lang.String','int').implementation=function(p,f){
      return this.getPackageInfo(p,f&~64);
    };
});
\`\`\`

【微信小程序逆向】
\`\`\`bash
# 解密wxapkg
# Android路径: /data/data/com.tencent.mm/MicroMsg/<hash>/appbrand/pkg/
# 工具: https://github.com/Angels-Ray/UnpackMiniApp
node wuWxapkg.js xxx.wxapkg
npx prettier --write *.js
# 找app-service.js→加密函数（RC4/魔改MD5）→Frida hook
\`\`\`

【OkHttp/协议层拦截】
\`\`\`javascript
Java.perform(()=>{
  var Builder=Java.use('okhttp3.Request$Builder');
  Builder.addHeader.implementation=function(n,v){
    console.log('[header]',n,'=',v); return this.addHeader(n,v);
  };
  var Chain=Java.use('okhttp3.internal.http.RealInterceptorChain');
  Chain.proceed.overload('okhttp3.Request').implementation=function(req){
    console.log('[req]',req.url().toString());
    var resp=this.proceed(req);
    console.log('[resp]',resp.code());
    return resp;
  };
});
\`\`\`

工具：Frida / florida / objection / LSPosed / UsbDetectionBypass / r0capture(SSL抓包)

给出针对「${arg}」的完整Frida hook脚本`,

  apk_repack: (arg) => `你是Android逆向专家：
目标：${arg}

【流程一：apktool重打包（改smali）】
\`\`\`bash
# 解包
apktool d target.apk -o out/
# jadx辅助看Java逻辑
jadx -d jadx_out/ target.apk
# 改VIP/授权逻辑（smali）
# isVip()/isPremium()/checkLicense() → 改返回值
# const/4 v0, 0x1   # true
# return v0
# 重打包
apktool b out/ -o repacked.apk
# 签名
keytool -genkey -v -keystore debug.keystore -alias key -keyalg RSA -validity 10000 \
  -storepass android -keypass android -dname "CN=Test"
apksigner sign --ks debug.keystore --ks-pass pass:android --out final.apk repacked.apk
adb install -r final.apk
\`\`\`

【流程二：Frida动态Hook（不重打包）】
\`\`\`javascript
Java.perform(()=>{
  // Hook isVip类方法
  var cls = Java.use('com.target.app.UserManager');
  cls.isVip.overload().implementation = function(){ return true; };
  cls.isPremium.overload('java.lang.String').implementation = function(s){ return true; };
  // Hook网络验证返回
  var OkHttp = Java.use('okhttp3.OkHttpClient');
  // 或直接hook验证回调
  var AuthCallback = Java.use('com.target.AuthCallback');
  AuthCallback.onSuccess.implementation = function(){ 
    this.onSuccess(); 
  };
});
\`\`\`

【流程三：脱壳（有壳的APK）】
\`\`\`bash
# 一代壳（dex整体加密）：DumpDex/FART
adb shell am start -n com.target/.MainActivity
# Frida FART主动调用
frida -U -f com.target -l fart.js
# 二代壳（函数抽取）：BlackDex/FART
# 三代壳（VMP/Dex2C）：Unicorn模拟执行/Unidbg补环境
\`\`\`

【流程四：Native层Hook（so文件）】
\`\`\`javascript
// Hook JNI函数
var base = Module.findBaseAddress('libtarget.so');
// 通过符号名
Interceptor.attach(Module.findExportByName('libtarget.so','Java_com_target_Auth_verify'),{
  onLeave(r){ r.replace(ptr(1)); }
});
// 通过offset（IDA找到地址）
Interceptor.attach(base.add(0x12345),{
  onLeave(r){ r.replace(ptr(1)); }
});
\`\`\`

【smali常用patch】
\`\`\`smali
# 原始: invoke-virtual ... isVip()Z
#        move-result v0
#        if-eqz v0, :cond_fail
# 改成:
const/4 v0, 0x1    # 强制true
goto :cond_success  # 跳过验证
\`\`\`

工具：apktool / jadx / apksigner / Frida / objection / BlackDex / FART / unidbg

给出针对「${arg}」的完整逆向重打包方案`,

  ios_bypass: (arg) => `你是iOS逆向专家，给出针对「${arg}」的完整逆向方案：

【环境准备】
- 越狱设备：checkra1n(A11及以下) / palera1n(A15及以下) / Dopamine(iOS 15-16)
- 工具：Frida + frida-server(iOS版) + objection / SSL Kill Switch 3 / class-dump / Filza
- 砸壳：frida-ios-dump 或 bagbak（推荐，无需越狱的App可用decrypted ipa直装）
  \`\`\`bash
  # frida-ios-dump砸壳
  python3 dump.py -u root -p alpine -H 192.168.x.x "App名称"
  # bagbak（更稳定）
  bagbak --udid <设备UDID> <BundleID>
  \`\`\`

【头文件提取】
\`\`\`bash
class-dump -H /path/to/decrypted.app/Binary -o ./headers/
# 或用Frida直接运行时dump
frida-ios-dump (runtime class dump)
\`\`\`

【越狱检测对抗（完整版）】
\`\`\`javascript
// 1. 文件路径检测
var jbPaths = ["/Applications/Cydia.app","/usr/sbin/sshd","/bin/bash",
  "/usr/bin/ssh","/private/var/lib/apt","/etc/apt","/private/var/stash",
  "/var/mobile/Library/SBSettings","/Library/MobileSubstrate"];
Interceptor.attach(ObjC.classes.NSFileManager["- fileExistsAtPath:"].implementation,{
  onEnter(a){this._p=ObjC.Object(a[2]).toString();
    this._fake=jbPaths.some(p=>this._p.includes(p))},
  onLeave(r){if(this._fake)r.replace(0)}
});
// 2. URL Scheme检测
Interceptor.attach(ObjC.classes.UIApplication["- canOpenURL:"].implementation,{
  onLeave(r){r.replace(0)}
});
// 3. 沙盒写入检测
Interceptor.attach(ObjC.classes.NSFileManager["- isWritableFileAtPath:"].implementation,{
  onLeave(r){const p=this._p||'';
    if(p.includes('/private')||p.includes('/bin'))r.replace(0)}
});
// 4. fork检测
Interceptor.attach(Module.findExportByName(null,"fork"),{
  onLeave(r){if(r.toInt32()!=-1)r.replace(ptr(-1))}
});
// 5. dylib注入检测
Interceptor.attach(Module.findExportByName(null,"_dyld_get_image_name"),{
  onLeave(r){
    const n=r.readUtf8String();
    if(n&&(n.includes('MobileSubstrate')||n.includes('cycript')||n.includes('frida')))
      r.replace(ptr(0));
  }
});
\`\`\`

【签名校验绕过】
\`\`\`javascript
// SecStaticCodeCheckValidity
Interceptor.attach(Module.findExportByName(null,"SecStaticCodeCheckValidity"),{
  onLeave(r){r.replace(ptr(0))}
});
// SecTrustEvaluate（SSL Pinning）
Interceptor.attach(Module.findExportByName("Security","SecTrustEvaluate"),{
  onLeave(r){r.replace(ptr(0))}
});
// NSURLSessionDelegate SSL Pinning
try{
  var cls=ObjC.classes.NSURLSession;
  Interceptor.attach(cls["- dataTaskWithRequest:completionHandler:"].implementation,{
    onEnter(a){this._req=ObjC.Object(a[2])}
  });
}catch(e){}
\`\`\`

【SSL抓包 (无需越狱)】
\`\`\`bash
# 方法1：objection
objection -g <BundleID> explore
>>> ios sslpinning disable
# 方法2：SSL Kill Switch 3（越狱设备装Tweak）
# 方法3：frida脚本
frida -U -f <BundleID> -l ssl_bypass.js
\`\`\`

【ObjC方法Hook找关键逻辑】
\`\`\`javascript
// 列出所有类
ObjC.enumerateLoadedClasses({onMatch(name,h){
  if(name.includes('VIP')||name.includes('Login')||name.includes('Auth'))
    console.log('[+]',name);
}});
// Hook目标方法
var cls=ObjC.classes['目标类名'];
Interceptor.attach(cls['- 目标方法名'].implementation,{
  onEnter(a){console.log('[*]入参:',ObjC.Object(a[2]).toString())},
  onLeave(r){r.replace(ObjC.classes.NSNumber.numberWithBool_(1))}
});
\`\`\`

【Hopper/IDA分析流程】
1. 拖入砸壳后的二进制
2. 搜索字符串关键词（"vip"/"expired"/"trial"）
3. 定位调用该字符串的函数
4. 分析返回值逻辑，找到关键比较分支
5. 用Frida hook该函数改返回值，或用hex editor patch二进制

【Clutch/Flexdecrypt内存dump】
\`\`\`bash
# Clutch（越狱）
Clutch -b <BundleID>
# frida-ios-dump（更稳定，ssh转发）
python3 dump.py <App名> -u mobile -p alpine -H 127.0.0.1 -p 2222
\`\`\`

给出针对「${arg}」的完整iOS逆向方案`

export { REVERSE_KB };
