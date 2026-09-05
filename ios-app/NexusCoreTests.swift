import Foundation

#if DEBUG
struct NexusCoreSelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        let contract = NexusTaskContract(goal: "测试", maxRounds: 2)
        let policy = NexusTerminationPolicy()
        if !policy.decide(contract: contract, output: "完成", round: 1, verified: true).shouldStop { failures.append("verified stop") }
        if policy.decide(contract: contract, output: "", round: 1, verified: false).shouldStop { failures.append("empty continue") }
        if !policy.decide(contract: contract, output: "x", round: 2, verified: false).shouldStop { failures.append("round limit") }
        if NexusModelCatalog.entry(for: "deepseek-reasoner").providerID != "deepseek" { failures.append("deepseek route") }
        if NexusModelCatalog.entry(for: "grok-4").providerID != "xai" { failures.append("grok route") }
        return failures
    }
}
#endif
