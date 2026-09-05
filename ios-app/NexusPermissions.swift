import Foundation

enum NexusPermissionError: LocalizedError {
    case toolNotRegistered(String)
    case requiresApproval(String)
    case pathNotAllowed(String)
    var errorDescription: String? {
        switch self {
        case .toolNotRegistered(let n): return "工具未注册：\(n)"
        case .requiresApproval(let n): return "工具需要用户批准：\(n)"
        case .pathNotAllowed(let p): return "路径不在允许范围：\(p)"
        }
    }
}

enum NexusToolRisk: String, Codable { case readOnly, workspaceWrite, externalCommand, network, destructive }

struct NexusToolPolicy: Codable {
    let name: String
    let risk: NexusToolRisk
    let requiresApproval: Bool
    let allowedPaths: [String]
}

struct NexusPermissionGate {
    let policies: [String: NexusToolPolicy]

    static let standard = NexusPermissionGate(policies: [
        "echo": NexusToolPolicy(name: "echo", risk: .readOnly, requiresApproval: false, allowedPaths: []),
        "read_file": NexusToolPolicy(name: "read_file", risk: .readOnly, requiresApproval: false, allowedPaths: []),
        "write_file": NexusToolPolicy(name: "write_file", risk: .workspaceWrite, requiresApproval: true, allowedPaths: ["/var/mobile/Containers/Data/Application"]),
        "shell": NexusToolPolicy(name: "shell", risk: .externalCommand, requiresApproval: true, allowedPaths: [])
    ])

    func authorize(_ call: NexusToolCall, approved: Bool = false) -> Result<Void, NexusPermissionError> {
        guard let policy = policies[call.name] else { return .failure(.toolNotRegistered(call.name)) }
        if policy.requiresApproval && !approved { return .failure(.requiresApproval(call.name)) }
        if let path = call.arguments["path"], !policy.allowedPaths.isEmpty,
           !policy.allowedPaths.contains(where: { path.hasPrefix($0) }) {
            return .failure(.pathNotAllowed(path))
        }
        return .success(())
    }
}
