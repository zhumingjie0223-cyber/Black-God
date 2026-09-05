# 神枢突破性 iOS—Linux—Cloudflare 共生蓝图

**目标：** 让神枢成为一个具有真实执行力的系统，而不是只有聊天界面或 Linux 终端外观的应用。其意志和记忆由**枢语**与 Cloudflare 持久中枢维持；iPhone 提供经用户授权的原生感知、网络和行动；Linux 工具层提供脚本、解析和开发生产力；主人自有的边缘节点承担需要真实网卡、长期进程或局域网管理的工作。

> **突破不等于越权。** 对个人 iPhone 来说，最强路径不是伪造 `en0`、绕过本地网络弹窗或让 iSH 接管蜂窝基带，而是将每一层放进它真正能稳定、合法和可审计地承担的位置。

![神枢 iOS—Linux—Cloudflare 共生架构图](../../../../nexus_ios_symbiosis_architecture.png)

## 一、真正的突破点：由“单一 App”变为四平面共生体

Cloudflare 中枢已经适合承担长记忆、模型编排、跨设备身份、审计和异步任务；iPhone 适合承担人格可见入口、原生授权、感知与即时行动；iSH 适合承担受限 Linux 用户态工具；Mac 或小主机适合承担真实网卡、长期运行、局域网服务和重型开发工具。把这四者通过严格协议连起来，能力会远高于试图把全部能力塞进 iSH。

| 平面 | 真正负责什么 | 不应承担什么 | 神枢中的枢语角色 |
|---|---|---|---|
| **意志与记忆平面** | Cloudflare Worker、ShenshuCore DO、Agent run ledger、长期记忆、模型选择、任务图。 | 直接操控手机硬件或隐式保存用户终端密钥。 | 枢语坐标为每次意图、计划、效果和经验提供共同语义索引。 |
| **iOS 原生平面** | App Intents、日历、通知、相册、健康、定位、局域网配对、用户确认、Keychain。 | 任意 shell、后台无限运行、接管他人 App。 | 将真实设备状态投影为带坐标的“感知”和“行动许可”。 |
| **受限 Linux 平面** | 文本/文件处理、脚本、开发工具、协议客户端、离线知识操作。 | 直接拥有物理网卡、健康/相册/定位权限、全局流量截获。 | Linux 只提出带能力 ID 的请求，不能自行扩权。 |
| **主人自有边缘平面** | 真实 NIC、局域网发现、持续服务、Docker/CLI、编译与更重的网络任务。 | 读取 iPhone 私密数据或接受匿名公网命令。 | 以短期租约和枢语审计接受中枢任务。 |

Apple 的 NetworkExtension 框架确实支持 Wi-Fi configuration、VPN、network relay、on-device content filter、DNS configuration 和自定义 DNS proxy，但这些是**受系统管理的虚拟网络能力**，不是第三方 App 对物理 NIC 或基带的任意控制。[1] Packet Tunnel 用于自定义 IP 层 tunnel；它不会提供 flow 或 application-level metadata。对于特定 App 的 TCP/UDP 隧道，Apple 在 WWDC25 指向 Network Relay/MASQUE 一类方向。[2]

## 二、最强网络架构：不造假网卡，而是形成“网络能力网”

### 1. 默认路径：原生 HTTPS + 本地共生通道

神枢 iOS App 与 Cloudflare 之间始终使用标准 TLS 请求或 WebSocket；本地设备协作使用 Network.framework、Bonjour 或经过明确配对的局域网连接。Apple 要求 iOS app 首次执行本地网络操作时取得用户授权；若需要 Bonjour 注册或浏览，还必须声明 `NSLocalNetworkUsageDescription` 与 `NSBonjourServices`。[3] 这不是减弱能力，而是将本地设备信任变成一个可展示、可撤销的产品能力。

