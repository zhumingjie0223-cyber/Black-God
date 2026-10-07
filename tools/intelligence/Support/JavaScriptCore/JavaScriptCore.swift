// Linux 无法加载 Apple JavaScriptCore。生产枢语包装保持原文编译，
// 引擎初始化明确失败，不伪造结果。这些声明检查 Swift 接口接入，不运行 JavaScript。
public final class JSValue {
    public var isObject: Bool { false }
    public func call(withArguments arguments: [Any]) -> JSValue? { nil }
    public func toString() -> String? { nil }
}
public final class JSContext {
    public var exception: JSValue?
    public init?() { return nil }
    @discardableResult public func evaluateScript(_ script: String) -> JSValue? { nil }
    public func objectForKeyedSubscript(_ key: String) -> JSValue? { nil }
}
