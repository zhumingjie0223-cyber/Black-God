// NexusDataReset.swift — 清除钥匙串与应用本地文件，汇总无法删除的项目。
import Foundation

extension Notification.Name {
    /// 抹除流程已执行；即使部分文件失败，也清空当前内存视图并显示错误。
    static let nexusDataWiped = Notification.Name("com.blackgod.nexus.dataWiped")
}

enum NexusDataReset {
    /// 返回失败说明；空数组表示全部已清除。可注入目录与钥匙串操作供隔离测试。
    @MainActor @discardableResult
    static func wipeAll(directory: URL? = nil, keychainWipe: (() -> [String])? = nil) -> [String] {
        var errors = keychainWipe?() ?? NexusKeychain.shared.wipeAll()
        let base = NexusStoreFile.directory(directory)
        let fm = FileManager.default
        if fm.fileExists(atPath: base.path) {
            do {
                let items = try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
                for url in items {
                    do { try fm.removeItem(at: url) }
                    catch { errors.append("清除 \(url.lastPathComponent) 失败：\(error.localizedDescription)") }
                }
            } catch { errors.append("读取本地数据目录失败：\(error.localizedDescription)") }
        }
        NotificationCenter.default.post(name: .nexusDataWiped, object: nil)
        return errors
    }
}