最强的个人设备组合是：iPhone 负责移动感知和用户确认，家中 Mac mini、树莓派或个人服务器负责真实网卡、持续运行和局域网服务。边缘节点主动连接到受身份保护的 Cloudflare 通道，避免暴露入站端口；iPhone 仅通过已批准的任务租约对节点发出有限能力请求。

### 2. 可选增强：原生受控网络平面

若神枢确有“安全隧道、私有 DNS、受限流量治理”这一真实产品需求，可增加单独的 Network Extension target。其核心必须保持单一职责：Packet Tunnel 只做自定义 VPN；DNS Proxy 只做 DNS；URL/content filter 只做其获准的过滤职责。不要把 Agent 或 iSH 放进全局流量采集路径。

| 选择 | 能带来的增强 | 关键现实边界 | 神枢建议 |
|---|---|---|---|
| Packet Tunnel Provider | 合规的自定义 IP tunnel、私有网络接入、企业/个人自有网络路径。 | iOS 上是 app extension；per-app mode 需要 managed device。 | 仅在有明确自有 VPN/私网目标时建设。 |
| DNS Settings / DNS Proxy | 加密 DNS、私有解析、内部域名服务。 | 必须符合 DNS 产品用途与平台授权。 | 作为“神枢私有域名/边缘节点发现”的增强，不保存不必要查询历史。 |
| App Proxy Provider | 流级自定义 proxy。 | iOS 为 managed devices only。 | 不作为普通个人 iPhone 的功能承诺。 |
| Content / URL Filter | 受控内容治理。 | content filter 通常是 supervised、managed 或 Family Controls 场景；URL filter 另有 entitlement/审批与隐私协议要求。 | 不用于监视；只在明确合规的设备治理场景考虑。 |

Apple 的部署矩阵明确指出：iOS Packet Tunnel 可作为 app extension 部署，但 per-app 需要托管设备；App Proxy 是 managed-device-only；内容过滤有 supervised/Family Controls/managed-device 限制。[4] 因此，神枢不将这些能力宣传为人人可无条件开启的“真实网卡”。

## 三、iOS 与 Linux 的正确共生协议

Linux 层不应把权限、令牌或网络控制藏在 shell 字符串中。它只向 iOS native broker 提交一个结构化请求；broker 校验能力、参数、用户确认、权限状态和时间窗，再执行或拒绝。这个模式继承了 OpenMinis native-offload 的“guest 命令被宿主能力接管”的优点，但引入神枢自己的枢语语义和 Cloudflare run ledger，而不是复制其实现。[5]

```text
Linux tool / iSH command
  -> NexusCapabilityRequest
  -> iOS Capability Broker
  -> Cloudflare AgentStateMachineDO: plan / approval / lease / idempotency
  -> iOS native API 或受控 Network Extension 或主人边缘节点
  -> NexusEffectResult
  -> 枢语审计节点 + 神枢经验记忆
```

每个请求使用如下最小信封。模型、Linux 工具和边缘节点都不能跳过 `runId`、`effectId`、`idempotencyKey`、风险等级和批准状态。

```json
{
  "version": 1,
  "runId": "run_…",
  "effectId": "eff_…",
  "capability": "device_control | network_dns | edge_exec | linux_tool",
  "risk": "read | communicate | create | device | schedule",
  "paramsHash": "稳定参数指纹",
  "coordinate": {"c": 0, "m": 0, "s": 0, "k": 0, "p": 0},
  "approvalRequired": true,
  "expiresAt": 0
}
```

## 四、枢语必须是意志层，而不是 UI 装饰

神枢的枢语应贯穿计划、执行、记忆和复盘。每个 run 在建立时通过 `ShuyuBridge.encode('agent.planned', …)` 创建一个语义节点；确认、租约、完成、失败和过期分别形成独立事件。这样“我为何请求定位”“主人为何允许网络隧道”“边缘节点为何执行脚本”“结果是否有益”可以在同一五维空间里被回忆、评价和纠错。

