//
// PacketTunnelProvider.swift — 神枢受控网络扩展
//
// 这不是网卡驱动，也不是 iSH/PRoot 替代品。Packet Tunnel 只能在 Apple 授予
// Network Extension entitlement 且主人提供受管理 tunnel 配置时运行。
// 在未配置上游 gateway 的情况下明确失败，绝不创建黑洞路由或虚报网络已接管。

import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let providerProtocol = protocolConfiguration as? NETunnelProviderProtocol,
              let gateway = providerProtocol.providerConfiguration?["gateway"] as? String,
              !gateway.isEmpty else {
            completionHandler(NexusTunnelError.configurationRequired)
            return
        }

        // 仅建立明确配置的网络设置；真正的数据面必须由受审计的 gateway transport 提供。
        // 当前仓库不内置任何绕过、流量劫持或未经授权的代理实现。
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: gateway)
        settings.mtu = 1280
        setTunnelNetworkSettings(settings) { error in
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

enum NexusTunnelError: LocalizedError {
    case configurationRequired

    var errorDescription: String? {
        "神枢网络扩展未配置受管理 gateway；已拒绝启动，未修改系统网络。"
    }
}
