import Foundation

#if DEBUG
/// 进程内自测（DEBUG 专用）。覆盖 ASI 执行闭环的纯逻辑：终止策略、模型路由、
/// 安全算术、工具调用解析、验证器，以及工具注册表 / Executor 端到端（async）。
/// 与 CI/本地的 Swift 包测试同源，改动核心逻辑时可在启动处调用做冒烟。
struct NexusCoreSelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        func expect(_ cond: Bool, _ tag: String) { if !cond { failures.append(tag) } }

        // 终止策略
        let contract = NexusTaskContract(goal: "测试", maxRounds: 2)
        let policy = NexusTerminationPolicy()
        expect(policy.decide(contract: contract, output: "完成", round: 1, verified: true).shouldStop, "verified stop")
        expect(!policy.decide(contract: contract, output: "", round: 1, verified: false).shouldStop, "empty continue")
        expect(policy.decide(contract: contract, output: "x", round: 2, verified: false).shouldStop, "round limit")

        // 模型路由（目录归一后每个 id 都能正确路由）
        expect(NexusModelCatalog.entry(for: "deepseek-reasoner").providerID == "deepseek", "deepseek route")
        expect(NexusModelCatalog.entry(for: "grok-4").providerID == "xai", "grok route")
        expect(NexusModelCatalog.entry(for: "claude-opus-5").providerType == .anthropic, "anthropic route")
        expect(NexusModelCatalog.entry(for: "unknown").providerID == NexusModelCatalog.entries[0].providerID, "route fallback")

        // 安全算术
        expect(NexusArithmetic.evaluate("(3+4)*2") == 14, "arith paren")
        expect(NexusArithmetic.evaluate("-3+5") == 2, "arith unary")
        expect(NexusArithmetic.evaluate("1/0") == nil, "arith div0")
        expect(NexusArithmetic.evaluate("2+") == nil, "arith trailing")
        expect(NexusArithmetic.evaluate("abc") == nil, "arith letters")

        // 工具调用解析 + 剥离
        let calls = NexusToolCallParser.parse("先算\n```tool\n{\"name\":\"calc\",\"arguments\":{\"expr\":\"1+1\"}}\n```")
        expect(calls.count == 1 && calls.first?.name == "calc" && calls.first?.arguments["expr"] == "1+1", "parse tool block")
        expect(NexusToolCallParser.stripCalls(from: "答案\n```tool\n{\"name\":\"x\"}\n```\n尾").contains("答案") &&
               !NexusToolCallParser.stripCalls(from: "答案\n```tool\n{\"name\":\"x\"}\n```\n尾").contains("```"), "strip tool block")

        // 验证器
        let verifier = BasicNexusVerifier()
        expect(verifier.verify(goal: "写关于春天的诗", output: "这是关于春天的诗").passed, "verify pass")
        expect(!verifier.verify(goal: "介绍量子计算", output: "抱歉，我无法回答").passed, "verify refusal")
        expect(!verifier.verify(goal: "任意", output: "").passed, "verify empty")

        return failures
    }

    @MainActor
    static func runAsync() async -> [String] {
        var failures: [String] = []
        func expect(_ cond: Bool, _ tag: String) { if !cond { failures.append(tag) } }

        let registry = NexusToolRegistry([EchoTool(), NexusClockTool(), NexusCalculatorTool()])
        expect(!registry.isEmpty && registry.tool(named: "calc") != nil, "registry")
        let echo = await registry.execute(NexusToolCall(name: "echo", arguments: ["text": "hi"]))
        expect(echo.succeeded && echo.output == "hi", "echo execute")
        let ghost = await registry.execute(NexusToolCall(name: "ghost"))
        expect(!ghost.succeeded, "unknown tool")
        let calc = await NexusCalculatorTool().execute(NexusToolCall(name: "calc", arguments: ["expr": "(3+4)*2"]))
        expect(calc.succeeded && calc.output == "14", "calc tool")

        final class Responder: @unchecked Sendable {
            var n = 0
            func reply() -> String {
                n += 1
                if n == 1 { return "```tool\n{\"name\":\"calc\",\"arguments\":{\"expr\":\"1+1\"}}\n```" }
                return "结果是 2"
            }
        }
        let responder = Responder()
        let executor = NexusExecutor(model: { _ in responder.reply() })
        let final = await executor.run(goal: "计算 1+1")
        expect(!final.contains("```tool"), "executor strips blocks")
        expect(executor.toolTraces.contains { $0.call.name == "calc" && $0.result == "2" }, "executor tool trace")

        return failures
    }
}
#endif