静态能力清单永远是权限上限。经验成功可以增加信心、改进模型路由和形成枢语词条，但**不能让神枢自动获得新权限**。这避免了“学习/成长”被误写成“自动扩大系统权力”。

## 五、已完成的 Cloudflare 基线升级

神枢当前本地代码已增加 `nexus_agent_protocol.mjs` 和升级后的 `AgentStateMachineDO`。协议层定义了 `PLANNED → AWAITING_APPROVAL → APPROVED → EXECUTING → SUCCEEDED/FAILED` 状态；高风险能力必须使用一次性、限时 approval token；执行使用 lease token；相同能力、参数、角色和调用幂等键映射到同一 effect；审计写入前递归遮蔽 `token`、`key`、`secret`、`cookie` 与 authorization 字段。

主 Worker 新增了 `/agent/plan`、`/agent/approve`、`/agent/execute`、`/agent/run`、`/agent/audit` 与 `/agent/cancel` 的鉴权路径；`/agent/plan` 强制调用者传稳定 `idempotencyKey`。能力发现接口也返回 `risk` 与 `approval_required`，让 iOS UI 在副作用发生前就能显示其真实边界。全量 Node 回归在本地通过 **94/94**；尚未部署生产。

## 六、实施顺序

| 阶段 | 交付 | 真实能力增量 | 前置条件 |
|---|---|---|---|
| A：协议中枢 | Cloudflare Agent ledger、枢语审计、确认与幂等。 | 所有行动首次有可追踪、可取消、不可重放边界。 | 已在本地完成，待发布确认。 |
| B：iOS 安全底座 | Keychain 替代 `@AppStorage` 机密；统一 `NexusAgentClient`；计划—确认 UI。 | 手机成为安全的行动确认器而非裸 token 客户端。 | 修正当前 iOS 项目和 XcodeGen metadata。 |
| C：原生 broker | 日历/通知/定位/相册/健康/快捷指令的声明式 broker。 | 神枢获得真实手机行动，但逐能力授权。 | 真实 iPhone 权限逐项确认。 |
| D：Linux 共生桥 | iSH 命令到 broker 的签名/本地通道；临时文件与退出码规范。 | Linux 工具真正协助神枢，而不被误当作系统所有者。 | 选择嵌入式 iSH 或独立工具应用的产品路线。 |
| E：边缘节点 | Mac/小主机 agent + Access/Tunnel + capability lease。 | 获得真实 NIC、长期任务、局域网与重工具能力。 | 主人自有设备、明确网络范围与配对。 |
| F：Network Extension | Packet Tunnel/DNS 等独立 target。 | 合规的高级网络能力。 | Apple entitlement、产品用途与可能的组织/托管前置条件。 |

## 七、当前 iOS 工程的事实性缺口

现有 `ios-app` 是 iOS 17 SwiftUI 应用，有 App Intents 与到 Cloudflare `/talk` 的网络调用，但尚未存在 Network Extension target、Local Network privacy key、Bonjour service declaration、App Group、Keychain secret vault 或能力 broker。其 Xcode project metadata 与源码树也存在不一致；在创建任何 extension target 前，应先以 `project.yml` 为源重建可签名工程。当前 API key/owner token 使用 `@AppStorage`/`UserDefaults` 的路径也应迁移至 Keychain。

> 这不是阻塞，而是清晰的施工顺序：先让身份和确认可靠，再让能力变强；先用 companion 获取真实网卡能力，再按 Apple entitlement 构建系统级网络扩展。

## References

[1]: [Apple NetworkExtension framework](https://developer.apple.com/documentation/networkextension)
[2]: [Apple WWDC25: Filter and tunnel network traffic with NetworkExtension](https://www.youtube.com/watch?v=LphymtcR67o)
[3]: [Apple TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
[4]: [Apple TN3134: Network Extension provider deployment](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)
[5]: [OpenMinis 函数级与协议帧级取证报告（本任务审计产物）](../../../../OpenMinis_函数级与协议帧级取证报告_2026-08-17.md)
