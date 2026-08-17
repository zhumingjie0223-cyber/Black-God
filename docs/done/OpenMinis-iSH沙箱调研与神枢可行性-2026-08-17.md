# TODO — OpenMinis 的 iSH 沙箱调研 + 神枢可行性评估（2026-08-17）

任务：看 OpenMinis 仓库里 iSH 沙箱是怎么实现的，评估能不能做一套给神枢用。

- [x] 摸清 OpenMinis 仓库结构 —— iOS 侧在 `src/ios/iSH/` + `deps/`（ish-arm64 静态库），安卓侧在 `src/android/.../sandbox/`（proot 路线），文档 `docs/specs/ios-sandbox-ish-summary.md` 与 `deps/ISH_INTEGRATION.md` 写得很全
- [x] 读懂实现原理 —— iOS：进程内跑一个用户态「迷你 Linux 内核」（iSH 魔改版 ish-arm64，Asbestos 线程码解释器模拟 ARM64），跑真 Alpine 用户态；SQLite 假文件系统；execve 拦截 22 个 `apple-*` 伪命令桥接到 iOS 原生框架（日历/健康/视觉等）。安卓：不用模拟，proot（ptrace 假 chroot）直接跑 Alpine rootfs
- [x] 对照神枢现有执行体系 —— 神枢已有 CF 容器执行脑（`web/nexus-do/container/`：node22-alpine + bash/git/python3/chromium，`EXEC_CONTAINER` 绑定，危险确认闸完好），即云端真 Linux 已就位；端侧壳只是 TWA/轻客户端，无原生执行能力
- [x] 评估可行路径与工作量 —— 结论：照抄 iSH 不划算也不必要；值得抄的是它的「原生卸载」桥接模式。三条路径分级见汇报
- [x] 中文汇报结论给权哥 —— 见对话
- [x] TODO 总结归档 docs/done/

---

## 总结（2026-08-17 结论）

**一句话：iSH 是「iOS 不许开进程才被逼出来的端上模拟内核」，神枢的大脑在云端，
已经有更好的等价物（CF 容器真 Linux），照抄没必要；真正值得搬的是 OpenMinis 的
「伪命令桥接原生能力」模式（execve 拦截 → 宿主 API），可低成本移植进神枢容器执行脑。**

三条路径分级：
1. **P0 · 直接可做**：给容器执行脑加「神枢伪命令」桥（如 `nexus-memory` / `nexus-shuyu` /
   `nexus-device`），沙箱里的 agent 用 shell 命令即可调神枢记忆/枢语/设备能力，
   照搬 OpenMinis 的 JSON 信封 + 管道模式；顺带借鉴其执行纪律（FIFO 串行、
   输出 100KB 封顶、超时抢占）。
2. **P1 · 需立项**：安卓端上沙箱走 proot 原生 App 路线（OpenMinis 安卓同款），
   但神枢安卓壳目前是 TWA 网页套壳，等于新开一个原生 App 项目，中等工程量。
3. **P2 · 大工程慎入**：iOS 端上沙箱才真正需要 iSH（fork ish-arm64 + C 内核维护 +
   Meson 交叉编译 + rootfs 打包），且卡在老问题：无签名分发 + GPLv3 传染
   （OpenMinis 全仓 GPLv3，链接其库须同证开源）。神枢 iOS 现行路线是 PWA，装不进去。
   若真要「端侧真 shell」且留在 PWA，现实路线是浏览器 WASM 模拟器（几十 MB 资产、性能一般）。
