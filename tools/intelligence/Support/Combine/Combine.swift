// Linux 声明适配器。发布器不发送值；这些名称用于编译真实聊天入口，
// 不验证 Combine 的通知和订阅行为。
public final class AnyCancellable { public init() {} }
public struct PortablePublisher<Output> {
    public init() {}
    public func dropFirst(_ count: Int = 1) -> Self { self }
    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable { AnyCancellable() }
    public func send() {}
}
public protocol ObservableObject: AnyObject {}
public extension ObservableObject {
    var objectWillChange: PortablePublisher<Void> { PortablePublisher() }
}
@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public var projectedValue: PortablePublisher<Value> { PortablePublisher() }
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
