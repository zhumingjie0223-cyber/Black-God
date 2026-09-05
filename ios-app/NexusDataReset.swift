// NexusDataReset.swift — 「清除全部数据」：钥匙串全部条目 + Application Support 下全部本地文件

import Foundation

extension Notification.Name {
    /// 数据已抹除；各内存态存储收到后清空自身，避免重启前旧数据还挂在界面上
    static let nexusDataWiped = Notification.Name("com.blackgod.nexus.dataWiped")
}

enum NexusDataReset {
    /// 兑现商店描述与隐私政策里的"一键清除全部数据"：
    /// 所有服务商 API Key、选中模型、记忆、评估记录、检查点、工具工作区文件。
    /// 本 App 零后端，本地这两处就是全部数据。
    static func wipeAll() {
        NexusKeychain.shared.wipeAll()
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for url in items { try? fm.removeItem(at: url) }
        }
        NotificationCenter.default.post(name: .nexusDataWiped, object: nil)
    }
}
